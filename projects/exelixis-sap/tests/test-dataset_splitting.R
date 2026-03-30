# Test Suite: Dataset Splitting Functions
# Tests orchestrate_dataset_split() and merge_split_datasets()

library(testthat)
library(dplyr)

# Source the functions
source("../R/orchestrate_dataset_split.R")
source("../R/merge_split_datasets.R")


# --- Test orchestrate_dataset_split() -----------------------------------------

test_that("orchestrate_dataset_split rejects invalid inputs", {
  # Non-list input
  expect_error(
    orchestrate_dataset_split("not a list"),
    "`dataset_spec` must be a list"
  )

  # Missing required fields
  spec_incomplete <- list(dataset_name = "ADSL")
  expect_error(
    orchestrate_dataset_split(spec_incomplete),
    "missing required fields"
  )

  # Non-data-frame variables
  spec_bad_vars <- list(
    dataset_name = "ADSL",
    variables = "not a data frame",
    total_variables = 50
  )
  expect_error(
    orchestrate_dataset_split(spec_bad_vars),
    "`dataset_spec\\$variables` must be a data frame"
  )

  # Invalid threshold
  spec_valid <- list(
    dataset_name = "ADSL",
    variables = data.frame(variable = c("USUBJID", "AGE")),
    total_variables = 2
  )
  expect_error(
    orchestrate_dataset_split(spec_valid, threshold = -10),
    "`threshold` must be a positive number"
  )
})


test_that("orchestrate_dataset_split returns no split for small datasets", {
  spec <- list(
    dataset_name = "ADAE",
    variables = data.frame(
      variable = c("USUBJID", "STUDYID", "AESEQ", "AEDECOD", "AESTDTC"),
      label = c("Subject ID", "Study ID", "AE Seq", "AE Term", "AE Start Date")
    ),
    total_variables = 5
  )

  result <- orchestrate_dataset_split(spec, threshold = 40)

  expect_false(result$split_required)
  expect_equal(result$n_agents, 1)
  expect_null(result$split_plan)
  expect_null(result$merge_strategy)
})


test_that("orchestrate_dataset_split creates split plan for large datasets", {
  # Simulate ADSL with 101 variables
  variables <- data.frame(
    variable = c(
      "USUBJID", "STUDYID",
      # Demographics
      "AGE", "SEX", "RACE", "ETHNIC", "COUNTRY", "REGION",
      # Biomarkers
      "EGFRMUT", "KRASMUT", "ALK", "ROS1MUT", "PDL1",
      # Comorbidities
      "MYHIS", "CVAIS", "CONGHF", "DIA", "CCIGRP",
      # Baseline
      "ECOG0", "ECOG_BL", "SMOKGRP",
      # Staging
      "TSTAGE", "NSTAGE", "MSTAGE", "AJCCSTG",
      # Treatment
      "LOTSNUM", "PFSIND", "OSIND",
      # Dates
      "RFSTDTC", "RFENDTC",
      # Add more variables to reach 101
      paste0("VAR", 1:71)
    ),
    label = paste("Label", 1:101)
  )

  spec <- list(
    dataset_name = "ADSL",
    variables = variables,
    total_variables = 101
  )

  result <- orchestrate_dataset_split(spec, threshold = 40)

  expect_true(result$split_required)
  expect_true(result$n_agents >= 2)
  expect_true(is.list(result$split_plan))
  expect_true(!is.null(result$merge_strategy))

  # Check split plan structure
  for (agent_plan in result$split_plan) {
    expect_true("agent_id" %in% names(agent_plan))
    expect_true("part_number" %in% names(agent_plan))
    expect_true("variables" %in% names(agent_plan))
    expect_true("checkpoint_file" %in% names(agent_plan))
    expect_true("required_keys" %in% names(agent_plan))

    # All parts must include merge keys
    expect_true(all(c("USUBJID", "STUDYID") %in% agent_plan$variables))

    # Each part should have reasonable variable count
    # Allow up to 50 for imperfect splits (target is 30, but packing may exceed threshold)
    expect_true(agent_plan$variable_count >= 10)
    expect_true(agent_plan$variable_count <= 50)
  }
})


