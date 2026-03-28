# =============================================================================
# sim_su.R
# Simulation: SU (Substance Use) domain — NPM-008 / XB010-101
# One record per subject (tobacco / cigarette use)
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

# --- Load DM spine ------------------------------------------------------------
# DM is the authoritative subject list; all SU records are anchored to it
dm <- readRDS("cohort/output-data/dm.rds")

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

saveRDS(su_xpt, "cohort/output-data/sdtm/su.rds")
su_xpt %>% xportr_write("cohort/output-data/sdtm/su.xpt")

# --- Validation ---------------------------------------------------------------
message("--- SU Validation ---")

# Row count
stopifnot("nrow must be 40" = nrow(su) == 40)
message("nrow: ", nrow(su), " [PASS]")

# All USUBJIDs present in DM
missing_subj <- setdiff(su$USUBJID, dm$USUBJID)
stopifnot("All USUBJIDs must be in DM" = length(missing_subj) == 0)
message("USUBJID coverage: all ", nrow(su), " in DM [PASS]")

# SUSEQ = 1 for all rows
stopifnot("SUSEQ must be 1 for all rows" = all(su$SUSEQ == 1L))
message("SUSEQ = 1 for all rows [PASS]")

# Smoking status distribution
status_pct <- su %>%
  dplyr::count(SUSCAT) %>%
  dplyr::mutate(pct = round(n / sum(n) * 100, 1))

message("Smoking status distribution:")
print(status_pct)

current_pct <- status_pct$pct[status_pct$SUSCAT == "CURRENT"]
former_pct  <- status_pct$pct[status_pct$SUSCAT == "FORMER"]
never_pct   <- status_pct$pct[status_pct$SUSCAT == "NEVER"]

stopifnot("CURRENT % must be 25–55" = dplyr::between(current_pct, 25, 55))
stopifnot("FORMER % must be 35–55"  = dplyr::between(former_pct,  35, 55))
stopifnot("NEVER % must be 10–20"   = dplyr::between(never_pct,   10, 20))
message("Smoking status distribution [PASS]")

# SUDOSE: never and former must be 0; current must be > 0
stopifnot(
  "Non-smokers must have SUDOSE = 0" =
    all(su$SUDOSE[su$SUSCAT != "CURRENT"] == 0)
)
stopifnot(
  "Current smokers must have SUDOSE > 0" =
    all(su$SUDOSE[su$SUSCAT == "CURRENT"] > 0)
)
message("SUDOSE logic [PASS]")

# XPT file written
stopifnot("XPT must exist" = file.exists("cohort/output-data/sdtm/su.xpt"))
message("XPT written to cohort/output-data/sdtm/su.xpt [PASS]")

message("--- All validations passed ---")
