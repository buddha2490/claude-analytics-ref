# Test file for summarize_date()

library(testthat)
library(tibble)
library(lubridate)

# Source the function
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_date.R")

test_that("summarize_date works with character dates", {
  x <- c("2024-01-01", "2024-01-15", "2024-01-31")
  result <- summarize_date(x, "TEST_DT")

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1)
  expect_equal(result$Variable, "TEST_DT")
  expect_equal(result$`Earliest Date`, "2024-01-01")
  expect_equal(result$`Latest Date`, "2024-01-31")
  expect_equal(result$`Range (days)`, 30)
  expect_equal(result$`N Non-Missing`, 3)
  expect_equal(result$Missing, 0)
})

test_that("summarize_date works with Date objects", {
  x <- as.Date(c("2024-01-01", "2024-01-15", "2024-01-31"))
  result <- summarize_date(x, "TEST_DT")

  expect_equal(result$`Earliest Date`, "2024-01-01")
  expect_equal(result$`Latest Date`, "2024-01-31")
  expect_equal(result$`Range (days)`, 30)
  expect_equal(result$`N Non-Missing`, 3)
  expect_equal(result$Missing, 0)
})

test_that("summarize_date handles missing values", {
  x <- c("2024-01-01", NA, "2024-01-31", NA)
  result <- summarize_date(x, "TEST_DT")

  expect_equal(result$`N Non-Missing`, 2)
  expect_equal(result$Missing, 2)
  expect_equal(result$`Earliest Date`, "2024-01-01")
  expect_equal(result$`Latest Date`, "2024-01-31")
})

test_that("summarize_date handles all missing values", {
  x <- c(NA_character_, NA_character_, NA_character_)
  result <- summarize_date(x, "TEST_DT")

  expect_equal(result$`N Non-Missing`, 0)
  expect_equal(result$Missing, 3)
  expect_true(is.na(result$`Earliest Date`))
  expect_true(is.na(result$`Latest Date`))
  expect_true(is.na(result$`Range (days)`))
})

test_that("summarize_date handles single date", {
  x <- "2024-01-15"
  result <- summarize_date(x, "TEST_DT")

  expect_equal(result$`Earliest Date`, "2024-01-15")
  expect_equal(result$`Latest Date`, "2024-01-15")
  expect_equal(result$`Range (days)`, 0)
  expect_equal(result$`N Non-Missing`, 1)
  expect_equal(result$Missing, 0)
})

test_that("summarize_date handles invalid date strings", {
  x <- c("2024-01-01", "not-a-date", "2024-01-31")
  result <- summarize_date(x, "TEST_DT")

  # Invalid dates are treated as NA
  expect_equal(result$`N Non-Missing`, 2)
  expect_equal(result$Missing, 1)
  expect_equal(result$`Earliest Date`, "2024-01-01")
  expect_equal(result$`Latest Date`, "2024-01-31")
})

test_that("summarize_date errors on invalid input type", {
  expect_error(
    summarize_date(c(1, 2, 3), "TEST_DT"),
    "`x` must be a character or Date vector."
  )

  expect_error(
    summarize_date(list("2024-01-01"), "TEST_DT"),
    "`x` must be a character or Date vector."
  )
})

test_that("summarize_date errors on invalid var_name", {
  expect_error(
    summarize_date(c("2024-01-01"), c("VAR1", "VAR2")),
    "`var_name` must be a single character string."
  )

  expect_error(
    summarize_date(c("2024-01-01"), 123),
    "`var_name` must be a single character string."
  )
})

test_that("summarize_date calculates range correctly for large spans", {
  x <- c("2020-01-01", "2024-12-31")
  result <- summarize_date(x, "TEST_DT")

  expect_equal(result$`Range (days)`, as.integer(as.Date("2024-12-31") - as.Date("2020-01-01")))
  expect_equal(result$`N Non-Missing`, 2)
})

test_that("summarize_date handles partial dates gracefully", {
  # Partial dates that can't be parsed become NA
  x <- c("2024-01-01", "2024-01", "2024", "2024-12-31")
  result <- summarize_date(x, "TEST_DT")

  # Only the full dates parse successfully
  expect_equal(result$`N Non-Missing`, 2)
  expect_equal(result$Missing, 2)
})
