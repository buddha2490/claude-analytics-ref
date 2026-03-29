# =============================================================================
# Program: projects/exelixis-sap/programs/adam_adae.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADAE — Adverse Events Analysis Dataset
# Author: r-clinical-programmer agent
# Date: 2026-03-29
#
# Source Domains:
#   - AE: USUBJID, AESEQ, AETERM, AEDECOD, AESOC, AESTDTC, AEENDTC, AESER,
#         AEREL, AESEV, AEACN
#   - HO: USUBJID, HOHNKID, HOSTDTC, HOENDTC (hospitalization linked to AE)
#   - ADSL: USUBJID, TRTSDT, TRTEDT (treatment dates for TRTEMFL)
#
# CDISC References:
#   - ADaM-IG v1.3 Occurrence Data Structure
#   - Treatment-emergent: AESTDT >= TRTSDT per plan Section 4.5
#   - Flag convention: Y/blank per plan Section 5 Global Conventions (R7)
#
# Dependencies:
#   - ADSL (projects/exelixis-sap/output-data/adam/adsl.xpt) — required for TRTSDT
#
# Notes:
#   - HO linkage via HOHNKID = as.character(AESEQ) per R6 decision
#   - See projects/exelixis-sap/artifacts/Open-questions-cdisc.md
# =============================================================================

# --- Load packages -----------------------------------------------------------
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------
ae <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ae.xpt")
ho <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ho.xpt")
adsl <- haven::read_xpt("projects/exelixis-sap/output-data/adam/adsl.xpt")
dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")

# --- Data Contract Validation (Step 4 Checkpoint) ----------------------------
message("\n=== Data Contract Validation ===")

# List all columns in source domains
message("AE columns: ", paste(names(ae), collapse = ", "))
message("HO columns: ", paste(names(ho), collapse = ", "))
message("ADSL columns: ", paste(names(adsl), collapse = ", "))

# Expected variables from plan Section 4.5
# NOTE: Plan lists AEBODSYS and AEOUT, but actual data has AESOC (System Organ Class)
#       and no AEOUT variable. Using AESOC as the body system variable.
plan_vars_ae <- c("USUBJID", "AETERM", "AEDECOD", "AESOC", "AESTDTC", "AEENDTC",
                  "AESER", "AEREL", "AESEV", "AEACN", "AESEQ")
actual_vars_ae <- names(ae)

missing_vars_ae <- setdiff(plan_vars_ae, actual_vars_ae)
extra_vars_ae <- setdiff(actual_vars_ae, plan_vars_ae)

