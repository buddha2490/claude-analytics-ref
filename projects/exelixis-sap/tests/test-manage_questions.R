# Tests for manage_questions.R

library(testthat)
library(yaml)
library(tibble)

# Load functions
source("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/R/manage_questions.R")

# --- Setup Test Environment -------------------------------------------------

test_yaml_path <- tempfile(fileext = ".yaml")
test_code_dir <- tempdir()

# Create minimal YAML structure
initial_yaml <- list(
  questions = list(
    list(
      id = "R1",
      text = "Test resolved question",
      status = "resolved",
      resolution = "Test resolution",
      rationale = "Test rationale",
      affected_code = list(
        list(file = "test.R", lines = c(10, 20), marker = "REVISIT: Test R1")
      ),
      resolved_by = "tester",
      resolved_date = "2026-03-27"
    ),
    list(
      id = "W1",
      text = "Test open warning",
      status = "open",
      severity = "warning",
      rationale = "Test warning rationale",
      affected_code = list(
        list(file = "test.R", lines = c(50, 60), marker = "REVISIT: Test W1")
      ),
      flagged_by = "tester",
      flagged_date = "2026-03-27"
    )
  )
)

yaml::write_yaml(initial_yaml, test_yaml_path)

# Create test R file with REVISIT comments
test_r_file <- file.path(test_code_dir, "test_code.R")
writeLines(c(
  "# Test R file",
  "x <- 1",
  "# REVISIT: Quan 2011 weights used per R1",
  "y <- 2",
  "# REVISIT: CCI derived from MH.MHTERM per W1",
  "z <- 3",
  "# REVISIT: This has no ID at all",
  "a <- 4",
  "# REVISIT: This references non-existent B99"
), test_r_file)

# --- Tests ------------------------------------------------------------------

test_that("list_questions returns all questions", {
  result <- list_questions(test_yaml_path)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2)
  expect_true("R1" %in% result$id)
  expect_true("W1" %in% result$id)
})

test_that("list_questions filters by status", {
  result_resolved <- list_questions(test_yaml_path, status_filter = "resolved")
  result_open <- list_questions(test_yaml_path, status_filter = "open")

  expect_equal(nrow(result_resolved), 1)
  expect_equal(result_resolved$id, "R1")

  expect_equal(nrow(result_open), 1)
  expect_equal(result_open$id, "W1")
})

test_that("list_questions filters by dataset", {
  result <- list_questions(test_yaml_path, dataset_filter = "test.R")

  expect_equal(nrow(result), 2)
})

test_that("add_question creates new question", {
  add_question(
    yaml_path = test_yaml_path,
    id = "W2",
    text = "New test question",
    rationale = "Testing add_question",
    affected_code = list(
      list(file = "new.R", lines = c(1, 10), marker = "REVISIT: W2")
    ),
    severity = "warning",
    flagged_by = "testthat",
    flagged_date = "2026-03-27"
  )

  result <- list_questions(test_yaml_path)
  expect_equal(nrow(result), 3)
  expect_true("W2" %in% result$id)

  w2 <- result %>% filter(id == "W2")
  expect_equal(w2$status, "open")
  expect_equal(w2$severity, "warning")
})

test_that("add_question prevents duplicate IDs", {
  expect_error(
    add_question(
      yaml_path = test_yaml_path,
      id = "R1",  # Duplicate
      text = "Duplicate question",
      rationale = "Should fail"
    ),
    "already exists"
  )
})

test_that("resolve_question updates status", {
  resolve_question(
    yaml_path = test_yaml_path,
    id = "W1",
    resolution = "Test resolution for W1",
    resolved_by = "testthat",
    resolved_date = "2026-03-27"
  )

  result <- list_questions(test_yaml_path, status_filter = "resolved")
  expect_equal(nrow(result), 2)  # R1 and now W1
  expect_true("W1" %in% result$id)

  w1 <- result %>% filter(id == "W1")
  expect_equal(w1$resolution, "Test resolution for W1")
  expect_equal(w1$resolved_by, "testthat")
})

test_that("resolve_question fails for non-existent ID", {
  expect_error(
    resolve_question(
      yaml_path = test_yaml_path,
      id = "X99",
      resolution = "Should fail"
    ),
    "not found"
  )
})

test_that("is_question_resolved returns correct status", {
  expect_true(is_question_resolved(test_yaml_path, "R1"))
  expect_true(is_question_resolved(test_yaml_path, "W1"))  # Now resolved
})

test_that("is_question_resolved fails for non-existent ID", {
  expect_error(
    is_question_resolved(test_yaml_path, "X99"),
    "not found"
  )
})

test_that("check_revisit_comments finds all REVISIT markers", {
  result <- check_revisit_comments(test_code_dir, test_yaml_path)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 4)  # 4 REVISIT comments in test file
})

test_that("check_revisit_comments validates question IDs", {
  result <- check_revisit_comments(test_code_dir, test_yaml_path)

  # R1 exists and is valid
  r1_row <- result %>% filter(question_id == "R1")
  expect_equal(r1_row$status, "OK")

  # W1 exists and is valid
  w1_row <- result %>% filter(question_id == "W1")
  expect_equal(w1_row$status, "OK")

  # No ID case
  no_id_row <- result %>% filter(!has_id)
  expect_equal(nrow(no_id_row), 1)
  expect_true(str_detect(no_id_row$status, "No question ID"))

  # B99 does not exist in YAML
  b99_row <- result %>% filter(question_id == "B99")
  expect_equal(nrow(b99_row), 1)
  expect_true(str_detect(b99_row$status, "not found"))
})

test_that("add_question validates severity", {
  expect_error(
    add_question(
      yaml_path = test_yaml_path,
      id = "W99",
      text = "Invalid severity",
      rationale = "Test",
      severity = "invalid"
    ),
    "must be one of"
  )
})

test_that("print_questions handles empty input", {
  empty_df <- tibble()
  expect_message(print_questions(empty_df), "No questions")
})

# --- Cleanup ----------------------------------------------------------------

unlink(test_yaml_path)
unlink(test_r_file)

message("\n✓ All tests passed for manage_questions.R")
