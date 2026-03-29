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
# Updated:   2026-03-28 — Added validation with validate_sdtm_domain()
# =============================================================================

library(tidyverse)
library(lubridate)
library(haven)
library(xportr)

# --- Source validation functions ---------------------------------------------
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Load CT reference -------------------------------------------------------
ct_reference <- readRDS("output-data/sdtm/ct_reference.rds")


# --- Constants ---------------------------------------------------------------

STUDYID    <- "NPM008"
N_SUBJECTS <- 40
STUDY_END  <- as.Date("2027-01-31")
SITES      <- c("01", "02", "03", "04", "05")

set.seed(43)

n <- N_SUBJECTS


# --- Subject identifiers -----------------------------------------------------

subjid <- paste0("A", formatC(seq(1001, 1040), width = 4, flag = "0"))
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
# Constrained to ensure after date shift, max is 2025-06-30
rfst_date_raw <- as.Date("2022-01-01") +
  sample(0:as.integer(as.Date("2025-06-16") - as.Date("2022-01-01")), n, replace = TRUE)

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
# Target ~70% death rate, so use longer scale (more censoring)
os_days_raw <- rweibull(n, shape = 1.0, scale = 600)

# For non-NE subjects, ensure os_days >= pfs_days + runif(30, 120)
os_floor <- ifelse(
  bor != "NE",
  pfs_days + runif(n, 30, 120),
  0
)
os_days_raw <- pmax(os_days_raw, os_floor)

# Cap at administrative censoring limit
os_days <- pmin(os_days_raw, admin_days)

# Death indicator: ~70% target
# Use os_days_raw < admin_days as base, then force some to be censored
death_ind_raw <- as.integer(os_days_raw < admin_days)

# If death rate too high, randomly censor some subjects
observed_death_rate <- mean(death_ind_raw)
if (observed_death_rate > 0.75) {
  # Randomly flip some deaths to censored
  n_to_censor <- round(sum(death_ind_raw) * 0.30)
  dead_indices <- which(death_ind_raw == 1)
  censor_indices <- sample(dead_indices, n_to_censor)
  death_ind_raw[censor_indices] <- 0
}

death_ind <- death_ind_raw

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

# Ensure RFENDTC > RFSTDTC for all subjects (add 1 day if equal)
rend_date <- pmax(rend_date, rfst_date + 1)

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

# Birth date (de-identified): use Jan 1 of birth year for compliance with ISO 8601
# Birth year = year of RFSTDTC minus AGE
brthdtc <- paste0(as.character(year(rfst_date) - age), "-01-01")


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


# --- Validation --------------------------------------------------------------

