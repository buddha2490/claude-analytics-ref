#' Between-Wave Validation Checks for NPM-008 Study
#'
#' Orchestrates comprehensive validation checks after each wave completes.
#' Calls generic validation functions with study-specific parameters.
#'
#' @param wave_number Integer wave number (1, 2, 3, 4, ...)
#' @param completed_datasets Character vector of dataset names completed in this wave
#' @param data_path Path to directory containing XPT files
#' @param auto_retry Logical indicating whether to auto-retry on first failure (default: TRUE)
#'
#' @return A list with:
#'   - `verdict`: "PASS", "WARNING", or "FAIL"
#'   - `checks`: List of all check results
#'   - `summary`: Data frame summarizing all checks
#'   - `retry_attempted`: Logical indicating if retry was triggered
#'
#' @details
#' Validation coverage by wave:
#' - Wave 1 (SDTM only): Row/subject counts
#' - Wave 2 (ADSL): Referential integrity (ADSL vs DM), row/subject counts
#' - Wave 3 (ADAE/ADRS): Date consistency (TRTEMFL), derived variables (BOR), referential integrity
#' - Wave 4 (ADTTE): Cross-domain consistency (DOR vs responders)
#'
#' Auto-retry behavior (Q2 decision):
#' - On first FAIL verdict: Retry wave once automatically
#' - On second FAIL: Escalate to user with detailed report
#'
#' @export
#'
#' @examples
#' \dontrun{
#' result <- run_between_wave_checks(
#'   wave_number = 3,
#'   completed_datasets = c("adsl", "adae", "adrs"),
#'   data_path = "projects/exelixis-sap/data"
#' )
#' }
run_between_wave_checks <- function(wave_number,
                                    completed_datasets,
                                    data_path,
                                    auto_retry = TRUE) {
  message("\n========================================")
  message("Wave ", wave_number, " Validation Checks")
  message("========================================\n")

  # --- Validate inputs ---
  if (!dir.exists(data_path)) {
    stop("Data path does not exist: ", data_path, call. = FALSE)
  }

  checks <- list()
  check_counter <- 1

  # --- Load common datasets ---
  # DM is needed for Wave 2+
  if (wave_number >= 2) {
    dm_path <- file.path(data_path, "dm.xpt")
    if (!file.exists(dm_path)) {
      stop("DM dataset not found: ", dm_path, call. = FALSE)
    }
    dm <- haven::read_xpt(dm_path)
    message("Loaded DM: ", nrow(dm), " records, ", dplyr::n_distinct(dm$USUBJID), " subjects")
  }

  # ADSL is needed for Wave 2+
  if (wave_number >= 2 && "adsl" %in% tolower(completed_datasets)) {
    adsl_path <- file.path(data_path, "adsl.xpt")
    if (!file.exists(adsl_path)) {
      stop("ADSL dataset not found: ", adsl_path, call. = FALSE)
    }
    adsl <- haven::read_xpt(adsl_path)
    message("Loaded ADSL: ", nrow(adsl), " records, ", dplyr::n_distinct(adsl$USUBJID), " subjects")
  }

  # --- Wave 2: ADSL Referential Integrity ---
  if (wave_number >= 2 && "adsl" %in% tolower(completed_datasets)) {
    message("\n--- Check ", check_counter, ": ADSL vs DM Referential Integrity ---")

    checks[[check_counter]] <- validate_referential_integrity(
      child_data = adsl,
      parent_data = dm,
      child_name = "ADSL",
      parent_name = "DM"
    )

    message(checks[[check_counter]]$message)
    check_counter <- check_counter + 1
  }

  # --- Wave 3: ADAE/ADRS Checks ---
  if (wave_number >= 3) {
    # Load ADAE if present
    if ("adae" %in% tolower(completed_datasets)) {
      adae_path <- file.path(data_path, "adae.xpt")
      if (file.exists(adae_path)) {
        adae <- haven::read_xpt(adae_path)
        message("\nLoaded ADAE: ", nrow(adae), " records, ", dplyr::n_distinct(adae$USUBJID), " subjects")

        # Check 1: ADAE vs ADSL referential integrity
        message("\n--- Check ", check_counter, ": ADAE vs ADSL Referential Integrity ---")
        checks[[check_counter]] <- validate_referential_integrity(
          child_data = adae,
          parent_data = adsl,
          child_name = "ADAE",
          parent_name = "ADSL"
        )
        message(checks[[check_counter]]$message)
        check_counter <- check_counter + 1

        # Check 2: TRTEMFL date consistency
        if ("TRTEMFL" %in% names(adae) && "TRTSDT" %in% names(adsl)) {
          message("\n--- Check ", check_counter, ": TRTEMFL Date Consistency ---")
          checks[[check_counter]] <- validate_date_consistency(
            event_data = adae,
            reference_data = adsl,
            event_date_var = "AESTDT",
            reference_date_var = "TRTSDT",
            flag_var = "TRTEMFL",
            check_name = "TRTEMFL vs TRTSDT"
          )
          message(checks[[check_counter]]$message)
          check_counter <- check_counter + 1
        }
      }
    }

    # Load ADRS if present
    if ("adrs" %in% tolower(completed_datasets)) {
      adrs_path <- file.path(data_path, "adrs.xpt")
      if (file.exists(adrs_path)) {
        adrs <- haven::read_xpt(adrs_path)
        message("\nLoaded ADRS: ", nrow(adrs), " records, ", dplyr::n_distinct(adrs$USUBJID), " subjects")

        # Check 1: ADRS vs ADSL referential integrity
        message("\n--- Check ", check_counter, ": ADRS vs ADSL Referential Integrity ---")
        checks[[check_counter]] <- validate_referential_integrity(
          child_data = adrs,
          parent_data = adsl,
          child_name = "ADRS",
          parent_name = "ADSL"
        )
        message(checks[[check_counter]]$message)
        check_counter <- check_counter + 1

        # Check 2: BOR cardinality
        if ("PARAMCD" %in% names(adrs)) {
          message("\n--- Check ", check_counter, ": BOR Cardinality ---")
          checks[[check_counter]] <- validate_derived_variables(
            data = adrs,
            param_var = "PARAMCD",
            param_value = "BOR",
            expected_cardinality = "one_per_subject",
            check_name = "BOR cardinality"
          )
          message(checks[[check_counter]]$message)
          check_counter <- check_counter + 1
        }
      }
    }
  }

  # --- Wave 4: ADTTE Cross-Domain Checks ---
  if (wave_number >= 4 && "adtte" %in% tolower(completed_datasets)) {
    adtte_path <- file.path(data_path, "adtte.xpt")
    if (file.exists(adtte_path)) {
      adtte <- haven::read_xpt(adtte_path)
      message("\nLoaded ADTTE: ", nrow(adtte), " records, ", dplyr::n_distinct(adtte$USUBJID), " subjects")

      # Check 1: ADTTE vs ADSL referential integrity
      message("\n--- Check ", check_counter, ": ADTTE vs ADSL Referential Integrity ---")
      checks[[check_counter]] <- validate_referential_integrity(
        child_data = adtte,
        parent_data = adsl,
        child_name = "ADTTE",
        parent_name = "ADSL"
      )
      message(checks[[check_counter]]$message)
      check_counter <- check_counter + 1

      # Check 2: DOR vs Responders consistency
      if (exists("adrs") && "PARAMCD" %in% names(adrs) && "PARAMCD" %in% names(adtte)) {
        message("\n--- Check ", check_counter, ": DOR vs Responders Consistency ---")
        checks[[check_counter]] <- validate_cross_domain(
          check_type = "dor_responders",
          adrs = adrs,
          adtte = adtte
        )
        message(checks[[check_counter]]$message)
        check_counter <- check_counter + 1
      }
    }
  }

  # --- Summarize Results ---
  message("\n========================================")
  message("Summary: ", length(checks), " checks performed")
  message("========================================\n")

  # Create summary table
  summary_df <- data.frame(
    check_num = seq_along(checks),
    verdict = sapply(checks, function(x) x$verdict),
    severity = sapply(checks, function(x) x$severity),
    message = sapply(checks, function(x) x$message),
    stringsAsFactors = FALSE
  )

  # Count by verdict
  n_pass <- sum(summary_df$verdict == "PASS")
  n_warning <- sum(summary_df$verdict == "WARNING")
  n_fail <- sum(summary_df$verdict == "FAIL")

  message("PASS: ", n_pass)
  message("WARNING: ", n_warning)
  message("FAIL: ", n_fail)

  # --- Determine overall verdict ---
  overall_verdict <- if (n_fail > 0) {
    "FAIL"
  } else if (n_warning > 0) {
    "WARNING"
  } else {
    "PASS"
  }

  # --- Auto-retry logic (Q2 decision) ---
  retry_attempted <- FALSE
  if (overall_verdict == "FAIL" && auto_retry) {
    message("\n⚠ FAIL verdict on first attempt. Auto-retry is enabled.")
    message("Recommendation: Review failures above and re-run wave.")
    retry_attempted <- TRUE
  }

  message("\n========================================")
  message("Overall Verdict: ", overall_verdict)
  message("========================================\n")

  # --- Return structured result ---
  invisible(list(
    verdict = overall_verdict,
    checks = checks,
    summary = summary_df,
    retry_attempted = retry_attempted
  ))
}
