# Test suite for profile_data()

library(testthat)
library(dplyr)
library(haven)
library(stringr)

# Source function - assumes working directory is project root
if (!exists("profile_data")) {
  source("R/profile_data.R")
}

# --- Setup: Create test data ---
test_data_dir <- tempdir()
test_output_dir <- file.path(tempdir(), "profiles")

# Create simulated LB domain
lb_data <- tibble::tibble(
  USUBJID = rep(paste0("NPM-008-001-", sprintf("%03d", 1:40)), each = 10),
  LBTESTCD = rep(c("EGFR", "KRAS", "ALK", "BRAF", "PD-L1",
                   "HER2", "ROS1", "MET", "RET", "NTRK"), 40),
  LBTEST = rep(c("EGFR Mutation", "KRAS Mutation", "ALK Translocation",
                 "BRAF Mutation", "PD-L1 Expression", "HER2 Amplification",
                 "ROS1 Fusion", "MET Amplification", "RET Fusion",
                 "NTRK Fusion"), 40),
  LBSTRESC = c(
    rep("ALTERED", 12), rep("NOT ALTERED", 25), rep("NOT TESTED", 3),  # EGFR
    rep("DETECTED", 5), rep("NOT DETECTED", 35),                       # KRAS
    rep("POSITIVE", 8), rep("NEGATIVE", 32),                           # ALK
    rep("ALTERED", 3), rep("NOT ALTERED", 37),                         # BRAF
    rep("HIGH", 15), rep("LOW", 20), rep("NEGATIVE", 5),               # PD-L1
    rep("AMPLIFIED", 4), rep("NOT AMPLIFIED", 36),                     # HER2
    rep("DETECTED", 2), rep("NOT DETECTED", 38),                       # ROS1
    rep("AMPLIFIED", 6), rep("NOT AMPLIFIED", 34),                     # MET
    rep("DETECTED", 1), rep("NOT DETECTED", 39),                       # RET
    rep("DETECTED", 3), rep("NOT DETECTED", 37)                        # NTRK
  ),
  LBCAT = rep("BIOMARKER", 400),
  LBMETHOD = rep("NGS", 400)
)

# Add variable labels
attr(lb_data$USUBJID, "label") <- "Unique Subject Identifier"
attr(lb_data$LBTESTCD, "label") <- "Laboratory Test Code"
attr(lb_data$LBTEST, "label") <- "Laboratory Test Name"
attr(lb_data$LBSTRESC, "label") <- "Result in Standard Format"
attr(lb_data$LBCAT, "label") <- "Category for Lab Test"
attr(lb_data$LBMETHOD, "label") <- "Method of Test"

# Write XPT file
haven::write_xpt(lb_data, file.path(test_data_dir, "lb.xpt"))

# Create simulated MH domain
mh_data <- tibble::tibble(
  USUBJID = c(
    rep(paste0("NPM-008-001-", sprintf("%03d", 1:20)), each = 2),
    rep(paste0("NPM-008-001-", sprintf("%03d", 21:40)), each = 1)
  ),
  MHCAT = c(
    rep("PRIMARY", 40),
    rep("SECONDARY", 20)
  ),
  MHTERM = c(
    rep("Non-Small Cell Lung Cancer", 30),
    rep("Small Cell Lung Cancer", 10),
    rep("Hypertension", 10),
    rep("Diabetes Mellitus Type 2", 10)
  ),
  MHSTDTC = as.character(seq.Date(as.Date("2023-01-01"),
                                  by = "week", length.out = 60))
)

attr(mh_data$USUBJID, "label") <- "Unique Subject Identifier"
attr(mh_data$MHCAT, "label") <- "Category for Medical History"
attr(mh_data$MHTERM, "label") <- "Reported Term for the Medical History"
attr(mh_data$MHSTDTC, "label") <- "Start Date/Time of Medical History Event"

haven::write_xpt(mh_data, file.path(test_data_dir, "mh.xpt"))


# --- Test 1: Basic functionality ---
test_that("profile_data generates output for specified variables", {
  result <- profile_data(
    domain = "LB",
    variables = c("LBTESTCD", "LBSTRESC"),
    data_path = test_data_dir,
    output_path = test_output_dir
  )

  expect_type(result, "list")
  expect_equal(result$domain, "LB")
  expect_equal(result$n_records, 400)
  expect_equal(result$n_subjects, 40)
  expect_equal(result$variables_profiled, c("LBTESTCD", "LBSTRESC"))
  expect_true(file.exists(result$output_file))
})


# --- Test 2: Auto-detection of categorical variables ---
test_that("profile_data auto-detects categorical variables when variables=NULL", {
  result <- profile_data(
    domain = "MH",
    variables = NULL,
    data_path = test_data_dir,
    output_path = test_output_dir
  )

  expect_true("MHCAT" %in% result$variables_profiled)
  expect_true("MHTERM" %in% result$variables_profiled)
  expect_true("USUBJID" %in% result$variables_profiled)
})


