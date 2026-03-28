#!/usr/bin/env Rscript
#' Run validate_plan Test Suite
#'
#' Simplified test runner that executes key tests without full testthat
#' infrastructure to avoid .Rprofile conflicts.

source("../R/validate_plan.R")

cat("\n")
cat("========================================\n")
cat(" validate_plan Test Suite\n")
cat("========================================\n\n")

test_count <- 0
pass_count <- 0
fail_count <- 0

run_test <- function(name, test_fn) {
  test_count <<- test_count + 1
  cat(sprintf("Test %d: %s ... ", test_count, name))

  tryCatch({
    test_fn()
    pass_count <<- pass_count + 1
    cat("PASS\n")
  }, error = function(e) {
    fail_count <<- fail_count + 1
    cat("FAIL\n")
    cat(sprintf("  Error: %s\n", e$message))
  })
}

# --- Test 1: Input validation ----------------------------------------------

run_test("Invalid plan_path", function() {
  tryCatch({
    validate_plan(123)
    stop("Should have thrown error")
  }, error = function(e) {
    if (!grepl("must be a single character string", e$message)) {
      stop("Wrong error message")
    }
  })
})

# --- Test 2: Large datasets ------------------------------------------------

run_test("Detects >40 var dataset without strategy", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c("# Test", "", "### ADSL (101 variables)", ""), temp_plan)

  result <- validate_plan(temp_plan)

  if (result$verdict != "WARNING") {
    stop(sprintf("Expected WARNING, got %s", result$verdict))
  }
  if (!any(grepl("ADSL has 101 variables", result$warnings))) {
    stop("Did not detect large dataset")
  }

  unlink(temp_plan)
})

run_test("Passes when strategy documented", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "### ADSL (101 variables)",
    "Checkpoint: demographics, then biomarkers"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("checkpoint strategy documented", result$passes, ignore.case = TRUE))) {
    stop("Did not recognize checkpoint strategy")
  }

  unlink(temp_plan)
})

# --- Test 3: Repeated patterns ---------------------------------------------

run_test("Detects repeated patterns without helpers", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "Biomarker flags:", "EGFRFL biomarker flag",
    "KRASFL biomarker flag", "ALKFL biomarker flag"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("repeated derivation patterns", result$warnings, ignore.case = TRUE))) {
    stop("Did not detect repeated patterns")
  }

  unlink(temp_plan)
})

# --- Test 4: HIGH complexity -----------------------------------------------

run_test("Detects HIGH complexity without checkpoints", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c("# Test", "", "Complexity: HIGH"), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("HIGH complexity.*without checkpoint", result$warnings))) {
    stop("Did not detect HIGH complexity issue")
  }

  unlink(temp_plan)
})

# --- Test 5: Open questions ------------------------------------------------

run_test("Detects unresolved open questions", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "## Open Questions", "",
    "- [ ] Unresolved question"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (result$verdict != "BLOCKING") {
    stop(sprintf("Expected BLOCKING, got %s", result$verdict))
  }
  if (!any(grepl("unresolved open questions", result$blocking, ignore.case = TRUE))) {
    stop("Did not detect unresolved questions")
  }

  unlink(temp_plan)
})

run_test("Passes when questions resolved", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "## Open Questions", "",
    "All questions resolved."
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("All resolved", result$passes))) {
    stop("Did not recognize resolved questions")
  }

  unlink(temp_plan)
})

# --- Test 6: Dependencies --------------------------------------------------

run_test("Detects missing dependency docs", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "### ADSL", "### ADRS", "### ADAE"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("no dependency/wave structure", result$warnings))) {
    stop("Did not detect missing dependencies")
  }

  unlink(temp_plan)
})

run_test("Passes when waves documented", function() {
  temp_plan <- tempfile(fileext = ".md")
  writeLines(c(
    "# Test", "",
    "## Wave 1", "- ADSL", "",
    "## Wave 2", "- ADRS"
  ), temp_plan)

  result <- validate_plan(temp_plan)

  if (!any(grepl("Documented with waves", result$passes))) {
    stop("Did not recognize wave documentation")
  }

  unlink(temp_plan)
})

# --- Test 7: Source domains ------------------------------------------------

run_test("Detects missing source domains", function() {
  temp_plan <- tempfile(fileext = ".md")
  temp_data_dir <- tempdir()

  writeLines(c("# Test", "", "Source domains: DM, AE, EX"), temp_plan)

  dm_file <- file.path(temp_data_dir, "dm.xpt")
  ae_file <- file.path(temp_data_dir, "ae.xpt")
  writeLines("", dm_file)
  writeLines("", ae_file)

  result <- validate_plan(temp_plan, data_path = temp_data_dir)

  if (result$verdict != "BLOCKING") {
    stop(sprintf("Expected BLOCKING, got %s", result$verdict))
  }
  if (!any(grepl("EX", result$blocking))) {
    stop("Did not detect missing domain")
  }

  unlink(temp_plan)
  unlink(dm_file)
  unlink(ae_file)
})

# --- Summary ---------------------------------------------------------------

cat("\n")
cat("========================================\n")
cat(sprintf(" Results: %d tests\n", test_count))
cat("========================================\n")
cat(sprintf("  PASS: %d\n", pass_count))
cat(sprintf("  FAIL: %d\n", fail_count))
cat("\n")

if (fail_count > 0) {
  stop(sprintf("%d test(s) failed", fail_count))
} else {
  cat("All tests passed! ✓\n\n")
}
