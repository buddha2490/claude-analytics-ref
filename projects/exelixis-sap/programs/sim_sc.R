# =============================================================================
# Program:   sim_sc.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Domain:    SC — Subject Characteristics
# Purpose:   Simulate SC domain with 3 records per subject: education,
#            marital status, and annual household income. Writes sc.xpt.
# Seed:      set.seed(46) — domain offset 4 from base seed 42
# Author:    r-clinical-programmer agent
# Date:      2026-03-27
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

# --- Source validation functions ----------------------------------------------

source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")


# --- Load DM spine ------------------------------------------------------------

dm <- readRDS("output-data/sdtm/dm.rds")

# Retain identifiers and reference date for SC derivation
dm_spine <- dm %>%
  dplyr::select(USUBJID, RFICDTC, RFSTDTC)


# --- Constants ----------------------------------------------------------------

STUDYID <- "NPM008"

set.seed(46)


# --- Per-subject sampling -----------------------------------------------------

# Define test definitions as a named list for clarity
sc_tests <- list(
  list(
    testcd = "EDUC",
    test   = "Highest level of education completed",
    values = c(
      "Did not graduate High School",
      "Graduated High School",
      "Attended College or Technical School",
      "Graduated from College or Technical School",
      "Graduate Degree"
    ),
    probs  = c(0.10, 0.25, 0.25, 0.25, 0.15)
  ),
  list(
    testcd = "MARISTAT",
    test   = "Marital status",
    values = c(
      "Married or Domestic Partner",
      "Single",
      "Divorced",
      "Widowed",
      "Separated",
      "Unknown"
    ),
    probs  = c(0.50, 0.15, 0.15, 0.12, 0.03, 0.05)
  ),
  list(
    testcd = "INCOME",
    test   = "Annual household income",
    values = c(
      "Less than $25,000",
      "$25,000 to less than $50,000",
      "$50,000 to less than $75,000",
      "$75,000 to less than $100,000",
      "$100,000 or more",
      "Prefer not to answer",
      "Unknown"
    ),
    probs  = c(0.15, 0.20, 0.20, 0.15, 0.20, 0.05, 0.05)
  )
)

# Generate one row per subject per test using pmap
# Outer loop: each test definition produces one column of responses
sc_long <- pmap_dfr(
  list(
    testcd = map_chr(sc_tests, "testcd"),
    test   = map_chr(sc_tests, "test"),
    vals   = map(sc_tests, "values"),
    probs  = map(sc_tests, "probs"),
    seq_n  = list(1L, 2L, 3L)
  ),
  function(testcd, test, vals, probs, seq_n) {
    # Sample one value per subject
    dm_spine %>%
      dplyr::mutate(
        STUDYID  = STUDYID,
        DOMAIN   = "SC",
        SCSEQ    = seq_n,
        SCTESTCD = testcd,
        SCTEST   = test,
        SCORRES  = sample(vals, n(), replace = TRUE, prob = probs),
        SCDTC    = RFICDTC
      )
  }
) %>%
  # Sort by subject then sequence to give canonical ordering
  dplyr::arrange(USUBJID, SCSEQ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, SCSEQ,
    SCTESTCD, SCTEST, SCORRES, SCDTC
  )


# --- Domain-specific validation checks ----------------------------------------

