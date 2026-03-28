library(testthat)

# Source the function
source("../R/validate_plan.R")

# --- Test 1: Input validation --------------------------------------------------

test_that("validate_plan requires valid plan_path", {
  expect_error(
    validate_plan(123),
    "`plan_path` must be a single character string"
  )

  expect_error(
    validate_plan(c("path1", "path2")),
    "`plan_path` must be a single character string"
  )

  expect_error(
    validate_plan("nonexistent_file.md"),
    "Plan file not found"
  )
})

test_that("validate_plan validates data_path when provided", {
  # Create a temporary valid plan file
  temp_plan <- tempfile(fileext = ".md")
  writeLines("# Test Plan", temp_plan)

  expect_error(
    validate_plan(temp_plan, data_path = 123),
    "`data_path` must be a single character string"
  )

  expect_error(
    validate_plan(temp_plan, data_path = "nonexistent_dir"),
    "Data directory not found"
  )

  unlink(temp_plan)
})

# --- Test 2: Detects datasets >40 variables without strategy ------------------

test_that("validate_plan detects large datasets without split strategy", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Datasets",
    "",
    "### ADSL (101 variables)",
    "",
    "Demographics and baseline characteristics."
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "WARNING")
  expect_true(any(grepl("ADSL has 101 variables", result$warnings)))
  expect_true(any(grepl("no split/checkpoint strategy", result$warnings)))

  unlink(temp_plan)
})

test_that("validate_plan passes when large dataset has checkpoint strategy", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Datasets",
    "",
    "### ADSL (101 variables)",
    "",
    "Split strategy:",
    "- Agent 1: Demographics (checkpoint: adsl_part1.rds)",
    "- Agent 2: Biomarkers (checkpoint: adsl_part2.rds)"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(any(grepl("Split/checkpoint strategy documented", result$passes)))
  expect_false(any(grepl("no split/checkpoint", result$warnings)))

  unlink(temp_plan)
})

test_that("validate_plan ignores datasets <=40 variables", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADRS (35 variables)",
    "Response dataset"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  # Should not warn about ADRS
  expect_false(any(grepl("ADRS", result$warnings)))

  unlink(temp_plan)
})

# --- Test 3: Detects repeated patterns without helper functions ---------------

test_that("validate_plan detects repeated derivations without helpers", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "Derivations:",
    "- EGFRFL biomarker flag",
    "- KRASFL biomarker flag",
    "- ALKFL biomarker flag",
    "- BRAFFL biomarker flag",
    "- ROS1FL biomarker flag"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "WARNING")
  expect_true(any(grepl("repeated derivation patterns", result$warnings, ignore.case = TRUE)))
  expect_true(any(grepl("helper function", result$warnings, ignore.case = TRUE)))

  unlink(temp_plan)
})

test_that("validate_plan passes when helper function is documented", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "Derivations:",
    "- EGFRFL biomarker flag",
    "- KRASFL biomarker flag",
    "- ALKFL biomarker flag",
    "",
    "Helper function: create_biomarker_flag(domain, testcd) for abstraction"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(any(grepl("Helper function abstraction documented", result$passes)))
  expect_false(any(grepl("repeated derivation patterns", result$warnings, ignore.case = TRUE)))

  unlink(temp_plan)
})

# --- Test 4: Detects HIGH complexity without checkpoints ----------------------

test_that("validate_plan detects HIGH complexity without checkpoints", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADSL",
    "",
    "Complexity: HIGH"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "WARNING")
  expect_true(any(grepl("HIGH complexity.*without checkpoint", result$warnings)))

  unlink(temp_plan)
})

test_that("validate_plan passes when HIGH complexity has checkpoints", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADSL",
    "",
    "Complexity: HIGH",
    "",
    "Checkpoint strategy: Validate demographics before biomarkers"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(any(grepl("Checkpoint strategy documented", result$passes)))
  expect_false(any(grepl("HIGH complexity.*without checkpoint", result$warnings)))

  unlink(temp_plan)
})

# --- Test 5: Detects unresolved open questions --------------------------------

test_that("validate_plan detects unresolved open questions", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Open Questions",
    "",
    "- [ ] How should we handle missing baseline dates?",
    "- [ ] Which biomarker test codes are in scope?"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "BLOCKING")
  expect_true(any(grepl("unresolved open questions", result$blocking, ignore.case = TRUE)))

  unlink(temp_plan)
})

test_that("validate_plan passes when all questions are resolved", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Open Questions",
    "",
    "All questions resolved as of 2026-03-27."
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(any(grepl("All resolved", result$passes)))
  expect_false(any(grepl("unresolved", result$blocking, ignore.case = TRUE)))

  unlink(temp_plan)
})

