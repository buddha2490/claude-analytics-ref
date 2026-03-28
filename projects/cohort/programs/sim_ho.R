# =============================================================================
# sim_ho.R
# Study: NPM-008 / XB010-101
# Domain: HO — Healthcare Encounters (Hospitalizations)
# Description: Simulate one HO record per AE where AESHOSP == "Y".
#              Source: ae.rds filtered to hospitalized AEs.
# =============================================================================

library(tidyverse)
library(haven)

# set.seed: domain order 18, per project convention (seed = 42 + 18 = 60)
set.seed(60)

# --- Load inputs --------------------------------------------------------------

ae <- readRDS("cohort/output-data/ae.rds")
dm <- readRDS("cohort/output-data/dm.rds")

# --- Filter to hospitalized AEs ----------------------------------------------

ae_hosp <- ae %>%
  dplyr::filter(AESHOSP == "Y") %>%
  dplyr::select(USUBJID, AESEQ, AESTDTC)

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

ho <- ae_hosp %>%
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

attr(ho$STUDYID, "label") <- "Study Identifier"
attr(ho$DOMAIN,  "label") <- "Domain Abbreviation"
attr(ho$USUBJID, "label") <- "Unique Subject Identifier"
attr(ho$HOSEQ,   "label") <- "Sequence Number"
attr(ho$HOTERM,  "label") <- "Healthcare Encounter Term"
attr(ho$HOSTDTC, "label") <- "Start Date/Time of Encounter"
attr(ho$HOENDTC, "label") <- "End Date/Time of Encounter"
attr(ho$HOHNKID, "label") <- "Link to Related AE Sequence Number"

# --- Validation --------------------------------------------------------------

message("--- Validation ---")

# 1. Row count matches expected hospitalized AE records
n_expected <- sum(ae$AESHOSP == "Y", na.rm = TRUE)
stopifnot("Row count mismatch" = nrow(ho) == n_expected)
message("PASS nrow == ", n_expected)

# 2. All USUBJID exist in DM
missing_subj <- setdiff(ho$USUBJID, dm$USUBJID)
stopifnot("USUBJID not in DM" = length(missing_subj) == 0)
message("PASS all USUBJID in DM")

# 3. HOSEQ unique within USUBJID
dupes <- ho %>%
  dplyr::count(USUBJID, HOSEQ) %>%
  dplyr::filter(n > 1)
stopifnot("HOSEQ not unique per USUBJID" = nrow(dupes) == 0)
message("PASS HOSEQ unique per USUBJID")

# 4. HOSTDTC >= AESTDTC for all records
date_check <- ae_hosp %>%
  dplyr::select(USUBJID, AESEQ, AESTDTC, HOSTDTC) %>%
  dplyr::filter(as.Date(HOSTDTC) < as.Date(AESTDTC))
stopifnot("HOSTDTC precedes AESTDTC" = nrow(date_check) == 0)
message("PASS HOSTDTC >= AESTDTC for all records")

# 5. HOENDTC > HOSTDTC for all records
end_check <- ho %>%
  dplyr::filter(as.Date(HOENDTC) <= as.Date(HOSTDTC))
stopifnot("HOENDTC not after HOSTDTC" = nrow(end_check) == 0)
message("PASS HOENDTC > HOSTDTC for all records")

# 6. No missing values in key variables
key_vars <- c("STUDYID","DOMAIN","USUBJID","HOSEQ","HOTERM","HOSTDTC","HOENDTC","HOHNKID")
na_check <- ho %>%
  dplyr::select(dplyr::all_of(key_vars)) %>%
  dplyr::summarise(dplyr::across(dplyr::everything(), ~ sum(is.na(.)))) %>%
  tidyr::pivot_longer(dplyr::everything()) %>%
  dplyr::filter(value > 0)
stopifnot("Missing values in key variables" = nrow(na_check) == 0)
message("PASS no missing values in key variables")

# --- Preview -----------------------------------------------------------------

message("\n--- HO dataset preview ---")
print(ho)

# --- Write XPT ---------------------------------------------------------------

saveRDS(ho, "cohort/output-data/sdtm/ho.rds")
haven::write_xpt(ho, "cohort/output-data/sdtm/ho.xpt")
message("XPT written to: cohort/output-data/sdtm/ho.xpt")
