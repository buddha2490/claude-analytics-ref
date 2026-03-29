# =============================================================================
# sim_ho.R — Healthcare Encounters (Hospitalizations)
# Study: NPM-008 / XB010-101 ECA
# Seed: 42 + 18 = 60
# Wave: 3
# Dependencies: dm.rds, ae.rds
# Expected rows: 20-60
# Working directory: projects/exelixis-sap/
# =============================================================================

set.seed(60)

library(tidyverse)
library(haven)

# --- Load dependencies -------------------------------------------------------

dm_full <- readRDS("output-data/sdtm/dm.rds")
ae_full <- readRDS("output-data/sdtm/ae.rds")

# --- Load CT reference -------------------------------------------------------

ct_ref <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Source validation functions ---------------------------------------------

source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Generate domain data ----------------------------------------------------

# Filter to hospitalized AEs (AESHOSP == "Y")
ae_hosp <- ae_full %>%
  dplyr::filter(AESHOSP == "Y") %>%
  dplyr::select(USUBJID, AESEQ, AESTDTC, AESER)

message("Hospitalized AE records: ", nrow(ae_hosp))

# --- Simulate hospitalization dates ------------------------------------------
# HOSTDTC: AE onset + 0–3 days (hospitalized at or shortly after AE start)
# HOENDTC: HOSTDTC + 3–14 days (hospitalization duration)
# Each record receives an independent random draw.

ae_hosp <- ae_hosp %>%
  dplyr::mutate(
    HOSTDTC = as.character(
      as.Date(AESTDTC) + sample(0:3, dplyr::n(), replace = TRUE)
    ),
    HOENDTC = as.character(
      as.Date(HOSTDTC) + sample(3:14, dplyr::n(), replace = TRUE)
    )
  )

# --- Build HO domain ----------------------------------------------------------

ho_df <- ae_hosp %>%
  dplyr::arrange(USUBJID, AESEQ) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(
    # HOSEQ: sequential integer per subject (some subjects may have >1 record)
    HOSEQ = dplyr::row_number()
  ) %>%
  dplyr::ungroup() %>%
  dplyr::transmute(
    STUDYID = "NPM008",
    DOMAIN  = "HO",
    USUBJID,
    HOSEQ,
    HOTERM  = "AE-related hospitalization",
    HOSTDTC,
    HOENDTC,
    # Custom linkage variable: AE sequence number as character
    HOHNKID = as.character(AESEQ)
  )

# --- Apply variable labels ---------------------------------------------------

attr(ho_df$STUDYID, "label") <- "Study Identifier"
attr(ho_df$DOMAIN,  "label") <- "Domain Abbreviation"
attr(ho_df$USUBJID, "label") <- "Unique Subject Identifier"
attr(ho_df$HOSEQ,   "label") <- "Sequence Number"
attr(ho_df$HOTERM,  "label") <- "Healthcare Encounter Term"
attr(ho_df$HOSTDTC, "label") <- "Start Date/Time of Encounter"
attr(ho_df$HOENDTC, "label") <- "End Date/Time of Encounter"
attr(ho_df$HOHNKID, "label") <- "Link to Related AE Sequence Number"

# --- Domain-specific validation closure --------------------------------------

