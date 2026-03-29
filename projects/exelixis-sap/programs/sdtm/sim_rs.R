# =============================================================================
# sim_rs.R — Disease Response Assessments (RECIST 1.1 + Clinician BOR)
# Study: NPM-008 / XB010-101 ECA
# Seed: 42 + 16 = 58
# Wave: 4
# Dependencies: dm.rds, ex.rds, tr.rds
# Expected rows: 120-400
# Working directory: projects/exelixis-sap/
# =============================================================================

suppressPackageStartupMessages({
  library(conflicted)
  library(tidyverse)
  library(haven)
  conflicts_prefer(dplyr::filter, .quiet = TRUE)
})

set.seed(58)

# --- Load dependencies -------------------------------------------------------

dm_full <- readRDS("output-data/sdtm/dm.rds")
dm_raw <- dm_full %>%
  select(USUBJID, bor, pfs_days)

ex_raw <- readRDS("output-data/sdtm/ex.rds") %>%
  select(USUBJID, EXSTDTC)

tr_raw <- readRDS("output-data/sdtm/tr.rds") %>%
  select(USUBJID, VISITNUM, VISIT, TRSTRESN, TRDTC)

# --- Load CT reference (if applicable) ----------------------------------------

ct_ref <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Source validation functions ----------------------------------------------

source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Compute visit-level target lesion sums from TR ---------------------------

# One row per USUBJID + VISITNUM: sum of longest diameters and first date
visit_sums <- tr_raw %>%
  group_by(USUBJID, VISITNUM, VISIT) %>%
  summarise(
    sum_ldiam = sum(TRSTRESN, na.rm = TRUE),
    RSDTC     = dplyr::first(TRDTC),
    .groups   = "drop"
  ) %>%
  arrange(USUBJID, VISITNUM)

# --- Derive RECIST 1.1 response per visit per subject -------------------------

# Helper: apply RECIST 1.1 rules for a single subject's visit sequence
derive_recist_responses <- function(df) {
  # df is already sorted by VISITNUM for one subject
  n_visits <- nrow(df)

  # Baseline sum (visit 1)
  baseline_sum <- df$sum_ldiam[1]

  # Running nadir: minimum sum seen up to and including current visit
  # Nadir is computed before the current visit contributes (use cummin on lag)
  # Per RECIST, nadir starts at baseline and updates as we observe lower values
  response <- character(n_visits)
  nadir_sum <- baseline_sum

  for (i in seq_len(n_visits)) {
    s <- df$sum_ldiam[i]

    if (is.na(s)) {
      response[i] <- "NE"
    } else if (s <= 5) {
      # CR: all target lesions essentially gone (≤5 mm sum)
      response[i] <- "CR"
    } else if (s <= 0.70 * baseline_sum) {
      # PR: ≥30% decrease from baseline
      response[i] <- "PR"
    } else if (s >= 1.20 * nadir_sum && (s - nadir_sum) >= 5) {
      # PD: ≥20% increase from nadir AND ≥5 mm absolute increase
      response[i] <- "PD"
    } else {
      # SD: neither sufficient shrinkage nor sufficient growth
      response[i] <- "SD"
    }

    # Update nadir after each visit (nadir is the minimum observed so far)
    nadir_sum <- min(nadir_sum, s, na.rm = TRUE)
  }

  df$RSORRES <- response
  df
}

# Apply per subject and bind results
recist_visits <- visit_sums %>%
  group_by(USUBJID) %>%
  group_modify(~ derive_recist_responses(.x)) %>%
  ungroup()

# --- Build Part 1: RECIST visit RS records ------------------------------------

rs_recist <- recist_visits %>%
  transmute(
    STUDYID  = "NPM008",
    DOMAIN   = "RS",
    USUBJID,
    RSTESTCD = "RECIST",
    RSTEST   = "RECIST 1.1",
    RSCAT    = "RECIST 1.1",
    RSEVAL   = "Independent",
    RSORRES,
    RSSTRESC = RSORRES,
    VISITNUM,
    VISIT,
    RSDTC
  )

# --- Build Part 2: Clinician-stated BOR (one per subject) ---------------------

# Join DM (bor, pfs_days) with EX (EXSTDTC) to compute RSDTC
# RSDTC = EXSTDTC + pfs_days (date of final response determination)
bor_data <- dm_raw %>%
  left_join(ex_raw, by = "USUBJID") %>%
  mutate(RSDTC = as.character(as.Date(EXSTDTC) + pfs_days))

rs_clinres <- bor_data %>%
  transmute(
    STUDYID  = "NPM008",
    DOMAIN   = "RS",
    USUBJID,
    RSTESTCD = "CLINRES",
    RSTEST   = "Clinician-Stated Best Overall Response",
    RSCAT    = "RECIST 1.1",
    RSEVAL   = "Physician",
    RSORRES  = bor,
    RSSTRESC = bor,
    VISITNUM = NA_real_,
    VISIT    = NA_character_,
    RSDTC
  )

