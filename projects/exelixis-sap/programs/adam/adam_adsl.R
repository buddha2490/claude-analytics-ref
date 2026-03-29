# =============================================================================
# Program: projects/exelixis-sap/programs/adam_adsl.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADSL — Subject-Level Analysis Dataset
# Author: r-clinical-programmer agent
# Date: 2026-03-29
#
# Source Domains:
#   - DM: USUBJID, STUDYID, SITEID, BRTHDTC, SEX, RACE, ETHNIC, RFSTDTC, RFENDTC, RFICDTC, ACTARMCD, DTHDTC, DTHFL, AGE, AGEU, COUNTRY
#   - MH: USUBJID, MHTERM, MHSTDTC, MHCAT (actual: MHSTDTC not MHDTC)
#   - QS: USUBJID, QSTESTCD, QSORRES, VISIT (actual: QSORRES not QSSTRESN)
#   - SU: USUBJID, SUTRT, SUSCAT
#   - SC: USUBJID, SCTESTCD, SCORRES
#   - LB: USUBJID, LBTESTCD, LBSTRESN, LBSTRESC, VISIT
#   - DS: USUBJID, DSDECOD, DSTERM, DSDTC
#   - EX: USUBJID, EXTRT, EXSTDTC, EXENDTC
#   - PR: USUBJID, PRTRT, PRCAT, PRSTDTC
#   - TU: USUBJID, TUTESTCD, TULOC
#   - ADLOT: USUBJID, LOT, INDEXFL, REGIMEN, LOTSTDTC, LOTENDTC
#
# CDISC References:
#   - ADaM-IG v1.3 ADSL structure (one row per subject)
#   - Charlson Comorbidity Index (Quan 2011 weights)
#   - NPM-008 biomarker terminology (ALTERED/NOT ALTERED)
#
# Dependencies:
#   - ADLOT (projects/exelixis-sap/output-data/adam/adlot.xpt) — required for INDEXFL, PRIORLN
# =============================================================================

library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------

dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
mh <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/mh.xpt")
qs <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/qs.xpt")
su <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/su.xpt")
sc <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/sc.xpt")
lb <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/lb.xpt")
ds <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ds.xpt")
ex <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ex.xpt")
pr <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/pr.xpt")
tu <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/tu.xpt")
adlot <- haven::read_xpt("projects/exelixis-sap/output-data/adam/adlot.xpt")

# --- Data Contract Validation (Step 4) --------------------------------------
message("=== Data Contract Validation ===")

# Validate DM variables
plan_vars_dm <- c("USUBJID", "STUDYID", "SITEID", "BRTHDTC", "SEX", "RACE",
                  "ETHNIC", "RFSTDTC", "RFENDTC", "RFICDTC", "ACTARMCD",
                  "DTHDTC", "DTHFL", "AGE", "AGEU", "COUNTRY")
actual_vars_dm <- names(dm)
missing_vars_dm <- setdiff(plan_vars_dm, actual_vars_dm)

