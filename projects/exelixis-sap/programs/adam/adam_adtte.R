# =============================================================================
# Program: projects/exelixis-sap/programs/adam_adtte.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADTTE — Time to Event
# Author: r-clinical-programmer agent
# Date: 2026-03-29
#
# Source Domains:
#   - DM: USUBJID, DTHDTC, DTHFL, STUDYID
#   - RS: USUBJID, RSSTRESC, RSDTC, RSTESTCD
#   - ADSL: USUBJID, TRTSDT, TRTEDT, RFENDTC
#   - ADRS: USUBJID, PARAMCD, AVALC, ADT (for DOR derivation)
#
# Parameters:
#   - PFS: Progression-free survival (days to progression/death or censoring)
#   - OS: Overall survival (days to death or censoring)
#   - DOR: Duration of response (days from first response to progression/death)
#
# CDISC References:
#   - ADaM-IG v1.3 ADTTE structure
#   - Month conversion factor: days / 30.4375 (per SAP, see Open-questions R4)
#
# Dependencies:
#   - ADSL (projects/exelixis-sap/output-data/adam/adsl.xpt) — TRTSDT, TRTEDT, RFENDTC
#   - ADRS (projects/exelixis-sap/output-data/adam/adrs.xpt) — BOR and response dates for DOR
# =============================================================================

# --- Load packages -----------------------------------------------------------
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------
dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
rs <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/rs.xpt")
adsl <- haven::read_xpt("projects/exelixis-sap/output-data/adam/adsl.xpt")
adrs <- haven::read_xpt("projects/exelixis-sap/output-data/adam/adrs.xpt")

# --- Data Contract Validation Checkpoint -------------------------------------

message("\n=== Data Contract Validation Checkpoint ===")

# Expected variables from plan Section 4.6
plan_vars_dm <- c("USUBJID", "DTHDTC", "DTHFL", "STUDYID")
plan_vars_rs <- c("USUBJID", "RSSTRESC", "RSDTC", "RSTESTCD")
plan_vars_adsl <- c("USUBJID", "TRTSDT", "TRTEDT", "RFENDTC")
plan_vars_adrs <- c("USUBJID", "PARAMCD", "AVALC", "ADT")

actual_vars_dm <- names(dm)
actual_vars_rs <- names(rs)
actual_vars_adsl <- names(adsl)
actual_vars_adrs <- names(adrs)

