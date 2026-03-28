library(testthat)
library(dplyr)

# Source function - assumes working directory is project root
if (!exists("validate_derived_variables")) {
  source("R/validate_derived_variables.R")
}

test_that("validate_derived_variables detects cardinality violations for one_per_subject", {
  # Create dataset with BOR parameter where one subject has 2 records
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR", "BOR"),
    AVALC = c("PR", "CR", "CR", "SD"),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$n_violations, 1)
  expect_true(any(result$violations$USUBJID == "NPM-008-002"))
})

test_that("validate_derived_variables passes with correct one_per_subject cardinality", {
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("PR", "CR", "SD"),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$severity, "INFO")
  expect_equal(result$n_violations, 0)
})

test_that("validate_derived_variables detects missing subjects for one_per_subject", {
  # Dataset has 4 subjects but only 3 have BOR
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003", "NPM-008-004",
                "NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR", "OTHER", "OTHER", "OTHER", "OTHER"),
    AVALC = c("PR", "CR", "SD", "X", "Y", "Z", "W"),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$n_violations, 1)  # NPM-008-004 missing BOR
  expect_match(result$message, "1 subjects with n = 0")
})

test_that("validate_derived_variables handles zero_or_one_per_subject", {
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("DOR", "DOR", "DOR", "OTHER"),
    AVAL = c(30, 45, 60, 10),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "DOR",
    expected_cardinality = "zero_or_one_per_subject",
    check_name = "DOR cardinality"
  )

  expect_equal(result$verdict, "WARNING")
  expect_equal(result$severity, "WARNING")
  expect_equal(result$n_violations, 1)  # NPM-008-002 has 2 records
})

test_that("validate_derived_variables allows multiple_allowed", {
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-001", "NPM-008-002"),
    PARAMCD = c("VISIT", "VISIT", "VISIT"),
    AVAL = c(1, 2, 1),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "VISIT",
    expected_cardinality = "multiple_allowed",
    check_name = "VISIT cardinality"
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$n_violations, 0)
})

test_that("validate_derived_variables warns when parameter not found", {
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("BOR", "BOR"),
    AVALC = c("PR", "CR"),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "NOTFOUND",
    expected_cardinality = "one_per_subject",
    check_name = "Missing parameter"
  )

  expect_equal(result$verdict, "WARNING")
  expect_match(result$message, "No records found with PARAMCD='NOTFOUND'")
})

test_that("validate_derived_variables detects multiple violation types", {
  # Some subjects missing, some with duplicates
  data <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-002", "NPM-008-003",
                "NPM-008-004", "NPM-008-005"),
    PARAMCD = c("BOR", "BOR", "BOR", "OTHER", "BOR", "OTHER"),
    AVALC = c("PR", "CR", "SD", "X", "PD", "Y"),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "FAIL")
  # Should detect: NPM-008-002 (duplicate), NPM-008-003 and NPM-008-005 (missing)
  expect_equal(result$n_violations, 3)
  expect_match(result$message, "1 subjects with n != 1")
  expect_match(result$message, "2 subjects with n = 0")
})

test_that("validate_derived_variables errors on missing USUBJID", {
  data <- data.frame(
    SUBJECT_ID = c("NPM-008-001"),
    PARAMCD = c("BOR"),
    stringsAsFactors = FALSE
  )

  expect_error(
    validate_derived_variables(data, "PARAMCD", "BOR", "one_per_subject"),
    "Column `USUBJID` not found"
  )
})

test_that("validate_derived_variables errors on missing param_var", {
  data <- data.frame(
    USUBJID = c("NPM-008-001"),
    PARAM = c("BOR"),
    stringsAsFactors = FALSE
  )

  expect_error(
    validate_derived_variables(data, "PARAMCD", "BOR", "one_per_subject"),
    "Column `PARAMCD` not found"
  )
})

test_that("validate_derived_variables errors on invalid cardinality", {
  data <- data.frame(
    USUBJID = c("NPM-008-001"),
    PARAMCD = c("BOR"),
    stringsAsFactors = FALSE
  )

  expect_error(
    validate_derived_variables(data, "PARAMCD", "BOR", "invalid"),
    "`expected_cardinality` must be one of"
  )
})

test_that("validate_derived_variables handles large datasets efficiently", {
  # Create dataset with 100 subjects
  n_subjects <- 100
  data <- data.frame(
    USUBJID = rep(sprintf("NPM-008-%03d", 1:n_subjects), each = 2),
    PARAMCD = rep(c("BOR", "OTHER"), times = n_subjects),
    AVALC = rep(c("PR", "X"), times = n_subjects),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$n_violations, 0)
})

test_that("validate_derived_variables truncates violation list", {
  # Create dataset with many violations
  data <- data.frame(
    USUBJID = rep(sprintf("NPM-008-%03d", 1:15), each = 2),
    PARAMCD = rep("BOR", 30),
    AVALC = rep("PR", 30),
    stringsAsFactors = FALSE
  )

  result <- validate_derived_variables(
    data = data,
    param_var = "PARAMCD",
    param_value = "BOR",
    expected_cardinality = "one_per_subject",
    check_name = "BOR cardinality"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$n_violations, 15)
  expect_equal(nrow(result$violations), 10)  # Truncated to 10 rows
})
