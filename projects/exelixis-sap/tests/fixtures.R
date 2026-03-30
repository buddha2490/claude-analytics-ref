# Test Fixtures for SDTM Validation
#
# Reusable mock data generators and test utilities

#' Create Mock DM Dataset for Testing
#'
#' @param n_subjects Number of subjects to create (default: 3)
#' @param include_death_vars Logical. Include DTHFL and DTHDTC columns?
#' @param study_id Character. Study identifier (default: "NPM008")
#'
#' @return Data frame with mock DM structure
#' @keywords internal
create_test_dm <- function(n_subjects = 3,
                           include_death_vars = FALSE,
                           study_id = "NPM008") {
  dm <- data.frame(
    STUDYID = rep(study_id, n_subjects),
    DOMAIN = rep("DM", n_subjects),
    USUBJID = sprintf(
      "%s-%02d-A%04d",
      study_id,
      1:n_subjects,
      1001:(1000 + n_subjects)
    ),
    RFSTDTC = rep("2024-01-15", n_subjects),
    RFENDTC = rep("2024-06-15", n_subjects),
    ARMCD = rep("TRT", n_subjects),
    ARM = rep("Treatment", n_subjects),
    ACTARMCD = rep("TRT", n_subjects),
    ACTARM = rep("Treatment", n_subjects)
  )

  if (include_death_vars) {
    dm$DTHFL <- rep("N", n_subjects)
    dm$DTHDTC <- rep(NA_character_, n_subjects)
  }

  dm
}

#' Create Mock AE Dataset for Testing
#'
#' @param n_records Number of AE records to create (default: 5)
#' @param usubjids Character vector of USUBJIDs to use. If NULL, generates
#'   standard test IDs.
#' @param study_id Character. Study identifier (default: "NPM008")
#'
#' @return Data frame with mock AE structure
#' @keywords internal
create_test_ae <- function(n_records = 5,
                           usubjids = NULL,
                           study_id = "NPM008") {
  if (is.null(usubjids)) {
    usubjids <- sprintf(
      "%s-01-A%04d",
      study_id,
      1001:(1000 + n_records)
    )
  }

  data.frame(
    STUDYID = rep(study_id, n_records),
    DOMAIN = rep("AE", n_records),
    USUBJID = usubjids,
    AESEQ = 1:n_records,
    AESTDTC = rep("2024-02-01", n_records),
    AETERM = rep("Headache", n_records)
  )
}

#' Create Mock Validation Result for Testing
#'
#' @param verdict Character: "PASS", "FAIL", "WARNING", or "BLOCKING"
#' @param n_checks Integer: number of checks in result
#' @param n_failures Integer: number of failed checks
#' @param n_warnings Integer: number of warning checks
#'
#' @return List with validation result structure
#' @keywords internal
create_test_validation_result <- function(verdict = "PASS",
                                          n_checks = 3,
                                          n_failures = 0,
                                          n_warnings = 0) {
  list(
    verdict = verdict,
    severity = if (verdict == "FAIL") "CRITICAL" else "INFO",
    message = sprintf(
      "%d checks run: %d passed, %d failed, %d warnings",
      n_checks,
      n_checks - n_failures - n_warnings,
      n_failures,
      n_warnings
    ),
    details = list(
      n_checks = n_checks,
      n_failures = n_failures,
      n_warnings = n_warnings
    )
  )
}

#' Create Test Directory Structure for SDTM Validation
#'
#' Creates temporary directories for SDTM data and logs. Uses withr::local_tempdir()
#' so cleanup is automatic at end of test scope.
#'
#' @return List with paths: base_dir, sdtm_dir, log_dir
#' @keywords internal
create_test_dirs <- function() {
  base_dir <- withr::local_tempdir()
  sdtm_dir <- file.path(base_dir, "sdtm")
  log_dir <- file.path(base_dir, "logs")

  dir.create(sdtm_dir)
  dir.create(log_dir, showWarnings = FALSE)

  list(
    base_dir = base_dir,
    sdtm_dir = sdtm_dir,
    log_dir = log_dir
  )
}

#' Source R Function if Not Already Loaded
#'
#' Helper to conditionally source function files in tests.
#'
#' @param func_name Function name to check
#' @param file_path Path to source file (relative to project root)
#'
#' @keywords internal
source_if_needed <- function(func_name, file_path) {
  if (!exists(func_name, mode = "function")) {
    source(file_path)
  }
}
