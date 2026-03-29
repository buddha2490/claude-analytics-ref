# =============================================================================
# sim_tr.R
# Simulate SDTM TR (Tumor Results - Measurements) domain
# NPM-008 / XB010-101 SDTM simulation project
#
# Wave: 3
# Seed: 42 + 15 = 57
# Dependencies: dm.rds, tu.rds, ex.rds, ct_reference.rds
# Expected rows: 400-1200
# Working directory: projects/exelixis-sap/
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

set.seed(57)  # TR is domain order 15: 42 + 15 = 57

# --- Load dependencies -------------------------------------------------------
dm_full <- readRDS("output-data/sdtm/dm.rds")

dm <- dm_full %>%
  dplyr::select(USUBJID, bor, pfs_days)

# Use only first EX record per subject (start of treatment = RFSTDTC)
ex <- readRDS("output-data/sdtm/ex.rds") %>%
  dplyr::arrange(USUBJID, EXSTDTC) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::slice(1) %>%
  dplyr::ungroup() %>%
  dplyr::select(USUBJID, EXSTDTC)

# Target lesions only
tu_target <- readRDS("output-data/sdtm/tu.rds") %>%
  dplyr::filter(TUORRES == "TARGET") %>%
  dplyr::select(USUBJID, TULNKID)

# Combine subject-level inputs
subj <- dm %>%
  dplyr::left_join(ex, by = "USUBJID")

# --- Load CT reference (not used for TR, but required for validation framework) ---
ct_ref <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Source validation functions ----------------------------------------------
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Visit schedule helper ---------------------------------------------------
# Returns a tibble of (VISITNUM, VISIT, offset_days) for a subject's PFS window
build_visit_schedule <- function(pfs_days) {
  # Fixed visits
  fixed_visits <- tibble::tibble(
    VISITNUM   = 1:7,
    VISIT      = c(
      "Baseline RECIST assessment",
      "Week 6",
      "Week 12",
      "Week 18",
      "Week 24",
      "Week 30",
      "Week 36"
    ),
    offset_days = c(-7, 42, 84, 126, 168, 210, 252)
  )

  # Post-week-36 visits every 84 days (only if pfs_days reaches at least week 48)
  if (pfs_days >= 336) {
    extra_offsets <- seq(336, pfs_days, by = 84)
  } else {
    extra_offsets <- numeric(0)
  }

  if (length(extra_offsets) > 0) {
    extra_visitnum <- seq(8, 7 + length(extra_offsets))
    extra_weeks    <- (extra_offsets / 7) %>% round()
    extra_visits   <- tibble::tibble(
      VISITNUM    = extra_visitnum,
      VISIT       = paste0("Week ", extra_weeks),
      offset_days = extra_offsets
    )
    all_visits <- dplyr::bind_rows(fixed_visits, extra_visits)
  } else {
    all_visits <- fixed_visits
  }

  # Keep only visits within PFS window (visit date offset <= pfs_days)
  all_visits <- all_visits %>%
    dplyr::filter(offset_days <= pfs_days)

  # Safety: ensure at least 2 visits (baseline + one follow-up) are included
  # This prevents edge case where pfs_days < 42 leaves only baseline
  if (nrow(all_visits) < 2) {
    # Force inclusion of Week 6 even if PFS < 42
    all_visits <- fixed_visits %>%
      dplyr::filter(VISITNUM <= 2)
  }

  all_visits
}

