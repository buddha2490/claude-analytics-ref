# =============================================================================
# Program:   sim_dm.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Domain:    DM — Demographics
# Purpose:   Simulate the DM subject spine with latent outcome variables.
#            Writes dm.xpt (CDISC variables only) and dm.rds (full data frame
#            including all latent variables for downstream domain programs).
# Seed:      set.seed(43) — domain offset 1 from base seed 42
# Author:    r-clinical-programmer agent
# Date:      2026-03-25
# =============================================================================

library(tidyverse)
library(lubridate)
library(haven)
library(xportr)


# --- Constants ---------------------------------------------------------------

STUDYID    <- "NPM008"
N_SUBJECTS <- 40
STUDY_END  <- as.Date("2027-01-31")
SITES      <- c("01", "02", "03", "04", "05")

set.seed(43)

n <- N_SUBJECTS


# --- Subject identifiers -----------------------------------------------------

subjid <- paste0("A", formatC(seq(1001, 1040), width = 5, flag = "0"))
siteid <- sample(SITES, n, replace = TRUE)
usubjid <- paste0("NPM008-", siteid, "-", subjid)


# --- Outcome assignment (latent variables) -----------------------------------

# Best overall response: PR 18%, CR 0%, SD 40%, PD 35%, NE 7%
bor <- sample(
  c("PR", "CR", "SD", "PD", "NE"),
  n,
  replace = TRUE,
  prob = c(0.18, 0.00, 0.40, 0.35, 0.07)
)

# Reference start date (index date): uniform draw across enrollment window
rfst_date_raw <- as.Date("2022-01-01") +
  sample(0:as.integer(as.Date("2025-06-30") - as.Date("2022-01-01")), n, replace = TRUE)

# Date shift: per-patient jitter applied to all dates (-14 to +14 days)
date_shift <- sample(-14:14, n, replace = TRUE)

# Administrative censoring limit per subject (days from rfst to STUDY_END)
admin_days <- as.integer(STUDY_END - rfst_date_raw)

# PFS days by BOR stratum
pfs_days_raw <- case_when(
  bor %in% c("PR", "CR") ~ rweibull(n, shape = 1.5, scale = 210),
  bor == "SD"             ~ rexp(n, rate = log(2) / 150),
  bor == "PD"             ~ rexp(n, rate = log(2) / 45),
  bor == "NE"             ~ 0,
  TRUE                    ~ 0
)

# Cap at administrative censoring limit
pfs_days <- pmin(pfs_days_raw, admin_days)

# Event flag: progressed before study end
pfs_event <- as.integer(pfs_days_raw < admin_days & bor != "NE")

# OS days: Weibull for all; constrained os >= pfs + [30, 120] for non-NE
os_days_raw <- rweibull(n, shape = 1.2, scale = 450)

# For non-NE subjects, ensure os_days >= pfs_days + runif(30, 120)
os_floor <- ifelse(
  bor != "NE",
  pfs_days + runif(n, 30, 120),
  0
)
os_days_raw <- pmax(os_days_raw, os_floor)

# Cap at administrative censoring limit
os_days <- pmin(os_days_raw, admin_days)

# Death indicator
death_ind <- as.integer(os_days_raw < admin_days)

# DTHFL
dthfl <- ifelse(death_ind == 1, "Y", NA_character_)


# --- Dates (with date_shift applied) -----------------------------------------

# Apply per-patient shift to reference start date
rfst_date <- rfst_date_raw + date_shift

# Reference end date logic:
#   Progressed (pfs_event==1): RFSTDTC + pfs_days
#   Deceased (death_ind==1, not progressed): RFSTDTC + os_days
#   Otherwise: min(STUDY_END, RFSTDTC + pfs_days)
rend_date_raw <- case_when(
  pfs_event == 1 ~ rfst_date_raw + round(pfs_days),
  death_ind == 1 ~ rfst_date_raw + round(os_days),
  TRUE           ~ pmin(STUDY_END, rfst_date_raw + round(pfs_days))
)
rend_date <- rend_date_raw + date_shift

# Informed consent date: RFSTDTC - 7 to 30 days
rfic_date <- rfst_date - sample(7:30, n, replace = TRUE)

# Death date: RFSTDTC + os_days (shifted); NA if alive
dthdtc_date <- ifelse(
  death_ind == 1,
  as.character(rfst_date + round(os_days)),
  NA_character_
)


# --- Demographics ------------------------------------------------------------

age <- pmax(18L, pmin(84L, round(rnorm(n, mean = 64, sd = 9))))

sex <- sample(c("M", "F"), n, replace = TRUE, prob = c(0.55, 0.45))

race <- sample(
  c(
    "WHITE",
    "BLACK OR AFRICAN AMERICAN",
    "ASIAN",
    "AMERICAN INDIAN OR ALASKA NATIVE",
    "NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER",
    "MULTIPLE",
    "NOT REPORTED",
    "UNKNOWN"
  ),
  n,
  replace = TRUE,
  prob = c(0.70, 0.12, 0.10, 0.02, 0.01, 0.02, 0.02, 0.01)
)

ethnic <- sample(
  c("NOT HISPANIC OR LATINO", "HISPANIC OR LATINO", "NOT REPORTED", "UNKNOWN"),
  n,
  replace = TRUE,
  prob = c(0.80, 0.10, 0.06, 0.04)
)

