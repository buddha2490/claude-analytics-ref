# =============================================================================
# sim_tr.R
# Simulate SDTM TR (Tumor Results - Measurements) domain
# NPM-008 / XB010-101 SDTM simulation project
#
# Inputs:
#   cohort/output-data/dm.rds  -- DM spine with bor, pfs_days
#   cohort/output-data/ex.rds  -- EX data (EXSTDTC = RFSTDTC)
#   cohort/output-data/tu.rds  -- TU data (TULNKID, TUORRES per subject)
#
# Outputs:
#   cohort/output-data/sdtm/tr.xpt  -- SDTM XPT for submission
#   cohort/output-data/sdtm/tr.rds  -- RDS for downstream RS domain
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

set.seed(57)  # TR is domain order 15: 42 + 15 = 57

# --- Paths -------------------------------------------------------------------
base_dir  <- "/Users/briancarter/Rdata/claude-analytics-ref/cohort"
data_dir  <- file.path(base_dir, "output-data")

# --- Load inputs -------------------------------------------------------------
dm <- readRDS(file.path(data_dir, "dm.rds")) %>%
  dplyr::select(USUBJID, bor, pfs_days)

# Use only first EX record per subject (start of treatment = RFSTDTC)
ex <- readRDS(file.path(data_dir, "ex.rds")) %>%
  dplyr::arrange(USUBJID, EXSTDTC) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::slice(1) %>%
  dplyr::ungroup() %>%
  dplyr::select(USUBJID, EXSTDTC)

# Target lesions only
tu_target <- readRDS(file.path(data_dir, "tu.rds")) %>%
  dplyr::filter(TUORRES == "TARGET") %>%
  dplyr::select(USUBJID, TULNKID)

# Combine subject-level inputs
subj <- dm %>%
  dplyr::left_join(ex, by = "USUBJID")

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

  # PR: sum at visit 2 must be <= 70% of baseline sum.
  # Scale all lesions then nudge the largest down if rounding leaves sum > threshold.
  if (bor == "PR" && n_visits >= 2) {
    baseline_sum <- sum(sizes[1, ])
    threshold    <- baseline_sum * 0.70
    visit2_sum   <- sum(sizes[2, ])
    if (visit2_sum > threshold && visit2_sum > 0) {
      scale_factor   <- threshold / visit2_sum
      sizes[2, ]     <- round(sizes[2, ] * scale_factor, 1)
      # Nudge largest lesion down by 0.1mm until sum is within threshold
      while (sum(sizes[2, ]) > threshold) {
        largest_idx    <- which.max(sizes[2, ])
        sizes[2, largest_idx] <- sizes[2, largest_idx] - 0.1
      }
      sizes[2, ] <- pmax(0, sizes[2, ])
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

# --- Save outputs ------------------------------------------------------------
message("Writing tr.rds...")
saveRDS(tr, file.path(data_dir, "tr.rds"))

message("Writing tr.xpt...")
haven::write_xpt(tr, file.path(data_dir, "tr.xpt"))

message("TR domain complete: ", nrow(tr), " records, ",
        dplyr::n_distinct(tr$USUBJID), " subjects.")

# --- Validation --------------------------------------------------------------
message("\n--- Validation ---")

dm_ids <- dm$USUBJID

# 1. All USUBJID in TR exist in DM
tr_ids_check <- dplyr::setdiff(unique(tr$USUBJID), dm_ids)
stopifnot(
  "FAIL: TR contains USUBJIDs not in DM" = length(tr_ids_check) == 0
)
message("PASS: All TR USUBJIDs exist in DM")

# 2. TRSEQ unique per USUBJID
trseq_check <- tr %>%
  dplyr::group_by(USUBJID, TRSEQ) %>%
  dplyr::filter(dplyr::n() > 1) %>%
  nrow()
stopifnot("FAIL: TRSEQ not unique within USUBJID" = trseq_check == 0)
message("PASS: TRSEQ is unique within each USUBJID")

# 3. All TRLNKID values exist in TU for the same subject
lnkid_check <- tr %>%
  dplyr::select(USUBJID, TRLNKID) %>%
  dplyr::distinct() %>%
  dplyr::anti_join(
    tu_target %>% dplyr::select(USUBJID, TULNKID),
    by = c("USUBJID" = "USUBJID", "TRLNKID" = "TULNKID")
  ) %>%
  nrow()
stopifnot(
  "FAIL: TR TRLNKID values not found in TU for matching USUBJID" = lnkid_check == 0
)
message("PASS: All TRLNKID values exist in TU for the same subject")

# 4. PR subjects: minimum sum of target lesion sizes at any visit <= 70% of baseline
pr_subjects <- dm %>% dplyr::filter(bor == "PR") %>% dplyr::pull(USUBJID)

if (length(pr_subjects) > 0) {
  pr_sums <- tr %>%
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

  stopifnot(
    "FAIL: Some PR subjects never achieve <= 70% of baseline sum" = nrow(pr_check) == 0
  )
  message("PASS: All PR subjects achieve <= 70% of baseline sum at some visit")
}

# 5. PD subjects: at some visit, sum >= 120% of nadir AND >= 5mm increase
pd_subjects <- dm %>% dplyr::filter(bor == "PD") %>% dplyr::pull(USUBJID)

if (length(pd_subjects) > 0) {
  pd_check <- purrr::map_lgl(pd_subjects, function(subj_id) {
    subj_sums <- tr %>%
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
  stopifnot("FAIL: Some PD subjects never meet PD RECIST criteria" = n_fail == 0)
  message("PASS: All PD subjects meet PD RECIST criteria (>=120% nadir, >=5mm increase)")
}

# 6. NE subjects: only 1 visit (baseline) in TR
ne_subjects <- dm %>% dplyr::filter(bor == "NE") %>% dplyr::pull(USUBJID)

if (length(ne_subjects) > 0) {
  ne_visit_check <- tr %>%
    dplyr::filter(USUBJID %in% ne_subjects) %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarise(n_visits = dplyr::n_distinct(VISITNUM), .groups = "drop") %>%
    dplyr::filter(n_visits > 1)
  stopifnot(
    "FAIL: NE subjects have more than 1 visit in TR" = nrow(ne_visit_check) == 0
  )
  message("PASS: NE subjects have only baseline visit in TR")
}

# 7. TRSTRESN >= 0 for all records
neg_check <- sum(tr$TRSTRESN < 0, na.rm = TRUE)
stopifnot("FAIL: Some TRSTRESN values are negative" = neg_check == 0)
message("PASS: All TRSTRESN values are >= 0")

message("\nAll validations passed. TR domain saved to:\n  ",
        file.path(data_dir, "tr.rds"), "\n  ",
        file.path(data_dir, "tr.xpt"))
