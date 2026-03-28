#' Validate Cross-Domain Consistency
#'
#' Checks logical consistency between related datasets, such as ensuring
#' DOR records exist only for responders (CR/PR in ADRS).
#'
#' @param check_type Character string specifying the check to perform:
#'   - "dor_responders": DOR count must match CR/PR count in ADRS
#'   - "custom": Custom check using user-provided function
#' @param ... Additional arguments passed to specific check functions
#'
#' @return A list with:
#'   - `verdict`: "PASS", "WARNING", or "FAIL"
#'   - `severity`: "CRITICAL" or "WARNING" or "INFO"
#'   - `details`: List containing check-specific details
#'   - `message`: Human-readable summary
#'
#' @details
#' Severity classification:
#' - CRITICAL: DOR/responder mismatch (indicates derivation logic error)
#' - WARNING: Unexpected patterns requiring review
#'
#' @export
#'
#' @examples
#' \dontrun{
#' adrs <- haven::read_xpt("data/adrs.xpt")
#' adtte <- haven::read_xpt("data/adtte.xpt")
#' result <- validate_cross_domain(
#'   check_type = "dor_responders",
#'   adrs = adrs,
#'   adtte = adtte
#' )
#' }
validate_cross_domain <- function(check_type, ...) {
  # --- Dispatch to specific check function ---
  switch(check_type,
    "dor_responders" = validate_dor_responders(...),
    stop("Unsupported check_type: ", check_type, call. = FALSE)
  )
}

#' Validate DOR Records Match Responders
#'
#' Internal function to check DOR/responder consistency.
#'
#' @param adrs Data frame containing ADRS with BOR parameter
#' @param adtte Data frame containing ADTTE with DOR parameter
#' @param bor_param_value Character value for BOR parameter (default: "BOR")
#' @param dor_param_value Character value for DOR parameter (default: "DOR")
#' @param response_values Character vector of response values (default: c("CR", "PR"))
#'
#' @return List with validation results
#' @keywords internal
validate_dor_responders <- function(adrs,
                                   adtte,
                                   bor_param_value = "BOR",
                                   dor_param_value = "DOR",
                                   response_values = c("CR", "PR")) {
  # --- Validate inputs ---
  if (!is.data.frame(adrs)) {
    stop("`adrs` must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(adtte)) {
    stop("`adtte` must be a data frame.", call. = FALSE)
  }
  if (!"PARAMCD" %in% names(adrs)) {
    stop("Column `PARAMCD` not found in adrs.", call. = FALSE)
  }
  if (!"PARAMCD" %in% names(adtte)) {
    stop("Column `PARAMCD` not found in adtte.", call. = FALSE)
  }
  if (!"AVALC" %in% names(adrs)) {
    stop("Column `AVALC` not found in adrs.", call. = FALSE)
  }

  # --- Count responders in ADRS ---
  responders <- adrs %>%
    dplyr::filter(
      .data$PARAMCD == bor_param_value,
      .data$AVALC %in% response_values
    )
  n_responders <- nrow(responders)
  responder_subjects <- unique(responders$USUBJID)

  # --- Count DOR records in ADTTE ---
  dor_records <- adtte %>%
    dplyr::filter(.data$PARAMCD == dor_param_value)
  n_dor <- nrow(dor_records)
  dor_subjects <- unique(dor_records$USUBJID)

  # --- Check consistency ---
  # DOR records should exist for all and only responders
  missing_dor <- setdiff(responder_subjects, dor_subjects)
  extra_dor <- setdiff(dor_subjects, responder_subjects)

  n_missing_dor <- length(missing_dor)
  n_extra_dor <- length(extra_dor)

  # --- Determine verdict and severity ---
  if (n_missing_dor == 0 && n_extra_dor == 0) {
    verdict <- "PASS"
    severity <- "INFO"
    msg <- sprintf(
      "✓ DOR/Responder consistency: %d DOR records match %d responders (BOR CR/PR)",
      n_dor, n_responders
    )
  } else {
    verdict <- "FAIL"
    severity <- "CRITICAL"

    issues <- character()
    if (n_missing_dor > 0) {
      issues <- c(issues,
                 sprintf("%d responders missing DOR records", n_missing_dor))
    }
    if (n_extra_dor > 0) {
      issues <- c(issues,
                 sprintf("%d DOR records for non-responders", n_extra_dor))
    }

    msg <- sprintf(
      "✗ DOR/Responder mismatch: %s (Expected %d DOR = %d responders, found %d DOR)",
      paste(issues, collapse = ", "),
      n_responders,
      n_responders,
      n_dor
    )
  }

  # --- Return structured result ---
  list(
    verdict = verdict,
    severity = severity,
    details = list(
      n_responders = n_responders,
      n_dor = n_dor,
      missing_dor = head(missing_dor, 10),
      extra_dor = head(extra_dor, 10),
      n_missing_dor = n_missing_dor,
      n_extra_dor = n_extra_dor
    ),
    message = msg
  )
}