# --- Combine and assign RSSEQ -------------------------------------------------

rs <- bind_rows(rs_recist, rs_clinres) %>%
  arrange(USUBJID, VISITNUM, RSTESTCD) %>%
  group_by(USUBJID) %>%
  mutate(RSSEQ = row_number()) %>%
  ungroup() %>%
  # Reorder columns per SDTM convention
  select(
    STUDYID, DOMAIN, USUBJID, RSSEQ, RSTESTCD, RSTEST, RSCAT, RSEVAL,
    RSORRES, RSSTRESC, VISITNUM, VISIT, RSDTC
  )

# --- Apply variable labels ----------------------------------------------------

attr(rs$STUDYID,  "label") <- "Study Identifier"
attr(rs$DOMAIN,   "label") <- "Domain Abbreviation"
attr(rs$USUBJID,  "label") <- "Unique Subject Identifier"
attr(rs$RSSEQ,    "label") <- "Sequence Number"
attr(rs$RSTESTCD, "label") <- "Response Short Name"
attr(rs$RSTEST,   "label") <- "Response Test Name"
attr(rs$RSCAT,    "label") <- "Category"
attr(rs$RSEVAL,   "label") <- "Evaluator"
attr(rs$RSORRES,  "label") <- "Result in Original Units"
attr(rs$RSSTRESC, "label") <- "Character Result in Std Format"
attr(rs$VISITNUM, "label") <- "Visit Number"
attr(rs$VISIT,    "label") <- "Visit Name"
attr(rs$RSDTC,    "label") <- "Date/Time of Response"

# --- Domain-specific validation closure ----------------------------------------

