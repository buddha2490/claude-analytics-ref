# Pre-flight validation script for ADaM automation workflow
# Date: 2026-03-29

# --- Phase 0: Validate Plan Structure -------------------------------------------

message("=" , paste(rep("=", 79), collapse = ""))
message("PRE-FLIGHT VALIDATION - Phase 0: Plan Structure")
message("=", paste(rep("=", 79), collapse = ""))

# Load validation function
suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

source("R/validate_plan.R")

result <- validate_plan(
  plan_path = "plans/plan_adam_automation_2026-03-29.md",
  data_path = "output-data/sdtm"
)

cat("\n")
cat(result$report)
cat("\n")

# Check verdict
if (result$verdict == "BLOCKING") {
  stop("Plan validation FAILED with BLOCKING issues. Resolve before proceeding.", call. = FALSE)
} else if (result$verdict == "WARNING") {
  message("\n✓ Plan validation passed with WARNINGS. Review before proceeding.")
} else {
  message("\n✓ Plan validation PASSED.")
}

# --- Phase 1: Profile Key Source Domains ----------------------------------------

message("\n")
message("=", paste(rep("=", 79), collapse = ""))
message("PRE-FLIGHT VALIDATION - Phase 1: Data Profiling")
message("=", paste(rep("=", 79), collapse = ""))

source("R/profile_data.R")

# Profile LB domain
message("\nProfiling LB domain...")
profile_data(
  domain = "LB",
  variables = c("LBTESTCD", "LBSTRESC", "LBBLFL"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)

# Profile MH domain
message("\nProfiling MH domain...")
profile_data(
  domain = "MH",
  variables = c("MHCAT", "MHTERM"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)

# Profile QS domain
message("\nProfiling QS domain...")
profile_data(
  domain = "QS",
  variables = c("QSTESTCD", "QSORRES", "VISIT"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)

message("\n✓ Data profiling complete. Profiles saved to data-profiles/")

# --- Phase 2: Load Study Memories -----------------------------------------------

message("\n")
message("=", paste(rep("=", 79), collapse = ""))
message("PRE-FLIGHT VALIDATION - Phase 2: Study Memories")
message("=", paste(rep("=", 79), collapse = ""))

memory_dir <- ".claude/agent-memory"
if (dir.exists(memory_dir)) {
  memory_files <- list.files(memory_dir, pattern = "\\.md$", full.names = TRUE)
  memory_files <- memory_files[!basename(memory_files) %in% c("MEMORY.md", "README.md")]

  if (length(memory_files) > 0) {
    message("\nFound ", length(memory_files), " memory file(s):")
    for (f in memory_files) {
      message("  - ", basename(f))
    }
    message("\n✓ Memories will be automatically loaded by agents.")
  } else {
    message("\nNo study-specific memories found (first run).")
  }
} else {
  message("\nNo memory directory found (first run).")
}

# --- Phase 3: Basic Infrastructure Validation -----------------------------------

message("\n")
message("=", paste(rep("=", 79), collapse = ""))
message("PRE-FLIGHT VALIDATION - Phase 3: Infrastructure")
message("=", paste(rep("=", 79), collapse = ""))

suppressPackageStartupMessages({
  library(haven)
  library(tidyr)
  library(lubridate)
})

# 1. Required SDTM domains exist
message("\nChecking SDTM domains...")
required_domains <- c("dm", "ae", "bs", "cm", "ds", "ec", "ex", "ho",
                      "ie", "lb", "mh", "pr", "qs", "rs", "sc", "su",
                      "tr", "tu", "vs")

missing_domains <- character(0)
for (d in required_domains) {
  f <- file.path("output-data/sdtm", paste0(d, ".xpt"))
  if (!file.exists(f)) {
    missing_domains <- c(missing_domains, d)
  }
}

if (length(missing_domains) > 0) {
  stop("Missing SDTM domains: ", paste(missing_domains, collapse = ", "), call. = FALSE)
} else {
  message("  ✓ All ", length(required_domains), " SDTM domains present")
}

# 2. DM validation
message("\nChecking DM domain...")
dm <- haven::read_xpt("output-data/sdtm/dm.xpt")
message("  ✓ DM has ", nrow(dm), " subjects")

required_dm_cols <- c("STUDYID", "USUBJID", "RFSTDTC", "RFENDTC",
                      "DTHDTC", "DTHFL", "AGE", "SEX", "RACE",
                      "ETHNIC", "ACTARMCD", "BRTHDTC", "SITEID")
missing_cols <- setdiff(required_dm_cols, names(dm))

if (length(missing_cols) > 0) {
  stop("DM missing required columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
} else {
  message("  ✓ DM has all required columns")
}

# 3. Package availability
message("\nChecking package availability...")
required_pkgs <- c("haven", "dplyr", "tidyr", "stringr", "lubridate",
                   "xportr", "admiral", "purrr")

missing_pkgs <- character(0)
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_pkgs <- c(missing_pkgs, pkg)
  }
}

if (length(missing_pkgs) > 0) {
  stop("Missing required packages: ", paste(missing_pkgs, collapse = ", "), call. = FALSE)
} else {
  message("  ✓ All required packages available")
}

# 4. Create output directories
message("\nCreating output directories...")
dirs_to_create <- c(
  "logs_2026-03-29",
  "qa_2026-03-29",
  "data-profiles"
)

for (d in dirs_to_create) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
    message("  ✓ Created: ", d)
  } else {
    message("  ✓ Exists: ", d)
  }
}

# --- Summary --------------------------------------------------------------------

message("\n")
message("=", paste(rep("=", 79), collapse = ""))
message("PRE-FLIGHT VALIDATION COMPLETE")
message("=", paste(rep("=", 79), collapse = ""))
message("\nVERDICT: ", result$verdict)
message("\nAll pre-flight checks passed. Ready to execute Wave 1.")
message("\n")