# --- Lesion size trajectory --------------------------------------------------
# Simulate lesion measurements for one subject across visits.
# Returns a data frame with one row per (lesion x visit).
simulate_subject_tr <- function(usubjid, bor, pfs_days, exstdtc_chr, tulnkids) {

  rfstdtc <- as.Date(exstdtc_chr)

  # NE subjects: baseline only
  if (bor == "NE") {
    visits <- tibble::tibble(
      VISITNUM    = 1L,
      VISIT       = "Baseline RECIST assessment",
      offset_days = -7
    )
  } else {
    visits <- build_visit_schedule(pfs_days)
  }

  n_visits  <- nrow(visits)
  n_lesions <- length(tulnkids)

  # Baseline sizes: runif(1, 15, 80) per lesion
  baseline_sizes <- stats::runif(n_lesions, min = 15, max = 80)

  # Storage: matrix[visit, lesion]
  sizes <- matrix(NA_real_, nrow = n_visits, ncol = n_lesions)
  sizes[1, ] <- round(baseline_sizes, 1)

  # Nadir tracking for PD/SD RECIST constraints
  nadir_sum <- sum(sizes[1, ])

  # Iterate visits 2+
  if (n_visits > 1) {
    for (v in 2:n_visits) {
      prev <- sizes[v - 1, ]

      updated <- switch(
        bor,
        "PR" = {
          if (v <= 3) {
            # Shrink 15-35%
            round(pmax(0, prev * stats::runif(n_lesions, 0.65, 0.85)), 1)
          } else {
            # Slight drift after nadir
            round(pmax(0, prev * stats::runif(n_lesions, 0.95, 1.10)), 1)
          }
        },
        "CR" = {
          if (v <= 3) {
            # Approach 0
            round(pmax(0, prev * stats::runif(n_lesions, 0.0, 0.2)), 1)
          } else {
            # Stay near 0
            round(pmax(0, prev * stats::runif(n_lesions, 0.0, 0.3)), 1)
          }
        },
        "SD" = {
          # ±10% random walk
          round(pmax(0, prev * stats::runif(n_lesions, 0.90, 1.10)), 1)
        },
        "PD" = {
          # 15-30% increase per visit
          round(prev * stats::runif(n_lesions, 1.15, 1.30), 1)
        },
        "NE" = prev  # safety — NE never reaches v >= 2 in this branch
      )

      sizes[v, ] <- updated

      # Update nadir
      current_sum <- sum(updated)
      if (current_sum < nadir_sum) nadir_sum <- current_sum
    }
  }

  # --- RECIST constraint enforcement -----------------------------------------

  # PR: minimum sum across all visits must be <= 70% of baseline sum.
  # Find the visit with minimum sum and ensure it meets the threshold.
  if (bor == "PR" && n_visits >= 2) {
    baseline_sum <- sum(sizes[1, ])
    threshold    <- baseline_sum * 0.70

    # Find visit with minimum sum
    visit_sums   <- apply(sizes, 1, sum)
    min_visit    <- which.min(visit_sums)
    min_sum      <- visit_sums[min_visit]

    # If minimum sum > threshold, force it down
    # Use a more aggressive target (69.5% to ensure rounding doesn't push us over)
    if (min_sum > threshold && min_sum > 0) {
      aggressive_threshold <- baseline_sum * 0.695
      scale_factor         <- aggressive_threshold / min_sum
      sizes[min_visit, ]   <- round(sizes[min_visit, ] * scale_factor, 1)

      # Verify we're actually below threshold after rounding
      # If not, nudge down iteratively
      while (sum(sizes[min_visit, ]) > threshold && max(sizes[min_visit, ]) > 0.1) {
        largest_idx                   <- which.max(sizes[min_visit, ])
        sizes[min_visit, largest_idx] <- pmax(0, sizes[min_visit, largest_idx] - 0.1)
      }
      sizes[min_visit, ] <- pmax(0, sizes[min_visit, ])
    }
  }

  # PD: at final visit, sum >= 120% of nadir AND >= 5mm absolute increase
  if (bor == "PD" && n_visits >= 2) {
    final_sum    <- sum(sizes[n_visits, ])
    nadir_final  <- min(apply(sizes, 1, sum))
    target_pd    <- max(nadir_final * 1.20, nadir_final + 5)

    if (final_sum < target_pd) {
      if (final_sum > 0) {
        scale_factor          <- target_pd / final_sum
        sizes[n_visits, ]     <- round(sizes[n_visits, ] * scale_factor, 1)
      } else {
        # Edge: all lesions at 0 — force minimum PD increase
        sizes[n_visits, ] <- round(rep(target_pd / n_lesions, n_lesions), 1)
      }
    }
  }

  # --- Build records ---------------------------------------------------------
  # Add ±3 day jitter to each visit date
  records <- purrr::map_dfr(seq_len(n_visits), function(v) {
    visit_date  <- rfstdtc + visits$offset_days[v]
    jitter_days <- sample(-3:3, 1)
    trdtc       <- format(visit_date + jitter_days, "%Y-%m-%d")

    purrr::map_dfr(seq_len(n_lesions), function(l) {
      size <- sizes[v, l]
      tibble::tibble(
        USUBJID  = usubjid,
        TRLNKID  = tulnkids[l],
        VISITNUM = as.numeric(visits$VISITNUM[v]),
        VISIT    = visits$VISIT[v],
        TRDTC    = trdtc,
        TRSTRESN = size
      )
    })
  })

  records
}