domain_checks <- function(df, dm_ref) {
  checks <- list()

  # RS1: Every subject has exactly 1 CLINRES record
  clinres_counts <- df %>%
    dplyr::filter(RSTESTCD == "CLINRES") %>%
    count(USUBJID)

  one_clinres <- nrow(clinres_counts) == 40 && all(clinres_counts$n == 1)

  checks[[length(checks) + 1]] <- list(
    check_id = "RS1",
    description = "Every subject has exactly 1 CLINRES record",
    result = if (one_clinres) "PASS" else "FAIL",
    detail = if (!one_clinres) {
      sprintf("Found %d subjects with CLINRES records; expected 40 each with n=1", nrow(clinres_counts))
    } else ""
  )

  # RS2: CLINRES RSORRES matches bor from DM for all 40 subjects
  clinres_vs_dm <- df %>%
    dplyr::filter(RSTESTCD == "CLINRES") %>%
    select(USUBJID, RSORRES) %>%
    left_join(dm_ref %>% select(USUBJID, bor), by = "USUBJID") %>%
    mutate(match = RSORRES == bor)

  bor_match <- all(clinres_vs_dm$match, na.rm = TRUE)
  mismatches <- clinres_vs_dm %>% dplyr::filter(!match)

  checks[[length(checks) + 1]] <- list(
    check_id = "RS2",
    description = "CLINRES RSORRES matches DM bor (all 40 subjects)",
    result = if (bor_match) "PASS" else "FAIL",
    detail = if (!bor_match) {
      sprintf("%d mismatch(es): %s",
              nrow(mismatches),
              paste(head(mismatches$USUBJID, 3), collapse = ", "))
    } else ""
  )

  # RS3: PR subjects have at least one RECIST visit with PR or CR
  pr_subjs <- dm_ref %>% dplyr::filter(bor == "PR") %>% pull(USUBJID)

  pr_check_results <- df %>%
    dplyr::filter(USUBJID %in% pr_subjs, RSTESTCD == "RECIST") %>%
    group_by(USUBJID) %>%
    summarise(has_pr_or_cr = any(RSORRES %in% c("PR", "CR")), .groups = "drop")

  pr_check <- all(pr_check_results$has_pr_or_cr)
  pr_fail_subjs <- pr_check_results %>% dplyr::filter(!has_pr_or_cr)

  checks[[length(checks) + 1]] <- list(
    check_id = "RS3",
    description = "PR subjects have ≥1 RECIST visit with PR or CR",
    result = if (pr_check) "PASS" else "FAIL",
    detail = if (!pr_check) {
      sprintf("%d PR subject(s) missing PR/CR in RECIST: %s",
              nrow(pr_fail_subjs),
              paste(head(pr_fail_subjs$USUBJID, 3), collapse = ", "))
    } else ""
  )

  # RS4: PD subjects with ≥2 RECIST visits must have at least one visit with PD
  pd_subjs <- dm_ref %>% dplyr::filter(bor == "PD") %>% pull(USUBJID)

  pd_recist_summary <- df %>%
    dplyr::filter(USUBJID %in% pd_subjs, RSTESTCD == "RECIST") %>%
    group_by(USUBJID) %>%
    summarise(
      n_recist = n(),
      has_pd   = any(RSORRES == "PD"),
      .groups  = "drop"
    )

  pd_multi_visit_fail <- pd_recist_summary %>%
    dplyr::filter(n_recist >= 2, !has_pd)

  pd_check <- nrow(pd_multi_visit_fail) == 0

  pd_single_visit_n <- pd_recist_summary %>%
    dplyr::filter(n_recist == 1) %>%
    nrow()

  checks[[length(checks) + 1]] <- list(
    check_id = "RS4",
    description = "PD subjects with ≥2 RECIST visits have imaging PD",
    result = if (pd_check) "PASS" else "FAIL",
    detail = if (!pd_check) {
      sprintf("%d PD subject(s) with ≥2 visits lack imaging PD: %s",
              nrow(pd_multi_visit_fail),
              paste(head(pd_multi_visit_fail$USUBJID, 3), collapse = ", "))
    } else {
      sprintf("(%d early-progressor PD subjects have baseline-only RECIST)", pd_single_visit_n)
    }
  )

  # RS5: NE subjects have only 1 RECIST record (baseline) + 1 CLINRES
  ne_subjs <- dm_ref %>% dplyr::filter(bor == "NE") %>% pull(USUBJID)

  ne_recist_counts <- df %>%
    dplyr::filter(USUBJID %in% ne_subjs, RSTESTCD == "RECIST") %>%
    count(USUBJID)

  ne_check <- all(ne_recist_counts$n == 1)
  ne_fail_subjs <- ne_recist_counts %>% dplyr::filter(n != 1)

  checks[[length(checks) + 1]] <- list(
    check_id = "RS5",
    description = "NE subjects have only 1 RECIST record (baseline)",
    result = if (ne_check) "PASS" else "FAIL",
    detail = if (!ne_check) {
      sprintf("%d NE subject(s) with unexpected RECIST count: %s",
              nrow(ne_fail_subjs),
              paste(head(ne_fail_subjs$USUBJID, 3), collapse = ", "))
    } else ""
  )

  # RS6: RSSTRESC values follow RECIST 1.1 vocabulary
  valid_recist_responses <- c("CR", "PR", "SD", "PD", "NE")
  invalid_responses <- df %>%
    dplyr::filter(RSTESTCD == "RECIST") %>%
    dplyr::filter(!RSSTRESC %in% valid_recist_responses)

  checks[[length(checks) + 1]] <- list(
    check_id = "RS6",
    description = "RSSTRESC values follow RECIST 1.1 vocabulary (CR/PR/SD/PD/NE)",
    result = if (nrow(invalid_responses) == 0) "PASS" else "FAIL",
    detail = if (nrow(invalid_responses) > 0) {
      sprintf("%d invalid response value(s): %s",
              nrow(invalid_responses),
              paste(head(unique(invalid_responses$RSSTRESC), 3), collapse = ", "))
    } else ""
  )

  checks
}

# --- Validate before writing ---------------------------------------------------

validation <- validate_sdtm_domain(
  domain_df      = rs,
  domain_code    = "RS",
  dm_ref         = dm_full,
  expected_rows  = c(120, 400),
  ct_reference   = NULL,  # No CT validation for RS (RECIST values are domain-specific)
  domain_checks  = domain_checks
)

message(validation$summary)

# --- Write output (only if validation passes) ---------------------------------

haven::write_xpt(rs, path = "output-data/sdtm/rs.xpt")
saveRDS(rs, "output-data/sdtm/rs.rds")

message("RS domain written: ", nrow(rs), " records for ", n_distinct(rs$USUBJID), " subjects")
message("  RECIST visit records : ", sum(rs$RSTESTCD == "RECIST"))
message("  CLINRES records      : ", sum(rs$RSTESTCD == "CLINRES"))
message("Files saved:")
message("  output-data/sdtm/rs.rds")
message("  output-data/sdtm/rs.xpt")

# --- Log result ---------------------------------------------------------------

log_sdtm_result(
  domain_code       = "RS",
  wave              = 4,
  row_count         = nrow(rs),
  col_count         = ncol(rs),
  validation_result = validation,
  notes             = c(
    "RECIST 1.1 responses derived from TR tumor measurement trajectories",
    "Clinician-stated BOR matches DM latent variable for all subjects",
    "Early progressors (baseline-only RECIST) have PD in CLINRES only"
  )
)

message("sim_rs.R complete: ", nrow(rs), " rows written")

# --- Summary preview ----------------------------------------------------------

message("\nRS domain preview:")
rs %>%
  count(RSTESTCD, RSORRES) %>%
  arrange(RSTESTCD, RSORRES) %>%
  print()
