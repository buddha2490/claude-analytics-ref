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


# --- Load DM spine ------------------------------------------------------------

dm <- readRDS("cohort/output-data/dm.rds")

# Retain only the identifiers needed for SC derivation
dm_spine <- dm %>%
  dplyr::select(USUBJID, RFICDTC)


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


# --- Validate structure -------------------------------------------------------

stopifnot(
  "SC must have exactly 120 rows (40 subjects x 3 tests)"  = nrow(sc_long) == 120L,
  "SC must have exactly 40 distinct USUBJID"               = dplyr::n_distinct(sc_long$USUBJID) == 40L,
  "Each subject must have exactly 3 records"               = all(table(sc_long$USUBJID) == 3L)
)


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
saveRDS(sc_xpt, "cohort/output-data/sdtm/sc.rds")
haven::write_xpt(sc_xpt, path = "cohort/output-data/sdtm/sc.xpt")


# --- Summary ------------------------------------------------------------------

message("SC simulation complete: ", nrow(sc_xpt), " records written to cohort/output-data/sdtm/sc.xpt")
message("Distinct USUBJID: ", dplyr::n_distinct(sc_xpt$USUBJID))
message("\nEDUC distribution:")
message(paste(capture.output(table(dplyr::filter(sc_xpt, SCTESTCD == "EDUC")$SCORRES)), collapse = "\n"))
message("\nMARISTAT distribution:")
message(paste(capture.output(table(dplyr::filter(sc_xpt, SCTESTCD == "MARISTAT")$SCORRES)), collapse = "\n"))
message("\nINCOME distribution:")
message(paste(capture.output(table(dplyr::filter(sc_xpt, SCTESTCD == "INCOME")$SCORRES)), collapse = "\n"))
