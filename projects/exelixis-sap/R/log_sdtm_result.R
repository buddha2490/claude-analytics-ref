#' Log SDTM Result
#'
#' Write structured log entries from within sim_*.R programs. Appends to a
#' shared machine validation log file.
#'
#' @param domain_code Character: domain code (e.g., "DM")
#' @param wave Integer: wave number
#' @param row_count Integer: nrow(domain_df)
#' @param col_count Integer: ncol(domain_df)
#' @param validation_result List returned from validate_sdtm_domain()
#' @param notes Optional character vector of notes
#' @param log_dir Directory for log file (default: "logs/")
#'
#' @return NULL (called for side effect of appending to log file)
#' @export
log_sdtm_result <- function(
  domain_code,
  wave,
  row_count,
  col_count,
  validation_result,
  notes = NULL,
  log_dir = "logs/"
) {
  # --- Validate inputs ---
  if (!is.character(domain_code) || length(domain_code) != 1) {
    stop("`domain_code` must be a single character string.", call. = FALSE)
  }
  if (!is.numeric(wave) || length(wave) != 1) {
    stop("`wave` must be a single numeric value.", call. = FALSE)
  }
  if (!is.numeric(row_count) || length(row_count) != 1) {
    stop("`row_count` must be a single numeric value.", call. = FALSE)
  }
  if (!is.numeric(col_count) || length(col_count) != 1) {
    stop("`col_count` must be a single numeric value.", call. = FALSE)
  }
  if (!is.list(validation_result)) {
    stop("`validation_result` must be a list.", call. = FALSE)
  }
  if (!all(c("verdict", "checks", "summary") %in% names(validation_result))) {
    stop("`validation_result` must contain 'verdict', 'checks', and 'summary' elements.", call. = FALSE)
  }

  # --- Create log directory if it doesn't exist ---
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE)
  }

  # --- Construct log file path ---
  log_date <- format(Sys.Date(), "%Y-%m-%d")
  log_path <- file.path(log_dir, paste0("sdtm_domain_log_", log_date, ".md"))

  # --- Write header if log file doesn't exist ---
  if (!file.exists(log_path)) {
    header <- sprintf(
      "# SDTM Domain Validation Log\n\n**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA\n**Date:** %s\n\n---\n\n",
      log_date
    )
    cat(header, file = log_path)
  }

  # --- Prepare timestamp ---
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  # --- Extract check statistics ---
  checks <- validation_result$checks
  pass_count <- sum(checks$result == "PASS")
  fail_count <- sum(checks$result == "FAIL")
  warning_count <- sum(checks$result == "WARNING")
  total_count <- nrow(checks)

  # --- Build log entry ---
  log_entry <- sprintf("### %s — %s\n\n", domain_code, timestamp)
  log_entry <- paste0(log_entry, sprintf("- **Wave:** %d\n", wave))
  log_entry <- paste0(log_entry, sprintf("- **Rows:** %d\n", row_count))
  log_entry <- paste0(log_entry, sprintf("- **Columns:** %d\n", col_count))
  log_entry <- paste0(log_entry, sprintf("- **Validation:** %s\n", validation_result$verdict))
  log_entry <- paste0(log_entry, sprintf("- **Checks:** %d/%d PASS", pass_count, total_count))

  if (fail_count > 0) {
    log_entry <- paste0(log_entry, sprintf(", %d FAIL", fail_count))
  }
  if (warning_count > 0) {
    log_entry <- paste0(log_entry, sprintf(", %d WARNING", warning_count))
  }
  log_entry <- paste0(log_entry, "\n")

  # --- Add notes if provided ---
  if (!is.null(notes) && length(notes) > 0) {
    log_entry <- paste0(log_entry, "- **Notes:**\n")
    for (note in notes) {
      log_entry <- paste0(log_entry, sprintf("  - %s\n", note))
    }
  }

  # --- Add detailed check failures if any ---
  if (fail_count > 0) {
    log_entry <- paste0(log_entry, "\n**Failed Checks:**\n\n")
    failed_checks <- checks[checks$result == "FAIL", ]
    for (i in seq_len(nrow(failed_checks))) {
      check <- failed_checks[i, ]
      log_entry <- paste0(log_entry, sprintf("- **%s**: %s\n", check$check_id, check$description))
      if (nzchar(check$detail)) {
        log_entry <- paste0(log_entry, sprintf("  - Detail: %s\n", check$detail))
      }
    }
  }

  # --- Add warning details if any ---
  if (warning_count > 0) {
    log_entry <- paste0(log_entry, "\n**Warnings:**\n\n")
    warning_checks <- checks[checks$result == "WARNING", ]
    for (i in seq_len(nrow(warning_checks))) {
      check <- warning_checks[i, ]
      log_entry <- paste0(log_entry, sprintf("- **%s**: %s\n", check$check_id, check$description))
      if (nzchar(check$detail)) {
        log_entry <- paste0(log_entry, sprintf("  - Detail: %s\n", check$detail))
      }
    }
  }

  log_entry <- paste0(log_entry, "\n---\n\n")

  # --- Append to log file ---
  cat(log_entry, file = log_path, append = TRUE)

  invisible(NULL)
}