test_that("orchestrate_dataset_split balances variable distribution", {
  # Create a dataset with 100 variables
  variables <- data.frame(
    variable = c(
      "USUBJID", "STUDYID",
      paste0("AGE", 1:20),    # Demographics
      paste0("MUT", 1:30),    # Biomarkers
      paste0("MH", 1:25),     # Comorbidities
      paste0("OTHER", 1:23)   # Uncategorized
    )
  )

  spec <- list(
    dataset_name = "ADSL",
    variables = variables,
    total_variables = 100
  )

  result <- orchestrate_dataset_split(spec, threshold = 40)

  # Extract variable counts per agent
  var_counts <- sapply(result$split_plan, function(x) x$variable_count)

  # Check that distribution is reasonably balanced
  # No agent should have >2x the mean (allows for some imbalance)
  mean_count <- mean(var_counts)
  expect_true(all(var_counts <= mean_count * 2))

  # Total variables should match (accounting for key duplication)
  total_unique_vars <- length(unique(unlist(
    lapply(result$split_plan, function(x) x$variables)
  )))
  expect_equal(total_unique_vars, 100)
})


# --- Test merge_split_datasets() ----------------------------------------------

test_that("merge_split_datasets rejects invalid inputs", {
  # Single file
  expect_error(
    merge_split_datasets("file1.rds", "output.xpt"),
    "at least 2 files"
  )

  # Non-character checkpoint_files
  expect_error(
    merge_split_datasets(list("file1.rds", "file2.rds"), "output.xpt"),
    "`checkpoint_files` must be a character vector"
  )

  # Missing output_path
  expect_error(
    merge_split_datasets(c("file1.rds", "file2.rds"), NULL),
    "`output_path` must be a single character string"
  )

  # Empty merge_keys
  expect_error(
    merge_split_datasets(c("file1.rds", "file2.rds"), "output.xpt", merge_keys = character()),
    "`merge_keys` must be a non-empty character vector"
  )
})


test_that("merge_split_datasets detects missing files", {
  checkpoint_files <- c(
    "/nonexistent/file1.rds",
    "/nonexistent/file2.rds"
  )

  expect_error(
    merge_split_datasets(checkpoint_files, "output.xpt"),
    "Checkpoint files not found"
  )
})


test_that("merge_split_datasets successfully merges valid checkpoints", {
  # Create temporary checkpoint files
  temp_dir <- tempdir()

  # Part 1: Demographics
  part1 <- data.frame(
    USUBJID = c("001", "002", "003"),
    STUDYID = c("NPM008", "NPM008", "NPM008"),
    AGE = c(65, 72, 58),
    SEX = c("M", "F", "M")
  )
  file1 <- file.path(temp_dir, "test_part1.rds")
  saveRDS(part1, file1)

  # Part 2: Biomarkers
  part2 <- data.frame(
    USUBJID = c("001", "002", "003"),
    STUDYID = c("NPM008", "NPM008", "NPM008"),
    EGFRMUT = c("Y", "N", "Y"),
    KRASMUT = c("N", "Y", "N")
  )
  file2 <- file.path(temp_dir, "test_part2.rds")
  saveRDS(part2, file2)

  # Part 3: Staging
  part3 <- data.frame(
    USUBJID = c("001", "002", "003"),
    STUDYID = c("NPM008", "NPM008", "NPM008"),
    TSTAGE = c("T2", "T3", "T1"),
    NSTAGE = c("N1", "N0", "N2")
  )
  file3 <- file.path(temp_dir, "test_part3.rds")
  saveRDS(part3, file3)

  # Merge
  output_path <- file.path(temp_dir, "test_merged.xpt")
  result <- merge_split_datasets(
    checkpoint_files = c(file1, file2, file3),
    output_path = output_path
  )

  # Validate structure
  expect_true("merged_data" %in% names(result))
  expect_true("validation_report" %in% names(result))
  expect_true("output_path" %in% names(result))

  # Check merged data
  merged <- result$merged_data
  expect_equal(nrow(merged), 3)
  expect_equal(ncol(merged), 8)  # 2 keys + 2 from part1 + 2 from part2 + 2 from part3

  expect_true(all(c("USUBJID", "STUDYID", "AGE", "SEX", "EGFRMUT", "KRASMUT", "TSTAGE", "NSTAGE") %in% names(merged)))

  # Check validation report
  report <- result$validation_report
  expect_true(report$subject_consistency$passed)
  expect_true(report$column_uniqueness$passed)
  expect_true(report$row_count$passed)

  # Check output file created
  expect_true(file.exists(output_path))

  # Clean up
  unlink(c(file1, file2, file3, output_path))
})