# --- Simulate all subjects ---------------------------------------------------
message("Simulating TR domain for ", nrow(subj), " subjects...")

tr_raw <- purrr::map_dfr(seq_len(nrow(subj)), function(i) {
  row       <- subj[i, ]
  usubjid   <- row$USUBJID
  bor       <- row$bor
  pfs_days  <- row$pfs_days
  exstdtc   <- row$EXSTDTC
  tulnkids  <- tu_target %>%
    dplyr::filter(USUBJID == usubjid) %>%
    dplyr::pull(TULNKID)

  # Subjects with no target lesions get no TR records
  if (length(tulnkids) == 0) return(NULL)

  simulate_subject_tr(
    usubjid   = usubjid,
    bor       = bor,
    pfs_days  = pfs_days,
    exstdtc_chr = exstdtc,
    tulnkids  = tulnkids
  )
})

# --- Build final SDTM TR dataset --------------------------------------------
tr <- tr_raw %>%
  dplyr::arrange(USUBJID, VISITNUM, TRLNKID) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(TRSEQ = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    STUDYID  = "NPM008",
    DOMAIN   = "TR",
    TRTESTCD = "LDIAM",
    TRTEST   = "Longest Diameter",
    TRORRES  = as.character(TRSTRESN),
    TRSTRESC = TRORRES,
    TRSTRESU = "mm"
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, TRSEQ, TRLNKID,
    TRTESTCD, TRTEST, TRORRES, TRSTRESC, TRSTRESN, TRSTRESU,
    VISITNUM, VISIT, TRDTC
  )

# --- Apply variable labels ---------------------------------------------------
attr(tr$STUDYID,  "label") <- "Study Identifier"
attr(tr$DOMAIN,   "label") <- "Domain Abbreviation"
attr(tr$USUBJID,  "label") <- "Unique Subject Identifier"
attr(tr$TRSEQ,    "label") <- "Sequence Number"
attr(tr$TRLNKID,  "label") <- "Link ID"
attr(tr$TRTESTCD, "label") <- "Tumor Result Test Short Name"
attr(tr$TRTEST,   "label") <- "Tumor Result Test Name"
attr(tr$TRORRES,  "label") <- "Result or Finding in Original Units"
attr(tr$TRSTRESC, "label") <- "Character Result/Finding in Std Format"
attr(tr$TRSTRESN, "label") <- "Numeric Result/Finding in Standard Units"
attr(tr$TRSTRESU, "label") <- "Standard Units"
attr(tr$VISITNUM, "label") <- "Visit Number"
attr(tr$VISIT,    "label") <- "Visit Name"
attr(tr$TRDTC,    "label") <- "Date/Time of Assessment"

