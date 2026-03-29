# ============================================================================#
# Program: adam_adbs.R
# Purpose: Create ADBS (Biospecimen) ADaM dataset for NPM-008
# Date: 2026-03-28
# Author: r-clinical-programmer agent
# Description: Low complexity dataset - direct mapping from BS domain with
#              standard date conversions and study day derivation
# ============================================================================#

# --- Load packages ----------------------------------------------------------
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data -------------------------------------------------------
# Read from XPT files only (not .rds) per plan Section 5 Global Conventions
dm <- read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
bs <- read_xpt("projects/exelixis-sap/output-data/sdtm/bs.xpt")

message("Loaded DM: ", nrow(dm), " subjects")
message("Loaded BS: ", nrow(bs), " records")

# --- Data Contract Validation -----------------------------------------------
# Checkpoint: Verify all required variables exist before derivations
message("\n--- Data Structure Exploration ---")
message("BS columns: ", paste(names(bs), collapse=", "))
message("DM columns: ", paste(names(dm), collapse=", "))

# Expected variables from plan Section 4.2
plan_vars_bs <- c("USUBJID", "BSDTC", "BSMETHOD", "BSANTREG", "BSHIST", "BSSPEC")
plan_vars_dm <- c("USUBJID", "STUDYID", "RFSTDTC")

actual_vars_bs <- names(bs)
actual_vars_dm <- names(dm)

missing_vars_bs <- setdiff(plan_vars_bs, actual_vars_bs)
missing_vars_dm <- setdiff(plan_vars_dm, actual_vars_dm)

if (length(missing_vars_bs) > 0) {
  stop(
    "Plan lists variables not found in BS: ", paste(missing_vars_bs, collapse=", "),
    "\nActual BS variables: ", paste(actual_vars_bs, collapse=", "),
    call. = FALSE
  )
}

if (length(missing_vars_dm) > 0) {
  stop(
    "Plan lists variables not found in DM: ", paste(missing_vars_dm, collapse=", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse=", "),
    call. = FALSE
  )
}

message("✓ Data contract OK (BS): All ", length(plan_vars_bs), " expected variables found")
message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# --- Select and merge base variables ----------------------------------------
# Start with BS domain and select required variables
adbs <- bs %>%
  select(
    USUBJID,
    BSDTC,
    BSMETHOD,
    BSANTREG,
    BSHIST,
    BSSPEC
  )

# Merge STUDYID and RFSTDTC from DM
adbs <- adbs %>%
  left_join(
    dm %>% select(USUBJID, STUDYID, RFSTDTC),
    by = "USUBJID"
  )

# --- Derive numeric date and study day --------------------------------------
# Convert character ISO 8601 date to numeric SAS date
adbs <- adbs %>%
  mutate(
    # Numeric date (days since 1960-01-01 per SAS convention)
    BSDT = as.numeric(as.Date(BSDTC)),

    # Study day per CDISC formula (no day zero)
    # ADY = date - RFSTDTC + 1 if date >= RFSTDTC
    # ADY = date - RFSTDTC if date < RFSTDTC
    RFSTDT = as.numeric(as.Date(RFSTDTC)),
    ADY = case_when(
      is.na(BSDT) | is.na(RFSTDT) ~ NA_real_,
      BSDT >= RFSTDT ~ BSDT - RFSTDT + 1,
      TRUE ~ BSDT - RFSTDT
    )
  ) %>%
  select(-RFSTDT)  # Remove temporary RFSTDT calculation variable

# --- Rename variables to ADaM conventions -----------------------------------
# Per plan Section 4.2: BSMETHOD -> BSTRT, BSANTREG -> BSLOC
adbs <- adbs %>%
  rename(
    BSTRT = BSMETHOD,   # Biopsy method (treatment/method)
    BSLOC = BSANTREG    # Anatomical region (location)
  )

# --- Reorder columns --------------------------------------------------------
# Standard ADaM column order: identifiers, dates, numeric dates, derivations
adbs <- adbs %>%
  select(
    STUDYID,
    USUBJID,
    BSDTC,
    BSDT,
    BSTRT,
    BSLOC,
    BSHIST,
    BSSPEC,
    ADY
  )

# --- Apply variable labels --------------------------------------------------
# Create metadata frame for xportr
adbs_meta <- tibble::tibble(
  variable = c(
    "STUDYID",
    "USUBJID",
    "BSDTC",
    "BSDT",
    "BSTRT",
    "BSLOC",
    "BSHIST",
    "BSSPEC",
    "ADY"
  ),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Biospecimen Collection Date",
    "Biospecimen Collection Date (Numeric)",
    "Biospecimen Collection Method",
    "Biospecimen Anatomical Location",
    "Histology Result",
    "Specimen Type",
    "Analysis Relative Day"
  ),
  type = c(
    "character",
    "character",
    "character",
    "numeric",
    "character",
    "character",
    "character",
    "character",
    "numeric"
  )
)

# Apply labels and types
adbs <- adbs %>%
  xportr_label(metadata = adbs_meta, domain = "ADBS") %>%
  xportr_type(metadata = adbs_meta, domain = "ADBS")

# --- Validation checks ------------------------------------------------------
message("\n--- Validation Checks ---")

# Row and subject counts
message("ADBS row count: ", nrow(adbs))
message("ADBS subject count: ", n_distinct(adbs$USUBJID))
message("Source BS subject count: ", n_distinct(bs$USUBJID))

# Key variable completeness
key_vars <- c("STUDYID", "USUBJID", "BSDTC", "BSDT")
na_counts <- sapply(adbs[, key_vars], function(x) sum(is.na(x)))
message("\nKey variable NA counts:")
for (i in seq_along(na_counts)) {
  message("  ", names(na_counts)[i], ": ", na_counts[i])
}

# CDISC compliance: all subjects must exist in DM
subjects_not_in_dm <- setdiff(adbs$USUBJID, dm$USUBJID)
if (length(subjects_not_in_dm) > 0) {
  warning(
    "Found ", length(subjects_not_in_dm),
    " subjects in ADBS not in DM: ",
    paste(head(subjects_not_in_dm), collapse=", "),
    call. = FALSE
  )
} else {
  message("✓ All ADBS subjects exist in DM")
}

# Check for unexpected duplicates (multiple specimens per subject is expected)
message("\nSpecimen distribution:")
specimen_counts <- adbs %>%
  count(USUBJID) %>%
  count(n, name = "n_subjects")
print(specimen_counts)

# Date range validation
message("\nDate ranges:")
message("  BSDTC range: ", min(adbs$BSDTC, na.rm=TRUE), " to ",
        max(adbs$BSDTC, na.rm=TRUE))
message("  ADY range: ", min(adbs$ADY, na.rm=TRUE), " to ",
        max(adbs$ADY, na.rm=TRUE))

message("\n✓ Validation complete")

# --- Save dataset -----------------------------------------------------------
# Write to XPT format
write_xpt(adbs, "projects/exelixis-sap/output-data/adam/adbs.xpt")
saveRDS(adbs, "projects/exelixis-sap/output-data/adam/adbs.rds")

message("\n✓ ADBS dataset saved to: projects/exelixis-sap/output-data/adam/adbs.xpt")
message("✓ ADBS dataset saved to: projects/exelixis-sap/output-data/adam/adbs.rds")
message("Final dimensions: ", nrow(adbs), " rows × ", ncol(adbs), " columns")