sc_domain_checks <- function(domain_df, dm_ref) {
  checks <- list()

  # SC1: Each subject has exactly 3 records (EDUC, MARISTAT, INCOME)
  sc_per_subj <- domain_df %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarize(n_records = dplyr::n(), .groups = "drop")

  if (any(sc_per_subj$n_records != 3)) {
    bad_subj <- sc_per_subj %>%
      dplyr::filter(n_records != 3) %>%
      dplyr::pull(USUBJID)
    checks[[length(checks) + 1]] <- list(
      check_id = "SC1",
      description = "Each subject has exactly 3 records (EDUC, MARISTAT, INCOME)",
      result = "FAIL",
      detail = sprintf("%d subject(s) with != 3 records: %s",
                      length(bad_subj),
                      paste(head(bad_subj, 3), collapse = ", "))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "SC1",
      description = "Each subject has exactly 3 records (EDUC, MARISTAT, INCOME)",
      result = "PASS",
      detail = ""
    )
  }

  # SC2: SCDTC is consent date (RFICDTC) and before RFSTDTC
  if ("SCDTC" %in% names(domain_df) && "USUBJID" %in% names(domain_df) &&
      "RFICDTC" %in% names(dm_ref) && "RFSTDTC" %in% names(dm_ref)) {

    dm_dates <- dm_ref %>%
      dplyr::select(USUBJID, RFICDTC, RFSTDTC)

    sc_dates <- domain_df %>%
      dplyr::select(USUBJID, SCDTC) %>%
      dplyr::distinct() %>%
      dplyr::left_join(dm_dates, by = "USUBJID")

    # Check SCDTC equals RFICDTC
    scdtc_mismatch <- sc_dates %>%
      dplyr::filter(SCDTC != RFICDTC)

    # Check SCDTC before RFSTDTC
    scdtc_after_rf <- sc_dates %>%
      dplyr::filter(!is.na(SCDTC), !is.na(RFSTDTC), SCDTC >= RFSTDTC)

    if (nrow(scdtc_mismatch) > 0) {
      checks[[length(checks) + 1]] <- list(
        check_id = "SC2",
        description = "SCDTC equals RFICDTC (consent date) and is before RFSTDTC",
        result = "FAIL",
        detail = sprintf("%d subject(s) where SCDTC != RFICDTC",
                        nrow(scdtc_mismatch))
      )
    } else if (nrow(scdtc_after_rf) > 0) {
      checks[[length(checks) + 1]] <- list(
        check_id = "SC2",
        description = "SCDTC equals RFICDTC (consent date) and is before RFSTDTC",
        result = "FAIL",
        detail = sprintf("%d subject(s) where SCDTC >= RFSTDTC",
                        nrow(scdtc_after_rf))
      )
    } else {
      checks[[length(checks) + 1]] <- list(
        check_id = "SC2",
        description = "SCDTC equals RFICDTC (consent date) and is before RFSTDTC",
        result = "PASS",
        detail = ""
      )
    }
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "SC2",
      description = "SCDTC equals RFICDTC (consent date) and is before RFSTDTC",
      result = "FAIL",
      detail = "Required date columns not found"
    )
  }

  # SC3: All three required SCTESTCD values present for each subject
  required_testcds <- c("EDUC", "MARISTAT", "INCOME")

  testcd_check <- domain_df %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarize(
      testcds = list(sort(unique(SCTESTCD))),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      has_all = purrr::map_lgl(testcds, ~all(required_testcds %in% .x))
    )

  missing_testcd <- testcd_check %>%
    dplyr::filter(!has_all)

  if (nrow(missing_testcd) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "SC3",
      description = "All subjects have EDUC, MARISTAT, and INCOME records",
      result = "FAIL",
      detail = sprintf("%d subject(s) missing one or more SCTESTCD values",
                      nrow(missing_testcd))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "SC3",
      description = "All subjects have EDUC, MARISTAT, and INCOME records",
      result = "PASS",
      detail = ""
    )
  }

  checks
}


# --- Validate SDTM domain -----------------------------------------------------

# Load CT reference if available
ct_ref_path <- "output-data/sdtm/ct_reference.rds"
ct_reference <- if (file.exists(ct_ref_path)) {
  readRDS(ct_ref_path)
} else {
  NULL
}

# Run validation
validation_result <- validate_sdtm_domain(
  domain_df = sc_long,
  domain_code = "SC",
  dm_ref = dm,
  expected_rows = c(120, 120),  # Exact: 40 subjects × 3 records
  ct_reference = ct_reference,
  domain_checks = sc_domain_checks
)

message("\n", validation_result$summary)


# --- XPT export ---------------------------------------------------------------

# Variable metadata for xportr labelling and typing
sc_meta <- tibble::tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "SCSEQ",
    "SCTESTCD", "SCTEST", "SCORRES", "SCDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Subject Characteristic Short Name",
    "Subject Characteristic",
    "Result or Finding in Original Units",
    "Date/Time of Collection"
  ),
  type = c(
    "character", "character", "character", "numeric",
    "character", "character", "character", "character"
  ),
  # SAS lengths: 8 for numeric; 200 for character (covers longest SCORRES values)
  length = c(200L, 200L, 200L, 8L, 200L, 200L, 200L, 200L)
)

sc_xpt <- sc_long %>%
  xportr_label(sc_meta, domain = "SC") %>%
  xportr_type(sc_meta, domain = "SC") %>%
  xportr_length(sc_meta, domain = "SC")

# Write XPT
saveRDS(sc_xpt, "output-data/sdtm/sc.rds")
haven::write_xpt(sc_xpt, path = "output-data/sdtm/sc.xpt")


# --- Log validation result ----------------------------------------------------

log_sdtm_result(
  domain_code = "SC",
  wave = 1,
  row_count = nrow(sc_xpt),
  col_count = ncol(sc_xpt),
  validation_result = validation_result,
  notes = c(
    "3 records per subject: EDUC, MARISTAT, INCOME",
    "SCDTC set to RFICDTC (consent date)"
  )
)


# --- Summary ------------------------------------------------------------------

message("\nSC simulation complete: ", nrow(sc_xpt), " records written to output-data/sdtm/sc.xpt")
message("Distinct USUBJID: ", dplyr::n_distinct(sc_xpt$USUBJID))
message("\nEDUC distribution:")
print(table(dplyr::filter(sc_xpt, SCTESTCD == "EDUC")$SCORRES))
message("\nMARISTAT distribution:")
print(table(dplyr::filter(sc_xpt, SCTESTCD == "MARISTAT")$SCORRES))
message("\nINCOME distribution:")
print(table(dplyr::filter(sc_xpt, SCTESTCD == "INCOME")$SCORRES))