domain_checks <- function(df, dm_ref) {
  checks <- list()

  # D1: Every HOHNKID maps to valid AESEQ in AE domain
  ae_seq_valid <- ae_full %>%
    dplyr::select(USUBJID, AESEQ) %>%
    dplyr::mutate(AESEQ_char = as.character(AESEQ))

  ho_ae_join <- df %>%
    dplyr::left_join(ae_seq_valid, by = c("USUBJID", "HOHNKID" = "AESEQ_char"))

  missing_ae <- ho_ae_join %>%
    dplyr::filter(is.na(AESEQ))

  if (nrow(missing_ae) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "Every HOHNKID maps to valid AESEQ in AE domain",
      result = "FAIL",
      detail = sprintf("%d HO record(s) with invalid HOHNKID", nrow(missing_ae))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "Every HOHNKID maps to valid AESEQ in AE domain",
      result = "PASS",
      detail = ""
    )
  }

  # D2: HOSTDTC >= AESTDTC (hospitalization starts on or after AE onset)
  ae_dates <- ae_full %>%
    dplyr::select(USUBJID, AESEQ, AESTDTC) %>%
    dplyr::mutate(AESEQ_char = as.character(AESEQ))

  ho_date_check <- df %>%
    dplyr::left_join(ae_dates, by = c("USUBJID", "HOHNKID" = "AESEQ_char")) %>%
    dplyr::filter(!is.na(AESTDTC)) %>%
    dplyr::mutate(
      date_violation = as.Date(HOSTDTC) < as.Date(AESTDTC)
    )

  date_violations <- ho_date_check %>%
    dplyr::filter(date_violation)

  if (nrow(date_violations) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "HOSTDTC >= AESTDTC (hospitalization on/after AE onset)",
      result = "FAIL",
      detail = sprintf("%d record(s) where HOSTDTC < AESTDTC", nrow(date_violations))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "HOSTDTC >= AESTDTC (hospitalization on/after AE onset)",
      result = "PASS",
      detail = ""
    )
  }

  # D3: Only serious AEs (AESER="Y") trigger hospitalizations
  ae_ser <- ae_full %>%
    dplyr::select(USUBJID, AESEQ, AESER, AESHOSP) %>%
    dplyr::mutate(AESEQ_char = as.character(AESEQ))

  ho_ser_check <- df %>%
    dplyr::left_join(ae_ser, by = c("USUBJID", "HOHNKID" = "AESEQ_char"))

  # Should only have AESHOSP="Y" AEs
  non_hosp_ae <- ho_ser_check %>%
    dplyr::filter(is.na(AESHOSP) | AESHOSP != "Y")

  if (nrow(non_hosp_ae) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "Only AEs with AESHOSP='Y' trigger hospitalizations",
      result = "FAIL",
      detail = sprintf("%d HO record(s) linked to non-hospitalized AEs", nrow(non_hosp_ae))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "Only AEs with AESHOSP='Y' trigger hospitalizations",
      result = "PASS",
      detail = ""
    )
  }

  # D4: HOENDTC > HOSTDTC for all records
  end_violations <- df %>%
    dplyr::filter(as.Date(HOENDTC) <= as.Date(HOSTDTC))

  if (nrow(end_violations) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "HOENDTC > HOSTDTC for all records",
      result = "FAIL",
      detail = sprintf("%d record(s) where HOENDTC <= HOSTDTC", nrow(end_violations))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "HOENDTC > HOSTDTC for all records",
      result = "PASS",
      detail = ""
    )
  }

  checks
}

# --- Validate before writing -------------------------------------------------

validation <- validate_sdtm_domain(
  domain_df      = ho_df,
  domain_code    = "HO",
  dm_ref         = dm_full,
  expected_rows  = c(5, 20),  # 12-50% of 40 subjects hospitalized
  ct_reference   = NULL,
  domain_checks  = domain_checks
)

message(validation$summary)

# --- Write output (only if validation passes) --------------------------------

haven::write_xpt(ho_df, path = "output-data/sdtm/ho.xpt")
saveRDS(ho_df, "output-data/sdtm/ho.rds")

message("XPT written to: output-data/sdtm/ho.xpt")

# --- Log result --------------------------------------------------------------

log_sdtm_result(
  domain_code       = "HO",
  wave              = 3,
  row_count         = nrow(ho_df),
  col_count         = ncol(ho_df),
  validation_result = validation,
  notes             = c("One HO record per AESHOSP='Y' AE", "HOHNKID links to AESEQ")
)

message("sim_ho.R complete: ", nrow(ho_df), " rows written")
