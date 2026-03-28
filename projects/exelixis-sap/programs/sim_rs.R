# sim_rs.R
# Simulate SDTM RS domain — Response Assessments (RECIST 1.1 visits + BOR)
# NPM-008 / XB010-101 simulated data
# Domain order: 16 → set.seed(58)

library(tidyverse)
library(haven)

set.seed(58)

# --- Load inputs --------------------------------------------------------------

dm_raw <- readRDS("cohort/output-data/dm.rds") %>%
  select(USUBJID, bor, pfs_days)

ex_raw <- readRDS("cohort/output-data/ex.rds") %>%
  select(USUBJID, EXSTDTC)

tr_raw <- readRDS("cohort/output-data/tr.rds") %>%
  select(USUBJID, VISITNUM, VISIT, TRSTRESN, TRDTC)

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

# --- Write outputs ------------------------------------------------------------

saveRDS(rs, "cohort/output-data/sdtm/rs.rds")
haven::write_xpt(rs, "cohort/output-data/sdtm/rs.xpt")

message("RS domain written: ", nrow(rs), " records for ", n_distinct(rs$USUBJID), " subjects")
message("  RECIST visit records : ", sum(rs$RSTESTCD == "RECIST"))
message("  CLINRES records      : ", sum(rs$RSTESTCD == "CLINRES"))
message("Files saved:")
message("  cohort/output-data/sdtm/rs.rds")
message("  cohort/output-data/sdtm/rs.xpt")

# --- Validation ---------------------------------------------------------------

message("\n--- Validation ---")

dm_all <- readRDS("cohort/output-data/dm.rds")

# Check 1: all USUBJID in DM
subj_in_dm <- all(rs$USUBJID %in% dm_all$USUBJID)
message("Check 1 — All USUBJID in DM: ", subj_in_dm)
stopifnot("FAIL: subjects in RS not in DM" = subj_in_dm)

# Check 2: RSSEQ unique per USUBJID
seq_unique <- rs %>%
  group_by(USUBJID) %>%
  summarise(n_seq = n(), n_distinct_seq = n_distinct(RSSEQ)) %>%
  mutate(ok = n_seq == n_distinct_seq) %>%
  pull(ok) %>%
  all()
message("Check 2 — RSSEQ unique per USUBJID: ", seq_unique)
stopifnot("FAIL: RSSEQ not unique per USUBJID" = seq_unique)

# Check 3: every subject has exactly 1 CLINRES record
clinres_counts <- rs %>%
  dplyr::filter(RSTESTCD == "CLINRES") %>%
  count(USUBJID)
one_clinres <- nrow(clinres_counts) == 40 && all(clinres_counts$n == 1)
message("Check 3 — Every subject has exactly 1 CLINRES: ", one_clinres)
stopifnot("FAIL: CLINRES count per subject is not exactly 1" = one_clinres)

# Check 4: CLINRES RSORRES matches bor from DM for all 40 subjects
clinres_vs_dm <- rs %>%
  dplyr::filter(RSTESTCD == "CLINRES") %>%
  select(USUBJID, RSORRES) %>%
  left_join(dm_all %>% select(USUBJID, bor), by = "USUBJID") %>%
  mutate(match = RSORRES == bor)
bor_match <- all(clinres_vs_dm$match)
message("Check 4 — CLINRES RSORRES matches DM bor (all 40): ", bor_match)
if (!bor_match) {
  message("  Mismatches:")
  print(clinres_vs_dm %>% dplyr::filter(!match))
}
stopifnot("FAIL: CLINRES BOR does not match DM bor" = bor_match)

# Check 5: PR subjects have at least one RECIST visit with PR or CR
pr_subjs <- dm_all %>% dplyr::filter(bor == "PR") %>% pull(USUBJID)
pr_check <- rs %>%
  dplyr::filter(USUBJID %in% pr_subjs, RSTESTCD == "RECIST") %>%
  group_by(USUBJID) %>%
  summarise(has_pr_or_cr = any(RSORRES %in% c("PR", "CR"))) %>%
  pull(has_pr_or_cr) %>%
  all()
message("Check 5 — PR subjects have ≥1 RECIST visit with PR or CR: ", pr_check)
if (!pr_check) {
  message("  PR subjects missing RECIST PR/CR:")
  rs %>%
    dplyr::filter(USUBJID %in% pr_subjs, RSTESTCD == "RECIST") %>%
    group_by(USUBJID) %>%
    summarise(responses = paste(RSORRES, collapse = ", ")) %>%
    print()
}
stopifnot("FAIL: PR subject missing confirming RECIST response" = pr_check)

# Check 6: PD subjects with ≥2 RECIST visits must have at least one visit with PD
# Single-visit PD subjects are early progressors — PD is clinician-stated only (CLINRES)
# The RECIST criteria require follow-up imaging; they cannot be met with baseline alone.
pd_subjs <- dm_all %>% dplyr::filter(bor == "PD") %>% pull(USUBJID)

pd_recist_summary <- rs %>%
  dplyr::filter(USUBJID %in% pd_subjs, RSTESTCD == "RECIST") %>%
  group_by(USUBJID) %>%
  summarise(
    n_recist = n(),
    has_pd   = any(RSORRES == "PD"),
    .groups  = "drop"
  )

# Subjects with ≥2 RECIST visits must confirm PD on imaging
pd_multi_visit_fail <- pd_recist_summary %>%
  dplyr::filter(n_recist >= 2, !has_pd)

pd_check <- nrow(pd_multi_visit_fail) == 0

pd_single_visit_n <- pd_recist_summary %>%
  dplyr::filter(n_recist == 1) %>%
  nrow()

message("Check 6 — PD subjects with ≥2 RECIST visits have imaging PD: ", pd_check)
message("  (", pd_single_visit_n, " early-progressor subjects have baseline-only RECIST; PD is CLINRES-only)")
if (!pd_check) {
  message("  PD subjects with ≥2 visits but no imaging PD:")
  print(pd_multi_visit_fail)
}
stopifnot("FAIL: multi-visit PD subject missing RECIST PD response" = pd_check)

# Check 7: NE subjects have only 1 RECIST record (baseline) + 1 CLINRES
ne_subjs <- dm_all %>% dplyr::filter(bor == "NE") %>% pull(USUBJID)
ne_recist_counts <- rs %>%
  dplyr::filter(USUBJID %in% ne_subjs, RSTESTCD == "RECIST") %>%
  count(USUBJID)
ne_check <- all(ne_recist_counts$n == 1)
message("Check 7 — NE subjects have only 1 RECIST record (baseline): ", ne_check)
if (!ne_check) {
  message("  NE subjects with unexpected RECIST counts:")
  print(ne_recist_counts)
}
stopifnot("FAIL: NE subject has more than 1 RECIST record" = ne_check)

message("\nAll validation checks PASSED.")

# --- Summary preview ----------------------------------------------------------

message("\nRS domain preview:")
rs %>%
  count(RSTESTCD, RSORRES) %>%
  arrange(RSTESTCD, RSORRES) %>%
  print()
