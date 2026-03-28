# =============================================================================
# Program: cohort/adam_adsl.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADSL — Subject-Level Analysis Dataset
# Author: r-clinical-programmer agent
# Date: 2026-03-27
#
# Source Domains:
#   - DM: USUBJID, STUDYID, SITEID, BRTHDTC, SEX, RACE, ETHNIC, RFSTDTC,
#         RFENDTC, RFICDTC, ACTARMCD, DTHDTC, DTHFL, AGE, AGEU, COUNTRY
#   - MH: USUBJID, MHTERM, MHSTDTC, MHCAT, MHBODSYS (comorbidities, staging, diagnosis)
#   - QS: USUBJID, QSTESTCD, QSSTRESN, VISIT (ECOG, smoking)
#   - SU: USUBJID, SUTRT, SUSCAT (smoking status)
#   - LB: USUBJID, LBTESTCD, LBSTRESN, LBSTRESC, VISIT (biomarkers)
#   - DS: USUBJID, DSDECOD, DSTERM, DSSTDTC (disposition)
#   - EX: USUBJID, EXTRT, EXSTDTC, EXENDTC (treatment dates)
#   - PR: USUBJID, PRTRT, PRCAT, PRSTDTC (prior therapies)
#   - TU: USUBJID, TUTESTCD, TULOC, TUSTRESC (metastases)
#   - ADLOT: USUBJID, LOT, INDEXFL, REGIMEN, LOTSTDTC (line of therapy)
#
# CDISC References:
#   - ADaM-IG v1.3 Subject-Level Analysis Dataset (ADSL)
#   - CDISC CT: SEX, RACE, ETHNIC
#   - Charlson Comorbidity Index: Quan 2011 updated weights
#
# Dependencies:
#   - ADLOT (cohort/output-data/adam/adlot.xpt) — required for INDEXFL, PRIORLN
# =============================================================================

# --- Load packages -----------------------------------------------------------
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------
dm <- haven::read_xpt("cohort/output-data/sdtm/dm.xpt")
mh <- haven::read_xpt("cohort/output-data/sdtm/mh.xpt")
qs <- haven::read_xpt("cohort/output-data/sdtm/qs.xpt")
su <- haven::read_xpt("cohort/output-data/sdtm/su.xpt")
lb <- haven::read_xpt("cohort/output-data/sdtm/lb.xpt")
ds <- haven::read_xpt("cohort/output-data/sdtm/ds.xpt")
ex <- haven::read_xpt("cohort/output-data/sdtm/ex.xpt")
pr <- haven::read_xpt("cohort/output-data/sdtm/pr.xpt")
tu <- haven::read_xpt("cohort/output-data/sdtm/tu.xpt")
adlot <- haven::read_xpt("cohort/output-data/adam/adlot.xpt")

# --- Start with DM demographics ---------------------------------------------
adsl <- dm %>%
  select(STUDYID, USUBJID, SITEID, BRTHDTC, SEX, RACE, ETHNIC,
         RFSTDTC, RFENDTC, RFICDTC, ACTARMCD, DTHDTC, DTHFL,
         AGE, AGEU, COUNTRY)

# Derive ARM and ACTARM from ACTARMCD (DM does not contain ARM/ACTARM)
# Simple mapping for this study
adsl <- adsl %>%
  mutate(
    ARMCD = ACTARMCD,
    ARM = paste0("Treatment Arm ", ACTARMCD),
    ACTARM = ARM
  )

# --- Derive reference dates and death flag ----------------------------------
adsl <- adsl %>%
  mutate(
    RFSTDT = as.numeric(as.Date(RFSTDTC)),
    RFENDT = as.numeric(as.Date(RFENDTC)),
    RFICDT = as.numeric(as.Date(RFICDTC)),
    DTHDT = as.numeric(as.Date(DTHDTC))
  )