# Validate DM
missing_vars_dm <- setdiff(plan_vars_dm, actual_vars_dm)
if (length(missing_vars_dm) > 0) {
  stop(
    "Plan lists variables not found in DM: ", paste(missing_vars_dm, collapse = ", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# Validate RS
missing_vars_rs <- setdiff(plan_vars_rs, actual_vars_rs)
if (length(missing_vars_rs) > 0) {
  stop(
    "Plan lists variables not found in RS: ", paste(missing_vars_rs, collapse = ", "),
    "\nActual RS variables: ", paste(actual_vars_rs, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (RS): All ", length(plan_vars_rs), " expected variables found")

# Validate ADSL
missing_vars_adsl <- setdiff(plan_vars_adsl, actual_vars_adsl)
if (length(missing_vars_adsl) > 0) {
  stop(
    "Plan lists variables not found in ADSL: ", paste(missing_vars_adsl, collapse = ", "),
    "\nActual ADSL variables: ", paste(actual_vars_adsl, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (ADSL): All ", length(plan_vars_adsl), " expected variables found")

# Validate ADRS
missing_vars_adrs <- setdiff(plan_vars_adrs, actual_vars_adrs)
if (length(missing_vars_adrs) > 0) {
  stop(
    "Plan lists variables not found in ADRS: ", paste(missing_vars_adrs, collapse = ", "),
    "\nActual ADRS variables: ", paste(actual_vars_adrs, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (ADRS): All ", length(plan_vars_adrs), " expected variables found")

# --- Data Exploration --------------------------------------------------------

message("\n=== Data Exploration ===")

# Check RS structure
message("\nRS domain structure:")
message("  Rows: ", nrow(rs))
message("  Subjects: ", n_distinct(rs$USUBJID))
message("  RSTESTCD values: ", paste(unique(rs$RSTESTCD), collapse = ", "))
message("  RSSTRESC values (first 10): ", paste(head(unique(rs$RSSTRESC), 10), collapse = ", "))

# Check DM death data
message("\nDM death data:")
message("  Subjects with DTHFL='Y': ", sum(dm$DTHFL == "Y", na.rm = TRUE))
message("  Subjects with non-missing DTHDTC: ", sum(!is.na(dm$DTHDTC)))

# Check ADRS records
message("\nADRS records:")
message("  Total records: ", nrow(adrs))
message("  PARAMCD values: ", paste(unique(adrs$PARAMCD), collapse = ", "))
adrs_resp_summary <- adrs %>%
  dplyr::filter(PARAMCD == "OVRLRESP", AVALC %in% c("CR", "PR")) %>%
  nrow()
message("  Subjects with CR/PR in OVRLRESP: ", adrs_resp_summary)

# Check ADSL TRTSDT completeness
message("\nADSL treatment dates:")
message("  Subjects: ", nrow(adsl))
message("  Missing TRTSDT: ", sum(is.na(adsl$TRTSDT)))
message("  Missing RFENDTC: ", sum(is.na(adsl$RFENDTC)))

# --- Derive progression date from RS -----------------------------------------
# Filter to RECIST overall response assessments (RSTESTCD = 'RECIST')
# NOTE: RSTESTCD = 'CLINRES' are clinician-stated BOR and not used for event derivation
rs_recist <- rs %>%
  dplyr::filter(RSTESTCD == "RECIST") %>%
  dplyr::mutate(RSDTC_DATE = as.Date(RSDTC))

# Identify first progression date per subject
progression <- rs_recist %>%
  dplyr::filter(RSSTRESC == "PD") %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    PROGDT = min(RSDTC_DATE, na.rm = TRUE),
    .groups = "drop"
  )

# --- Derive death date from DM -----------------------------------------------
death <- dm %>%
  dplyr::filter(DTHFL == "Y" & !is.na(DTHDTC)) %>%
  dplyr::mutate(DTHDT = as.Date(DTHDTC)) %>%
  dplyr::select(USUBJID, DTHDT)

# --- Derive last disease assessment date from RS -----------------------------
last_assessment <- rs_recist %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    LASTASDT = max(RSDTC_DATE, na.rm = TRUE),
    .groups = "drop"
  )

# --- Identify responders from ADRS -------------------------------------------
# For DOR, identify subjects who achieved CR or PR (from BOR parameter)
# and find their first confirmed response date
responders_bor <- adrs %>%
  dplyr::filter(PARAMCD == "BOR", AVALC %in% c("CR", "PR")) %>%
  dplyr::select(USUBJID, BOR = AVALC)

# First response date from visit-level OVRLRESP records
first_response <- adrs %>%
  dplyr::filter(PARAMCD == "OVRLRESP", AVALC %in% c("CR", "PR")) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    FIRSTRESPDT = min(ADT, na.rm = TRUE),
    .groups = "drop"
  )

# --- Merge all event data with ADSL ------------------------------------------
adsl_tte <- adsl %>%
  dplyr::select(USUBJID, STUDYID, TRTSDT, TRTEDT, RFENDTC) %>%
  dplyr::mutate(
    RFENDDT = as.numeric(as.Date(RFENDTC)),
    TRTSDTN = TRTSDT  # Already numeric in ADSL
  ) %>%
  dplyr::left_join(progression, by = "USUBJID") %>%
  dplyr::left_join(death, by = "USUBJID") %>%
  dplyr::left_join(last_assessment, by = "USUBJID") %>%
  dplyr::left_join(responders_bor, by = "USUBJID") %>%
  dplyr::left_join(first_response, by = "USUBJID") %>%
  dplyr::mutate(
    PROGDTN = as.numeric(PROGDT),
    DTHDTN = as.numeric(DTHDT),
    LASTASN = as.numeric(LASTASDT),
    FIRSTRESP = as.numeric(FIRSTRESPDT)
  )

# --- Derive PFS parameter ----------------------------------------------------
adtte_pfs <- adsl_tte %>%
  dplyr::mutate(
    PARAMCD = "PFS",
    PARAM = "Progression-Free Survival (Months)",
    STARTDT = TRTSDTN,

    # Event logic: progression or death, whichever comes first
    EVENT_PROG = !is.na(PROGDTN),
    EVENT_DTH = !is.na(DTHDTN),

    # Determine event date and type
    EVNTDT = dplyr::case_when(
      EVENT_PROG & EVENT_DTH ~ pmin(PROGDTN, DTHDTN, na.rm = TRUE),
      EVENT_PROG ~ PROGDTN,
      EVENT_DTH ~ DTHDTN,
      TRUE ~ NA_real_
    ),

    EVNTTYPE = dplyr::case_when(
      !is.na(EVNTDT) & EVNTDT == PROGDTN ~ "PROGRESSIVE DISEASE",
      !is.na(EVNTDT) & EVNTDT == DTHDTN ~ "DEATH",
      TRUE ~ NA_character_
    ),

    # Censoring: use last disease assessment or RFENDTC if no assessment
    # Use max(LASTASN, RFENDDT, TRTSDTN) to ensure ADT >= STARTDT
    CNSRDT = dplyr::case_when(
      is.na(EVNTDT) & !is.na(LASTASN) ~ pmax(LASTASN, TRTSDTN, na.rm = TRUE),
      is.na(EVNTDT) & !is.na(RFENDDT) ~ pmax(RFENDDT, TRTSDTN, na.rm = TRUE),
      TRUE ~ NA_real_
    ),

    CNSRTYPE = dplyr::case_when(
      !is.na(CNSRDT) & CNSRDT == LASTASN ~ "LAST DISEASE ASSESSMENT",
      !is.na(CNSRDT) & CNSRDT == RFENDDT ~ "STUDY END DATE",
      !is.na(CNSRDT) & CNSRDT == TRTSDTN ~ "TREATMENT START DATE",
      TRUE ~ NA_character_
    ),

    # Final ADT and CNSR
    ADT = dplyr::coalesce(EVNTDT, CNSRDT),
    CNSR = ifelse(is.na(EVNTDT), 1, 0),

    # AVAL: time from STARTDT to ADT in months
    # REVISIT: Month conversion uses days/30.4375 per SAP (Open-questions-cdisc.md R4)
    AVAL = (ADT - STARTDT + 1) / 30.4375,

    EVNTDESC = EVNTTYPE,
    CNSDTDSC = CNSRTYPE
  ) %>%
  dplyr::select(USUBJID, STUDYID, PARAMCD, PARAM, STARTDT, ADT, AVAL, CNSR,
         EVNTDESC, CNSDTDSC)

# --- Derive OS parameter -----------------------------------------------------
adtte_os <- adsl_tte %>%
  dplyr::mutate(
    PARAMCD = "OS",
    PARAM = "Overall Survival (Months)",
    STARTDT = TRTSDTN,

    # Event logic: death only
    EVENT_DTH = !is.na(DTHDTN),

    # Determine event or censoring
    EVNTDT = dplyr::if_else(EVENT_DTH, DTHDTN, NA_real_),
    EVNTTYPE = dplyr::if_else(EVENT_DTH, "DEATH", NA_character_),

    # Censoring: RFENDTC (last known alive)
    # Use max(RFENDDT, TRTSDTN) to ensure ADT >= STARTDT
    CNSRDT = dplyr::if_else(is.na(EVNTDT), pmax(RFENDDT, TRTSDTN, na.rm = TRUE), NA_real_),
    CNSRTYPE = dplyr::if_else(!is.na(CNSRDT), "LAST KNOWN ALIVE", NA_character_),

    # Final ADT and CNSR
    ADT = dplyr::coalesce(EVNTDT, CNSRDT),
    CNSR = ifelse(is.na(EVNTDT), 1, 0),

    # AVAL: time from STARTDT to ADT in months
    # REVISIT: Month conversion uses days/30.4375 per SAP (Open-questions-cdisc.md R4)
    AVAL = (ADT - STARTDT + 1) / 30.4375,

    EVNTDESC = EVNTTYPE,
    CNSDTDSC = CNSRTYPE
  ) %>%
  dplyr::select(USUBJID, STUDYID, PARAMCD, PARAM, STARTDT, ADT, AVAL, CNSR,
         EVNTDESC, CNSDTDSC)

# --- Derive DOR parameter (responders only) ----------------------------------
# DOR is only calculated for subjects who achieved CR or PR
adtte_dor <- adsl_tte %>%
  dplyr::filter(!is.na(BOR) & BOR %in% c("CR", "PR")) %>%
  dplyr::mutate(
    PARAMCD = "DOR",
    PARAM = "Duration of Response (Months)",
    STARTDT = FIRSTRESP,

    # Event logic: progression or death after response
    EVENT_PROG = !is.na(PROGDTN) & PROGDTN >= FIRSTRESP,
    EVENT_DTH = !is.na(DTHDTN) & DTHDTN >= FIRSTRESP,

    # Determine event date and type
    EVNTDT = dplyr::case_when(
      EVENT_PROG & EVENT_DTH ~ pmin(PROGDTN, DTHDTN, na.rm = TRUE),
      EVENT_PROG ~ PROGDTN,
      EVENT_DTH ~ DTHDTN,
      TRUE ~ NA_real_
    ),

    EVNTTYPE = dplyr::case_when(
      !is.na(EVNTDT) & EVNTDT == PROGDTN ~ "PROGRESSIVE DISEASE",
      !is.na(EVNTDT) & EVNTDT == DTHDTN ~ "DEATH",
      TRUE ~ NA_character_
    ),

    # Censoring: use last disease assessment after response
    # Use max(LASTASN, RFENDDT, FIRSTRESP) to ensure ADT >= STARTDT
    CNSRDT = dplyr::case_when(
      is.na(EVNTDT) & !is.na(LASTASN) & LASTASN >= FIRSTRESP ~ pmax(LASTASN, FIRSTRESP, na.rm = TRUE),
      is.na(EVNTDT) & !is.na(RFENDDT) ~ pmax(RFENDDT, FIRSTRESP, na.rm = TRUE),
      is.na(EVNTDT) ~ FIRSTRESP,
      TRUE ~ NA_real_
    ),

    CNSRTYPE = dplyr::case_when(
      !is.na(CNSRDT) & CNSRDT == LASTASN ~ "LAST DISEASE ASSESSMENT",
      !is.na(CNSRDT) & CNSRDT == RFENDDT ~ "STUDY END DATE",
      !is.na(CNSRDT) & CNSRDT == FIRSTRESP ~ "FIRST RESPONSE DATE",
      TRUE ~ NA_character_
    ),

    # Final ADT and CNSR
    ADT = dplyr::coalesce(EVNTDT, CNSRDT),
    CNSR = ifelse(is.na(EVNTDT), 1, 0),

    # AVAL: time from first response to ADT in months
    # REVISIT: Month conversion uses days/30.4375 per SAP (Open-questions-cdisc.md R4)
    AVAL = (ADT - STARTDT + 1) / 30.4375,

    EVNTDESC = EVNTTYPE,
    CNSDTDSC = CNSRTYPE
  ) %>%
  dplyr::select(USUBJID, STUDYID, PARAMCD, PARAM, STARTDT, ADT, AVAL, CNSR,
         EVNTDESC, CNSDTDSC)

# --- Combine all parameters --------------------------------------------------
adtte <- dplyr::bind_rows(adtte_pfs, adtte_os, adtte_dor) %>%
  dplyr::arrange(USUBJID, PARAMCD)

# --- Apply variable labels and types -----------------------------------------
adtte_meta <- tibble::tibble(
  variable = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "STARTDT",
               "ADT", "AVAL", "CNSR", "EVNTDESC", "CNSDTDSC"),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Parameter Code",
    "Parameter Description",
    "Start Date (Numeric SAS Date)",
    "Analysis Date (Numeric SAS Date)",
    "Analysis Value (Time in Months)",
    "Censoring (0=Event, 1=Censored)",
    "Event Description",
    "Censoring Date Description"
  ),
  type = c("character", "character", "character", "character", "numeric",
           "numeric", "numeric", "numeric", "character", "character")
)

adtte <- adtte %>%
  xportr::xportr_label(metadata = adtte_meta, domain = "ADTTE") %>%
  xportr::xportr_type(metadata = adtte_meta, domain = "ADTTE")

# --- Validation checks -------------------------------------------------------
message("\n=== ADTTE Validation ===")
message("Total rows: ", nrow(adtte))
message("Total subjects: ", n_distinct(adtte$USUBJID))

# Parameter counts
message("\nParameter counts:")
adtte %>%
  dplyr::count(PARAMCD) %>%
  print()

# Event vs censored by parameter
message("\nEvent vs censored by parameter:")
adtte %>%
  dplyr::count(PARAMCD, CNSR) %>%
  dplyr::mutate(CNSR_LABEL = ifelse(CNSR == 0, "Event", "Censored")) %>%
  dplyr::select(-CNSR) %>%
  print()

# Check for missing key variables
message("\nMissing value counts:")
sapply(adtte, function(x) sum(is.na(x))) %>% print()

# Check for negative AVAL
message("\nNegative AVAL values: ", sum(adtte$AVAL < 0, na.rm = TRUE))
if (any(adtte$AVAL < 0, na.rm = TRUE)) {
  message("WARNING: Negative AVAL detected!")
  adtte %>% dplyr::filter(AVAL < 0) %>% print()
}

# Check USUBJID all in ADSL
message("\nAll subjects in ADSL: ", all(adtte$USUBJID %in% adsl$USUBJID))

# Distribution of AVAL by parameter
message("\nAVAL distribution by parameter:")
adtte %>%
  dplyr::group_by(PARAMCD) %>%
  dplyr::summarise(
    N = dplyr::n(),
    Mean = mean(AVAL, na.rm = TRUE),
    Median = median(AVAL, na.rm = TRUE),
    Min = min(AVAL, na.rm = TRUE),
    Max = max(AVAL, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  print()

# --- Save dataset ------------------------------------------------------------
haven::write_xpt(adtte, "projects/exelixis-sap/output-data/adam/adtte.xpt", version = 5)
saveRDS(adtte, "projects/exelixis-sap/output-data/adam/adtte.rds")
message("\nDataset saved to: projects/exelixis-sap/output-data/adam/adtte.xpt")
message("Dataset saved to: projects/exelixis-sap/output-data/adam/adtte.rds")
message("Program complete.")
