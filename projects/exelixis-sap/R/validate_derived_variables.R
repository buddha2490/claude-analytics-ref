#' Validate Derived Variable Logic
#'
#' Performs spot-checks on derived variables to verify they follow expected
#' cardinality rules and derivation logic.
#'
#' @param data Data frame containing the derived variable
#' @param param_var Character string naming the parameter variable (e.g., "PARAMCD")
#' @param param_value Character value of the parameter to check (e.g., "BOR")
#' @param expected_cardinality Character describing expected cardinality:
#'   - "one_per_subject": Exactly 1 record per subject
#'   - "zero_or_one_per_subject": 0 or 1 records per subject
#'   - "multiple_allowed": Multiple records per subject allowed
#' @param check_name Character string describing the check (for reporting)
#'
#' @return A list with:
#'   - `verdict`: "PASS", "WARNING", or "FAIL"
#'   - `severity`: "CRITICAL" or "WARNING" or "INFO"
#'   - `violations`: Data frame of subjects violating cardinality (if any)
#'   - `n_violations`: Count of subjects with cardinality violations
#'   - `message`: Human-readable summary
#'
#' @details
#' Severity classification:
#' - CRITICAL: Cardinality violations for "one_per_subject" parameters (BOR, EOS)
#' - WARNING: Unexpected patterns that may indicate derivation issues
#'
#' Common cardinality checks:
#' - BOR (Best Overall Response): Must have exactly 1 record per subject
#' - EOS (End of Study): Must have exactly 1 record per subject
#' - DOR (Duration of Response): Only for responders (CR/PR)
#'
#' @export
#'
#' @examples
#' \dontrun{
#' adrs <- haven::read_xpt("data/adrs.xpt")
#' result <- validate_derived_variables(
#'   adrs,
#'   param_var = "PARAMCD",
#'   param_value = "BOR",
#'   expected_cardinality = "one_per_subject",
#'   check_name = "BOR cardinality"
#' )
#' }
validate_derived_variables <- function(data,
                                       param_var,
                                       param_value,
                                       expected_cardinality = "one_per_subject",
                                       check_name = "Derived variable") {
  # --- Validate inputs ---
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  if (!"USUBJID" %in% names(data)) {
    stop("Column `USUBJID` not found in data.", call. = FALSE)
  }
  if (!param_var %in% names(data)) {
    stop("Column `", param_var, "` not found in data.", call. = FALSE)
  }
  if (!expected_cardinality %in% c("one_per_subject", "zero_or_one_per_subject", "multiple_allowed")) {
    stop("`expected_cardinality` must be one of: 'one_per_subject', 'zero_or_one_per_subject', 'multiple_allowed'",
         call. = FALSE)
  }

  # --- Filter to parameter records ---
  param_records <- data %>%
    dplyr::filter(.data[[param_var]] == param_value)

  if (nrow(param_records) == 0) {
    return(list(
      verdict = "WARNING",
      severity = "WARNING",
      violations = data.frame(),
      n_violations = 0,
      message = sprintf("⚠ %s: No records found with %s='%s'",
                       check_name, param_var, param_value)
    ))
  }

  # --- Count records per subject ---
  subject_counts <- param_records %>%
    dplyr::count(USUBJID, name = "n_records")

  # --- Check cardinality ---
  violations <- switch(expected_cardinality,
    "one_per_subject" = subject_counts %>%
      dplyr::filter(n_records != 1),
    "zero_or_one_per_subject" = subject_counts %>%
      dplyr::filter(n_records > 1),
    "multiple_allowed" = data.frame(),  # No violations possible
    stop("Unsupported cardinality: ", expected_cardinality, call. = FALSE)
  )

  n_violations <- nrow(violations)
  n_subjects <- dplyr::n_distinct(param_records$USUBJID)

  # --- Also check for missing subjects (only for one_per_subject) ---
  missing_subjects <- data.frame()
  n_missing <- 0

  if (expected_cardinality == "one_per_subject") {
    all_subjects <- unique(data$USUBJID)
    param_subjects <- unique(param_records$USUBJID)
    missing_subjects_ids <- setdiff(all_subjects, param_subjects)
    n_missing <- length(missing_subjects_ids)

    if (n_missing > 0) {
      missing_subjects <- data.frame(
        USUBJID = head(missing_subjects_ids, 10),
        n_records = 0
      )
    }
  }

  # --- Combine violations ---
  all_violations <- dplyr::bind_rows(violations, missing_subjects)
  total_violations <- n_violations + n_missing

  # --- Determine verdict and severity ---
  if (total_violations == 0) {
    verdict <- "PASS"
    severity <- "INFO"
    msg <- sprintf(
      "✓ %s: All %d subjects have correct cardinality for %s='%s'",
      check_name, n_subjects, param_var, param_value
    )
  } else {
    severity <- if (expected_cardinality == "one_per_subject") "CRITICAL" else "WARNING"
    verdict <- if (severity == "CRITICAL") "FAIL" else "WARNING"

    violation_details <- character()
    if (n_violations > 0) {
      violation_details <- c(violation_details,
                            sprintf("%d subjects with n != 1", n_violations))
    }
    if (n_missing > 0) {
      violation_details <- c(violation_details,
                            sprintf("%d subjects with n = 0", n_missing))
    }

    msg <- sprintf(
      "%s %s: Cardinality violations for %s='%s': %s",
      if (verdict == "FAIL") "✗" else "⚠",
      check_name,
      param_var,
      param_value,
      paste(violation_details, collapse = ", ")
    )
  }

  # --- Return structured result ---
  list(
    verdict = verdict,
    severity = severity,
    violations = all_violations %>% head(10),
    n_violations = total_violations,
    message = msg
  )
}