if (length(missing_vars_ae) > 0) {
  stop(
    "Plan lists AE variables not found in data: ", paste(missing_vars_ae, collapse = ", "),
    "\nActual AE variables: ", paste(actual_vars_ae, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}

message("✓ Data contract OK (AE): All ", length(plan_vars_ae), " expected variables found")

# Validate HO
plan_vars_ho <- c("USUBJID", "HOTERM", "HOSTDTC", "HOENDTC", "HOSEQ", "HOHNKID")
actual_vars_ho <- names(ho)

missing_vars_ho <- setdiff(plan_vars_ho, actual_vars_ho)

if (length(missing_vars_ho) > 0) {
  stop(
    "Plan lists HO variables not found in data: ", paste(missing_vars_ho, collapse = ", "),
    "\nActual HO variables: ", paste(actual_vars_ho, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}

message("✓ Data contract OK (HO): All ", length(plan_vars_ho), " expected variables found")

# Validate ADSL
plan_vars_adsl <- c("USUBJID", "TRTSDT", "TRTEDT", "STUDYID")
actual_vars_adsl <- names(adsl)

missing_vars_adsl <- setdiff(plan_vars_adsl, actual_vars_adsl)

if (length(missing_vars_adsl) > 0) {
  stop(
    "Plan lists ADSL variables not found in data: ", paste(missing_vars_adsl, collapse = ", "),
    "\nActual ADSL variables: ", paste(actual_vars_adsl, collapse = ", "),
    "\nREVISIT: Update plan or check ADSL derivation",
    call. = FALSE
  )
}

message("✓ Data contract OK (ADSL): All ", length(plan_vars_adsl), " expected variables found")
message("Data contract validation complete.\n")

# --- Derive base variables from AE -------------------------------------------
# Start with AE domain, add numeric dates and study days

adae <- ae %>%
  # Convert dates to numeric
  mutate(
    AESTDT = as.numeric(as.Date(AESTDTC)),
    AEENDT = if_else(!is.na(AEENDTC),
                     as.numeric(as.Date(AEENDTC)),
                     NA_real_)
  ) %>%
  # Merge ADSL treatment dates
  left_join(
    adsl %>% dplyr::select(USUBJID, TRTSDT, TRTEDT),
    by = "USUBJID"
  ) %>%
  # Derive study days relative to treatment start
  # REVISIT: Study day calculation per CDISC (no day zero)
  mutate(
    ASTDY = case_when(
      is.na(AESTDT) ~ NA_real_,
      AESTDT >= TRTSDT ~ AESTDT - TRTSDT + 1,
      TRUE ~ AESTDT - TRTSDT
    ),
    AENDY = case_when(
      is.na(AEENDT) ~ NA_real_,
      AEENDT >= TRTSDT ~ AEENDT - TRTSDT + 1,
      TRUE ~ AEENDT - TRTSDT
    )
  ) %>%
  # Derive AE duration in days
  mutate(
    AEDUR = if_else(!is.na(AEENDT) & !is.na(AESTDT),
                    AEENDT - AESTDT + 1,
                    NA_real_)
  )

# --- Derive treatment-emergent flag ------------------------------------------
# TRTEMFL = 'Y' if AESTDT >= TRTSDT
# Per plan Section 4.5, line 351: treatment-emergent defined as on or after treatment start
# Flag convention: Y/blank (not Y/N) per plan Section 5 Global Conventions

adae <- adae %>%
  mutate(
    TRTEMFL = if_else(
      !is.na(AESTDT) & !is.na(TRTSDT) & AESTDT >= TRTSDT,
      "Y",
      NA_character_
    )
  )

# --- Derive severity numeric coding -------------------------------------------
# AESEVN: 1=MILD, 2=MODERATE, 3=SEVERE, 4=LIFE THREATENING, 5=DEATH

adae <- adae %>%
  mutate(
    AESEVN = case_when(
      toupper(AESEV) == "MILD" ~ 1L,
      toupper(AESEV) == "MODERATE" ~ 2L,
      toupper(AESEV) == "SEVERE" ~ 3L,
      toupper(AESEV) == "LIFE THREATENING" ~ 4L,
      toupper(AESEV) == "DEATH" ~ 5L,
      TRUE ~ NA_integer_
    )
  )

# --- Merge hospitalization data -----------------------------------------------
# REVISIT: AE-HO linkage via HOHNKID = AESEQ per R6 decision
# See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R6
# Join on USUBJID + HO.HOHNKID == as.character(AE.AESEQ)

adae <- adae %>%
  mutate(AESEQ_C = as.character(AESEQ)) %>%
  left_join(
    ho %>% dplyr::select(USUBJID, HOHNKID, HOSTDTC, HOENDTC),
    by = c("USUBJID", "AESEQ_C" = "HOHNKID")
  ) %>%
  # Derive hospitalization duration
  mutate(
    HOSPDUR = if_else(
      !is.na(HOSTDTC) & !is.na(HOENDTC),
      as.numeric(as.Date(HOENDTC) - as.Date(HOSTDTC)) + 1,
      NA_real_
    )
  ) %>%
  dplyr::select(-AESEQ_C)  # Remove temporary join key

# --- Finalize variable selection and ordering ---------------------------------
# Per plan Section 4.5: 20 variables expected in ADAE
adae <- adae %>%
  dplyr::select(
    STUDYID, USUBJID, AESEQ,
    AETERM, AEDECOD, AESOC,
    AESTDTC, AEENDTC, AESTDT, AEENDT,
    ASTDY, AENDY, AEDUR,
    AESER, AEREL, AESEV, AESEVN,
    AEACN,
    TRTEMFL, HOSPDUR
  )

# --- Apply variable labels and types ------------------------------------------
adae_meta <- tibble::tibble(
  variable = c(
    "STUDYID", "USUBJID", "AESEQ",
    "AETERM", "AEDECOD", "AESOC",
    "AESTDTC", "AEENDTC", "AESTDT", "AEENDT",
    "ASTDY", "AENDY", "AEDUR",
    "AESER", "AEREL", "AESEV", "AESEVN",
    "AEACN",
    "TRTEMFL", "HOSPDUR"
  ),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Adverse Event Sequence Number",
    "Reported Term for the Adverse Event",
    "Dictionary-Derived Term",
    "Primary System Organ Class",
    "Start Date/Time of Adverse Event",
    "End Date/Time of Adverse Event",
    "Analysis Start Date",
    "Analysis End Date",
    "Analysis Start Relative Day",
    "Analysis End Relative Day",
    "Adverse Event Duration (Days)",
    "Serious Event",
    "Relationship to Study Treatment",
    "Severity/Intensity",
    "Severity/Intensity Numeric",
    "Action Taken with Study Treatment",
    "Treatment Emergent Flag",
    "Hospitalization Duration (Days)"
  ),
  type = c(
    "character", "character", "integer",
    "character", "character", "character",
    "character", "character", "numeric", "numeric",
    "numeric", "numeric", "numeric",
    "character", "character", "character", "integer",
    "character",
    "character", "numeric"
  )
)

adae <- adae %>%
  xportr::xportr_label(metadata = adae_meta, domain = "ADAE") %>%
  xportr::xportr_type(metadata = adae_meta, domain = "ADAE")

# --- Validation checks --------------------------------------------------------
message("\n=== ADAE Validation ===")
message("Row count: ", nrow(adae))
message("Subject count: ", n_distinct(adae$USUBJID))

# Check key variable completeness
key_vars <- c("USUBJID", "AESEQ", "AETERM", "AESTDTC")
missing_counts <- sapply(adae[, key_vars], function(x) sum(is.na(x)))
message("\nMissing counts for key variables:")
print(missing_counts)

# Check TRTEMFL distribution
message("\nTRTEMFL distribution:")
print(table(adae$TRTEMFL, useNA = "ifany"))

# Check AESEVN distribution
message("\nAESEVN distribution:")
print(table(adae$AESEVN, useNA = "ifany"))

# Check HOSPDUR summary
message("\nHOSPDUR summary (for AEs with hospitalization):")
print(summary(adae$HOSPDUR[!is.na(adae$HOSPDUR)]))

# CDISC compliance: unique keys (USUBJID + AESEQ)
if (any(duplicated(adae[, c("USUBJID", "AESEQ")]))) {
  stop("BLOCKING: Duplicate USUBJID + AESEQ found in ADAE")
}

# Cross-domain consistency: all subjects in DM
if (!all(adae$USUBJID %in% dm$USUBJID)) {
  stop("BLOCKING: ADAE contains subjects not in DM")
}

message("\nValidation checks passed.")

# --- Save dataset -------------------------------------------------------------
output_dir <- "projects/exelixis-sap/output-data/adam"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

haven::write_xpt(adae, file.path(output_dir, "adae.xpt"))
saveRDS(adae, file.path(output_dir, "adae.rds"))
message("\nADAE saved to: ", file.path(output_dir, "adae.xpt"))
message("ADAE saved to: ", file.path(output_dir, "adae.rds"))
