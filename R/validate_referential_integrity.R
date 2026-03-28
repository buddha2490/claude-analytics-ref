#' Validate Referential Integrity Between Datasets
#'
#' Checks that all subjects (USUBJIDs) in child datasets exist in parent datasets.
#' This is a critical validation to ensure data consistency across domains.
#'
#' @param child_data Data frame containing the child dataset
#' @param parent_data Data frame containing the parent dataset
#' @param child_name Character string naming the child dataset (for reporting)
#' @param parent_name Character string naming the parent dataset (for reporting)
#' @param id_var Character string naming the subject ID variable (default: "USUBJID")
#'
#' @return A list with:
#'   - `verdict`: "PASS", "WARNING", or "FAIL"
#'   - `severity`: "CRITICAL" for failures, "WARNING" for warnings, "INFO" for passes
#'   - `missing_ids`: Vector of IDs in child but not in parent (if any)
#'   - `n_missing`: Count of missing IDs
#'   - `pct_missing`: Percentage of child records with missing parent IDs
#'   - `message`: Human-readable summary
#'
#' @details
#' Severity classification:
#' - CRITICAL: Any missing IDs (orphan records should never exist)
#' - Pass requires 100% referential integrity
#'
#' @export
#'
#' @examples
#' \dontrun{
#' dm <- haven::read_xpt("data/dm.xpt")
#' adsl <- haven::read_xpt("data/adsl.xpt")
#' result <- validate_referential_integrity(adsl, dm, "ADSL", "DM")
#' }
validate_referential_integrity <- function(child_data,
                                           parent_data,
                                           child_name,
                                           parent_name,
                                           id_var = "USUBJID") {
  # --- Validate inputs ---
  if (!is.data.frame(child_data)) {
    stop("`child_data` must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(parent_data)) {
    stop("`parent_data` must be a data frame.", call. = FALSE)
  }
  if (!id_var %in% names(child_data)) {
    stop("Column `", id_var, "` not found in child dataset `", child_name, "`.",
         call. = FALSE)
  }
  if (!id_var %in% names(parent_data)) {
    stop("Column `", id_var, "` not found in parent dataset `", parent_name, "`.",
         call. = FALSE)
  }

  # --- Extract unique IDs ---
  child_ids <- unique(child_data[[id_var]])
  parent_ids <- unique(parent_data[[id_var]])

  # --- Find orphan records ---
  missing_ids <- setdiff(child_ids, parent_ids)
  n_missing <- length(missing_ids)
  n_total <- length(child_ids)
  pct_missing <- round(100 * n_missing / n_total, 2)

  # --- Determine verdict and severity ---
  if (n_missing == 0) {
    verdict <- "PASS"
    severity <- "INFO"
    msg <- sprintf(
      "✓ Referential integrity OK: All %d subjects in %s exist in %s",
      n_total, child_name, parent_name
    )
  } else {
    verdict <- "FAIL"
    severity <- "CRITICAL"
    msg <- sprintf(
      "✗ Referential integrity violation: %s contains %d subjects (%.1f%%) not in %s: %s",
      child_name,
      n_missing,
      pct_missing,
      parent_name,
      paste(head(missing_ids, 10), collapse = ", ")
    )
    if (n_missing > 10) {
      msg <- paste0(msg, sprintf(" ... and %d more", n_missing - 10))
    }
  }

  # --- Return structured result ---
  list(
    verdict = verdict,
    severity = severity,
    missing_ids = missing_ids,
    n_missing = n_missing,
    pct_missing = pct_missing,
    message = msg
  )
}
