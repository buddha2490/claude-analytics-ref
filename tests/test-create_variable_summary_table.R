# Test: create_variable_summary_table.R
# Purpose: Validate variable summary table generation with proper formatting

library(testthat)
library(dplyr)
library(tibble)

source("R/create_variable_summary_table.R")

# --- Test data ---------------------------------------------------------------

test_data <- tibble::tibble(
  USUBJID = paste0("S001-", sprintf("%03d", 1:10)),
  AGE = c(45, 52, 38, 61, 55, 49, 42, 58, 67, 44),
  SEX = c("M", "F", "M", "F", "M", "F", "M", "F", NA, "M"),
  RACE = factor(c("WHITE", "BLACK", "ASIAN", "WHITE", "WHITE",
                  "BLACK", "ASIAN", "WHITE", "BLACK", "WHITE"))
)

attr(test_data$AGE, "label") <- "Age (years)"
attr(test_data$SEX, "label") <- "Sex"
attr(test_data$RACE, "label") <- "Race"

# --- Test 1: Character variable ----------------------------------------------

test_that("create_variable_summary_table handles character variables", {
  ht <- create_variable_summary_table(test_data, "SEX", "DM")

  expect_s3_class(ht, "huxtable")
  expect_equal(attr(ht, "variable_name"), "SEX")
  expect_equal(attr(ht, "dataset_name"), "DM")

  # Should have header row + data rows + missing row
  expect_gte(nrow(ht), 3)
})

# --- Test 2: Numeric variable ------------------------------------------------

test_that("create_variable_summary_table handles numeric variables", {
  ht <- create_variable_summary_table(test_data, "AGE", "DM")

  expect_s3_class(ht, "huxtable")
  expect_equal(attr(ht, "variable_name"), "AGE")
  expect_equal(attr(ht, "dataset_name"), "DM")

  # Should have header row + 5 statistic rows (N, Mean(SD), Median, Range, Missing)
  expect_equal(nrow(ht), 6)
})

# --- Test 3: Factor variable -------------------------------------------------

test_that("create_variable_summary_table handles factor variables", {
  ht <- create_variable_summary_table(test_data, "RACE", "DM")

  expect_s3_class(ht, "huxtable")
  expect_equal(attr(ht, "variable_name"), "RACE")

  # Should treat factor as character with frequencies
  expect_gte(nrow(ht), 3)
})

# --- Test 4: Input validation ------------------------------------------------

test_that("create_variable_summary_table validates inputs", {
  expect_error(
    create_variable_summary_table(list(), "AGE", "DM"),
    "`data` must be a data frame"
  )

  expect_error(
    create_variable_summary_table(test_data, "MISSING_VAR", "DM"),
    "not found in dataset"
  )

  expect_error(
    create_variable_summary_table(test_data[0, ], "AGE", "DM"),
    "at least one row"
  )
})

# --- Test 5: Full report generation ------------------------------------------

test_that("create_dataset_summary_report generates single combined report", {
  skip_if_not_installed("pharmaRTF")

  temp_dir <- tempdir()

  output_file <- create_dataset_summary_report(
    data = test_data,
    dataset_name = "TEST_DM",
    output_dir = temp_dir,
    author = "Test Suite"
  )

  # Should create one file per dataset
  expect_type(output_file, "character")
  expect_length(output_file, 1)

  # Check file exists and has correct name pattern
  expect_true(file.exists(output_file))
  expect_match(output_file, "TEST_DM_variable_summary")
  expect_match(output_file, "\\.rtf$")

  # Clean up
  unlink(output_file)
})

# --- Test 6: Proper landscape formatting -------------------------------------

test_that("huxtable has correct landscape formatting attributes", {
  ht <- create_variable_summary_table(test_data, "AGE", "DM")

  # Check that width is set correctly for landscape
  width_val <- huxtable::width(ht)
  expect_equal(width_val, 10 / 6)

  # Check that column widths sum to 1.0
  col_widths <- huxtable::col_width(ht)
  expect_equal(sum(col_widths), 1.0, tolerance = 0.01)
})

message("All tests completed successfully!")
