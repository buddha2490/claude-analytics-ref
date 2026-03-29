# =============================================================================
# Program:   sim_ie.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Domain:    IE — Inclusion/Exclusion Criteria
# Purpose:   Simulate the IE domain. 10 records per subject (5 inclusion +
#            5 exclusion criteria). All subjects meet all criteria (enrolled).
# Seed:      set.seed(44) — domain offset 2 from base seed 42
# Author:    r-clinical-programmer agent
# Date:      2026-03-27
# Updated:   2026-03-28 — Integrated validation functions
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

# Source validation functions
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

set.seed(44)


# --- Constants ---------------------------------------------------------------

STUDYID    <- "NPM008"
OUTPUT_DIR <- "output-data/sdtm"
WAVE       <- 1L

# Inclusion/exclusion criteria lookup table
ie_criteria <- tribble(
  ~IETESTCD, ~IETEST,                                                                         ~IECAT,
  "IC01",    "Pathologically confirmed locally advanced or metastatic NSCLC",                 "INCLUSION",
  "IC02",    "Radiographically measurable disease",                                           "INCLUSION",
  "IC03",    "ECOG performance score 0 or 1",                                                 "INCLUSION",
  "IC04",    "Received prior systemic anticancer therapy",                                    "INCLUSION",
  "IC05",    "Age 18 or older",                                                               "INCLUSION",
  "EC01",    "Radiation therapy within 14 days prior to index date",                          "EXCLUSION",
  "EC02",    "Untreated brain metastases",                                                    "EXCLUSION",
  "EC03",    "Severe liver disease per Charlson Comorbidity Index",                           "EXCLUSION",
  "EC04",    "Surgery in 4 weeks prior to index date",                                        "EXCLUSION",
  "EC05",    "Diagnosis of another malignancy in 2 years prior to index date",                "EXCLUSION"
)


# --- Read DM spine and CT reference ------------------------------------------

dm <- readRDS(file.path(OUTPUT_DIR, "dm.rds"))
ct_reference <- readRDS(file.path(OUTPUT_DIR, "ct_reference.rds"))


# --- Build IE dataset --------------------------------------------------------

# Cross-join each subject with the 10 criteria, then derive all variables
ie <- dm %>%
  dplyr::select(USUBJID, RFICDTC) %>%
  # One row per subject per criterion
  cross_join(ie_criteria) %>%
  # Sort for consistent IESEQ assignment: by subject then criterion order
  arrange(USUBJID, match(IETESTCD, ie_criteria$IETESTCD)) %>%
  group_by(USUBJID) %>%
  mutate(
    IESEQ = row_number()
  ) %>%
  ungroup() %>%
  mutate(
    STUDYID = STUDYID,
    DOMAIN  = "IE",
    # All subjects enrolled: inclusion met (YES), exclusion not met (NO)
    IEORRES = if_else(IECAT == "INCLUSION", "YES", "NO"),
    IESTRESC = IEORRES,
    # Date of collection = informed consent date from DM (already shifted)
    IEDTC = RFICDTC
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, IESEQ,
    IETESTCD, IETEST, IECAT,
    IEORRES, IESTRESC, IEDTC
  )


# --- Variable metadata for xportr --------------------------------------------

ie_meta <- tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "IESEQ",
    "IETESTCD", "IETEST", "IECAT",
    "IEORRES", "IESTRESC", "IEDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Incl/Excl Criterion Short Name",
    "Inclusion/Exclusion Criterion",
    "Incl/Excl Category",
    "I/E Criterion Original Result",
    "I/E Criterion Std Result",
    "Date of Collection"
  ),
  type = c(
    "character", "character", "character", "numeric",
    "character", "character", "character",
    "character", "character", "character"
  ),
  length = c(
    200L, 2L, 200L, NA_integer_,
    8L, 300L, 40L,
    8L, 8L, 20L
  )
)


# --- XPT export with validation ----------------------------------------------

ie_xpt <- ie %>%
  xportr_label(ie_meta, domain = "IE") %>%
  xportr_type(ie_meta, domain = "IE") %>%
  xportr_length(ie_meta, domain = "IE")

# Define IE-specific validation checks
ie_checks <- function(domain_df, dm_ref) {
  checks <- list()

  # IE1: 10 criteria per subject
  criteria_count <- domain_df %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
    dplyr::filter(n != 10)

  if (nrow(criteria_count) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE1",
      description = "10 criteria per subject (5 inclusion + 5 exclusion)",
      result = "FAIL",
      detail = sprintf("%d subject(s) have != 10 criteria", nrow(criteria_count))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE1",
      description = "10 criteria per subject (5 inclusion + 5 exclusion)",
      result = "PASS",
      detail = ""
    )
  }

  # IE2: IECAT valid (INCLUSION or EXCLUSION)
  invalid_iecat <- domain_df %>%
    dplyr::filter(!IECAT %in% c("INCLUSION", "EXCLUSION"))

  if (nrow(invalid_iecat) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE2",
      description = "IECAT must be INCLUSION or EXCLUSION",
      result = "FAIL",
      detail = sprintf("%d row(s) have invalid IECAT", nrow(invalid_iecat))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE2",
      description = "IECAT must be INCLUSION or EXCLUSION",
      result = "PASS",
      detail = ""
    )
  }

  # IE3: IEORRES consistent with IECAT
  ieorres_check <- domain_df %>%
    dplyr::filter(
      (IECAT == "INCLUSION" & IEORRES != "YES") |
      (IECAT == "EXCLUSION" & IEORRES != "NO")
    )

  if (nrow(ieorres_check) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE3",
      description = "IEORRES='YES' for inclusion, 'NO' for exclusion",
      result = "FAIL",
      detail = sprintf("%d row(s) have inconsistent IEORRES/IECAT", nrow(ieorres_check))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE3",
      description = "IEORRES='YES' for inclusion, 'NO' for exclusion",
      result = "PASS",
      detail = ""
    )
  }

  # IE4: No NA in IETESTCD
  if (anyNA(domain_df$IETESTCD)) {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE4",
      description = "No NA in IETESTCD",
      result = "FAIL",
      detail = sprintf("%d NA value(s) in IETESTCD", sum(is.na(domain_df$IETESTCD)))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "IE4",
      description = "No NA in IETESTCD",
      result = "PASS",
      detail = ""
    )
  }

  checks
}

# Run validation
message("\n--- IE Validation ---")
validation_result <- validate_sdtm_domain(
  domain_df = ie_xpt,
  domain_code = "IE",
  dm_ref = dm,
  expected_rows = c(400, 400),
  ct_reference = list(IECAT = ct_reference$IECAT),
  domain_checks = ie_checks
)

message(validation_result$summary)

# Log validation result
log_sdtm_result(
  domain_code = "IE",
  wave = WAVE,
  row_count = nrow(ie_xpt),
  col_count = ncol(ie_xpt),
  validation_result = validation_result,
  notes = c("10 criteria per subject: 5 inclusion + 5 exclusion",
            "All subjects meet eligibility (enrolled population)")
)

# Write output files
saveRDS(ie_xpt, file.path(OUTPUT_DIR, "ie.rds"))
haven::write_xpt(ie_xpt, path = file.path(OUTPUT_DIR, "ie.xpt"))

message("\nIE XPT written to: ", file.path(OUTPUT_DIR, "ie.xpt"))
message("IE RDS written to: ", file.path(OUTPUT_DIR, "ie.rds"))
message("IE simulation complete: ", nrow(ie_xpt), " records, ",
        dplyr::n_distinct(ie_xpt$USUBJID), " subjects.")
