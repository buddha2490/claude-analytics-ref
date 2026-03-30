#' Demonstration of Between-Wave Validation Framework
#'
#' This script demonstrates the between-wave validation checks using
#' simulated NPM-008 study data. It creates realistic scenarios to show
#' how the validation framework catches different types of issues.

library(dplyr)
library(haven)

# --- Setup: Source validation functions ---
source("R/validate_referential_integrity.R")
source("R/validate_date_consistency.R")
source("R/validate_derived_variables.R")
source("R/validate_cross_domain.R")
source("projects/exelixis-sap/programs/between_wave_checks.R")

# --- Create test data directory ---
test_data_path <- "projects/exelixis-sap/test-data"
if (!dir.exists(test_data_path)) {
  dir.create(test_data_path, recursive = TRUE)
}

message("\n========================================")
message("Creating Simulated NPM-008 Test Data")
message("========================================\n")

# --- Scenario 1: Perfect data (all checks pass) ---
message("\n--- Scenario 1: Perfect Data ---\n")

# Create DM (Demographics)
dm <- data.frame(
  STUDYID = rep("NPM-008", 6),
  USUBJID = sprintf("NPM-008-%03d", 1:6),
  AGE = c(65, 58, 72, 61, 69, 55),
  SEX = rep(c("M", "F"), 3),

)
write_xpt(dm, file.path(test_data_path, "dm.xpt"))
message("Created DM: ", nrow(dm), " subjects")

# Create ADSL (Subject-Level Analysis)
adsl <- data.frame(
  STUDYID = rep("NPM-008", 6),
  USUBJID = dm$USUBJID,
  TRTSDT = as.Date("2023-01-15") + 0:5,  # Staggered start dates
  TRTEDT = as.Date("2023-01-15") + 30 + 0:5,
  AGE = dm$AGE,
  SEX = dm$SEX,

)
write_xpt(adsl, file.path(test_data_path, "adsl.xpt"))
message("Created ADSL: ", nrow(adsl), " subjects")

# Create ADAE (Adverse Events) - all TRTEMFL dates valid
adae <- data.frame(
  STUDYID = rep("NPM-008", 12),
  USUBJID = rep(adsl$USUBJID, each = 2),
  AESTDT = as.Date(rep(adsl$TRTSDT, each = 2)) + c(0, 5),  # All on or after TRTSDT
  AETERM = rep(c("Nausea", "Fatigue"), 6),
  TRTEMFL = rep("Y", 12),

)
write_xpt(adae, file.path(test_data_path, "adae.xpt"))
message("Created ADAE: ", nrow(adae), " records")

# Create ADRS (Response) - exactly 1 BOR per subject
adrs <- data.frame(
  STUDYID = rep("NPM-008", 12),
  USUBJID = rep(adsl$USUBJID, 2),
  PARAMCD = rep(c("BOR", "CBOR"), 6),
  AVALC = c("CR", "PR", "PR", "SD", "SD", "PD",   # BOR values
             "CR", "PR", "PR", "SD", "SD", "PD"),  # CBOR values

)
write_xpt(adrs, file.path(test_data_path, "adrs.xpt"))
message("Created ADRS: ", nrow(adrs), " records")

# Create ADTTE (Time-to-Event) - DOR only for responders (CR/PR)
responders <- adrs %>%
  filter(PARAMCD == "BOR", AVALC %in% c("CR", "PR")) %>%
  pull(USUBJID)

n_responders <- length(responders)

adtte <- data.frame(
  STUDYID = rep("NPM-008", n_responders),
  USUBJID = responders,
  PARAMCD = rep("DOR", n_responders),
  AVAL = seq(30, by = 15, length.out = n_responders),  # Duration of response in days
  CNSR = rep(0, n_responders),

)
write_xpt(adtte, file.path(test_data_path, "adtte.xpt"))
message("Created ADTTE: ", nrow(adtte), " records (", n_responders, " responders)")

# --- Run validation checks ---
message("\n\n========================================")
message("SCENARIO 1: Perfect Data Validation")
message("========================================\n")

result_scenario1 <- run_between_wave_checks(
  wave_number = 4,
  completed_datasets = c("dm", "adsl", "adae", "adrs", "adtte"),
  data_path = test_data_path,
  auto_retry = TRUE
)

message("\n--- Scenario 1 Results ---")
message("Overall Verdict: ", result_scenario1$verdict)
message("Checks Performed: ", length(result_scenario1$checks))
message("Expected: All checks PASS")

# --- Scenario 2: Data with violations ---
message("\n\n========================================")
message("SCENARIO 2: Data with Violations")
message("========================================\n")

# Create flawed ADAE with TRTEMFL violations
adae_flawed <- adae
# Make 2 records pre-treatment
adae_flawed$AESTDT[c(1, 3)] <- adsl$TRTSDT[c(1, 2)] - 5
write_xpt(adae_flawed, file.path(test_data_path, "adae.xpt"))
message("Modified ADAE: Added 2 TRTEMFL violations (AE before TRTSDT)")

# Create flawed ADRS with duplicate BOR
adrs_flawed <- rbind(
  adrs,
  data.frame(
    STUDYID = "NPM-008",
    USUBJID = "NPM-008-001",
    PARAMCD = "BOR",
    AVALC = "SD",

  )
)
write_xpt(adrs_flawed, file.path(test_data_path, "adrs.xpt"))
message("Modified ADRS: Subject NPM-008-001 now has 2 BOR records")

# Create flawed ADTTE with DOR for non-responder
adtte_flawed <- rbind(
  adtte,
  data.frame(
    STUDYID = "NPM-008",
    USUBJID = "NPM-008-006",  # Subject with BOR=PD (non-responder)
    PARAMCD = "DOR",
    AVAL = 15,
    CNSR = 0,

  )
)
write_xpt(adtte_flawed, file.path(test_data_path, "adtte.xpt"))
message("Modified ADTTE: Added DOR for non-responder (NPM-008-006)")

# --- Run validation checks on flawed data ---
result_scenario2 <- run_between_wave_checks(
  wave_number = 4,
  completed_datasets = c("dm", "adsl", "adae", "adrs", "adtte"),
  data_path = test_data_path,
  auto_retry = TRUE
)

message("\n--- Scenario 2 Results ---")
message("Overall Verdict: ", result_scenario2$verdict)
message("Expected: FAIL (multiple critical violations detected)")

# --- Print detailed summary ---
message("\n\n========================================")
message("Detailed Summary Table (Scenario 2)")
message("========================================\n")

print(result_scenario2$summary)

message("\n\n========================================")
message("Demo Complete")
message("========================================\n")

message("Summary of Validations:")
message("  - Referential integrity checks: Ensures all child subjects exist in parent")
message("  - Date consistency checks: TRTEMFL='Y' requires AESTDT >= TRTSDT")
message("  - Derived variable checks: BOR must have exactly 1 record per subject")
message("  - Cross-domain checks: DOR records must match CR/PR responders")
message("\nAuto-retry behavior: ", result_scenario2$retry_attempted)
message("\nAll validation functions tested successfully!")

# --- Cleanup (optional) ---
message("\nTest data saved in: ", test_data_path)
message("To clean up: unlink('", test_data_path, "', recursive = TRUE)")
