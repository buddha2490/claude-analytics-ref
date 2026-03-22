library(testthat)
library(tibble)

# --- Source the function under test -------------------------------------------
# Locate project root by finding renv.lock, then source the function
project_root <- getwd()
while (!file.exists(file.path(project_root, "renv.lock")) && project_root != "/") {
  project_root <- dirname(project_root)
}
source(file.path(project_root, "R", "create_tfl.R"))

# --- Test Data ----------------------------------------------------------------
# Simulate a typical clinical trial summary ARDS
set.seed(42)

ards_normal <- tibble(
  trt01a   = c("Placebo", "Drug 10mg", "Drug 20mg"),
  n        = c("86", "88", "85"),
  mean_sd  = c("12.3 (4.5)", "15.1 (3.8)", "18.7 (4.1)"),
  median   = c("12.0", "15.0", "19.0"),
  p_value  = c("", "0.023", "<0.001")
)

titles_normal <- c(
  "Table 14.1.1",
  "Summary of Primary Efficacy Endpoint",
  "Intent-to-Treat Population"
)

footnotes_normal <- c(
  "SD = Standard Deviation.",
  "P-values from ANCOVA model adjusted for baseline.",
  "Program: t_14_1_1.R | Output: t_14_1_1.rtf"
)

headers_normal <- c(
  "trt01a"  = "Treatment",
  "n"       = "N",
  "mean_sd" = "Mean (SD)",
  "median"  = "Median",
  "p_value" = "P-value"
)

# --- Use a temp directory for all output files --------------------------------
test_dir <- tempdir()

# --- Tests --------------------------------------------------------------------

test_that("create_tfl produces an RTF file with normal input", {
  out_file <- file.path(test_dir, "test_normal.rtf")

  result <- create_tfl(
    ards = ards_normal,
    titles = titles_normal,
    footnotes = footnotes_normal,
    column_headers = headers_normal,
    output_file = out_file
  )

  # File should exist and be non-empty
  expect_true(file.exists(out_file))
  expect_gt(file.size(out_file), 0)

  # Return value should be the file path (invisible)
  expect_equal(result, out_file)
})

test_that("create_tfl works without explicit column_headers", {
  out_file <- file.path(test_dir, "test_auto_headers.rtf")

  # Should auto-convert snake_case to Title Case
  result <- create_tfl(
    ards = ards_normal,
    titles = c("Table 1"),
    output_file = out_file
  )

  expect_true(file.exists(out_file))
  expect_gt(file.size(out_file), 0)
})

test_that("create_tfl works without footnotes", {
  out_file <- file.path(test_dir, "test_no_footnotes.rtf")

  result <- create_tfl(
    ards = ards_normal,
    titles = c("Table 1"),
    footnotes = NULL,
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl supports portrait orientation", {
  out_file <- file.path(test_dir, "test_portrait.rtf")

  result <- create_tfl(
    ards = ards_normal,
    titles = c("Table 1"),
    output_file = out_file,
    page_orientation = "portrait"
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl works with partial column_headers", {
  out_file <- file.path(test_dir, "test_partial_headers.rtf")

  # Only map some columns — the rest should auto-format
  partial_headers <- c("trt01a" = "Treatment Group")

  result <- create_tfl(
    ards = ards_normal,
    titles = c("Table 1"),
    column_headers = partial_headers,
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl works with numeric columns in ARDS", {
  out_file <- file.path(test_dir, "test_numeric.rtf")

  # Numeric columns should be coerced to character automatically
  ards_numeric <- tibble(
    category = c("A", "B", "C"),
    count    = c(10, 20, 30),
    pct      = c(33.3, 66.7, 100.0)
  )

  result <- create_tfl(
    ards = ards_numeric,
    titles = c("Table with Numeric Data"),
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl creates output directory if it does not exist", {
  nested_dir <- file.path(test_dir, "subdir1", "subdir2")
  out_file <- file.path(nested_dir, "test_nested.rtf")

  # Directory should not exist yet
  if (dir.exists(nested_dir)) unlink(nested_dir, recursive = TRUE)

  result <- create_tfl(
    ards = ards_normal,
    titles = c("Table 1"),
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl errors on empty data frame", {
  out_file <- file.path(test_dir, "test_empty.rtf")
  empty_df <- tibble()

  expect_error(
    create_tfl(ards = empty_df, titles = c("Title"), output_file = out_file),
    "at least one row"
  )
})

test_that("create_tfl errors on non-data-frame input", {
  out_file <- file.path(test_dir, "test_bad_input.rtf")

  expect_error(
    create_tfl(ards = "not a dataframe", titles = c("Title"), output_file = out_file),
    "must be a data frame"
  )
})

test_that("create_tfl errors on missing titles", {
  out_file <- file.path(test_dir, "test_no_titles.rtf")

  expect_error(
    create_tfl(ards = ards_normal, titles = character(0), output_file = out_file),
    "at least one element"
  )
})

test_that("create_tfl errors on invalid output file extension", {
  expect_error(
    create_tfl(ards = ards_normal, titles = c("Title"), output_file = "output.pdf"),
    "must be a character string ending in .rtf"
  )
})

test_that("create_tfl errors on invalid page orientation", {
  out_file <- file.path(test_dir, "test_bad_orient.rtf")

  expect_error(
    create_tfl(ards = ards_normal, titles = c("Title"), output_file = out_file,
               page_orientation = "diagonal"),
    "landscape.*portrait"
  )
})

test_that("create_tfl handles single-row ARDS", {
  out_file <- file.path(test_dir, "test_single_row.rtf")

  single_row <- tibble(
    treatment = "Placebo",
    n = "50",
    result = "Normal"
  )

  result <- create_tfl(
    ards = single_row,
    titles = c("Table 1"),
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

test_that("create_tfl handles ARDS with NA values", {
  out_file <- file.path(test_dir, "test_na_values.rtf")

  ards_na <- tibble(
    group  = c("A", "B", "C"),
    value  = c("10", NA, "30"),
    note   = c(NA, "missing", NA)
  )

  result <- create_tfl(
    ards = ards_na,
    titles = c("Table with Missing Values"),
    output_file = out_file
  )

  expect_true(file.exists(out_file))
})

# --- Cleanup ------------------------------------------------------------------
# Remove temp files created during tests
test_files <- list.files(test_dir, pattern = "\\.rtf$", full.names = TRUE)
file.remove(test_files)

rm(list = ls())
