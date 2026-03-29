# =============================================================================
# Program:   sim_mh.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Domain:    MH — Medical History
# Purpose:   Simulate the MH domain from the DM spine. Generates one NSCLC
#            primary diagnosis record, one histology record, one clinical
#            staging record, and probabilistic comorbidity records per subject.
#            Writes mh.xpt to cohort/output-data/.
# Seed:      set.seed(45) — domain offset 3 from base seed 42
# Author:    r-clinical-programmer agent
# Date:      2026-03-27
# =============================================================================

library(tidyverse)
library(lubridate)
library(haven)
library(xportr)

source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")


# --- Seed and constants -------------------------------------------------------

set.seed(45)

STUDYID <- "NPM008"

# Comorbidity conditions, probabilities, and category
comorbidities <- tibble(
  mhterm = c(
    "Coronary Artery Disease",
    "Congestive Heart Failure",
    "Peripheral Vascular Disease",
    "Cerebrovascular Disease",
    "Chronic Pulmonary Disease",
    "Diabetes Without Complications",
    "Diabetes With Complications",
    "Renal Disease",
    "Mild Liver Disease",
    "Rheumatic Disease",
    "Peptic Ulcer Disease"
  ),
  prob = c(0.15, 0.08, 0.10, 0.08, 0.20, 0.18, 0.05, 0.10, 0.05, 0.05, 0.05),
  mhcat = "COMORBIDITY DIAGNOSES"
)


# --- Load DM spine and CT reference -------------------------------------------

dm <- readRDS("output-data/sdtm/dm.rds")
ct_reference <- readRDS("output-data/sdtm/ct_reference.rds")


# --- Per-subject fixed draws (vectorised before pmap loop) --------------------

n <- nrow(dm)

# NSCLC diagnosis date offset: days before RFSTDTC (90–1460 days)
nsclc_offset <- sample(90:1460, n, replace = TRUE)

# Histology: one draw per subject; probabilities from spec
histology_terms <- sample(
  c(
    "Adenocarcinoma",
    "Squamous Cell Carcinoma",
    "Large Cell Carcinoma",
    "NSCLC NOS"
  ),
  n,
  replace = TRUE,
  prob = c(0.60, 0.25, 0.05, 0.10)
)

# Staging: one draw per subject
staging_terms <- sample(
  c("Stage IV", "Stage IIIB", "Stage IIIA"),
  n,
  replace = TRUE,
  prob = c(0.70, 0.20, 0.10)
)

# Comorbidity flags: one bernoulli draw per condition per subject
# comorbidity_flags is n x n_comorbidities logical matrix
comorbidity_flags <- vapply(
  comorbidities$prob,
  function(p) as.logical(rbinom(n, size = 1, prob = p)),
  logical(n)
)

# Comorbidity date offsets: pre-draw one offset per subject per condition
# (30–1095 days before RFSTDTC). Only used when the flag is TRUE.
comorbidity_offsets <- matrix(
  sample(30:1095, n * nrow(comorbidities), replace = TRUE),
  nrow = n,
  ncol = nrow(comorbidities)
)


# --- Build MH records per subject ---------------------------------------------

mh_list <- pmap(
  list(
    usubjid        = dm$USUBJID,
    studyid        = dm$STUDYID,
    rfstdtc        = dm$RFSTDTC,
    nsclc_off      = nsclc_offset,
    hist_term      = histology_terms,
    stage_term     = staging_terms,
    comorb_flags   = split(comorbidity_flags, seq_len(n)),
    comorb_offsets = split(comorbidity_offsets, seq_len(n))
  ),
  function(usubjid, studyid, rfstdtc, nsclc_off,
           hist_term, stage_term, comorb_flags, comorb_offsets) {

    # RFSTDTC already includes the per-subject date_shift from sim_dm.R —
    # compute MH dates as offsets from the already-shifted RFSTDTC
    rfst_date   <- as.Date(rfstdtc)
    nsclc_date  <- as.character(rfst_date - nsclc_off)

    # --- Fixed records (all subjects) -----------------------------------------

    # 1. NSCLC primary diagnosis
    rec_nsclc <- tibble(
      STUDYID  = studyid,
      DOMAIN   = "MH",
      USUBJID  = usubjid,
      MHTERM   = "Non-small cell lung cancer",
      MHCAT    = "CANCER DIAGNOSIS",
      MHSTDTC  = nsclc_date,
      MHENDTC  = NA_character_
    )

    # 2. Histology — same start date as NSCLC diagnosis
    rec_hist <- tibble(
      STUDYID  = studyid,
      DOMAIN   = "MH",
      USUBJID  = usubjid,
      MHTERM   = hist_term,
      MHCAT    = "HISTOLOGY",
      MHSTDTC  = nsclc_date,
      MHENDTC  = NA_character_
    )

    # 3. Clinical staging — same start date as NSCLC diagnosis
    rec_stage <- tibble(
      STUDYID  = studyid,
      DOMAIN   = "MH",
      USUBJID  = usubjid,
      MHTERM   = stage_term,
      MHCAT    = "CLINICAL STAGING GROUP",
      MHSTDTC  = nsclc_date,
      MHENDTC  = NA_character_
    )

    # --- Probabilistic comorbidity records ------------------------------------

    # comorb_flags and comorb_offsets are vectors of length n_comorbidities
    # for this single subject (due to split() above)
    active_idx <- which(as.logical(comorb_flags))

    if (length(active_idx) > 0) {
      rec_comorbidities <- tibble(
        STUDYID  = studyid,
        DOMAIN   = "MH",
        USUBJID  = usubjid,
        MHTERM   = comorbidities$mhterm[active_idx],
        MHCAT    = comorbidities$mhcat[active_idx],
        MHSTDTC  = as.character(rfst_date - as.integer(comorb_offsets)[active_idx]),
        MHENDTC  = NA_character_
      )
    } else {
      rec_comorbidities <- tibble(
        STUDYID  = character(0),
        DOMAIN   = character(0),
        USUBJID  = character(0),
        MHTERM   = character(0),
        MHCAT    = character(0),
        MHSTDTC  = character(0),
        MHENDTC  = character(0)
      )
    }

    bind_rows(rec_nsclc, rec_hist, rec_stage, rec_comorbidities)
  }
)


