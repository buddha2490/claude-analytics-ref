# =============================================================================
# Script:    adam_preflight.R
# Purpose:   Pre-flight validation before ADaM derivation Wave 1
# Date:      2026-03-28
# =============================================================================

message(strrep("=", 70))
message("ADaM Pre-Flight Validation")
message(strrep("=", 70))

# --- 1. Required SDTM domains exist and are readable --------------------------
message("\n[1/4] Checking SDTM domain files...")

required_domains <- c("dm", "ae", "bs", "cm", "ds", "ec", "ex", "ho",
                      "ie", "lb", "mh", "pr", "qs", "rs", "sc", "su",
                      "tr", "tu", "vs")

missing_domains <- character(0)
for (d in required_domains) {
  f <- file.path("output-data/sdtm", paste0(d, ".xpt"))
  if (!file.exists(f)) {
    missing_domains <- c(missing_domains, paste0(d, ".xpt"))
  }
}

if (length(missing_domains) > 0) {
  stop("Missing SDTM domains: ", paste(missing_domains, collapse=", "), call. = FALSE)
} else {
  message("✓ All 19 SDTM XPT files present")
}

# --- 2. DM has expected N subjects and columns --------------------------------
message("\n[2/4] Validating DM structure...")

dm <- haven::read_xpt("output-data/sdtm/dm.xpt")

if (nrow(dm) != 40) {
  stop("DM has ", nrow(dm), " subjects, expected 40", call. = FALSE)
} else {
  message("✓ DM has 40 subjects")
}

required_dm_cols <- c("STUDYID", "USUBJID", "RFSTDTC", "RFENDTC",
                      "DTHDTC", "DTHFL", "AGE", "SEX", "RACE",
                      "ETHNIC", "ACTARMCD", "BRTHDTC", "SITEID")
missing_cols <- setdiff(required_dm_cols, names(dm))

if (length(missing_cols) > 0) {
  stop("DM missing columns: ", paste(missing_cols, collapse=", "), call. = FALSE)
} else {
  message("✓ DM has all ", length(required_dm_cols), " required columns")
}

# --- 3. Required packages available -------------------------------------------
message("\n[3/4] Checking R packages...")

required_pkgs <- c("haven", "dplyr", "tidyr", "stringr", "lubridate",
                   "xportr", "admiral", "purrr")
missing_pkgs <- character(0)

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_pkgs <- c(missing_pkgs, pkg)
  }
}

if (length(missing_pkgs) > 0) {
  stop("Missing packages: ", paste(missing_pkgs, collapse=", "), call. = FALSE)
} else {
  message("✓ All ", length(required_pkgs), " required packages available")
}

# --- 4. Output directories exist ----------------------------------------------
message("\n[4/4] Checking output directories...")

if (!dir.exists("logs")) {
  dir.create("logs", recursive = TRUE)
  message("✓ Created logs/")
} else {
  message("✓ logs/ exists")
}

if (!dir.exists("QA reviews")) {
  dir.create("QA reviews", recursive = TRUE)
  message("✓ Created QA reviews/")
} else {
  message("✓ QA reviews/ exists")
}

if (!dir.exists("output-data/adam")) {
  dir.create("output-data/adam", recursive = TRUE)
  message("✓ Created output-data/adam/")
} else {
  message("✓ output-data/adam/ exists")
}

# --- Summary ------------------------------------------------------------------
message("\n", strrep("=", 70))
message("✅ PRE-FLIGHT VALIDATION PASSED — Ready for ADaM Wave 1")
message(strrep("=", 70))
