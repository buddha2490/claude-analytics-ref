# Test file for summarize_numeric()

library(testthat)
library(tibble)

# Source the function
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_numeric.R")

test_that("summarize_numeric returns correct statistics for valid numeric data", {
  x <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
  result <- summarize_numeric(x, "TEST_VAR")

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)
  expect_equal(result$Variable, "TEST_VAR")
  expect_equal(result$N, 10)
  expect_equal(result$Mean, 5.5)
  expect_equal(result$SD, sd(x))
  expect_equal(result$Median, 5.5)
  expect_equal(result$Min, 1)
  expect_equal(result$Max, 10)
  expect_equal(result$Missing, 0)
})

test_that("summarize_numeric handles missing values correctly", {
  x <- c(1, 2, NA, 4, 5, NA, 7, 8, 9, 10)
  result <- summarize_numeric(x, "TEST_VAR")

  expect_equal(result$N, 8)
  expect_equal(result$Missing, 2)
  expect_equal(result$Mean, mean(c(1, 2, 4, 5, 7, 8, 9, 10)))
  expect_equal(result$Min, 1)
  expect_equal(result$Max, 10)
})

test_that("summarize_numeric handles all missing values", {
  x <- c(NA_real_, NA_real_, NA_real_, NA_real_)
  result <- summarize_numeric(x, "TEST_VAR")

  expect_equal(result$N, 0)
  expect_equal(result$Missing, 4)
  expect_true(is.na(result$Mean))
  expect_true(is.na(result$SD))
  expect_true(is.na(result$Median))
  expect_true(is.na(result$Min))
  expect_true(is.na(result$Max))
})

test_that("summarize_numeric handles integer input", {
  x <- as.integer(c(1, 2, 3, 4, 5))
  result <- summarize_numeric(x, "INT_VAR")

  expect_equal(result$N, 5)
  expect_equal(result$Mean, 3)
  expect_equal(result$Min, 1)
  expect_equal(result$Max, 5)
})

test_that("summarize_numeric errors on non-numeric input", {
  expect_error(
    summarize_numeric(c("a", "b", "c"), "TEST_VAR"),
    "`x` must be a numeric or integer vector."
  )

  expect_error(
    summarize_numeric(list(1, 2, 3), "TEST_VAR"),
    "`x` must be a numeric or integer vector."
  )
})

test_that("summarize_numeric errors on invalid var_name", {
  expect_error(
    summarize_numeric(c(1, 2, 3), c("VAR1", "VAR2")),
    "`var_name` must be a single character string."
  )

  expect_error(
    summarize_numeric(c(1, 2, 3), 123),
    "`var_name` must be a single character string."
  )
})

test_that("summarize_numeric handles single value", {
  x <- 42
  result <- summarize_numeric(x, "SINGLE_VAR")

  expect_equal(result$N, 1)
  expect_equal(result$Mean, 42)
  expect_equal(result$Median, 42)
  expect_equal(result$Min, 42)
  expect_equal(result$Max, 42)
  expect_true(is.na(result$SD))  # SD is NA for single value
  expect_equal(result$Missing, 0)
})
