# =============================================================================
# sim_su.R
# Simulation: SU (Substance Use) domain — NPM-008 / XB010-101
# One record per subject (tobacco / cigarette use)
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

# --- Load inputs --------------------------------------------------------------
dm <- readRDS("output-data/sdtm/dm.rds")
ct_reference <- readRDS("output-data/sdtm/ct_reference.rds")
source("R/validate_sdtm_domain.R")

n <- nrow(dm)   # expected: 40

# --- Set seed -----------------------------------------------------------------
# SU is domain order 5 → set.seed(42 + 5) = set.seed(47)
set.seed(47)

# --- Assign smoking status per subject ----------------------------------------
# NSCLC is strongly associated with smoking; distribution reflects trial population
smoking_status <- sample(
  c("CURRENT", "FORMER", "NEVER"),
  size    = n,
  replace = TRUE,
  prob    = c(0.40, 0.45, 0.15)
)

# --- Derive per-status variables ----------------------------------------------
# SUDOSE: current smokers get a random cig/day count; former and never = 0
# SUDUR:  ISO 8601 duration of use; never smokers get P0Y
sudose <- dplyr::case_when(
  smoking_status == "CURRENT" ~ round(runif(n, 5, 40), 1),
  TRUE                        ~ 0
)

sudur <- dplyr::case_when(
  smoking_status == "CURRENT" ~ paste0("P", sample(10:40, n, replace = TRUE), "Y"),
  smoking_status == "FORMER"  ~ paste0("P", sample(5:35,  n, replace = TRUE), "Y"),
  smoking_status == "NEVER"   ~ "P0Y"
)

# --- Build SU dataset ---------------------------------------------------------
su <- tibble(
  STUDYID = dm$STUDYID,
  DOMAIN  = "SU",
  USUBJID = dm$USUBJID,
  SUSEQ   = 1L,
  SUTRT   = "CIGARETTES",
  SUCAT   = "TOBACCO",
  SUSCAT  = smoking_status,
  SUPRESP = "Y",
  SUDOSE  = sudose,
  SUDOSU  = "CIGARETTES/DAY",
  SUDUR   = sudur,
  SUSTDTC = dm$RFICDTC   # substance use start = informed consent date
)

# --- Variable metadata for xportr pipeline ------------------------------------
# xportr functions require a data frame with dataset/variable columns
su_meta <- tibble::tibble(
  dataset  = "SU",
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "SUSEQ",
    "SUTRT",   "SUCAT",  "SUSCAT",  "SUPRESP",
    "SUDOSE",  "SUDOSU", "SUDUR",   "SUSTDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Reported Name of Substance",
    "Category",
    "Subcategory",
    "Pre-Specified",
    "Consumed Dose per Administration",
    "Dose Units",
    "Duration",
    "Start Date/Time of Substance Use"
  ),
  type = c(
    "text",    # STUDYID
    "text",    # DOMAIN
    "text",    # USUBJID
    "numeric", # SUSEQ
    "text",    # SUTRT
    "text",    # SUCAT
    "text",    # SUSCAT
    "text",    # SUPRESP
    "numeric", # SUDOSE
    "text",    # SUDOSU
    "text",    # SUDUR
    "text"     # SUSTDTC
  ),
  length = c(8L, 2L, 20L, NA_integer_, 11L, 7L, 7L, 1L, NA_integer_, 14L, 6L, 10L)
)

# --- Apply xportr pipeline and write XPT --------------------------------------
su_xpt <- su %>%
  xportr_label(su_meta, domain = "SU") %>%
  xportr_type(su_meta, domain = "SU") %>%
  xportr_length(su_meta, domain = "SU")