# --- Derive age at NSCLC diagnosis ------------------------------------------
# AGENSCLC: Age at NSCLC diagnosis (from MH primary cancer diagnosis date)
mh_nsclc <- mh %>%
  filter(MHCAT == "CANCER DIAGNOSIS") %>%
  group_by(USUBJID) %>%
  slice_min(as.Date(MHSTDTC), n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(USUBJID, MHSTDTC_DX = MHSTDTC)

adsl <- adsl %>%
  left_join(mh_nsclc, by = "USUBJID") %>%
  mutate(
    # BRTHDTC is just the year (partial date) - convert to approximate date
    AGENSCLC = if_else(
      !is.na(BRTHDTC) & !is.na(MHSTDTC_DX),
      as.numeric(
        lubridate::year(as.Date(MHSTDTC_DX)) - as.numeric(BRTHDTC)
      ),
      NA_real_
    ),
    AGEINDEX = AGE  # Age at index = AGE from DM (age at RFSTDTC)
  ) %>%
  select(-MHSTDTC_DX)

# --- Derive age group -------------------------------------------------------
adsl <- adsl %>%
  mutate(
    AGEINDEXGRP = if_else(AGEINDEX < 65, "<65", ">=65", NA_character_)
  )

# --- Checkpoint: Save demographics block ------------------------------------
saveRDS(adsl, "cohort/output-data/.adsl_checkpoint_demo.rds")

# --- Derive treatment dates from ADLOT index treatment ----------------------
# TRTSDT/TRTEDT from index treatment line (ADLOT where INDEXFL='Y')
# Not from all EX records — only from index regimen
adlot_trtdates <- adlot %>%
  filter(INDEXFL == "Y") %>%
  group_by(USUBJID) %>%
  summarize(
    TRTSDT = as.numeric(min(as.Date(LOTSTDTC), na.rm = TRUE)),
    TRTEDT = as.numeric(max(as.Date(LOTENDTC), na.rm = TRUE)),
    .groups = "drop"
  )

adsl <- adsl %>%
  left_join(adlot_trtdates, by = "USUBJID")

# --- Derive baseline ECOG ---------------------------------------------------
ecog_bl <- qs %>%
  filter(QSTESTCD == "ECOG", VISIT == "BASELINE") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  mutate(ECOGBL = as.numeric(QSORRES)) %>%
  select(USUBJID, ECOGBL)

adsl <- adsl %>%
  left_join(ecog_bl, by = "USUBJID")

# --- Derive smoking status --------------------------------------------------
smoke <- su %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(USUBJID, SMOKSTAT = SUSCAT)

adsl <- adsl %>%
  left_join(smoke, by = "USUBJID")

# --- Derive histology grouping ----------------------------------------------
hist <- mh %>%
  filter(MHCAT == "HISTOLOGY") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(USUBJID, HISTGRP = MHTERM)

adsl <- adsl %>%
  left_join(hist, by = "USUBJID")

# --- Checkpoint: Save demographics + baseline assessments -------------------
saveRDS(adsl, "cohort/output-data/.adsl_checkpoint_baseline.rds")

# --- Derive metastasis flags from TU -----------------------------------------
mets_brain <- tu %>%
  filter(TUTESTCD == "METS", str_detect(TULOC, regex("BRAIN", ignore_case = TRUE))) %>%
  distinct(USUBJID) %>%
  mutate(BRAINMET = "Y")

mets_liver <- tu %>%
  filter(TUTESTCD == "METS", str_detect(TULOC, regex("LIVER", ignore_case = TRUE))) %>%
  distinct(USUBJID) %>%
  mutate(LIVERMET = "Y")

mets_bone <- tu %>%
  filter(TUTESTCD == "METS", str_detect(TULOC, regex("BONE", ignore_case = TRUE))) %>%
  distinct(USUBJID) %>%
  mutate(BONEMET = "Y")

adsl <- adsl %>%
  left_join(mets_brain, by = "USUBJID") %>%
  left_join(mets_liver, by = "USUBJID") %>%
  left_join(mets_bone, by = "USUBJID")
# Note: left_join leaves NA for non-matches, which is correct Y/NA encoding
# haven::write_xpt() will convert NA_character_ to empty strings in XPT format

# --- Derive biomarker flags from LB (baseline only) --------------------------
# Filter to VISIT = BASELINE
lb_bl <- lb %>%
  filter(VISIT == "BASELINE")

# Helper function to create biomarker flag
# Actual LB data uses: ALTERED, NOT ALTERED, NOT TESTED, VUS
# IMPORTANT: Check "NOT ALTERED" and "NOT TESTED" BEFORE "ALTERED" to avoid substring matches
create_biomarker_flag <- function(data, testcd, flag_name) {
  data %>%
    filter(LBTESTCD == testcd) %>%
    group_by(USUBJID) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    mutate(
      !!flag_name := case_when(
        str_detect(LBSTRESC, regex("NOT ALTERED", ignore_case = TRUE)) ~ "N",
        str_detect(LBSTRESC, regex("NOT TESTED", ignore_case = TRUE)) ~ NA_character_,
        str_detect(LBSTRESC, regex("VUS", ignore_case = TRUE)) ~ NA_character_,
        str_detect(LBSTRESC, regex("ALTERED", ignore_case = TRUE)) ~ "Y",
        TRUE ~ NA_character_
      )
    ) %>%
    select(USUBJID, !!flag_name)
}

# Derive individual biomarker flags
egfr <- create_biomarker_flag(lb_bl, "EGFR", "EGFRMUT")
kras <- create_biomarker_flag(lb_bl, "KRAS", "KRASMUT")
alk <- create_biomarker_flag(lb_bl, "ALK", "ALKMUT")
ros1 <- create_biomarker_flag(lb_bl, "ROS1", "ROS1MUT")
ret <- create_biomarker_flag(lb_bl, "RET", "RETMUT")  # RET is its own biomarker
met <- create_biomarker_flag(lb_bl, "MET", "METMUT")
erbb2 <- create_biomarker_flag(lb_bl, "ERBB2", "ERBB2MUT")
ntrk1 <- create_biomarker_flag(lb_bl, "NTRK1", "NTRK1FUS")
ntrk2 <- create_biomarker_flag(lb_bl, "NTRK2", "NTRK2FUS")
ntrk3 <- create_biomarker_flag(lb_bl, "NTRK3", "NTRK3FUS")

# PDL1 — actual values are HIGH, LOW, NEGATIVE (not numeric)
# REVISIT: Threshold definition — using HIGH as positive for now
pdl1 <- lb_bl %>%
  filter(LBTESTCD == "PDL1SUM") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  mutate(
    PDL1POS = case_when(
      str_detect(LBSTRESC, regex("HIGH", ignore_case = TRUE)) ~ "Y",
      str_detect(LBSTRESC, regex("LOW|NEGATIVE", ignore_case = TRUE)) ~ "N",
      TRUE ~ NA_character_
    ),
    PDL1VAL = LBSTRESN
  ) %>%
  select(USUBJID, PDL1POS, PDL1VAL)

# MSI status — actual values are MSI-HIGH, MSS, NOT TESTED
msi <- lb_bl %>%
  filter(LBTESTCD == "MSISTAT") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  mutate(
    MSIHIGH = case_when(
      str_detect(LBSTRESC, regex("MSI-HIGH", ignore_case = TRUE)) ~ "Y",
      str_detect(LBSTRESC, regex("MSS", ignore_case = TRUE)) ~ "N",
      str_detect(LBSTRESC, regex("NOT TESTED", ignore_case = TRUE)) ~ NA_character_,
      TRUE ~ NA_character_
    )
  ) %>%
  select(USUBJID, MSIHIGH)

# TMB — numeric values, threshold >= 10 mutations/megabase
# REVISIT: TMB-high threshold — using >= 10 per standard practice
tmb <- lb_bl %>%
  filter(LBTESTCD == "TMB") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  mutate(
    TMBHIGH = case_when(
      !is.na(LBSTRESN) & LBSTRESN >= 10 ~ "Y",
      !is.na(LBSTRESN) & LBSTRESN < 10 ~ "N",
      TRUE ~ NA_character_
    ),
    TMBVAL = LBSTRESN
  ) %>%
  select(USUBJID, TMBHIGH, TMBVAL)

# Join all biomarker flags
adsl <- adsl %>%
  left_join(egfr, by = "USUBJID") %>%
  left_join(kras, by = "USUBJID") %>%
  left_join(alk, by = "USUBJID") %>%
  left_join(ros1, by = "USUBJID") %>%
  left_join(ret, by = "USUBJID") %>%
  left_join(met, by = "USUBJID") %>%
  left_join(erbb2, by = "USUBJID") %>%
  left_join(ntrk1, by = "USUBJID") %>%
  left_join(ntrk2, by = "USUBJID") %>%
  left_join(ntrk3, by = "USUBJID") %>%
  left_join(pdl1, by = "USUBJID") %>%
  left_join(msi, by = "USUBJID") %>%
  left_join(tmb, by = "USUBJID")

# --- Checkpoint: Save with biomarkers ---------------------------------------
saveRDS(adsl, "cohort/output-data/.adsl_checkpoint_biomarkers.rds")

# --- Derive comorbidity flags from MH ----------------------------------------
mh_comorb <- mh %>%
  filter(MHCAT == "COMORBIDITY DIAGNOSES")

# Helper function to create comorbidity flag
# Returns Y/NA encoding (not Y/N) per ADaM flag convention
create_comorb_flag <- function(data, search_terms, flag_name) {
  pattern <- paste(search_terms, collapse = "|")
  data %>%
    filter(str_detect(MHTERM, regex(pattern, ignore_case = TRUE))) %>%
    distinct(USUBJID) %>%
    mutate(!!flag_name := "Y")
}

# Derive comorbidity flags (Y/blank)
cad <- create_comorb_flag(mh_comorb, c("Coronary Artery", "Myocardial Infarction"), "CADFL")
diab <- create_comorb_flag(mh_comorb, c("Diabetes"), "DIABFL")
copd <- create_comorb_flag(mh_comorb, c("Pulmonary Disease", "COPD", "Chronic Obstructive"), "COPDFL")
pvd <- create_comorb_flag(mh_comorb, c("Peripheral Vascular"), "PVDFL")
cvd <- create_comorb_flag(mh_comorb, c("Cerebrovascular", "Stroke", "TIA"), "CVDFL")
dementia <- create_comorb_flag(mh_comorb, c("Dementia"), "DEMENTFL")
hemiplegia <- create_comorb_flag(mh_comorb, c("Hemiplegia", "Paraplegia"), "HEMIPLFL")
renal <- create_comorb_flag(mh_comorb, c("Renal Disease", "Kidney"), "RENALFL")
hepatic <- create_comorb_flag(mh_comorb, c("Liver Disease", "Hepatic"), "HEPATFL")

# Join comorbidity flags
adsl <- adsl %>%
  left_join(cad, by = "USUBJID") %>%
  left_join(diab, by = "USUBJID") %>%
  left_join(copd, by = "USUBJID") %>%
  left_join(pvd, by = "USUBJID") %>%
  left_join(cvd, by = "USUBJID") %>%
  left_join(dementia, by = "USUBJID") %>%
  left_join(hemiplegia, by = "USUBJID") %>%
  left_join(renal, by = "USUBJID") %>%
  left_join(hepatic, by = "USUBJID")

# --- Derive Charlson Comorbidity Index (Quan 2011 weights) ------------------
# REVISIT: Quan 2011 updated weights used — see artifacts/NPM-008/Open-questions-cdisc.md R1/R2
# Derived from MH.MHTERM (not ICD-10 codes)

# Quan 2011 weights (approximate — would need full mapping table in production)
adsl <- adsl %>%
  mutate(
    CCISCORE = 0 +
      if_else(CADFL == "Y", 1, 0, 0) +
      if_else(CVDFL == "Y", 1, 0, 0) +
      if_else(PVDFL == "Y", 1, 0, 0) +
      if_else(COPDFL == "Y", 1, 0, 0) +
      if_else(DEMENTFL == "Y", 2, 0, 0) +
      if_else(HEMIPLFL == "Y", 2, 0, 0) +
      if_else(DIABFL == "Y", 1, 0, 0) +
      if_else(RENALFL == "Y", 1, 0, 0) +
      if_else(HEPATFL == "Y", 3, 0, 0)
  )

# --- Checkpoint: Save with comorbidities ------------------------------------
saveRDS(adsl, "cohort/output-data/.adsl_checkpoint_comorbidities.rds")

# --- Derive staging variables from MH ----------------------------------------
stage_clin <- mh %>%
  filter(MHCAT == "CLINICAL STAGING GROUP") %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(USUBJID, CLINSTAGEGRP = MHTERM)

# For pathological staging (may not exist for all subjects)
stage_path <- mh %>%
  filter(str_detect(MHCAT, regex("PATH", ignore_case = TRUE))) %>%
  group_by(USUBJID) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(USUBJID, PATHSTAGEGRP = MHTERM)

adsl <- adsl %>%
  left_join(stage_clin, by = "USUBJID") %>%
  left_join(stage_path, by = "USUBJID")

# --- Derive treatment history from ADLOT and PR ------------------------------
# Validate ADLOT: each subject should have exactly one INDEXFL='Y' record
adlot_index_check <- adlot %>%
  filter(INDEXFL == "Y") %>%
  group_by(USUBJID) %>%
  summarize(n_index = n(), .groups = "drop")

if (any(adlot_index_check$n_index != 1)) {
  stop("ADLOT validation failed: Some subjects do not have exactly one INDEXFL='Y' record", call. = FALSE)
}

# INDEXFL: subject has index treatment
adlot_index <- adlot %>%
  filter(INDEXFL == "Y") %>%
  distinct(USUBJID) %>%
  mutate(INDEXFL_SUBJ = "Y")

# PRIORLN: count of prior lines of therapy
adlot_prior <- adlot %>%
  filter(INDEXFL == "Y") %>%
  select(USUBJID, INDEX_LOT = LOT)

adlot_prior_count <- adlot %>%
  left_join(adlot_prior, by = "USUBJID") %>%
  filter(LOT < INDEX_LOT) %>%
  group_by(USUBJID) %>%
  summarize(PRIORLN = n(), .groups = "drop")

adsl <- adsl %>%
  left_join(adlot_index, by = "USUBJID") %>%
  left_join(adlot_prior_count, by = "USUBJID") %>%
  mutate(
    INDEXFL = if_else(is.na(INDEXFL_SUBJ), NA_character_, INDEXFL_SUBJ),
    PRIORLN = if_else(is.na(PRIORLN), 0, PRIORLN)
  ) %>%
  select(-INDEXFL_SUBJ)

# Neoadjuvant and adjuvant flags (from PR domain)
# W5 open question: temporal relationship to surgery — using simple heuristic for now
# Y/NA encoding per ADaM flag convention
pr_neoadj <- pr %>%
  filter(str_detect(PRCAT, regex("NEOADJ", ignore_case = TRUE))) %>%
  distinct(USUBJID) %>%
  mutate(NEOADJFL = "Y")

pr_adj <- pr %>%
  filter(str_detect(PRCAT, regex("ADJUV", ignore_case = TRUE))) %>%
  distinct(USUBJID) %>%
  mutate(ADJUVFL = "Y")

adsl <- adsl %>%
  left_join(pr_neoadj, by = "USUBJID") %>%
  left_join(pr_adj, by = "USUBJID")

# --- Checkpoint: Save with treatment history --------------------------------
saveRDS(adsl, "cohort/output-data/.adsl_checkpoint_treatment.rds")

# --- Final variable selection and ordering ----------------------------------
# Select and order variables per ADaM ADSL standard
adsl <- adsl %>%
  select(
    # Identifiers
    STUDYID, USUBJID, SITEID,
    # Treatment
    ARM, ARMCD, ACTARM, ACTARMCD,
    # Demographics
    AGE, AGEU, AGEINDEX, AGEINDEXGRP, AGENSCLC,
    SEX, RACE, ETHNIC, COUNTRY,
    BRTHDTC,
    # Reference dates
    RFSTDTC, RFSTDT, RFENDTC, RFENDT, RFICDTC, RFICDT,
    # Treatment dates
    TRTSDT, TRTEDT,
    # Death
    DTHFL, DTHDTC, DTHDT,
    # Baseline assessments
    ECOGBL, SMOKSTAT, HISTGRP,
    # Staging
    CLINSTAGEGRP, PATHSTAGEGRP,
    # Metastases
    BRAINMET, LIVERMET, BONEMET,
    # Biomarkers
    EGFRMUT, KRASMUT, ALKMUT, ROS1MUT, RETMUT, METMUT, ERBB2MUT,
    NTRK1FUS, NTRK2FUS, NTRK3FUS,
    PDL1POS, PDL1VAL, MSIHIGH, TMBHIGH, TMBVAL,
    # Comorbidities
    CADFL, DIABFL, COPDFL, PVDFL, CVDFL, DEMENTFL, HEMIPLFL, RENALFL, HEPATFL,
    CCISCORE,
    # Treatment history
    INDEXFL, PRIORLN, NEOADJFL, ADJUVFL
  )

# --- Apply variable labels and types ----------------------------------------
# Build metadata programmatically to ensure alignment
var_labels <- list(
  STUDYID = "Study Identifier",
  USUBJID = "Unique Subject Identifier",
  SITEID = "Study Site Identifier",
  SUBJID = "Subject Identifier",
  ARM = "Treatment Arm",
  ARMCD = "Treatment Arm Code",
  ACTARM = "Actual Treatment Arm",
  ACTARMCD = "Actual Treatment Arm Code",
  AGE = "Age",
  AGEU = "Age Units",
  AGEINDEX = "Age at Index Treatment",
  AGEINDEXGRP = "Age at Index Group",
  AGENSCLC = "Age at NSCLC Diagnosis",
  SEX = "Sex",
  RACE = "Race",
  ETHNIC = "Ethnicity",
  COUNTRY = "Country",
  BRTHDTC = "Date of Birth",
  RFSTDTC = "Reference Start Date/Time",
  RFSTDT = "Reference Start Date",
  RFENDTC = "Reference End Date/Time",
  RFENDT = "Reference End Date",
  RFICDTC = "Informed Consent Date/Time",
  RFICDT = "Informed Consent Date",
  TRTSDT = "Treatment Start Date",
  TRTEDT = "Treatment End Date",
  DTHFL = "Death Flag",
  DTHDTC = "Death Date/Time",
  DTHDT = "Death Date",
  ECOGBL = "Baseline ECOG",
  SMOKSTAT = "Smoking Status",
  HISTGRP = "Histology Group",
  CLINSTAGEGRP = "Clinical Stage Group",
  PATHSTAGEGRP = "Pathological Stage Group",
  BRAINMET = "Brain Metastasis Flag",
  LIVERMET = "Liver Metastasis Flag",
  BONEMET = "Bone Metastasis Flag",
  EGFRMUT = "EGFR Mutation Flag",
  KRASMUT = "KRAS Mutation Flag",
  ALKMUT = "ALK Mutation Flag",
  ROS1MUT = "ROS1 Mutation Flag",
  RETMUT = "RET Mutation Flag",
  METMUT = "MET Mutation Flag",
  ERBB2MUT = "ERBB2 Mutation Flag",
  NTRK1FUS = "NTRK1 Fusion Flag",
  NTRK2FUS = "NTRK2 Fusion Flag",
  NTRK3FUS = "NTRK3 Fusion Flag",
  PDL1POS = "PDL1 Positive Flag",
  PDL1VAL = "PDL1 Value",
  MSIHIGH = "MSI-High Flag",
  TMBHIGH = "TMB-High Flag",
  TMBVAL = "TMB Value",
  CADFL = "Coronary Artery Disease Flag",
  DIABFL = "Diabetes Flag",
  COPDFL = "COPD Flag",
  PVDFL = "Peripheral Vascular Disease Flag",
  CVDFL = "Cerebrovascular Disease Flag",
  DEMENTFL = "Dementia Flag",
  HEMIPLFL = "Hemiplegia Flag",
  RENALFL = "Renal Disease Flag",
  HEPATFL = "Hepatic Disease Flag",
  CCISCORE = "Charlson Comorbidity Index Score",
  INDEXFL = "Index Treatment Flag",
  PRIORLN = "Prior Lines of Therapy",
  NEOADJFL = "Neoadjuvant Treatment Flag",
  ADJUVFL = "Adjuvant Treatment Flag"
)

var_types <- list(
  STUDYID = "character",
  USUBJID = "character",
  SITEID = "character",
  SUBJID = "character",
  ARM = "character",
  ARMCD = "character",
  ACTARM = "character",
  ACTARMCD = "character",
  AGE = "numeric",
  AGEU = "character",
  AGEINDEX = "numeric",
  AGEINDEXGRP = "character",
  AGENSCLC = "numeric",
  SEX = "character",
  RACE = "character",
  ETHNIC = "character",
  COUNTRY = "character",
  BRTHDTC = "character",
  RFSTDTC = "character",
  RFSTDT = "numeric",
  RFENDTC = "character",
  RFENDT = "numeric",
  RFICDTC = "character",
  RFICDT = "numeric",
  TRTSDT = "numeric",
  TRTEDT = "numeric",
  DTHFL = "character",
  DTHDTC = "character",
  DTHDT = "numeric",
  ECOGBL = "numeric",
  SMOKSTAT = "character",
  HISTGRP = "character",
  CLINSTAGEGRP = "character",
  PATHSTAGEGRP = "character",
  BRAINMET = "character",
  LIVERMET = "character",
  BONEMET = "character",
  EGFRMUT = "character",
  KRASMUT = "character",
  ALKMUT = "character",
  ROS1MUT = "character",
  RETMUT = "character",
  METMUT = "character",
  ERBB2MUT = "character",
  NTRK1FUS = "character",
  NTRK2FUS = "character",
  NTRK3FUS = "character",
  PDL1POS = "character",
  PDL1VAL = "numeric",
  MSIHIGH = "character",
  TMBHIGH = "character",
  TMBVAL = "numeric",
  CADFL = "character",
  DIABFL = "character",
  COPDFL = "character",
  PVDFL = "character",
  CVDFL = "character",
  DEMENTFL = "character",
  HEMIPLFL = "character",
  RENALFL = "character",
  HEPATFL = "character",
  CCISCORE = "numeric",
  INDEXFL = "character",
  PRIORLN = "numeric",
  NEOADJFL = "character",
  ADJUVFL = "character"
)

# --- Validation checks (BEFORE writing) -------------------------------------
cat("\n=== Validation Checks ===\n")
cat("Row count:", nrow(adsl), "\n")
cat("Expected row count (subjects in DM):", nrow(dm), "\n")
cat("Match:", nrow(adsl) == nrow(dm), "\n\n")

# Key variable completeness
key_vars <- c("USUBJID", "STUDYID", "AGE", "SEX", "RACE")
cat("Key variable completeness:\n")
print(sapply(adsl %>% select(all_of(key_vars)), function(x) sum(is.na(x))))

# Unique keys
cat("\nUnique USUBJID check:", !any(duplicated(adsl$USUBJID)), "\n")

# Cross-domain consistency
cat("All subjects in DM:", all(adsl$USUBJID %in% dm$USUBJID), "\n")

# Flag encoding check (before XPT write)
cat("\nFlag encoding check (before XPT write - should be Y or NA):\n")
cat("BRAINMET: Y=", sum(adsl$BRAINMET == "Y", na.rm=TRUE), ", NA=", sum(is.na(adsl$BRAINMET)), "\n")
cat("CADFL: Y=", sum(adsl$CADFL == "Y", na.rm=TRUE), ", NA=", sum(is.na(adsl$CADFL)), "\n")
cat("EGFRMUT: Y=", sum(adsl$EGFRMUT == "Y", na.rm=TRUE), ", N=", sum(adsl$EGFRMUT == "N", na.rm=TRUE), ", NA=", sum(is.na(adsl$EGFRMUT)), "\n")

# Apply labels using attr() directly (more reliable than xportr for this case)
for (var in names(adsl)) {
  if (var %in% names(var_labels)) {
    attr(adsl[[var]], "label") <- var_labels[[var]]
  }
}

# --- Save final dataset -----------------------------------------------------
saveRDS(adsl, "cohort/output-data/adam/adsl.rds")
haven::write_xpt(adsl, "cohort/output-data/adam/adsl.xpt")

message("\nADSL dataset created: cohort/output-data/adam/adsl.xpt")
message("Rows: ", nrow(adsl))
message("Variables: ", ncol(adsl))

# Clean up checkpoint files
file.remove("cohort/output-data/.adsl_checkpoint_demo.rds")
file.remove("cohort/output-data/.adsl_checkpoint_baseline.rds")
file.remove("cohort/output-data/.adsl_checkpoint_biomarkers.rds")
file.remove("cohort/output-data/.adsl_checkpoint_comorbidities.rds")
file.remove("cohort/output-data/.adsl_checkpoint_treatment.rds")

message("\nADSL implementation complete.")
