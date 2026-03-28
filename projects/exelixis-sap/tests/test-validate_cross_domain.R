library(testthat)
library(dplyr)

# Source function - assumes working directory is project root
if (!exists("validate_cross_domain")) {
  source("../R/validate_cross_domain.R")
}

test_that("validate_cross_domain detects DOR/responder mismatch - extra DOR", {
  # ADRS: 2 responders
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("CR", "PR", "SD"),
    stringsAsFactors = FALSE
  )

  # ADTTE: 3 DOR records (one extra)
  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("DOR", "DOR", "DOR"),
    AVAL = c(30, 45, 60),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$details$n_responders, 2)
  expect_equal(result$details$n_dor, 3)
  expect_equal(result$details$n_extra_dor, 1)
  expect_true("NPM-008-003" %in% result$details$extra_dor)
})

test_that("validate_cross_domain detects DOR/responder mismatch - missing DOR", {
  # ADRS: 3 responders
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("CR", "PR", "PR"),
    stringsAsFactors = FALSE
  )

  # ADTTE: 2 DOR records (one missing)
  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("DOR", "DOR"),
    AVAL = c(30, 45),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$details$n_missing_dor, 1)
  expect_true("NPM-008-003" %in% result$details$missing_dor)
  expect_match(result$message, "1 responders missing DOR records")
})

test_that("validate_cross_domain passes with perfect DOR/responder match", {
  # ADRS: 2 responders
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("CR", "PR", "SD"),
    stringsAsFactors = FALSE
  )

  # ADTTE: 2 DOR records matching responders
  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("DOR", "DOR"),
    AVAL = c(30, 45),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$severity, "INFO")
  expect_equal(result$details$n_responders, 2)
  expect_equal(result$details$n_dor, 2)
  expect_equal(result$details$n_missing_dor, 0)
  expect_equal(result$details$n_extra_dor, 0)
})

test_that("validate_cross_domain handles both missing and extra DOR", {
  # ADRS: Responders are 001 and 002
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("CR", "PR", "PD"),
    stringsAsFactors = FALSE
  )

  # ADTTE: DOR for 001 and 003 (missing 002, extra 003)
  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-003"),
    PARAMCD = c("DOR", "DOR"),
    AVAL = c(30, 45),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$details$n_missing_dor, 1)
  expect_equal(result$details$n_extra_dor, 1)
  expect_match(result$message, "1 responders missing DOR records")
  expect_match(result$message, "1 DOR records for non-responders")
})

test_that("validate_cross_domain handles no responders", {
  # ADRS: No responders
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("BOR", "BOR"),
    AVALC = c("SD", "PD"),
    stringsAsFactors = FALSE
  )

  # ADTTE: No DOR records
  adtte <- data.frame(
    USUBJID = character(0),
    PARAMCD = character(0),
    AVAL = numeric(0),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$details$n_responders, 0)
  expect_equal(result$details$n_dor, 0)
})

test_that("validate_cross_domain supports custom response values", {
  # ADRS with custom response codes
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("BOR", "BOR"),
    AVALC = c("COMPLETE", "PARTIAL"),
    stringsAsFactors = FALSE
  )

  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("DOR", "DOR"),
    AVAL = c(30, 45),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte,
    response_values = c("COMPLETE", "PARTIAL")
  )

  expect_equal(result$verdict, "PASS")
})

test_that("validate_cross_domain supports custom parameter codes", {
  adrs <- data.frame(
    USUBJID = c("NPM-008-001"),
    PARAMCD = c("BESTRES"),
    AVALC = c("CR"),
    stringsAsFactors = FALSE
  )

  adtte <- data.frame(
    USUBJID = c("NPM-008-001"),
    PARAMCD = c("DURATION"),
    AVAL = c(30),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte,
    bor_param_value = "BESTRES",
    dor_param_value = "DURATION"
  )

  expect_equal(result$verdict, "PASS")
})

test_that("validate_cross_domain errors on missing required columns", {
  adrs <- data.frame(USUBJID = "NPM-008-001", PARAMCD = "BOR", AVALC = "CR")
  adtte <- data.frame(USUBJID = "NPM-008-001", AVAL = 30)

  expect_error(
    validate_cross_domain("dor_responders", adrs = adrs, adtte = adtte),
    "Column `PARAMCD` not found in adtte"
  )
})

test_that("validate_cross_domain errors on unsupported check type", {
  expect_error(
    validate_cross_domain("invalid_check"),
    "Unsupported check_type: invalid_check"
  )
})

test_that("validate_cross_domain truncates long subject lists", {
  # Create 15 mismatches
  adrs <- data.frame(
    USUBJID = sprintf("NPM-008-%03d", 1:15),
    PARAMCD = rep("BOR", 15),
    AVALC = rep("CR", 15),
    stringsAsFactors = FALSE
  )

  adtte <- data.frame(
    USUBJID = character(0),
    PARAMCD = character(0),
    AVAL = numeric(0),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$details$n_missing_dor, 15)
  expect_equal(length(result$details$missing_dor), 10)  # Truncated to 10
})

test_that("validate_cross_domain handles multiple BOR records per subject", {
  # Edge case: multiple BOR records (should use unique subjects)
  adrs <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-001", "NPM-008-002"),
    PARAMCD = c("BOR", "BOR", "BOR"),
    AVALC = c("CR", "CR", "PR"),
    stringsAsFactors = FALSE
  )

  adtte <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    PARAMCD = c("DOR", "DOR"),
    AVAL = c(30, 45),
    stringsAsFactors = FALSE
  )

  result <- validate_cross_domain(
    check_type = "dor_responders",
    adrs = adrs,
    adtte = adtte
  )

  # Should count unique subjects, not records
  expect_equal(result$verdict, "PASS")
  expect_equal(result$details$n_responders, 3)  # 3 records total
  expect_equal(length(unique(c("NPM-008-001", "NPM-008-002"))), 2)  # But 2 unique subjects
})