# Define DM-specific validation checks (per plan Section 3.5)
dm_validation_checks <- function(dm_df, dm_ref) {
  checks <- list()

  # D1: Exactly 40 rows
  if (nrow(dm_df) != 40) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "Exactly 40 rows",
      result = "FAIL",
      detail = sprintf("Expected 40, got %d", nrow(dm_df))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "Exactly 40 rows",
      result = "PASS",
      detail = ""
    )
  }

  # D2: RFSTDTC < RFENDTC for all subjects
  date_comparison <- dm_df %>%
    dplyr::mutate(
      rfst = as.Date(RFSTDTC),
      rfend = as.Date(RFENDTC),
      valid = rfst < rfend
    )

  invalid_dates <- sum(!date_comparison$valid, na.rm = TRUE)
  if (invalid_dates > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "RFSTDTC < RFENDTC for all subjects",
      result = "FAIL",
      detail = sprintf("%d subject(s) have RFSTDTC >= RFENDTC", invalid_dates)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "RFSTDTC < RFENDTC for all subjects",
      result = "PASS",
      detail = ""
    )
  }

  # D3: DTHFL="Y" count in [26, 30] (target ~70%)
  dthfl_count <- sum(dm_df$DTHFL == "Y", na.rm = TRUE)
  if (dthfl_count < 26 || dthfl_count > 30) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "DTHFL=Y count in [26, 30] (target ~70%)",
      result = "FAIL",
      detail = sprintf("Expected [26, 30], got %d", dthfl_count)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "DTHFL=Y count in [26, 30] (target ~70%)",
      result = "PASS",
      detail = sprintf("%d subjects (%.1f%%)", dthfl_count, 100 * dthfl_count / 40)
    )
  }

  # D4: All latent variables are non-NA
  latent_vars <- c("bor", "pfs_days", "os_days", "date_shift", "pdl1_status",
                   "egfr_status", "alk_status", "kras_status", "n_target_lesions",
                   "n_prior_lots", "ecog_bl", "metastatic_sites", "brain_mets",
                   "liver_mets", "bone_mets", "de_novo_met")

  na_counts <- sapply(latent_vars, function(v) sum(is.na(dm_df[[v]])))
  latent_vars_with_na <- names(na_counts[na_counts > 0])

  if (length(latent_vars_with_na) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "All latent variables are non-NA",
      result = "FAIL",
      detail = sprintf("NA values found in: %s", paste(latent_vars_with_na, collapse = ", "))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "All latent variables are non-NA",
      result = "PASS",
      detail = sprintf("Checked %d latent variables", length(latent_vars))
    )
  }

  # D5: RFSTDTC range: 2022-01-01 to 2025-06-30
  rfst_dates <- as.Date(dm_df$RFSTDTC)
  min_rfst <- min(rfst_dates)
  max_rfst <- max(rfst_dates)

  if (min_rfst < as.Date("2022-01-01") || max_rfst > as.Date("2025-06-30")) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D5",
      description = "RFSTDTC range: 2022-01-01 to 2025-06-30",
      result = "FAIL",
      detail = sprintf("Actual range: %s to %s", min_rfst, max_rfst)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D5",
      description = "RFSTDTC range: 2022-01-01 to 2025-06-30",
      result = "PASS",
      detail = sprintf("Range: %s to %s", min_rfst, max_rfst)
    )
  }

  checks
}

# Extract CT reference values for DM variables
dm_ct <- list(
  SEX = ct_reference$SEX,
  RACE = ct_reference$RACE,
  ETHNIC = ct_reference$ETHNIC
)

# Run validation (DM serves as its own reference for universal checks)
validation_result <- validate_sdtm_domain(
  domain_df = dm,
  domain_code = "DM",
  dm_ref = dm,
  expected_rows = c(40, 40),
  ct_reference = dm_ct,
  domain_checks = dm_validation_checks
)

message(validation_result$summary)


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
output_dir <- "output-data/sdtm"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# Write XPT
haven::write_xpt(dm_xpt, path = file.path(output_dir, "dm.xpt"))

# Write full RDS (including latent variables) for downstream programs
saveRDS(dm, file.path(output_dir, "dm.rds"))


# --- Log result --------------------------------------------------------------

log_sdtm_result(
  domain_code = "DM",
  wave = 0,
  row_count = nrow(dm),
  col_count = ncol(dm),
  validation_result = validation_result,
  notes = c(
    sprintf("DTHFL=Y: %d subjects (%.1f%%)", sum(dm$DTHFL == "Y", na.rm = TRUE),
            100 * sum(dm$DTHFL == "Y", na.rm = TRUE) / 40),
    sprintf("BOR: PR=%d, CR=%d, SD=%d, PD=%d, NE=%d",
            sum(dm$bor == "PR"), sum(dm$bor == "CR"), sum(dm$bor == "SD"),
            sum(dm$bor == "PD"), sum(dm$bor == "NE"))
  ),
  log_dir = "logs/"
)


# --- Summary -----------------------------------------------------------------

message("DM simulation complete: ", nrow(dm), " subjects written to dm.xpt")
message("DTHFL=Y: ", sum(dm$DTHFL == "Y", na.rm = TRUE), " subjects")
message("BOR distribution:\n", paste(capture.output(table(dm$bor)), collapse = "\n"))