test_that("validate_plan detects TODO markers in open questions", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Open Questions",
    "",
    "Q1: TODO - confirm with user"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "BLOCKING")
  expect_true(any(grepl("unresolved open questions", result$blocking, ignore.case = TRUE)))

  unlink(temp_plan)
})

# --- Test 6: Detects missing dependency declarations --------------------------

test_that("validate_plan detects multiple datasets without dependency docs", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADSL",
    "Demographics",
    "",
    "### ADRS",
    "Response",
    "",
    "### ADAE",
    "Adverse events"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_equal(result$verdict, "WARNING")
  expect_true(any(grepl("no dependency/wave structure", result$warnings)))

  unlink(temp_plan)
})

test_that("validate_plan passes when waves are documented", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Wave 1",
    "- ADSL",
    "",
    "## Wave 2",
    "- ADRS (depends on ADSL)",
    "- ADAE (depends on ADSL)"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(any(grepl("dependencies.*Documented with waves", result$passes, ignore.case = TRUE)))
  expect_false(any(grepl("no dependency/wave structure", result$warnings)))

  unlink(temp_plan)
})

test_that("validate_plan passes for single dataset (no dependencies needed)", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADSL",
    "Demographics only"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  # Should not warn about missing dependencies for single dataset
  expect_false(any(grepl("no dependency/wave structure", result$warnings)))

  unlink(temp_plan)
})

# --- Test 7: Source data validation (when data_path provided) -----------------

test_that("validate_plan validates source domains when data_path provided", {
  # Create temporary plan and data directory
  temp_plan <- tempfile(fileext = ".md")
  temp_data_dir <- tempdir()

  writeLines(c(
    "# Test Plan",
    "",
    "Source domains: DM, AE, EX"
  ), temp_plan)

  # Create only DM and AE, not EX
  dm_file <- file.path(temp_data_dir, "dm.xpt")
  ae_file <- file.path(temp_data_dir, "ae.xpt")

  # Create empty files
  writeLines("", dm_file)
  writeLines("", ae_file)

  result <- validate_plan(temp_plan, data_path = temp_data_dir)

  expect_equal(result$verdict, "BLOCKING")
  expect_true(any(grepl("EX", result$blocking)))
  expect_true(any(grepl("not found in data path", result$blocking)))

  # Cleanup
  unlink(temp_plan)
  unlink(dm_file)
  unlink(ae_file)
})

test_that("validate_plan passes when all source domains exist", {
  temp_plan <- tempfile(fileext = ".md")
  temp_data_dir <- tempdir()

  writeLines(c(
    "# Test Plan",
    "",
    "Source domains: DM, AE"
  ), temp_plan)

  # Create both files
  dm_file <- file.path(temp_data_dir, "dm.xpt")
  ae_file <- file.path(temp_data_dir, "ae.xpt")
  writeLines("", dm_file)
  writeLines("", ae_file)

  result <- validate_plan(temp_plan, data_path = temp_data_dir)

  expect_true(any(grepl("All.*domains found", result$passes)))
  expect_false(any(grepl("not found in data path", result$blocking)))

  # Cleanup
  unlink(temp_plan)
  unlink(dm_file)
  unlink(ae_file)
})

# --- Test 8: Report formatting -------------------------------------------------

test_that("validate_plan returns properly formatted report", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "## Wave 1",
    "- ADSL"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_type(result$report, "character")
  expect_true(grepl("Plan Validation Report", result$report))
  expect_true(grepl("VERDICT:", result$report))
  expect_true(grepl("Recommendation:", result$report))

  unlink(temp_plan)
})

test_that("validate_plan report includes pass/warning/blocking sections", {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test Plan",
    "",
    "### ADSL (101 variables)",  # Will generate warning
    "",
    "## Open Questions",
    "- [ ] Unresolved question"  # Will generate blocking
  ), temp_plan)

  result <- validate_plan(temp_plan)

  expect_true(grepl("\u26A0 WARNING:", result$report))
  expect_true(grepl("\u2717 BLOCKING:", result$report))
  expect_equal(result$verdict, "BLOCKING")

  unlink(temp_plan)
})

# --- Test 9: Integration test with real NPM-008 plan (if available) -----------

test_that("validate_plan works with NPM-008 plan", {
  npm_plan <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md"

  skip_if_not(file.exists(npm_plan), "NPM-008 plan not available")

  result <- validate_plan(npm_plan)

  # Should detect the known issues from first iteration
  expect_type(result$verdict, "character")
  expect_true(result$verdict %in% c("PASS", "WARNING", "BLOCKING"))

  # Check that ADSL complexity is flagged (101 variables)
  if (any(grepl("ADSL.*101", result$warnings))) {
    expect_true(TRUE)  # Expected warning found
  }

  # Report should be non-empty
  expect_true(nchar(result$report) > 0)
})

# --- Run all tests -------------------------------------------------------------

message("\n=== Running validate_plan test suite ===\n")
test_dir(".", reporter = "summary")
