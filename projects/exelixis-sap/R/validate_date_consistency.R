#' Validate Date Consistency Logic
#'
#' Checks date-based logical constraints, such as treatment-emergent flags
#' (TRTEMFL) requiring event dates on or after treatment start date.
#'
#' @param event_data Data frame containing event records with dates
#' @param reference_data Data frame containing reference dates (e.g., ADSL with TRTSDT)
#' @param event_date_var Character string naming the event date variable
#' @param reference_date_var Character string naming the reference date variable
#' @param flag_var Character string naming the flag variable to validate (e.g., "TRTEMFL")
#' @param flag_value Character value indicating the flag is set (default: "Y")
#' @param constraint Character description of the constraint (e.g., ">=", ">", "<=")
#' @param check_name Character string describing the check (for reporting)
#'
#' @return A list with:
#'   - `verdict`: "PASS", "WARNING", or "FAIL"
#'   - `severity`: "CRITICAL" or "WARNING" or "INFO"
#'   - `violations`: Data frame of records violating the constraint (if any)
#'   - `n_violations`: Count of violating records
#'   - `message`: Human-readable summary
#'
#' @details
#' Severity classification:
#' - CRITICAL: Any violations of TRTEMFL logic (treatment-emergent flag inconsistency)
#' - WARNING: Violations of other date logic that may indicate data issues
#'
#' Common constraints:
#' - TRTEMFL='Y' requires event_date >= treatment_start (constraint = ">=")
#' - Study day calculations require event_date != NA when flag set
#'
#' @export
#'
#' @examples
#' \dontrun{
#' adae <- haven::read_xpt("data/adae.xpt")
#' adsl <- haven::read_xpt("data/adsl.xpt")
#' result <- validate_date_consistency(
#'   adae, adsl,
#'   event_date_var = "AESTDT",
#'   reference_date_var = "TRTSDT",
#'   flag_var = "TRTEMFL",
#'   check_name = "TRTEMFL vs TRTSDT"
#' )
#' }
validate_date_consistency <- function(event_data,
                                      reference_data,
                                      event_date_var,
                                      reference_date_var,
                                      flag_var,
                                      flag_value = "Y",
                                      constraint = ">=",
                                      check_name = "Date consistency") {
  # --- Validate inputs ---
  if (!is.data.frame(event_data)) {
    stop("`event_data` must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(reference_data)) {
    stop("`reference_data` must be a data frame.", call. = FALSE)
  }
  if (!"USUBJID" %in% names(event_data)) {
    stop("Column `USUBJID` not found in event_data.", call. = FALSE)
  }
  if (!"USUBJID" %in% names(reference_data)) {
    stop("Column `USUBJID` not found in reference_data.", call. = FALSE)
  }
  if (!event_date_var %in% names(event_data)) {
    stop("Column `", event_date_var, "` not found in event_data.", call. = FALSE)
  }
  if (!reference_date_var %in% names(reference_data)) {
    stop("Column `", reference_date_var, "` not found in reference_data.",
         call. = FALSE)
  }
  if (!flag_var %in% names(event_data)) {
    stop("Column `", flag_var, "` not found in event_data.", call. = FALSE)
  }

  # --- Merge event data with reference dates ---
  merged_data <- event_data %>%
    dplyr::left_join(
      reference_data %>% dplyr::select(USUBJID, dplyr::all_of(reference_date_var)),
      by = "USUBJID"
    )

  # --- Filter to flagged records ---
  flagged_records <- merged_data %>%
    dplyr::filter(.data[[flag_var]] == flag_value)

  if (nrow(flagged_records) == 0) {
    return(list(
      verdict = "PASS",
      severity = "INFO",
      violations = data.frame(),
      n_violations = 0,
      message = sprintf("✓ %s: No records with %s='%s' to validate",
                       check_name, flag_var, flag_value)
    ))
  }

  # --- Apply constraint ---
  violations <- switch(constraint,
    ">=" = flagged_records %>%
      dplyr::filter(.data[[event_date_var]] < .data[[reference_date_var]]),
    ">" = flagged_records %>%
      dplyr::filter(.data[[event_date_var]] <= .data[[reference_date_var]]),
    "<=" = flagged_records %>%
      dplyr::filter(.data[[event_date_var]] > .data[[reference_date_var]]),
    "<" = flagged_records %>%
      dplyr::filter(.data[[event_date_var]] >= .data[[reference_date_var]]),
    stop("Unsupported constraint: ", constraint, call. = FALSE)
  )

  n_violations <- nrow(violations)
  n_total <- nrow(flagged_records)
  pct_violations <- round(100 * n_violations / n_total, 2)

  # --- Determine verdict and severity ---
  if (n_violations == 0) {
    verdict <- "PASS"
    severity <- "INFO"
    msg <- sprintf(
      "✓ %s: All %d records with %s='%s' satisfy %s %s %s",
      check_name, n_total, flag_var, flag_value,
      event_date_var, constraint, reference_date_var
    )
  } else {
    # TRTEMFL violations are critical, others are warnings
    severity <- if (flag_var == "TRTEMFL") "CRITICAL" else "WARNING"
    verdict <- if (severity == "CRITICAL") "FAIL" else "WARNING"

    msg <- sprintf(
      "%s %s: Found %d/%d records (%.1f%%) where %s='%s' but %s %s %s fails",
      if (verdict == "FAIL") "✗" else "⚠",
      check_name,
      n_violations,
      n_total,
      pct_violations,
      flag_var,
      flag_value,
      event_date_var,
      constraint,
      reference_date_var
    )
  }

  # --- Return structured result ---
  list(
    verdict = verdict,
    severity = severity,
    violations = violations %>%
      dplyr::select(
        USUBJID,
        dplyr::all_of(c(event_date_var, reference_date_var, flag_var))
      ) %>%
      head(10),
    n_violations = n_violations,
    message = msg
  )
}