# --- Domain-specific validation function -------------------------------------
su_checks <- function(su, dm_ref) {
  checks <- list()

  # D1: SUSEQ = 1 for all rows (1 record per subject)
  if (all(su$SUSEQ == 1L)) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "SUSEQ = 1 for all rows (1 record per subject)",
      result = "PASS",
      detail = ""
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D1",
      description = "SUSEQ = 1 for all rows (1 record per subject)",
      result = "FAIL",
      detail = sprintf("%d rows have SUSEQ != 1", sum(su$SUSEQ != 1))
    )
  }

  # D2: Smoking status distribution (25-55% current, 35-55% former, 10-20% never)
  status_pct <- su %>%
    dplyr::count(SUSCAT) %>%
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))

  current_pct <- status_pct$pct[status_pct$SUSCAT == "CURRENT"]
  former_pct  <- status_pct$pct[status_pct$SUSCAT == "FORMER"]
  never_pct   <- status_pct$pct[status_pct$SUSCAT == "NEVER"]

  current_ok <- dplyr::between(current_pct, 25, 55)
  former_ok  <- dplyr::between(former_pct, 35, 55)
  never_ok   <- dplyr::between(never_pct, 10, 20)

  if (current_ok && former_ok && never_ok) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "Smoking status distribution within expected ranges",
      result = "PASS",
      detail = sprintf("CURRENT=%0.1f%%, FORMER=%0.1f%%, NEVER=%0.1f%%",
                      current_pct, former_pct, never_pct)
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "D2",
      description = "Smoking status distribution within expected ranges",
      result = "FAIL",
      detail = sprintf("CURRENT=%0.1f%% (expect 25-55), FORMER=%0.1f%% (expect 35-55), NEVER=%0.1f%% (expect 10-20)",
                      current_pct, former_pct, never_pct)
    )
  }

  # D3: SUDOSE logic — never and former must be 0; current must be > 0
  non_smoker_dose_ok <- all(su$SUDOSE[su$SUSCAT != "CURRENT"] == 0)
  current_smoker_dose_ok <- all(su$SUDOSE[su$SUSCAT == "CURRENT"] > 0)

  if (non_smoker_dose_ok && current_smoker_dose_ok) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "SUDOSE logic (0 for former/never, >0 for current)",
      result = "PASS",
      detail = ""
    )
  } else {
    detail_parts <- c()
    if (!non_smoker_dose_ok) {
      detail_parts <- c(detail_parts, sprintf("%d non-current smokers have SUDOSE != 0",
                                             sum(su$SUDOSE[su$SUSCAT != "CURRENT"] != 0)))
    }
    if (!current_smoker_dose_ok) {
      detail_parts <- c(detail_parts, sprintf("%d current smokers have SUDOSE = 0",
                                             sum(su$SUDOSE[su$SUSCAT == "CURRENT"] == 0)))
    }
    checks[[length(checks) + 1]] <- list(
      check_id = "D3",
      description = "SUDOSE logic (0 for former/never, >0 for current)",
      result = "FAIL",
      detail = paste(detail_parts, collapse = "; ")
    )
  }

  # D4: SUDUR format check (ISO 8601 duration)
  sudur_valid <- stringr::str_detect(su$SUDUR, "^P\\d+Y$")
  if (all(sudur_valid)) {
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "SUDUR matches ISO 8601 duration format (P<n>Y)",
      result = "PASS",
      detail = ""
    )
  } else {
    invalid_count <- sum(!sudur_valid)
    checks[[length(checks) + 1]] <- list(
      check_id = "D4",
      description = "SUDUR matches ISO 8601 duration format (P<n>Y)",
      result = "FAIL",
      detail = sprintf("%d invalid SUDUR values", invalid_count)
    )
  }

  checks
}

# --- Validate using standard function ----------------------------------------
validation_result <- validate_sdtm_domain(
  domain_df = su_xpt,
  domain_code = "SU",
  dm_ref = dm,
  expected_rows = c(40, 40),  # Exactly 40 rows expected
  ct_reference = NULL,  # No CT reference for SU-specific variables
  domain_checks = su_checks
)

message(validation_result$summary)

# --- Write outputs ------------------------------------------------------------
saveRDS(su_xpt, "output-data/sdtm/su.rds")
su_xpt %>% xportr_write("output-data/sdtm/su.xpt")

message("SU XPT written to output-data/sdtm/su.xpt")
