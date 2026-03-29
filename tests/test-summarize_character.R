# Test file for summarize_character()

library(testthat)
library(tibble)
library(dplyr)

# Source the function
source("/Users/briancarter/Rdata/claude-analytics-ref/R/summarize_character.R")

test_that("summarize_character returns correct frequency table", {
  x <- c("A", "B", "A", "C", "B", "A")
  result <- summarize_character(x, "TEST_VAR")

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3)
  expect_equal(result$Variable, rep("TEST_VAR", 3))
  expect_equal(result$Value[1], "A")  # Most frequent first
  expect_equal(result$N[1], 3)
  expect_equal(result$Value[2], "B")
  expect_equal(result$N[2], 2)
  expect_equal(result$Value[3], "C")
  expect_equal(result$N[3], 1)
})

test_that("summarize_character calculates percentages correctly", {
  x <- c("A", "A", "B", "B", "B", "B", "C", "C", "C", "C")
  result <- summarize_character(x, "TEST_VAR")

  expect_equal(result$N[1], 4)  # B is most frequent
  expect_equal(result$Value[1], "B")
  expect_match(result$`N (%)`[1], "4 \\(40\\.0%\\)")
  expect_match(result$`N (%)`[2], "4 \\(40\\.0%\\)")  # C is tied
  expect_match(result$`N (%)`[3], "2 \\(20\\.0%\\)")  # A
})

test_that("summarize_character handles missing values", {
  x <- c("A", "B", NA, "A", NA, "C")
  result <- summarize_character(x, "TEST_VAR")

  expect_equal(nrow(result), 4)
  expect_true("(Missing)" %in% result$Value)

  missing_row <- result %>% filter(Value == "(Missing)")
  expect_equal(missing_row$N, 2)
})

test_that("summarize_character handles all missing values", {
  x <- c(NA_character_, NA_character_, NA_character_)
  result <- summarize_character(x, "TEST_VAR")

  expect_equal(nrow(result), 1)
  expect_equal(result$Value[1], "(Missing)")
  expect_equal(result$N[1], 3)
  expect_match(result$`N (%)`[1], "3 \\(100\\.0%\\)")
})

test_that("summarize_character handles factor input", {
  x <- factor(c("A", "B", "A", "C"), levels = c("C", "B", "A"))
  result <- summarize_character(x, "FACTOR_VAR")

  expect_equal(nrow(result), 3)
  expect_equal(result$Variable[1], "FACTOR_VAR")
  # Should be ordered by frequency, not factor levels
  expect_equal(result$Value[1], "A")
  expect_equal(result$N[1], 2)
})

test_that("summarize_character handles single value", {
  x <- "SINGLE"
  result <- summarize_character(x, "TEST_VAR")

  expect_equal(nrow(result), 1)
  expect_equal(result$Value[1], "SINGLE")
  expect_equal(result$N[1], 1)
  expect_match(result$`N (%)`[1], "1 \\(100\\.0%\\)")
})

test_that("summarize_character errors on non-character input", {
  expect_error(
    summarize_character(c(1, 2, 3), "TEST_VAR"),
    "`x` must be a character or factor vector."
  )

  expect_error(
    summarize_character(list("a", "b", "c"), "TEST_VAR"),
    "`x` must be a character or factor vector."
  )
})

test_that("summarize_character errors on invalid var_name", {
  expect_error(
    summarize_character(c("A", "B"), c("VAR1", "VAR2")),
    "`var_name` must be a single character string."
  )

  expect_error(
    summarize_character(c("A", "B"), 123),
    "`var_name` must be a single character string."
  )
})

test_that("summarize_character orders by frequency descending", {
  x <- c("C", "A", "B", "A", "B", "B")
  result <- summarize_character(x, "TEST_VAR")

  expect_equal(result$Value, c("B", "A", "C"))
  expect_equal(result$N, c(3, 2, 1))
})