# --- Domain-specific validation closure ----------------------------------------
domain_checks <- function(df, dm_ref) {
  checks <- list()

  # D1: All TRLNKID values exist in TU for the same subject
  tu_all <- readRDS("output-data/sdtm/tu.rds") %>%
    dplyr::filter(TUORRES == "TARGET") %>%
    dplyr::select(USUBJID, TULNKID)

  lnkid_check <- df %>%
    dplyr::select(USUBJID, TRLNKID) %>%
    dplyr::distinct() %>%
    dplyr::anti_join(
      tu_all,
      by = c("USUBJID" = "USUBJID", "TRLNKID" = "TULNKID")
    )

  if (nrow(lnkid_check) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "All TRLNKID values exist in TU for the same subject",
      result = "FAIL",
      detail = sprintf("%d TRLNKID value(s) not found in TU", nrow(lnkid_check))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "All TRLNKID values exist in TU for the same subject",
      result = "PASS",
      detail = ""
    )
  }

  # D2: TRSTRESN >= 0 for all records
  neg_count <- sum(df$TRSTRESN < 0, na.rm = TRUE)
  if (neg_count > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "TRSTRESN >= 0 (no negative tumor measurements)",
      result = "FAIL",
      detail = sprintf("%d record(s) have negative TRSTRESN", neg_count)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "TRSTRESN >= 0 (no negative tumor measurements)",
      result = "PASS",
      detail = ""
    )
  }

  # D3: PR subjects achieve <= 70% of baseline sum at some visit
  pr_subjects <- dm_ref %>% dplyr::filter(bor == "PR") %>% dplyr::pull(USUBJID)

  if (length(pr_subjects) > 0) {
    pr_sums <- df %>%
      dplyr::filter(USUBJID %in% pr_subjects) %>%
      dplyr::group_by(USUBJID, VISITNUM) %>%
      dplyr::summarise(sum_size = sum(TRSTRESN), .groups = "drop")

    pr_baseline_sums <- pr_sums %>%
      dplyr::filter(VISITNUM == 1) %>%
      dplyr::select(USUBJID, baseline_sum = sum_size)

    pr_check <- pr_sums %>%
      dplyr::left_join(pr_baseline_sums, by = "USUBJID") %>%
      dplyr::group_by(USUBJID) %>%
      dplyr::summarise(
        min_pct = min(sum_size / baseline_sum),
        .groups = "drop"
      ) %>%
      dplyr::filter(min_pct > 0.70)

    if (nrow(pr_check) > 0) {
      checks[[length(checks) + 1]] <- list(
        check_id = "D3",
        description = "PR subjects achieve <= 70% of baseline sum (RECIST PR criteria)",
        result = "FAIL",
        detail = sprintf("%d PR subject(s) never achieve <= 70%% threshold", nrow(pr_check))
      )
    } else {
      checks[[length(checks) + 1]] <- list(
        check_id = "D3",
        description = "PR subjects achieve <= 70% of baseline sum (RECIST PR criteria)",
        result = "PASS",
        detail = ""
      )
    }
  }

  # D4: PD subjects meet PD RECIST criteria (>=120% nadir AND >=5mm increase)
  pd_subjects <- dm_ref %>% dplyr::filter(bor == "PD") %>% dplyr::pull(USUBJID)

  if (length(pd_subjects) > 0) {
    pd_check <- purrr::map_lgl(pd_subjects, function(subj_id) {
      subj_sums <- df %>%
        dplyr::filter(USUBJID == subj_id) %>%
        dplyr::group_by(VISITNUM) %>%
        dplyr::summarise(sum_size = sum(TRSTRESN), .groups = "drop") %>%
        dplyr::arrange(VISITNUM)

      if (nrow(subj_sums) < 2) return(TRUE)  # Only baseline, skip

      nadir <- cummin(subj_sums$sum_size)
      any(
        subj_sums$sum_size >= nadir * 1.20 &
          subj_sums$sum_size >= nadir + 5 &
          subj_sums$VISITNUM > 1
      )
    })

    n_fail <- sum(!pd_check)
    if (n_fail > 0) {
      checks[[length(checks) + 1]] <- list(
        check_id = "D4",
        description = "PD subjects meet PD RECIST criteria (>=120% nadir, >=5mm increase)",
        result = "FAIL",
        detail = sprintf("%d PD subject(s) never meet PD RECIST criteria", n_fail)
      )
    } else {
      checks[[length(checks) + 1]] <- list(
        check_id = "D4",
        description = "PD subjects meet PD RECIST criteria (>=120% nadir, >=5mm increase)",
        result = "PASS",
        detail = ""
      )
    }
  }

  # D5: NE subjects have only baseline visit
  ne_subjects <- dm_ref %>% dplyr::filter(bor == "NE") %>% dplyr::pull(USUBJID)

  if (length(ne_subjects) > 0) {
    ne_visit_check <- df %>%
      dplyr::filter(USUBJID %in% ne_subjects) %>%
      dplyr::group_by(USUBJID) %>%
      dplyr::summarise(n_visits = dplyr::n_distinct(VISITNUM), .groups = "drop") %>%
      dplyr::filter(n_visits > 1)

    if (nrow(ne_visit_check) > 0) {
      checks[[length(checks) + 1]] <- list(
        check_id = "D5",
        description = "NE subjects have only baseline visit",
        result = "FAIL",
        detail = sprintf("%d NE subject(s) have more than 1 visit", nrow(ne_visit_check))
      )
    } else {
      checks[[length(checks) + 1]] <- list(
        check_id = "D5",
        description = "NE subjects have only baseline visit",
        result = "PASS",
        detail = ""
      )
    }
  }

  # D6: Measurement dates within or near treatment period
  ex_dates <- readRDS("output-data/sdtm/ex.rds") %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarise(
      rfstdtc = min(EXSTDTC, na.rm = TRUE),
      .groups = "drop"
    )

  dm_pfs <- dm_ref %>%
    dplyr::select(USUBJID, pfs_days)

  date_check <- df %>%
    dplyr::left_join(ex_dates, by = "USUBJID") %>%
    dplyr::left_join(dm_pfs, by = "USUBJID") %>%
    dplyr::mutate(
      trdtc_date = as.Date(TRDTC),
      rfstdtc_date = as.Date(rfstdtc),
      days_from_rfst = as.numeric(trdtc_date - rfstdtc_date)
    ) %>%
    dplyr::filter(days_from_rfst < -35 | days_from_rfst > (pfs_days + 35))  # Allow ±35 day window

  if (nrow(date_check) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D6",
      description = "Measurement dates within reasonable window of treatment period",
      result = "WARNING",
      detail = sprintf("%d record(s) outside expected date range", nrow(date_check))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D6",
      description = "Measurement dates within reasonable window of treatment period",
      result = "PASS",
      detail = ""
    )
  }

  checks
}

# --- Validate before writing ---------------------------------------------------
validation <- validate_sdtm_domain(
  domain_df      = tr,
  domain_code    = "TR",
  dm_ref         = dm_full,
  expected_rows  = c(400, 1200),
  ct_reference   = NULL,  # No CT for TR
  domain_checks  = domain_checks
)

message(validation$summary)

# --- Write output (only if validation passes) ---------------------------------
message("Writing tr.rds...")
saveRDS(tr, "output-data/sdtm/tr.rds")

message("Writing tr.xpt...")
haven::write_xpt(tr, "output-data/sdtm/tr.xpt")

# --- Log result ---------------------------------------------------------------
log_sdtm_result(
  domain_code       = "TR",
  wave              = 3,
  row_count         = nrow(tr),
  col_count         = ncol(tr),
  validation_result = validation,
  notes             = c(
    "Lesion size trajectories driven by BOR from DM latent",
    "RECIST constraints enforced: PR <= 70% baseline, PD >= 120% nadir + 5mm",
    "Visit schedule: baseline + every 6 weeks until PFS event"
  )
)

message("sim_tr.R complete: ", nrow(tr), " rows written")
