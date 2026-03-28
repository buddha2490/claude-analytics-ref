library(testthat)
library(dplyr)

# Source function - assumes working directory is project root
if (!exists("validate_date_consistency")) {
  source("R/validate_date_consistency.R")
}

test_that("validate_date_consistency detects TRTEMFL violations", {
  # Create reference data with treatment start dates
  reference <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    TRTSDT = as.Date(c("2023-01-15", "2023-02-01")),
    stringsAsFactors = FALSE
  )

  # Create event data with one violation
  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-002"),
    AESTDT = as.Date(c("2023-01-20", "2023-01-15", "2023-02-05")),
    TRTEMFL = c("Y", "Y", "Y"),
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "AESTDT",
    reference_date_var = "TRTSDT",
    flag_var = "TRTEMFL",
    check_name = "TRTEMFL vs TRTSDT"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$n_violations, 1)
  expect_match(result$message, "Found 1/3 records")
  expect_true(nrow(result$violations) > 0)
  expect_equal(result$violations$USUBJID[1], "NPM-008-002")
})

test_that("validate_date_consistency passes with all valid dates", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    TRTSDT = as.Date(c("2023-01-15", "2023-02-01")),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    AESTDT = as.Date(c("2023-01-15", "2023-02-01")),  # On or after TRTSDT
    TRTEMFL = c("Y", "Y"),
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "AESTDT",
    reference_date_var = "TRTSDT",
    flag_var = "TRTEMFL",
    check_name = "TRTEMFL vs TRTSDT"
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$severity, "INFO")
  expect_equal(result$n_violations, 0)
})

test_that("validate_date_consistency ignores non-flagged records", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    TRTSDT = as.Date(c("2023-01-15", "2023-02-01")),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-002"),
    AESTDT = as.Date(c("2023-01-20", "2023-01-15", "2023-02-05")),
    TRTEMFL = c("Y", "N", "Y"),  # Middle record not flagged
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "AESTDT",
    reference_date_var = "TRTSDT",
    flag_var = "TRTEMFL",
    check_name = "TRTEMFL vs TRTSDT"
  )

  expect_equal(result$verdict, "PASS")  # Only checks TRTEMFL='Y' records
})

test_that("validate_date_consistency handles <= constraint", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001"),
    ENDDT = as.Date("2023-12-31"),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-001"),
    EVENTDT = as.Date(c("2023-12-30", "2024-01-05")),
    FLAG = c("Y", "Y"),
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "EVENTDT",
    reference_date_var = "ENDDT",
    flag_var = "FLAG",
    constraint = "<=",
    check_name = "Event date <= End date"
  )

  expect_equal(result$verdict, "WARNING")  # Non-TRTEMFL violations are warnings
  expect_equal(result$n_violations, 1)
})

test_that("validate_date_consistency returns PASS when no flagged records", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001"),
    TRTSDT = as.Date("2023-01-15"),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001"),
    AESTDT = as.Date("2023-01-20"),
    TRTEMFL = c("N"),  # No flagged records
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "AESTDT",
    reference_date_var = "TRTSDT",
    flag_var = "TRTEMFL",
    check_name = "TRTEMFL vs TRTSDT"
  )

  expect_equal(result$verdict, "PASS")
  expect_match(result$message, "No records with TRTEMFL='Y'")
})

test_that("validate_date_consistency errors on missing columns", {
  reference <- data.frame(USUBJID = "NPM-008-001", TRTSDT = as.Date("2023-01-15"))
  event <- data.frame(USUBJID = "NPM-008-001", AESTDT = as.Date("2023-01-20"), TRTEMFL = "Y")

  # Missing event date variable
  expect_error(
    validate_date_consistency(
      event_data = event,
      reference_data = reference,
      event_date_var = "BADVAR",
      reference_date_var = "TRTSDT",
      flag_var = "TRTEMFL"
    ),
    "Column `BADVAR` not found"
  )

  # Missing reference date variable
  expect_error(
    validate_date_consistency(
      event_data = event,
      reference_data = reference,
      event_date_var = "AESTDT",
      reference_date_var = "BADVAR",
      flag_var = "TRTEMFL"
    ),
    "Column `BADVAR` not found"
  )

  # Missing flag variable
  expect_error(
    validate_date_consistency(
      event_data = event,
      reference_data = reference,
      event_date_var = "AESTDT",
      reference_date_var = "TRTSDT",
      flag_var = "BADVAR"
    ),
    "Column `BADVAR` not found"
  )
})

test_that("validate_date_consistency supports custom flag values", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001"),
    TRTSDT = as.Date("2023-01-15"),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-001"),
    AESTDT = as.Date(c("2023-01-10", "2023-01-20")),
    FLAG = c("TRUE", "TRUE"),
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "AESTDT",
    reference_date_var = "TRTSDT",
    flag_var = "FLAG",
    flag_value = "TRUE",
    check_name = "Custom flag"
  )

  expect_equal(result$n_violations, 1)
})

test_that("validate_date_consistency handles > constraint", {
  reference <- data.frame(
    USUBJID = c("NPM-008-001"),
    STARTDT = as.Date("2023-01-15"),
    stringsAsFactors = FALSE
  )

  event <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-001"),
    EVENTDT = as.Date(c("2023-01-15", "2023-01-16")),
    FLAG = c("Y", "Y"),
    stringsAsFactors = FALSE
  )

  result <- validate_date_consistency(
    event_data = event,
    reference_data = reference,
    event_date_var = "EVENTDT",
    reference_date_var = "STARTDT",
    flag_var = "FLAG",
    constraint = ">",
    check_name = "Event date > Start date"
  )

  expect_equal(result$n_violations, 1)  # 2023-01-15 not > 2023-01-15
})