if (length(missing_vars_dm) > 0) {
  stop(
    "Plan lists DM variables not found: ", paste(missing_vars_dm, collapse=", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# Validate MH variables (corrected for actual structure)
plan_vars_mh <- c("USUBJID", "MHTERM", "MHSTDTC", "MHCAT")
actual_vars_mh <- names(mh)
missing_vars_mh <- setdiff(plan_vars_mh, actual_vars_mh)

if (length(missing_vars_mh) > 0) {
  stop(
    "Plan lists MH variables not found: ", paste(missing_vars_mh, collapse=", "),
    "\nActual MH variables: ", paste(actual_vars_mh, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (MH): All ", length(plan_vars_mh), " expected variables found")

# Validate QS variables (corrected for actual structure)
plan_vars_qs <- c("USUBJID", "QSTESTCD", "QSORRES", "VISIT")
actual_vars_qs <- names(qs)
missing_vars_qs <- setdiff(plan_vars_qs, actual_vars_qs)

if (length(missing_vars_qs) > 0) {
  stop(
    "Plan lists QS variables not found: ", paste(missing_vars_qs, collapse=", "),
    "\nActual QS variables: ", paste(actual_vars_qs, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (QS): All ", length(plan_vars_qs), " expected variables found")

# Validate LB variables
plan_vars_lb <- c("USUBJID", "LBTESTCD", "LBSTRESN", "LBSTRESC", "VISIT")
actual_vars_lb <- names(lb)
missing_vars_lb <- setdiff(plan_vars_lb, actual_vars_lb)

if (length(missing_vars_lb) > 0) {
  stop(
    "Plan lists LB variables not found: ", paste(missing_vars_lb, collapse=", "),
    "\nActual LB variables: ", paste(actual_vars_lb, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (LB): All ", length(plan_vars_lb), " expected variables found")

# Validate ADLOT variables
plan_vars_adlot <- c("USUBJID", "LOT", "INDEXFL", "REGIMEN")
actual_vars_adlot <- names(adlot)
missing_vars_adlot <- setdiff(plan_vars_adlot, actual_vars_adlot)

if (length(missing_vars_adlot) > 0) {
  stop(
    "Plan lists ADLOT variables not found: ", paste(missing_vars_adlot, collapse=", "),
    "\nActual ADLOT variables: ", paste(actual_vars_adlot, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (ADLOT): All ", length(plan_vars_adlot), " expected variables found")

message("\n=== Starting ADSL derivations ===")

# --- Block 1: Demographics and reference dates -------------------------------

adsl <- dm %>%
  dplyr::select(
    USUBJID, STUDYID, SITEID, BRTHDTC, SEX, RACE, ETHNIC,
    RFSTDTC, RFENDTC, RFICDTC, ACTARMCD, DTHDTC, DTHFL,
    AGE, AGEU, COUNTRY
  ) %>%
  dplyr::mutate(
    # Convert reference dates to numeric
    RFSTDT = as.numeric(as.Date(RFSTDTC)),
    RFENDT = as.numeric(as.Date(RFENDTC)),
    RFICDT = as.numeric(as.Date(RFICDTC)),
    DTHDT = as.numeric(as.Date(DTHDTC))
  )

message("Block 1 complete: Demographics (", nrow(adsl), " subjects)")

# --- Block 2: Treatment dates from ADLOT ------------------------------------

# Get index treatment dates from ADLOT (where INDEXFL='Y')
index_lot <- adlot %>%
  dplyr::filter(INDEXFL == "Y") %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    TRTSTDTC = min(LOTSTDTC, na.rm = TRUE),
    TRTEDT_CALC = max(LOTENDTC, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    TRTSDT = as.numeric(as.Date(TRTSTDTC)),
    TRTEDT = as.numeric(as.Date(TRTEDT_CALC))
  ) %>%
  dplyr::select(USUBJID, TRTSDT, TRTEDT)

adsl <- adsl %>%
  dplyr::left_join(index_lot, by = "USUBJID")

message("Block 2 complete: Treatment dates (", sum(!is.na(adsl$TRTSDT)), " subjects with index treatment)")

# --- Block 3: Age variables --------------------------------------------------

# AGENSCLC: age at NSCLC diagnosis (from MH where MHCAT='CANCER DIAGNOSIS')
nsclc_diag <- mh %>%
  dplyr::filter(MHCAT == "CANCER DIAGNOSIS") %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(NSCLC_DIAGDT = min(MHSTDTC, na.rm = TRUE), .groups = "drop")

adsl <- adsl %>%
  dplyr::left_join(nsclc_diag, by = "USUBJID") %>%
  dplyr::mutate(
    AGENSCLC = as.numeric(difftime(
      as.Date(NSCLC_DIAGDT),
      as.Date(BRTHDTC),
      units = "days"
    )) / 365.25,
    AGEINDEX = as.numeric(difftime(
      as.Date(RFSTDTC),
      as.Date(BRTHDTC),
      units = "days"
    )) / 365.25,
    AGEINDEXGRP = ifelse(AGEINDEX < 65, "<65", ">=65")
  ) %>%
  dplyr::select(-NSCLC_DIAGDT)

message("Block 3 complete: Age variables")

# --- Block 4: Baseline assessments -------------------------------------------

# ECOGBL: baseline ECOG from QS (QSORRES is character, convert to numeric)
ecog_bl <- qs %>%
  dplyr::filter(QSTESTCD == "ECOG") %>%
  dplyr::left_join(adsl %>% dplyr::select(USUBJID, RFSTDT), by = "USUBJID") %>%
  dplyr::mutate(
    QSDT = as.numeric(as.Date(QSDTC)),
    ECOG_NUM = as.numeric(QSORRES)
  ) %>%
  dplyr::filter(QSDT <= RFSTDT | VISIT == "BASELINE") %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::arrange(USUBJID, dplyr::desc(QSDT)) %>%
  dplyr::slice(1) %>%
  dplyr::ungroup() %>%
  dplyr::select(USUBJID, ECOGBL = ECOG_NUM)

adsl <- adsl %>%
  dplyr::left_join(ecog_bl, by = "USUBJID")

# SMOKSTAT: smoking status from SU
smoke <- su %>%
  dplyr::filter(SUTRT == "TOBACCO") %>%
  dplyr::select(USUBJID, SMOKSTAT = SUSCAT) %>%
  dplyr::distinct(USUBJID, .keep_all = TRUE)

adsl <- adsl %>%
  dplyr::left_join(smoke, by = "USUBJID")

# HISTGRP: histology grouping from MH (MHCAT='HISTOLOGY')
histology <- mh %>%
  dplyr::filter(MHCAT == "HISTOLOGY") %>%
  dplyr::mutate(
    HISTGRP = dplyr::case_when(
      str_detect(toupper(MHTERM), "ADENOCARCINOMA") ~ "ADENOCARCINOMA",
      str_detect(toupper(MHTERM), "SQUAMOUS") ~ "SQUAMOUS CELL",
      str_detect(toupper(MHTERM), "LARGE CELL") ~ "LARGE CELL",
      TRUE ~ "OTHER/UNKNOWN"
    )
  ) %>%
  dplyr::select(USUBJID, HISTGRP) %>%
  dplyr::distinct(USUBJID, .keep_all = TRUE)

adsl <- adsl %>%
  dplyr::left_join(histology, by = "USUBJID")

message("Block 4 complete: Baseline assessments")

# --- Block 5: Metastasis flags -----------------------------------------------

# Brain metastasis
brain_met <- tu %>%
  dplyr::filter(TUTESTCD == "METS", str_detect(toupper(TULOC), "BRAIN")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(BRAINMET = "Y")

# Liver metastasis
liver_met <- tu %>%
  dplyr::filter(TUTESTCD == "METS", str_detect(toupper(TULOC), "LIVER")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(LIVERMET = "Y")

# Bone metastasis
bone_met <- tu %>%
  dplyr::filter(TUTESTCD == "METS", str_detect(toupper(TULOC), "BONE")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(BONEMET = "Y")

adsl <- adsl %>%
  dplyr::left_join(brain_met, by = "USUBJID") %>%
  dplyr::left_join(liver_met, by = "USUBJID") %>%
  dplyr::left_join(bone_met, by = "USUBJID") %>%
  dplyr::mutate(
    BRAINMET = ifelse(is.na(BRAINMET), NA_character_, BRAINMET),
    LIVERMET = ifelse(is.na(LIVERMET), NA_character_, LIVERMET),
    BONEMET = ifelse(is.na(BONEMET), NA_character_, BONEMET)
  )

message("Block 5 complete: Metastasis flags")

# --- Block 6: Biomarker flags ------------------------------------------------
# REVISIT: Biomarker terminology — ALTERED/NOT ALTERED per npm008_biomarker_terminology.md
# Memory alert: Check order matters to avoid substring bugs

# Helper function for biomarker flag derivation (per plan lines 284-323)
create_biomarker_flag <- function(lb_data, test_code, var_name) {
  # Order matters: check "NOT ALTERED" before "ALTERED" to avoid substring match

  # Filter to baseline for the specified test
  test_result <- lb_data %>%
    dplyr::filter(LBTESTCD == test_code, VISIT == "BASELINE") %>%
    dplyr::select(USUBJID, LBSTRESC)

  # Create flag variable
  result <- test_result %>%
    dplyr::mutate(
      !!var_name := dplyr::case_when(
        LBSTRESC == "NOT ALTERED" ~ "N",
        LBSTRESC == "NOT TESTED" ~ NA_character_,
        LBSTRESC == "ALTERED" ~ "Y",
        TRUE ~ NA_character_
      )
    ) %>%
    dplyr::select(USUBJID, !!rlang::sym(var_name)) %>%
    dplyr::distinct(USUBJID, .keep_all = TRUE)

  return(result)
}

# Apply for all 20 biomarkers
egfr <- create_biomarker_flag(lb, "EGFR", "EGFRMUT")
kras <- create_biomarker_flag(lb, "KRAS", "KRASMUT")
alk <- create_biomarker_flag(lb, "ALK", "ALK")
ros1 <- create_biomarker_flag(lb, "ROS1", "ROS1MUT")
ret <- create_biomarker_flag(lb, "RET", "RETMUT")
met <- create_biomarker_flag(lb, "MET", "METMUT")
erbb2 <- create_biomarker_flag(lb, "ERBB2", "ERBB2MUT")
ntrk1 <- create_biomarker_flag(lb, "NTRK1", "NTRK1FUS")
ntrk2 <- create_biomarker_flag(lb, "NTRK2", "NTRK2FUS")
ntrk3 <- create_biomarker_flag(lb, "NTRK3", "NTRK3FUS")
tp53 <- create_biomarker_flag(lb, "TP53", "TP53MUT")
rb1 <- create_biomarker_flag(lb, "RB1", "RB1MUT")
pdl1 <- create_biomarker_flag(lb, "PDL1", "PDL1")
msi <- create_biomarker_flag(lb, "MSI", "MSI")
tmb <- create_biomarker_flag(lb, "TMB", "TMB")
braf <- create_biomarker_flag(lb, "BRAF", "BRAFMUT")
her2 <- create_biomarker_flag(lb, "HER2", "HER2MUT")
pik3ca <- create_biomarker_flag(lb, "PIK3CA", "PIK3CAMUT")
stk11 <- create_biomarker_flag(lb, "STK11", "STK11MUT")
keap1 <- create_biomarker_flag(lb, "KEAP1", "KEAP1MUT")

# Merge all biomarker flags
adsl <- adsl %>%
  dplyr::left_join(egfr, by = "USUBJID") %>%
  dplyr::left_join(kras, by = "USUBJID") %>%
  dplyr::left_join(alk, by = "USUBJID") %>%
  dplyr::left_join(ros1, by = "USUBJID") %>%
  dplyr::left_join(ret, by = "USUBJID") %>%
  dplyr::left_join(met, by = "USUBJID") %>%
  dplyr::left_join(erbb2, by = "USUBJID") %>%
  dplyr::left_join(ntrk1, by = "USUBJID") %>%
  dplyr::left_join(ntrk2, by = "USUBJID") %>%
  dplyr::left_join(ntrk3, by = "USUBJID") %>%
  dplyr::left_join(tp53, by = "USUBJID") %>%
  dplyr::left_join(rb1, by = "USUBJID") %>%
  dplyr::left_join(pdl1, by = "USUBJID") %>%
  dplyr::left_join(msi, by = "USUBJID") %>%
  dplyr::left_join(tmb, by = "USUBJID") %>%
  dplyr::left_join(braf, by = "USUBJID") %>%
  dplyr::left_join(her2, by = "USUBJID") %>%
  dplyr::left_join(pik3ca, by = "USUBJID") %>%
  dplyr::left_join(stk11, by = "USUBJID") %>%
  dplyr::left_join(keap1, by = "USUBJID")

message("Block 6 complete: 20 biomarker flags")

# --- Block 7: Comorbidity flags and Charlson score --------------------------
# REVISIT: Quan 2011 weights used — see projects/exelixis-sap/artifacts/Open-questions-cdisc.md R1/R2

# Comorbidity flags derived from MH.MHTERM (MHCAT='COMORBIDITY DIAGNOSES')
# Using common medical terminology patterns

# Coronary artery disease
cad_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "CORONARY|MYOCARDIAL INFARCTION|ANGINA")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(CADFL = "Y")

# Diabetes
diab_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "DIABETES")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(DIABFL = "Y")

# COPD
copd_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "COPD|CHRONIC.*PULMONARY|EMPHYSEMA")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(COPDFL = "Y")

# Hypertension
htn_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "HYPERTENSION")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(HTNFL = "Y")

# Renal disease
renal_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "RENAL|KIDNEY")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(RENALFL = "Y")

# Hepatic disease
hepatic_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "HEPATIC|LIVER|CIRRHOSIS")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(HEPATICFL = "Y")

# Peripheral vascular disease
pvd_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "PERIPHERAL VASCULAR|CLAUDICATION")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(PVDFL = "Y")

# Cerebrovascular disease
cvd_fl <- mh %>%
  dplyr::filter(str_detect(toupper(MHTERM), "CEREBROVASCULAR|STROKE|TIA")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(CVDFL = "Y")

adsl <- adsl %>%
  dplyr::left_join(cad_fl, by = "USUBJID") %>%
  dplyr::left_join(diab_fl, by = "USUBJID") %>%
  dplyr::left_join(copd_fl, by = "USUBJID") %>%
  dplyr::left_join(htn_fl, by = "USUBJID") %>%
  dplyr::left_join(renal_fl, by = "USUBJID") %>%
  dplyr::left_join(hepatic_fl, by = "USUBJID") %>%
  dplyr::left_join(pvd_fl, by = "USUBJID") %>%
  dplyr::left_join(cvd_fl, by = "USUBJID") %>%
  dplyr::mutate(
    CADFL = ifelse(is.na(CADFL), NA_character_, CADFL),
    DIABFL = ifelse(is.na(DIABFL), NA_character_, DIABFL),
    COPDFL = ifelse(is.na(COPDFL), NA_character_, COPDFL),
    HTNFL = ifelse(is.na(HTNFL), NA_character_, HTNFL),
    RENALFL = ifelse(is.na(RENALFL), NA_character_, RENALFL),
    HEPATICFL = ifelse(is.na(HEPATICFL), NA_character_, HEPATICFL),
    PVDFL = ifelse(is.na(PVDFL), NA_character_, PVDFL),
    CVDFL = ifelse(is.na(CVDFL), NA_character_, CVDFL)
  )

# Charlson Comorbidity Index (Quan 2011 weights)
# REVISIT: Quan 2011 weights — weights of 0 for MI, PVD, CVD, PUD, DM without complications
adsl <- adsl %>%
  dplyr::mutate(
    CCISCORE =
      ifelse(CADFL == "Y", 0, 0) +  # MI = 0 per Quan 2011
      ifelse(PVDFL == "Y", 0, 0) +   # PVD = 0 per Quan 2011
      ifelse(CVDFL == "Y", 0, 0) +   # CVD = 0 per Quan 2011
      ifelse(COPDFL == "Y", 1, 0) +  # COPD = 1
      ifelse(DIABFL == "Y", 0, 0) +  # DM without complications = 0 per Quan 2011
      ifelse(RENALFL == "Y", 2, 0) + # Moderate/severe renal = 2
      ifelse(HEPATICFL == "Y", 1, 0) + # Mild liver = 1
      ifelse(HTNFL == "Y", 0, 0)     # HTN not in Charlson
  )

message("Block 7 complete: Comorbidity flags and Charlson score")

# --- Block 8: Staging variables ----------------------------------------------

# Clinical staging from MH (MHCAT='CLINICAL STAGING GROUP')
clin_stage <- mh %>%
  dplyr::filter(MHCAT == "CLINICAL STAGING GROUP") %>%
  dplyr::mutate(
    CLINSTAGEGRP = dplyr::case_when(
      str_detect(toupper(MHTERM), "STAGE I[^IV]") ~ "STAGE I",
      str_detect(toupper(MHTERM), "STAGE II") ~ "STAGE II",
      str_detect(toupper(MHTERM), "STAGE III") ~ "STAGE III",
      str_detect(toupper(MHTERM), "STAGE IV") ~ "STAGE IV",
      TRUE ~ MHTERM  # Use as-is if standard format
    )
  ) %>%
  dplyr::select(USUBJID, CLINSTAGEGRP) %>%
  dplyr::distinct(USUBJID, .keep_all = TRUE)

# Pathological staging (if available - may not exist in this simulated data)
path_stage <- mh %>%
  dplyr::filter(str_detect(toupper(MHCAT), "PATH")) %>%
  dplyr::mutate(
    PATHSTAGEGRP = dplyr::case_when(
      str_detect(toupper(MHTERM), "STAGE I[^IV]") ~ "STAGE I",
      str_detect(toupper(MHTERM), "STAGE II") ~ "STAGE II",
      str_detect(toupper(MHTERM), "STAGE III") ~ "STAGE III",
      str_detect(toupper(MHTERM), "STAGE IV") ~ "STAGE IV",
      TRUE ~ MHTERM
    )
  ) %>%
  dplyr::select(USUBJID, PATHSTAGEGRP) %>%
  dplyr::distinct(USUBJID, .keep_all = TRUE)

adsl <- adsl %>%
  dplyr::left_join(path_stage, by = "USUBJID") %>%
  dplyr::left_join(clin_stage, by = "USUBJID")

message("Block 8 complete: Staging variables")

# --- Block 9: Treatment history ----------------------------------------------

# Index flag and prior lines from ADLOT
lot_summary <- adlot %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    INDEXFL_ANY = any(INDEXFL == "Y", na.rm = TRUE),
    INDEX_LOT = ifelse(any(INDEXFL == "Y"), LOT[INDEXFL == "Y"][1], NA_integer_),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    INDEXFL = ifelse(INDEXFL_ANY, "Y", NA_character_)
  )

# Calculate prior lines
lot_prior <- adlot %>%
  dplyr::left_join(lot_summary %>% dplyr::select(USUBJID, INDEX_LOT), by = "USUBJID") %>%
  dplyr::filter(!is.na(INDEX_LOT)) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(
    PRIORLN = sum(LOT < INDEX_LOT[1], na.rm = TRUE),
    .groups = "drop"
  )

lot_summary <- lot_summary %>%
  dplyr::left_join(lot_prior, by = "USUBJID") %>%
  dplyr::mutate(PRIORLN = ifelse(is.na(PRIORLN), 0L, PRIORLN)) %>%
  dplyr::select(USUBJID, INDEXFL, PRIORLN)

adsl <- adsl %>%
  dplyr::left_join(lot_summary, by = "USUBJID")

# Neoadjuvant and adjuvant flags from PR
# REVISIT: W5 in Open-questions-cdisc.md — temporal relationship to surgery vs treatment category
neoadj <- pr %>%
  dplyr::filter(str_detect(toupper(PRCAT), "NEOADJUVANT")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(NEOADJFL = "Y")

adjuv <- pr %>%
  dplyr::filter(str_detect(toupper(PRCAT), "ADJUVANT")) %>%
  dplyr::select(USUBJID) %>%
  dplyr::distinct() %>%
  dplyr::mutate(ADJUVFL = "Y")

adsl <- adsl %>%
  dplyr::left_join(neoadj, by = "USUBJID") %>%
  dplyr::left_join(adjuv, by = "USUBJID") %>%
  dplyr::mutate(
    NEOADJFL = ifelse(is.na(NEOADJFL), NA_character_, NEOADJFL),
    ADJUVFL = ifelse(is.na(ADJUVFL), NA_character_, ADJUVFL)
  )

message("Block 9 complete: Treatment history")

# --- Final assembly and variable ordering ------------------------------------

# Select and order variables
adsl_final <- adsl %>%
  dplyr::select(
    # Identifiers
    STUDYID, USUBJID, SITEID,

    # Demographics
    AGE, AGEU, AGENSCLC, AGEINDEX, AGEINDEXGRP,
    SEX, RACE, ETHNIC, COUNTRY, BRTHDTC,

    # Reference dates
    RFSTDTC, RFSTDT, RFENDTC, RFENDT, RFICDTC, RFICDT,

    # Treatment dates and arm
    TRTSDT, TRTEDT, ACTARMCD,

    # Death
    DTHDTC, DTHDT, DTHFL,

    # Baseline assessments
    ECOGBL, SMOKSTAT, HISTGRP,

    # Metastasis flags
    BRAINMET, LIVERMET, BONEMET,

    # Biomarker flags (20 variables)
    EGFRMUT, KRASMUT, ALK, ROS1MUT, RETMUT, METMUT, ERBB2MUT,
    NTRK1FUS, NTRK2FUS, NTRK3FUS, TP53MUT, RB1MUT,
    PDL1, MSI, TMB, BRAFMUT, HER2MUT, PIK3CAMUT, STK11MUT, KEAP1MUT,

    # Comorbidity flags (8 variables)
    CADFL, DIABFL, COPDFL, HTNFL, RENALFL, HEPATICFL, PVDFL, CVDFL,

    # Charlson score
    CCISCORE,

    # Staging
    PATHSTAGEGRP, CLINSTAGEGRP,

    # Treatment history
    INDEXFL, PRIORLN, NEOADJFL, ADJUVFL
  )

message("\n=== ADSL derivation complete ===")
message("Final row count: ", nrow(adsl_final))
message("Final variable count: ", ncol(adsl_final))

# --- Apply variable labels ---------------------------------------------------

adsl_meta <- tibble::tibble(
  variable = names(adsl_final),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Study Site Identifier",
    "Age",
    "Age Units",
    "Age at NSCLC Diagnosis",
    "Age at Index Treatment",
    "Age Group at Index",
    "Sex",
    "Race",
    "Ethnicity",
    "Country",
    "Date of Birth",
    "Reference Start Date (Char)",
    "Reference Start Date (Numeric)",
    "Reference End Date (Char)",
    "Reference End Date (Numeric)",
    "Informed Consent Date (Char)",
    "Informed Consent Date (Numeric)",
    "Treatment Start Date (Numeric)",
    "Treatment End Date (Numeric)",
    "Actual Arm Code",
    "Date of Death (Char)",
    "Date of Death (Numeric)",
    "Death Flag",
    "Baseline ECOG Performance Status",
    "Smoking Status",
    "Histology Group",
    "Brain Metastasis Flag",
    "Liver Metastasis Flag",
    "Bone Metastasis Flag",
    "EGFR Mutation Flag",
    "KRAS Mutation Flag",
    "ALK Fusion Flag",
    "ROS1 Mutation Flag",
    "RET Mutation Flag",
    "MET Mutation Flag",
    "ERBB2 Mutation Flag",
    "NTRK1 Fusion Flag",
    "NTRK2 Fusion Flag",
    "NTRK3 Fusion Flag",
    "TP53 Mutation Flag",
    "RB1 Mutation Flag",
    "PDL1 Expression Flag",
    "MSI Status Flag",
    "TMB Status Flag",
    "BRAF Mutation Flag",
    "HER2 Mutation Flag",
    "PIK3CA Mutation Flag",
    "STK11 Mutation Flag",
    "KEAP1 Mutation Flag",
    "Coronary Artery Disease Flag",
    "Diabetes Flag",
    "COPD Flag",
    "Hypertension Flag",
    "Renal Disease Flag",
    "Hepatic Disease Flag",
    "Peripheral Vascular Disease Flag",
    "Cerebrovascular Disease Flag",
    "Charlson Comorbidity Index Score",
    "Pathological Stage Group",
    "Clinical Stage Group",
    "Index Treatment Line Flag",
    "Number of Prior Lines",
    "Neoadjuvant Treatment Flag",
    "Adjuvant Treatment Flag"
  ),
  type = c(
    "character", "character", "character",  # STUDYID, USUBJID, SITEID
    "numeric", "character", "numeric", "numeric", "character",  # Age vars
    "character", "character", "character", "character", "character",  # SEX-BRTHDTC
    "character", "numeric", "character", "numeric", "character", "numeric",  # Ref dates
    "numeric", "numeric",  # TRT dates
    "character",  # ACTARMCD
    "character", "numeric", "character",  # Death
    "numeric", "character", "character",  # ECOGBL, SMOKSTAT, HISTGRP
    "character", "character", "character",  # Mets flags
    rep("character", 20),  # 20 biomarker flags
    rep("character", 8),   # 8 comorbidity flags
    "numeric",  # CCISCORE
    "character", "character",  # Staging
    "character", "integer", "character", "character"  # Treatment history
  )
)

adsl_final <- adsl_final %>%
  xportr::xportr_label(metadata = adsl_meta, domain = "ADSL") %>%
  xportr::xportr_type(metadata = adsl_meta, domain = "ADSL")

# --- Write output dataset ----------------------------------------------------

haven::write_xpt(adsl_final, "projects/exelixis-sap/output-data/adam/adsl.xpt")
saveRDS(adsl_final, "projects/exelixis-sap/output-data/adam/adsl.rds")
message("\n✓ ADSL dataset written to: projects/exelixis-sap/output-data/adam/adsl.xpt")
message("✓ ADSL dataset written to: projects/exelixis-sap/output-data/adam/adsl.rds")

# --- Validation checks -------------------------------------------------------

message("\n=== Validation Checks ===")

# Row count
message("Row count: ", nrow(adsl_final))
message("Subject count: ", n_distinct(adsl_final$USUBJID))
message("Expected: One row per subject from DM (", n_distinct(dm$USUBJID), ")")

# Key variable completeness
key_vars <- c("STUDYID", "USUBJID", "SITEID", "AGE", "SEX", "RFSTDTC")
completeness <- sapply(adsl_final[, key_vars], function(x) sum(is.na(x)))
message("\nKey variable completeness:")
print(completeness)

# CDISC compliance: unique keys
if (any(duplicated(adsl_final$USUBJID))) {
  stop("BLOCKING: USUBJID is not unique in ADSL", call. = FALSE)
} else {
  message("✓ USUBJID is unique (no duplicates)")
}

# Cross-domain consistency: all subjects in DM
if (!all(adsl_final$USUBJID %in% dm$USUBJID)) {
  stop("BLOCKING: ADSL contains subjects not in DM", call. = FALSE)
} else {
  message("✓ All ADSL subjects exist in DM")
}

# Flag convention check (Y/blank, not Y/N)
flag_vars <- c("DTHFL", "BRAINMET", "LIVERMET", "BONEMET", "INDEXFL",
               "NEOADJFL", "ADJUVFL", "EGFRMUT", "KRASMUT", "CADFL", "DIABFL")
flag_check <- sapply(adsl_final[, flag_vars], function(x) {
  unique_vals <- unique(x[!is.na(x)])
  all(unique_vals %in% c("Y", "N"))
})
if (any(flag_check)) {
  warning("Some flags use Y/N instead of Y/blank: ", paste(names(flag_check)[flag_check], collapse=", "))
} else {
  message("✓ All flag variables use Y/blank convention")
}

message("\n✓✓✓ ADSL implementation complete ✓✓✓")
