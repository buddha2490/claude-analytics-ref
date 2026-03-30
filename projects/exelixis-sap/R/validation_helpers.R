#' Build Validation Result Object
#'
#' Creates a standardized validation result structure used across all
#' validation functions.
#'
#' @param verdict Character: "PASS", "WARNING", "FAIL", or "BLOCKING"
#' @param severity Character: "INFO", "WARNING", or "CRITICAL"
#' @param message Character: Human-readable summary message
#' @param details List of check-specific details (default: empty list)
#'
#' @return A validation_result object (list with class)
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' build_validation_result(
#'   verdict = VERDICT_PASS,
#'   severity = SEVERITY_INFO,
#'   message = "All checks passed",
#'   details = list(n_checks = 5, n_subjects = 100)
#' )
#' }
build_validation_result <- function(verdict, severity, message, details = list()) {
  structure(
    list(
      verdict = verdict,
      severity = severity,
      message = message,
      details = details
    ),
    class = c("validation_result", "list")
  )
}

#' Check Required Columns Exist
#'
#' Validates that a data frame contains all required columns. Throws
#' informative error if any columns are missing.
#'
#' @param data Data frame to check
#' @param required_cols Character vector of required column names
#' @param data_name Character. Name of the data frame (for error messages)
#'
#' @return Invisible TRUE if all checks pass
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' check_required_columns(
#'   dm,
#'   c("USUBJID", "STUDYID", "RFSTDTC"),
#'   "dm"
#' )
#' }
check_required_columns <- function(data, required_cols, data_name = "data") {
  # --- Validate inputs -----------------------------------------------------------
  if (!is.data.frame(data)) {
    stop("`", data_name, "` must be a data frame.", call. = FALSE)
  }

  # --- Check for missing columns -------------------------------------------------
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(
      "Column",
      if (length(missing_cols) > 1) "s" else "",
      " `", paste(missing_cols, collapse = "`, `"),
      "` not found in ", data_name, ".",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

#' Format Subject ID List for Display
#'
#' Truncates long subject ID lists and adds "and N more" suffix for
#' readable validation messages.
#'
#' @param ids Character vector of subject IDs
#' @param max_display Maximum number of IDs to display (default: 10)
#'
#' @return Character string with formatted ID list
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' format_subject_list(c("NPM008-01-A1001", "NPM008-01-A1002"))
#' # "NPM008-01-A1001, NPM008-01-A1002"
#'
#' format_subject_list(rep("NPM008-01-A1001", 15), max_display = 3)
#' # "NPM008-01-A1001, NPM008-01-A1001, NPM008-01-A1001, and 12 more"
#' }
format_subject_list <- function(ids, max_display = 10) {
  n_total <- length(ids)

  if (n_total == 0) {
    return("(none)")
  }

  if (n_total <= max_display) {
    return(paste(ids, collapse = ", "))
  }

  shown <- head(ids, max_display)
  n_hidden <- n_total - max_display

  paste0(
    paste(shown, collapse = ", "),
    sprintf(", and %d more", n_hidden)
  )
}

#' Add Validation Check to Results
#'
#' Helper function to append a check result to the checks data frame.
#' Eliminates repetitive rbind() boilerplate in validation functions.
#'
#' @param checks Existing checks data frame
#' @param check_id Character: unique check identifier
#' @param description Character: human-readable check description
#' @param result Character: "PASS", "FAIL", or "WARNING"
#' @param detail Character: additional detail (default: "")
#'
#' @return Updated checks data frame with new row appended
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' checks <- data.frame(
#'   check_id = character(),
#'   description = character(),
#'   result = character(),
#'   detail = character()
#' )
#'
#' checks <- add_check(
#'   checks,
#'   check_id = "U1",
#'   description = "DOMAIN column exists",
#'   result = "PASS"
#' )
#' }
add_check <- function(checks, check_id, description, result, detail = "") {
  rbind(
    checks,
    data.frame(
      check_id = check_id,
      description = description,
      result = result,
      detail = detail
    )
  )
}
