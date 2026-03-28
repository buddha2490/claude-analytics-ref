library(testthat)
library(dplyr)

# Source function - assumes working directory is project root
if (!exists("validate_referential_integrity")) {
  source("R/validate_referential_integrity.R")
}

test_that("validate_referential_integrity detects all orphan records", {
  # Create parent dataset (DM)
  parent <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  # Create child dataset with one orphan
  child <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-999"),
    AVAL = c(1, 2, 3),
    stringsAsFactors = FALSE
  )

  result <- validate_referential_integrity(
    child_data = child,
    parent_data = parent,
    child_name = "ADSL",
    parent_name = "DM"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$severity, "CRITICAL")
  expect_equal(result$n_missing, 1)
  expect_equal(result$missing_ids, "NPM-008-999")
  expect_match(result$message, "NPM-008-999")
})

test_that("validate_referential_integrity passes with perfect integrity", {
  parent <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  child <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002"),
    AVAL = c(1, 2),
    stringsAsFactors = FALSE
  )

  result <- validate_referential_integrity(
    child_data = child,
    parent_data = parent,
    child_name = "ADSL",
    parent_name = "DM"
  )

  expect_equal(result$verdict, "PASS")
  expect_equal(result$severity, "INFO")
  expect_equal(result$n_missing, 0)
  expect_length(result$missing_ids, 0)
})

test_that("validate_referential_integrity handles multiple orphans", {
  parent <- data.frame(
    USUBJID = c("NPM-008-001"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  child <- data.frame(
    USUBJID = c("NPM-008-001", "NPM-008-002", "NPM-008-003", "NPM-008-004"),
    AVAL = c(1, 2, 3, 4),
    stringsAsFactors = FALSE
  )

  result <- validate_referential_integrity(
    child_data = child,
    parent_data = parent,
    child_name = "ADAE",
    parent_name = "ADSL"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$n_missing, 3)
  expect_equal(result$pct_missing, 75)
  expect_setequal(result$missing_ids, c("NPM-008-002", "NPM-008-003", "NPM-008-004"))
})

test_that("validate_referential_integrity truncates long orphan lists", {
  parent <- data.frame(
    USUBJID = c("NPM-008-001"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  # Create 15 orphans
  orphan_ids <- paste0("NPM-008-", sprintf("%03d", 2:16))
  child <- data.frame(
    USUBJID = c("NPM-008-001", orphan_ids),
    AVAL = seq_len(16),
    stringsAsFactors = FALSE
  )

  result <- validate_referential_integrity(
    child_data = child,
    parent_data = parent,
    child_name = "ADAE",
    parent_name = "ADSL"
  )

  expect_equal(result$n_missing, 15)
  expect_match(result$message, "and 5 more")  # Shows first 10, then "and 5 more"
})

test_that("validate_referential_integrity errors on missing ID column", {
  parent <- data.frame(
    USUBJID = c("NPM-008-001"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  child <- data.frame(
    SUBJECT_ID = c("NPM-008-001"),  # Wrong column name
    AVAL = 1,
    stringsAsFactors = FALSE
  )

  expect_error(
    validate_referential_integrity(child, parent, "ADSL", "DM"),
    "Column `USUBJID` not found in child dataset"
  )
})

test_that("validate_referential_integrity errors on non-data-frame inputs", {
  parent <- data.frame(USUBJID = "NPM-008-001")

  expect_error(
    validate_referential_integrity("not a df", parent, "ADSL", "DM"),
    "`child_data` must be a data frame"
  )

  expect_error(
    validate_referential_integrity(parent, "not a df", "ADSL", "DM"),
    "`parent_data` must be a data frame"
  )
})

test_that("validate_referential_integrity handles custom ID variable", {
  parent <- data.frame(
    SUBJID = c("001", "002", "003"),
    STUDYID = "NPM-008",
    stringsAsFactors = FALSE
  )

  child <- data.frame(
    SUBJID = c("001", "999"),
    AVAL = c(1, 2),
    stringsAsFactors = FALSE
  )

  result <- validate_referential_integrity(
    child_data = child,
    parent_data = parent,
    child_name = "ADSL",
    parent_name = "DM",
    id_var = "SUBJID"
  )

  expect_equal(result$verdict, "FAIL")
  expect_equal(result$missing_ids, "999")
})