# --- Test 3: Output file content validation ---
test_that("profile_data generates well-formed markdown", {
  result <- profile_data(
    domain = "LB",
    variables = c("LBTESTCD"),
    data_path = test_data_dir,
    output_path = test_output_dir
  )

  md_content <- readLines(result$output_file)

  # Check header
  expect_true(any(grepl("^# Data Profile: LB", md_content)))
  expect_true(any(grepl("\\*\\*Records:\\*\\*", md_content)))
  expect_true(any(grepl("\\*\\*Subjects:\\*\\*", md_content)))

  # Check variable section
  expect_true(any(grepl("^## LBTESTCD", md_content)))

  # Check table structure
  expect_true(any(grepl("\\| Value \\| Count \\| Percent \\|", md_content)))

  # Check for actual data values
  expect_true(any(grepl("EGFR", md_content)))
  expect_true(any(grepl("KRAS", md_content)))
})


# --- Test 4: Cross-tabulation generation ---
test_that("profile_data generates cross-tabulations for related variables", {
  result <- profile_data(
    domain = "LB",
    variables = c("LBTESTCD", "LBSTRESC"),
    data_path = test_data_dir,
    output_path = test_output_dir
  )

  md_content <- readLines(result$output_file)

  # Should contain cross-tabulation section
  expect_true(any(grepl("# Cross-Tabulations", md_content)))
  expect_true(any(grepl("LBTESTCD × LBSTRESC", md_content)))
})


# --- Test 5: Top N limiting ---
test_that("profile_data limits output to top_n values", {
  # Create domain with many unique values
  high_card_data <- tibble::tibble(
    USUBJID = paste0("NPM-008-001-", sprintf("%03d", 1:100)),
    TESTVAR = paste0("VALUE_", 1:100)
  )

  attr(high_card_data$USUBJID, "label") <- "Unique Subject Identifier"
  attr(high_card_data$TESTVAR, "label") <- "Test Variable"

  haven::write_xpt(high_card_data, file.path(test_data_dir, "hc.xpt"))

  result <- profile_data(
    domain = "HC",
    variables = "TESTVAR",
    data_path = test_data_dir,
    output_path = test_output_dir,
    top_n = 10
  )

  md_content <- readLines(result$output_file)

  # Should warn about high cardinality
  expect_true(any(grepl("High cardinality", md_content)))

  # Count actual data rows in the table
  # Table format:
  # | Value | Count | Percent |  <- header (line N)
  # |-------|-------|---------|  <- separator (line N+1)
  # | VALUE_1 | 1 | 1.0% |     <- data rows start (line N+2)
  # ...
  # | VALUE_10 | 1 | 1.0% |    <- last data row (line M)
  # (blank line)                <- line M+1
  # ---                         <- section divider (line M+2)

  table_header <- which(grepl("\\| Value \\| Count \\| Percent \\|", md_content))[1]
  section_divider <- which(grepl("^---$", md_content))
  section_divider <- section_divider[section_divider > table_header][1]

  # Count lines that start with "| " and are between separator and section divider
  # (excluding header and separator rows)
  data_row_lines <- (table_header + 2):(section_divider - 2)
  data_rows <- md_content[data_row_lines]
  n_data_rows <- sum(grepl("^\\|", data_rows))

  expect_lte(n_data_rows, 10)
})


# --- Test 6: Input validation ---
test_that("profile_data validates inputs correctly", {
  expect_error(
    profile_data(domain = 123, data_path = test_data_dir,
                output_path = test_output_dir),
    "must be a single character string"
  )

  expect_error(
    profile_data(domain = "LB", variables = 123,
                data_path = test_data_dir, output_path = test_output_dir),
    "must be a character vector or NULL"
  )

  expect_error(
    profile_data(domain = "LB", data_path = "/nonexistent/path",
                output_path = test_output_dir),
    "Data path does not exist"
  )

  expect_error(
    profile_data(domain = "XX", data_path = test_data_dir,
                output_path = test_output_dir),
    "XPT file not found"
  )

  expect_error(
    profile_data(domain = "LB", variables = c("NOTAVAR"),
                data_path = test_data_dir, output_path = test_output_dir),
    "Variables not found in LB"
  )
})


# --- Test 7: Terminology detection (ALTERED vs POSITIVE) ---
test_that("profile_data detects mixed terminology patterns", {
  result <- profile_data(
    domain = "LB",
    variables = c("LBSTRESC"),
    data_path = test_data_dir,
    output_path = test_output_dir
  )

  md_content <- readLines(result$output_file)

  # Should show both ALTERED and POSITIVE in results
  expect_true(any(grepl("ALTERED", md_content)))
  expect_true(any(grepl("POSITIVE", md_content)))
  expect_true(any(grepl("DETECTED", md_content)))
})


# --- Cleanup ---
unlink(test_output_dir, recursive = TRUE)
unlink(file.path(test_data_dir, "*.xpt"))
