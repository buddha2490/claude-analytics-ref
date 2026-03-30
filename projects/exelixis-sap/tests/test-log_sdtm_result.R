# Test: log_sdtm_result.R

library(testthat)
library(withr)

# Source the function
source("../R/log_sdtm_result.R")

# --- Create mock validation result ---
create_mock_validation_pass <- function() {
  list(
    verdict = "PASS",
    checks = data.frame(
      check_id = c("U1", "U2", "U3"),
      description = c("Check 1", "Check 2", "Check 3"),
      result = c("PASS", "PASS", "PASS"),
      detail = c("", "", ""),

    ),
    summary = "AE validation: PASS (3 PASS, 0 FAIL, 0 WARNING)"
  )
}

create_mock_validation_fail <- function() {
  list(
    verdict = "FAIL",
    checks = data.frame(
      check_id = c("U1", "U2", "U3", "U4"),
      description = c("Check 1", "Check 2", "Check 3", "Check 4"),
      result = c("PASS", "FAIL", "PASS", "FAIL"),
      detail = c("", "Detail for failure 1", "", "Detail for failure 2"),

    ),
    summary = "AE validation: FAIL (2 PASS, 2 FAIL, 0 WARNING)"
  )
}

create_mock_validation_warning <- function() {
  list(
    verdict = "PASS",
    checks = data.frame(
      check_id = c("U1", "U2", "U8"),
      description = c("Check 1", "Check 2", "Row count check"),
      result = c("PASS", "PASS", "WARNING"),
      detail = c("", "", "Actual: 150, Expected: [100, 120]"),

    ),
    summary = "AE validation: PASS (2 PASS, 0 FAIL, 1 WARNING)"
  )
}

# === Test log file creation ===
test_that("Log file is created if it doesn't exist", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))

  expect_true(file.exists(log_path))
})

test_that("Log file has header when created", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  expect_true(any(grepl("# SDTM Domain Validation Log", log_content)))
  expect_true(any(grepl("Study.*NPM-008", log_content)))
})

# === Test log entry format ===
test_that("Log entry has correct structure", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  # Check for section header
  expect_true(any(grepl("### AE —", log_content)))

  # Check for required fields
  expect_true(any(grepl("\\*\\*Wave:\\*\\*", log_content)))
  expect_true(any(grepl("\\*\\*Rows:\\*\\*", log_content)))
  expect_true(any(grepl("\\*\\*Columns:\\*\\*", log_content)))
  expect_true(any(grepl("\\*\\*Validation:\\*\\*", log_content)))
  expect_true(any(grepl("\\*\\*Checks:\\*\\*", log_content)))
})

test_that("Log entry contains correct values", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "DM",
    wave = 2,
    row_count = 40,
    col_count = 25,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  expect_true(any(grepl("### DM —", log_content)))
  expect_true(any(grepl("Wave:\\*\\* 2", log_content)))
  expect_true(any(grepl("Rows:\\*\\* 40", log_content)))
  expect_true(any(grepl("Columns:\\*\\* 25", log_content)))
  expect_true(any(grepl("Validation:\\*\\* PASS", log_content)))
})

# === Test append behavior ===
test_that("Multiple calls append to same log file", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  # First call
  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  # Second call
  log_sdtm_result(
    domain_code = "CM",
    wave = 1,
    row_count = 80,
    col_count = 18,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  # Both entries should be present
  expect_true(any(grepl("### AE —", log_content)))
  expect_true(any(grepl("### CM —", log_content)))

  # Header should only appear once
  header_count <- sum(grepl("# SDTM Domain Validation Log", log_content))
  expect_equal(header_count, 1)
})

# === Test notes handling ===
test_that("NULL notes are handled correctly", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    notes = NULL,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  # Notes section should not be present
  expect_false(any(grepl("\\*\\*Notes:\\*\\*", log_content)))
})

test_that("Character vector notes are formatted correctly", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    notes = c("First note", "Second note"),
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  # Notes section should be present
  expect_true(any(grepl("\\*\\*Notes:\\*\\*", log_content)))
  expect_true(any(grepl("First note", log_content)))
  expect_true(any(grepl("Second note", log_content)))
})

# === Test validation result parsing ===
test_that("PASS verdict is logged correctly", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  expect_true(any(grepl("Validation:\\*\\* PASS", log_content)))
  expect_true(any(grepl("Checks:\\*\\* 3/3 PASS", log_content)))

  # Should not have Failed Checks section
  expect_false(any(grepl("\\*\\*Failed Checks:", log_content)))
})

test_that("FAIL verdict is logged with details", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_fail()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  expect_true(any(grepl("Validation:\\*\\* FAIL", log_content)))
  expect_true(any(grepl("Checks:\\*\\* 2/4 PASS, 2 FAIL", log_content)))

  # Should have Failed Checks section
  expect_true(any(grepl("\\*\\*Failed Checks:", log_content)))
  expect_true(any(grepl("Detail for failure 1", log_content)))
  expect_true(any(grepl("Detail for failure 2", log_content)))
})

test_that("WARNING verdict is logged with details", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_warning()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  expect_true(any(grepl("Validation:\\*\\* PASS", log_content)))
  expect_true(any(grepl("Checks:\\*\\* 2/3 PASS, 1 WARNING", log_content)))

  # Should have Warnings section
  expect_true(any(grepl("\\*\\*Warnings:", log_content)))
  expect_true(any(grepl("Actual: 150, Expected: \\[100, 120\\]", log_content)))
})

# === Test timestamp format ===
test_that("Timestamp format is correct", {
  local_tempdir <- withr::local_tempdir()

  validation_result <- create_mock_validation_pass()

  log_sdtm_result(
    domain_code = "AE",
    wave = 1,
    row_count = 100,
    col_count = 20,
    validation_result = validation_result,
    log_dir = local_tempdir
  )

  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(local_tempdir, paste0("sdtm_domain_log_", log_date, ".md"))
  log_content <- readLines(log_path)

  # Look for timestamp pattern YYYY-MM-DD HH:MM:SS
  timestamp_line <- grep("### AE —", log_content, value = TRUE)
  expect_true(grepl("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", timestamp_line))
})

# === Test input validation ===
test_that("Invalid domain_code triggers error", {
  local_tempdir <- withr::local_tempdir()
  validation_result <- create_mock_validation_pass()

  expect_error(
    log_sdtm_result(c("AE", "CM"), 1, 100, 20, validation_result, log_dir = local_tempdir),
    "`domain_code` must be a single character string"
  )
})

test_that("Invalid wave triggers error", {
  local_tempdir <- withr::local_tempdir()
  validation_result <- create_mock_validation_pass()

  expect_error(
    log_sdtm_result("AE", "one", 100, 20, validation_result, log_dir = local_tempdir),
    "`wave` must be a single numeric value"
  )
})

test_that("Invalid validation_result triggers error", {
  local_tempdir <- withr::local_tempdir()

  expect_error(
    log_sdtm_result("AE", 1, 100, 20, "not a list", log_dir = local_tempdir),
    "`validation_result` must be a list"
  )
})

test_that("Incomplete validation_result triggers error", {
  local_tempdir <- withr::local_tempdir()

  incomplete_result <- list(verdict = "PASS")

  expect_error(
    log_sdtm_result("AE", 1, 100, 20, incomplete_result, log_dir = local_tempdir),
    "must contain 'verdict', 'checks', and 'summary'"
  )
})

message("\n=== All log_sdtm_result tests completed ===\n")