actarmcd <- sample(
  as.character(1:9),
  n,
  replace = TRUE,
  prob = c(0.30, 0.20, 0.15, 0.10, 0.08, 0.07, 0.04, 0.04, 0.02)
)

# Birth year only (de-identified): year of RFSTDTC minus AGE
brthdtc <- as.character(year(rfst_date) - age)


# --- Additional latent variables ---------------------------------------------

pdl1_status <- sample(
  c("HIGH", "LOW", "NEGATIVE"),
  n,
  replace = TRUE,
  prob = c(0.30, 0.50, 0.20)
)

egfr_status <- sample(
  c("ALTERED", "NOT ALTERED"),
  n,
  replace = TRUE,
  prob = c(0.15, 0.85)
)

alk_status <- sample(
  c("ALTERED", "NOT ALTERED"),
  n,
  replace = TRUE,
  prob = c(0.05, 0.95)
)

kras_status <- sample(
  c("ALTERED", "NOT ALTERED"),
  n,
  replace = TRUE,
  prob = c(0.25, 0.75)
)

n_target_lesions  <- sample(2:5, n, replace = TRUE)
n_prior_lots      <- sample(1:3, n, replace = TRUE, prob = c(0.4, 0.4, 0.2))
ecog_bl           <- sample(c(0L, 1L), n, replace = TRUE, prob = c(0.45, 0.55))
metastatic_sites  <- sample(1:5, n, replace = TRUE, prob = c(0.15, 0.30, 0.25, 0.20, 0.10))
brain_mets        <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.15, 0.85))
liver_mets        <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.20, 0.80))
bone_mets         <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.35, 0.65))
de_novo_met       <- sample(c(TRUE, FALSE), n, replace = TRUE, prob = c(0.55, 0.45))


# --- Assemble full data frame (CDISC + latent) --------------------------------

dm <- tibble(
  # CDISC DM variables
  STUDYID  = STUDYID,
  DOMAIN   = "DM",
  USUBJID  = usubjid,
  SUBJID   = subjid,
  RFSTDTC  = as.character(rfst_date),
  RFENDTC  = as.character(rend_date),
  RFICDTC  = as.character(rfic_date),
  DTHDTC   = dthdtc_date,
  DTHFL    = dthfl,
  SITEID   = siteid,
  BRTHDTC  = brthdtc,
  AGE      = age,
  AGEU     = "YEARS",
  SEX      = sex,
  RACE     = race,
  ETHNIC   = ethnic,
  ACTARMCD = actarmcd,
  COUNTRY  = "USA",
  # Latent variables (downstream use only — not exported to XPT)
  bor             = bor,
  pfs_days        = round(pfs_days),
  os_days         = round(os_days),
  death_ind       = death_ind,
  pfs_event       = pfs_event,
  date_shift      = date_shift,
  pdl1_status     = pdl1_status,
  egfr_status     = egfr_status,
  alk_status      = alk_status,
  kras_status     = kras_status,
  n_target_lesions = n_target_lesions,
  n_prior_lots    = n_prior_lots,
  ecog_bl         = ecog_bl,
  metastatic_sites = metastatic_sites,
  brain_mets      = brain_mets,
  liver_mets      = liver_mets,
  bone_mets       = bone_mets,
  de_novo_met     = de_novo_met
)


# --- XPT export (CDISC variables only) ---------------------------------------

# Variable metadata: labels and types for xportr (data frame format required)
cdisc_vars <- c(
  "STUDYID", "DOMAIN", "USUBJID", "SUBJID",
  "RFSTDTC", "RFENDTC", "RFICDTC", "DTHDTC", "DTHFL",
  "SITEID", "BRTHDTC", "AGE", "AGEU",
  "SEX", "RACE", "ETHNIC", "ACTARMCD", "COUNTRY"
)

dm_meta <- tibble(
  variable = cdisc_vars,
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Subject Identifier in the Study",
    "Subject Reference Start Date/Time",
    "Subject Reference End Date/Time",
    "Date/Time of Informed Consent",
    "Date/Time of Death",
    "Subject Death Flag",
    "Study Site Identifier",
    "Date/Time of Birth",
    "Age",
    "Age Units",
    "Sex",
    "Race",
    "Ethnicity",
    "Actual Arm Code",
    "Country"
  ),
  type = case_when(
    variable == "AGE" ~ "numeric",
    TRUE              ~ "character"
  )
)

dm_xpt <- dm %>%
  dplyr::select(all_of(cdisc_vars)) %>%
  xportr_label(dm_meta, domain = "DM") %>%
  xportr_type(dm_meta, domain = "DM")

# Ensure output directory exists
output_dir <- "cohort/output-data/sdtm"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Write XPT
haven::write_xpt(dm_xpt, path = file.path(output_dir, "dm.xpt"))

# Write full RDS (including latent variables) for downstream programs
saveRDS(dm, file.path(output_dir, "dm.rds"))


# --- Summary -----------------------------------------------------------------

message("DM simulation complete: ", nrow(dm), " subjects written to cohort/output-data/sdtm/dm.xpt")
message("DTHFL=Y: ", sum(dm$DTHFL == "Y", na.rm = TRUE), " subjects")
message("BOR distribution:\n", paste(capture.output(table(dm$bor)), collapse = "\n"))
