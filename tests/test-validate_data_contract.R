library(testthat)
library(haven)
library(dplyr)
library(stringr)

# Source the function
source("R/validate_data_contract.R")

test_that("validate_data_contract validates inputs correctly", {
  expect_error(
    validate_data_contract(plan_path = 123, sdtm_path = "path"),
    "`plan_path` must be a single character string"
  )

  expect_error(
    validate_data_contract(plan_path = "nonexistent.md", sdtm_path = "path"),
    "Plan file not found"
  )

  expect_error(
    validate_data_contract(
      plan_path = "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md",
      sdtm_path = "nonexistent"
    ),
    "SDTM directory not found"
  )
})

test_that("extract_source_variable_tables parses plan correctly", {
  # Create a minimal test plan
  plan_lines <- c(
    "# Test Plan",
    "",
    "**Source variables:**",
    "",
    "| Domain | Variables | Purpose |",
    "|--------|-----------|---------|",
    "| DM | USUBJID, AGE, SEX | Demographics |",
    "| AE | USUBJID, AETERM, AESTDTC | Adverse events |",
    "",
    "Some other text",
    "",
    "**Source variables:**",
    "",
    "| Domain | Variables | Purpose |",
    "|--------|-----------|---------|",
    "| EX | USUBJID, EXDOSE | Exposure |"
  )

  result <- extract_source_variable_tables(plan_lines)

  expect_type(result, "list")
  expect_true("DM" %in% names(result))
  expect_true("AE" %in% names(result))
  expect_true("EX" %in% names(result))

  expect_equal(sort(result$DM), sort(c("USUBJID", "AGE", "SEX")))
  expect_equal(sort(result$AE), sort(c("USUBJID", "AETERM", "AESTDTC")))
  expect_equal(sort(result$EX), sort(c("USUBJID", "EXDOSE")))
})

test_that("find_alternative_variable detects common substitutions", {
  actual_vars <- c("USUBJID", "MHSTDTC", "MHTERM", "QSORRES")

  # MHDTC -> MHSTDTC
  result <- find_alternative_variable("MHDTC", actual_vars)
  expect_equal(result, "MHSTDTC")

  # QSSTRESN -> QSORRES
  result <- find_alternative_variable("QSSTRESN", actual_vars)
  expect_equal(result, "QSORRES")

  # No alternative exists
  result <- find_alternative_variable("NOTEXIST", actual_vars)
  expect_null(result)
})

test_that("validate_data_contract works end-to-end with real plan", {
  plan_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md"
  sdtm_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/sdtm"

  # Skip if data doesn't exist
  if (!dir.exists(sdtm_path)) {
    skip("SDTM data directory not found")
  }

  result <- validate_data_contract(
    plan_path = plan_path,
    sdtm_path = sdtm_path
  )

  expect_type(result, "list")
  expect_true("verdict" %in% names(result))
  expect_true("issues" %in% names(result))
  expect_true("report" %in% names(result))
  expect_true("summary" %in% names(result))

  expect_true(result$verdict %in% c("PASS", "FAIL"))
  expect_s3_class(result$issues, "data.frame")
  expect_type(result$report, "character")

  # Report should be formatted markdown
  expect_true(grepl("Data Contract Validation Report", result$report))
  expect_true(grepl("VERDICT:", result$report))
})

test_that("validate_data_contract can filter specific domains", {
  plan_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md"
  sdtm_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/sdtm"

  # Skip if data doesn't exist
  if (!dir.exists(sdtm_path)) {
    skip("SDTM data directory not found")
  }

  result <- validate_data_contract(
    plan_path = plan_path,
    sdtm_path = sdtm_path,
    domains = c("DM", "AE")
  )

  expect_type(result, "list")

  # If there are issues, they should only be for DM or AE
  if (nrow(result$issues) > 0) {
    expect_true(all(result$issues$domain %in% c("DM", "AE")))
  }
})

# Run tests
test_file("/Users/briancarter/Rdata/claude-analytics-ref/tests/test-validate_data_contract.R")