# --- Assemble full MH dataset -------------------------------------------------

mh_raw <- bind_rows(mh_list)

# Add MHSEQ: sequential integer per USUBJID, ordered as generated
mh <- mh_raw %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(MHSEQ = row_number()) %>%
  dplyr::ungroup() %>%
  # MHDECOD: Dictionary-Derived Term — copy of MHTERM for simulated data
  dplyr::mutate(MHDECOD = MHTERM) %>%
  dplyr::select(STUDYID, DOMAIN, USUBJID, MHSEQ, MHTERM, MHDECOD, MHCAT, MHSTDTC, MHENDTC)


# --- MH-specific validation checks --------------------------------------------

mh_checks <- function(mh_df, dm_ref) {
  checks <- list()

  # MH1: MHSTDTC < RFSTDTC for all rows (MH events precede study entry)
  date_check <- mh_df %>%
    dplyr::left_join(dplyr::select(dm_ref, USUBJID, RFSTDTC), by = "USUBJID") %>%
    dplyr::filter(!is.na(MHSTDTC)) %>%
    dplyr::filter(as.Date(MHSTDTC) >= as.Date(RFSTDTC))

  if (nrow(date_check) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "MH1",
      description = "All MHSTDTC must be before RFSTDTC",
      result = "FAIL",
      detail = sprintf("%d row(s) have MHSTDTC >= RFSTDTC", nrow(date_check))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "MH1",
      description = "All MHSTDTC must be before RFSTDTC",
      result = "PASS",
      detail = ""
    )
  }

  # MH2: No NA in MHTERM
  if (anyNA(mh_df$MHTERM)) {
    na_count <- sum(is.na(mh_df$MHTERM))
    checks[[length(checks) + 1]] <- list(
      check_id = "MH2",
      description = "MHTERM must not contain NA",
      result = "FAIL",
      detail = sprintf("%d NA value(s) in MHTERM", na_count)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "MH2",
      description = "MHTERM must not contain NA",
      result = "PASS",
      detail = ""
    )
  }

  # MH3: Every subject has at least one CANCER DIAGNOSIS record
  cancer_dx_subjects <- mh_df %>%
    dplyr::filter(MHCAT == "CANCER DIAGNOSIS") %>%
    dplyr::pull(USUBJID) %>%
    unique()

  all_subjects <- unique(mh_df$USUBJID)
  missing_subjects <- setdiff(all_subjects, cancer_dx_subjects)

  if (length(missing_subjects) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "MH3",
      description = "Every subject has at least one CANCER DIAGNOSIS record",
      result = "FAIL",
      detail = sprintf("%d subject(s) missing CANCER DIAGNOSIS: %s",
                      length(missing_subjects),
                      paste(head(missing_subjects, 3), collapse = ", "))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "MH3",
      description = "Every subject has at least one CANCER DIAGNOSIS record",
      result = "PASS",
      detail = ""
    )
  }

  checks
}

# --- Validate -----------------------------------------------------------------

validation_result <- validate_sdtm_domain(
  domain_df = mh,
  domain_code = "MH",
  dm_ref = dm,
  expected_rows = c(80, 200),
  ct_reference = NULL,  # No CT validation for MH in this wave
  domain_checks = mh_checks
)

message(validation_result$summary)

# --- Log result ---------------------------------------------------------------

log_sdtm_result(
  domain_code = "MH",
  wave = 1,
  row_count = nrow(mh),
  col_count = ncol(mh),
  validation_result = validation_result,
  notes = c(
    sprintf("Records per subject — min: %d, max: %d, median: %.1f",
            min(table(mh$USUBJID)),
            max(table(mh$USUBJID)),
            median(table(mh$USUBJID)))
  )
)


# --- XPT export ---------------------------------------------------------------

mh_meta <- tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "MHSEQ",
    "MHTERM", "MHDECOD", "MHCAT", "MHSTDTC", "MHENDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Reported Term for the Medical History",
    "Dictionary-Derived Term",
    "Category for Medical History",
    "Start Date/Time of Medical History Event",
    "End Date/Time of Medical History Event"
  ),
  type = c(
    "character", "character", "character", "numeric",
    "character", "character", "character", "character", "character"
  )
)

mh_xpt <- mh %>%
  xportr_label(mh_meta, domain = "MH") %>%
  xportr_type(mh_meta, domain = "MH")

output_dir <- "output-data/sdtm"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

saveRDS(mh_xpt, file.path(output_dir, "mh.rds"))
haven::write_xpt(mh_xpt, path = file.path(output_dir, "mh.xpt"))

message("✓ MH domain written to: ", file.path(output_dir, "mh.xpt"))
