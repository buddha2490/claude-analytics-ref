# Test file for summarize_variable()

library(testthat)
library(tibble)
library(lubridate)
library(stringr)

# Source all required functions
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_numeric.R")
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_character.R")
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_date.R")
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_variable.R")

test_that("summarize_variable routes numeric variables correctly", {
  x <- c(1, 2, 3, 4, 5)
  result <- summarize_variable(x, "AGE")

  expect_s3_class(result, "tbl_df")
  expect_true("Mean" %in% names(result))
  expect_true("SD" %in% names(result))
  expect_equal(result$Variable, "AGE")
})

test_that("summarize_variable routes integer variables correctly", {
  x <- as.integer(c(1, 2, 3, 4, 5))
  result <- summarize_variable(x, "COUNT")

  expect_s3_class(result, "tbl_df")
  expect_true("Mean" %in% names(result))
  expect_equal(result$Variable, "COUNT")
})

test_that("summarize_variable routes character variables correctly", {
  x <- c("A", "B", "A", "C")
  result <- summarize_variable(x, "SEX")

  expect_s3_class(result, "tbl_df")
  expect_true("N (%)" %in% names(result))
  expect_equal(result$Variable[1], "SEX")
})

test_that("summarize_variable routes factor variables correctly", {
  x <- factor(c("Low", "High", "Medium", "High"))
  result <- summarize_variable(x, "GRADE")

  expect_s3_class(result, "tbl_df")
  expect_true("N (%)" %in% names(result))
  expect_equal(result$Variable[1], "GRADE")
})

test_that("summarize_variable routes Date variables correctly", {
  x <- as.Date(c("2024-01-01", "2024-01-15", "2024-01-31"))
  result <- summarize_variable(x, "REFDT")

  expect_s3_class(result, "tbl_df")
  expect_true("Earliest Date" %in% names(result))
  expect_true("Latest Date" %in% names(result))
  expect_equal(result$Variable, "REFDT")
})

test_that("summarize_variable treats variables ending in DT as dates", {
  # Character vector that ends in "DT" should be routed to date summary
  x <- c("2024-01-01", "2024-01-15", "2024-01-31")
  result <- summarize_variable(x, "STARTDT")

  expect_s3_class(result, "tbl_df")
  expect_true("Earliest Date" %in% names(result))
  expect_true("Latest Date" %in% names(result))
  expect_equal(result$Variable, "STARTDT")
})

test_that("summarize_variable does NOT treat DTC variables as dates", {
  # Variables ending in "DTC" should be treated as character
  x <- c("2024-01-01", "2024-01", "2024")
  result <- summarize_variable(x, "STARTDTC")

  expect_s3_class(result, "tbl_df")
  expect_true("N (%)" %in% names(result))
  expect_equal(result$Variable[1], "STARTDTC")
})

test_that("summarize_variable handles variable name case sensitivity", {
  # "dt" suffix should not trigger date handling (only "DT")
  x <- c("value1", "value2", "value1")
  result <- summarize_variable(x, "myvarDt")

  # Should still treat as character since lowercase "t"
  expect_true("N (%)" %in% names(result))
})

test_that("summarize_variable errors on unsupported types", {
  x <- list(a = 1, b = 2)
  expect_error(
    summarize_variable(x, "TEST_VAR"),
    "Cannot summarize variable of type: list"
  )
})

test_that("summarize_variable errors on invalid var_name", {
  expect_error(
    summarize_variable(c(1, 2, 3), c("VAR1", "VAR2")),
    "`var_name` must be a single character string."
  )

  expect_error(
    summarize_variable(c(1, 2, 3), 123),
    "`var_name` must be a single character string."
  )
})

test_that("summarize_variable preserves variable name in output", {
  x_num <- c(1, 2, 3)
  x_char <- c("A", "B", "A")

  result_num <- summarize_variable(x_num, "MY_NUM_VAR")
  result_char <- summarize_variable(x_char, "MY_CHAR_VAR")

  expect_equal(result_num$Variable, "MY_NUM_VAR")
  expect_equal(result_char$Variable[1], "MY_CHAR_VAR")
})

test_that("summarize_variable handles DT suffix with mixed case correctly", {
  # "STARTDT" should trigger date handling
  x <- c("2024-01-01", "2024-01-15")
  result <- summarize_variable(x, "STARTDT")

  expect_true("Earliest Date" %in% names(result))

  # "STARTdt" should NOT trigger date handling (lowercase)
  result2 <- summarize_variable(x, "STARTdt")
  expect_true("N (%)" %in% names(result2))
})