test_that("merge_split_datasets detects subject set mismatch", {
  temp_dir <- tempdir()

  # Part 1: 3 subjects
  part1 <- data.frame(
    USUBJID = c("001", "002", "003"),
    STUDYID = c("NPM008", "NPM008", "NPM008"),
    AGE = c(65, 72, 58)
  )
  file1 <- file.path(temp_dir, "mismatch_part1.rds")
  saveRDS(part1, file1)

  # Part 2: Different subjects
  part2 <- data.frame(
    USUBJID = c("001", "002", "004"),  # 004 instead of 003
    STUDYID = c("NPM008", "NPM008", "NPM008"),
    EGFRMUT = c("Y", "N", "Y")
  )
  file2 <- file.path(temp_dir, "mismatch_part2.rds")
  saveRDS(part2, file2)

  output_path <- file.path(temp_dir, "mismatch_output.xpt")

  expect_error(
    merge_split_datasets(c(file1, file2), output_path),
    "Subject sets differ"
  )

  # Clean up
  unlink(c(file1, file2))
})


test_that("merge_split_datasets detects duplicate columns", {
  temp_dir <- tempdir()

  # Part 1
  part1 <- data.frame(
    USUBJID = c("001", "002"),
    STUDYID = c("NPM008", "NPM008"),
    AGE = c(65, 72)
  )
  file1 <- file.path(temp_dir, "dup_part1.rds")
  saveRDS(part1, file1)

  # Part 2 (has duplicate column AGE)
  part2 <- data.frame(
    USUBJID = c("001", "002"),
    STUDYID = c("NPM008", "NPM008"),
    AGE = c(66, 73)  # Duplicate!
  )
  file2 <- file.path(temp_dir, "dup_part2.rds")
  saveRDS(part2, file2)

  output_path <- file.path(temp_dir, "dup_output.xpt")

  expect_error(
    merge_split_datasets(c(file1, file2), output_path),
    "Duplicate columns detected"
  )

  # Clean up
  unlink(c(file1, file2))
})


test_that("merge_split_datasets detects missing merge keys", {
  temp_dir <- tempdir()

  # Part 1: has keys
  part1 <- data.frame(
    USUBJID = c("001", "002"),
    STUDYID = c("NPM008", "NPM008"),
    AGE = c(65, 72)
  )
  file1 <- file.path(temp_dir, "nokey_part1.rds")
  saveRDS(part1, file1)

  # Part 2: missing STUDYID
  part2 <- data.frame(
    USUBJID = c("001", "002"),
    EGFRMUT = c("Y", "N")
  )
  file2 <- file.path(temp_dir, "nokey_part2.rds")
  saveRDS(part2, file2)

  output_path <- file.path(temp_dir, "nokey_output.xpt")

  expect_error(
    merge_split_datasets(c(file1, file2), output_path),
    "missing merge keys"
  )

  # Clean up
  unlink(c(file1, file2))
})


# --- Test print_validation_report() -------------------------------------------

test_that("print_validation_report displays report correctly", {
  report <- list(
    subject_consistency = list(
      check = "All checkpoints have identical USUBJID sets",
      passed = TRUE,
      details = "All 3 checkpoints have 40 subjects"
    ),
    column_uniqueness = list(
      check = "No duplicate column names",
      passed = TRUE,
      details = "No duplicate columns found"
    ),
    row_count = list(
      check = "Row count unchanged",
      passed = TRUE,
      details = "Expected: 40, Actual: 40"
    )
  )

  # Should return TRUE (all passed)
  expect_true(print_validation_report(report))
})


test_that("print_validation_report handles failures", {
  report <- list(
    subject_consistency = list(
      check = "Subject consistency",
      passed = FALSE,
      details = "Mismatch detected"
    )
  )

  # Should return FALSE
  expect_false(print_validation_report(report))
})


# --- Test suite complete ------------------------------------------------------
# Note: This file is intended to be run via testthat::test_file() or
# test_dir(). Running it directly with source() will execute all test_that()
# blocks but won't provide test_dir() summary output.
