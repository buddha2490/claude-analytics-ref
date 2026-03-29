# Required packages for validation function
suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(rlang)
})

#' Validate SDTM Domain
#'
#' Perform universal SDTM validation checks plus optional domain-specific checks.
#' Called by every sim_*.R program before writing XPT output.
#'
#' @param domain_df Data frame to validate
#' @param domain_code Character: domain code (e.g., "AE")
#' @param dm_ref Data frame: DM dataset for cross-checks
#' @param expected_rows Numeric vector: c(min, max) row count range
#' @param ct_reference Optional named list of CT value vectors
#' @param domain_checks Optional function(domain_df, dm_ref) for custom checks
#'
#' @return A list with verdict, checks, and summary
#' @export
validate_sdtm_domain <- function(
  domain_df,
  domain_code,
  dm_ref,
  expected_rows,
  ct_reference = NULL,
  domain_checks = NULL
) {
  # --- Validate inputs ---
  if (!is.data.frame(domain_df)) {
    stop("`domain_df` must be a data frame.", call. = FALSE)
  }
  if (!is.character(domain_code) || length(domain_code) != 1) {
    stop("`domain_code` must be a single character string.", call. = FALSE)
  }
  if (!is.data.frame(dm_ref)) {
    stop("`dm_ref` must be a data frame.", call. = FALSE)
  }
  if (!is.numeric(expected_rows) || length(expected_rows) != 2) {
    stop("`expected_rows` must be a numeric vector of length 2: c(min, max).", call. = FALSE)
  }

  # --- Initialize checks data frame ---
  checks <- data.frame(
    check_id = character(),
    description = character(),
    result = character(),
    detail = character(),
    stringsAsFactors = FALSE
  )

  # --- Universal Check U1: DOMAIN column matches domain_code ---
  if (!"DOMAIN" %in% names(domain_df)) {
    checks <- rbind(checks, data.frame(
      check_id = "U1",
      description = "DOMAIN column exists and matches domain_code",
      result = "FAIL",
      detail = "DOMAIN column not found",
      stringsAsFactors = FALSE
    ))
  } else if (!all(domain_df$DOMAIN == domain_code, na.rm = TRUE)) {
    invalid_count <- sum(domain_df$DOMAIN != domain_code, na.rm = TRUE)
    checks <- rbind(checks, data.frame(
      check_id = "U1",
      description = "DOMAIN column exists and matches domain_code",
      result = "FAIL",
      detail = sprintf("%d rows have DOMAIN != '%s'", invalid_count, domain_code),
      stringsAsFactors = FALSE
    ))
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U1",
      description = "DOMAIN column exists and matches domain_code",
      result = "PASS",
      detail = "",
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U2: STUDYID is constant and equals "NPM008" ---
  if (!"STUDYID" %in% names(domain_df)) {
    checks <- rbind(checks, data.frame(
      check_id = "U2",
      description = "STUDYID is constant and equals NPM008",
      result = "FAIL",
      detail = "STUDYID column not found",
      stringsAsFactors = FALSE
    ))
  } else {
    unique_studyids <- unique(domain_df$STUDYID)
    if (length(unique_studyids) != 1 || unique_studyids[1] != "NPM008") {
      checks <- rbind(checks, data.frame(
        check_id = "U2",
        description = "STUDYID is constant and equals NPM008",
        result = "FAIL",
        detail = sprintf("Found STUDYID values: %s", paste(unique_studyids, collapse = ", ")),
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U2",
        description = "STUDYID is constant and equals NPM008",
        result = "PASS",
        detail = "",
        stringsAsFactors = FALSE
      ))
    }
  }

  # --- Universal Check U3: USUBJID matches regex ---
  if (!"USUBJID" %in% names(domain_df)) {
    checks <- rbind(checks, data.frame(
      check_id = "U3",
      description = "USUBJID matches regex ^NPM008-\\\\d{2}-[A-Z]\\\\d{4}$",
      result = "FAIL",
      detail = "USUBJID column not found",
      stringsAsFactors = FALSE
    ))
  } else {
    invalid_usubjid <- domain_df$USUBJID[!stringr::str_detect(domain_df$USUBJID, "^NPM008-\\d{2}-[A-Z]\\d{4}$")]
    if (length(invalid_usubjid) > 0) {
      checks <- rbind(checks, data.frame(
        check_id = "U3",
        description = "USUBJID matches regex ^NPM008-\\\\d{2}-[A-Z]\\\\d{4}$",
        result = "FAIL",
        detail = sprintf("%d invalid USUBJID(s): %s",
                        length(invalid_usubjid),
                        paste(head(invalid_usubjid, 3), collapse = ", ")),
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U3",
        description = "USUBJID matches regex ^NPM008-\\\\d{2}-[A-Z]\\\\d{4}$",
        result = "PASS",
        detail = "",
        stringsAsFactors = FALSE
      ))
    }
  }

  # --- Universal Check U4: All USUBJIDs exist in dm_ref ---
  if ("USUBJID" %in% names(domain_df) && "USUBJID" %in% names(dm_ref)) {
    missing_usubjids <- dplyr::anti_join(
      domain_df, dm_ref, by = "USUBJID"
    ) %>%
      dplyr::pull(USUBJID) %>%
      unique()

    if (length(missing_usubjids) > 0) {
      checks <- rbind(checks, data.frame(
        check_id = "U4",
        description = "All USUBJIDs exist in DM reference",
        result = "FAIL",
        detail = sprintf("%d USUBJID(s) not in DM: %s",
                        length(missing_usubjids),
                        paste(head(missing_usubjids, 3), collapse = ", ")),
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U4",
        description = "All USUBJIDs exist in DM reference",
        result = "PASS",
        detail = "",
        stringsAsFactors = FALSE
      ))
    }
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U4",
      description = "All USUBJIDs exist in DM reference",
      result = "FAIL",
      detail = "USUBJID column missing from domain_df or dm_ref",
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U5: SEQ is unique integer within each USUBJID ---
  seq_col <- paste0(domain_code, "SEQ")
  if (seq_col %in% names(domain_df)) {
    if ("USUBJID" %in% names(domain_df)) {
      # Check if SEQ is integer
      if (!is.numeric(domain_df[[seq_col]])) {
        checks <- rbind(checks, data.frame(
          check_id = "U5",
          description = sprintf("%s is unique integer within each USUBJID", seq_col),
          result = "FAIL",
          detail = sprintf("%s is not numeric", seq_col),
          stringsAsFactors = FALSE
        ))
      } else {
        # Check for uniqueness within USUBJID
        dup_check <- domain_df %>%
          dplyr::group_by(USUBJID) %>%
          dplyr::summarize(
            n_rows = dplyr::n(),
            n_unique_seq = dplyr::n_distinct(!!rlang::sym(seq_col)),
            .groups = "drop"
          ) %>%
          dplyr::filter(n_rows != n_unique_seq)

        if (nrow(dup_check) > 0) {
          checks <- rbind(checks, data.frame(
            check_id = "U5",
            description = sprintf("%s is unique integer within each USUBJID", seq_col),
            result = "FAIL",
            detail = sprintf("%d USUBJID(s) have duplicate %s values",
                            nrow(dup_check), seq_col),
            stringsAsFactors = FALSE
          ))
        } else {
          checks <- rbind(checks, data.frame(
            check_id = "U5",
            description = sprintf("%s is unique integer within each USUBJID", seq_col),
            result = "PASS",
            detail = "",
            stringsAsFactors = FALSE
          ))
        }
      }
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U5",
        description = sprintf("%s is unique integer within each USUBJID", seq_col),
        result = "FAIL",
        detail = "USUBJID column not found",
        stringsAsFactors = FALSE
      ))
    }
  } else {
    # SEQ column not present - this is acceptable for some domains
    checks <- rbind(checks, data.frame(
      check_id = "U5",
      description = sprintf("%s is unique integer within each USUBJID", seq_col),
      result = "PASS",
      detail = sprintf("%s column not present (acceptable)", seq_col),
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U6: No NA in required variables ---
  required_vars <- c("STUDYID", "DOMAIN", "USUBJID")
  present_required <- required_vars[required_vars %in% names(domain_df)]

  if (length(present_required) < length(required_vars)) {
    checks <- rbind(checks, data.frame(
      check_id = "U6",
      description = "No NA in required variables (STUDYID, DOMAIN, USUBJID)",
      result = "FAIL",
      detail = sprintf("Missing required columns: %s",
                      paste(setdiff(required_vars, present_required), collapse = ", ")),
      stringsAsFactors = FALSE
    ))
  } else {
    na_counts <- sapply(present_required, function(var) sum(is.na(domain_df[[var]])))
    if (any(na_counts > 0)) {
      vars_with_na <- names(na_counts[na_counts > 0])
      checks <- rbind(checks, data.frame(
        check_id = "U6",
        description = "No NA in required variables (STUDYID, DOMAIN, USUBJID)",
        result = "FAIL",
        detail = sprintf("NA values found in: %s", paste(vars_with_na, collapse = ", ")),
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U6",
        description = "No NA in required variables (STUDYID, DOMAIN, USUBJID)",
        result = "PASS",
        detail = "",
        stringsAsFactors = FALSE
      ))
    }
  }

  # --- Universal Check U7: All DTC columns match ISO 8601 format ---
  dtc_cols <- names(domain_df)[stringr::str_detect(names(domain_df), "DTC$")]

  if (length(dtc_cols) > 0) {
    invalid_dates <- list()
    for (col in dtc_cols) {
      non_na_values <- domain_df[[col]][!is.na(domain_df[[col]])]
      if (length(non_na_values) > 0) {
        invalid <- non_na_values[!stringr::str_detect(non_na_values, "^\\d{4}-\\d{2}-\\d{2}")]
        if (length(invalid) > 0) {
          invalid_dates[[col]] <- head(invalid, 3)
        }
      }
    }

    if (length(invalid_dates) > 0) {
      detail_msg <- paste(
        sapply(names(invalid_dates), function(col) {
          sprintf("%s: %s", col, paste(invalid_dates[[col]], collapse = ", "))
        }),
        collapse = "; "
      )
      checks <- rbind(checks, data.frame(
        check_id = "U7",
        description = "All DTC columns match ISO 8601 format (YYYY-MM-DD)",
        result = "FAIL",
        detail = detail_msg,
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U7",
        description = "All DTC columns match ISO 8601 format (YYYY-MM-DD)",
        result = "PASS",
        detail = sprintf("Checked %d DTC column(s)", length(dtc_cols)),
        stringsAsFactors = FALSE
      ))
    }
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U7",
      description = "All DTC columns match ISO 8601 format (YYYY-MM-DD)",
      result = "PASS",
      detail = "No DTC columns present",
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U8: Row count within expected range (WARNING) ---
  actual_rows <- nrow(domain_df)
  min_rows <- expected_rows[1]
  max_rows <- expected_rows[2]

  if (actual_rows < min_rows || actual_rows > max_rows) {
    warning(
      sprintf("Domain %s row count (%d) outside expected range [%d, %d]",
              domain_code, actual_rows, min_rows, max_rows),
      call. = FALSE
    )
    checks <- rbind(checks, data.frame(
      check_id = "U8",
      description = "Row count within expected range",
      result = "WARNING",
      detail = sprintf("Actual: %d, Expected: [%d, %d]", actual_rows, min_rows, max_rows),
      stringsAsFactors = FALSE
    ))
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U8",
      description = "Row count within expected range",
      result = "PASS",
      detail = sprintf("Actual: %d, Expected: [%d, %d]", actual_rows, min_rows, max_rows),
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U9: No fully duplicate rows ---
  if (any(duplicated(domain_df))) {
    dup_count <- sum(duplicated(domain_df))
    checks <- rbind(checks, data.frame(
      check_id = "U9",
      description = "No fully duplicate rows",
      result = "FAIL",
      detail = sprintf("%d duplicate row(s) found", dup_count),
      stringsAsFactors = FALSE
    ))
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U9",
      description = "No fully duplicate rows",
      result = "PASS",
      detail = "",
      stringsAsFactors = FALSE
    ))
  }

  # --- Universal Check U10: CT values validated ---
  if (!is.null(ct_reference)) {
    ct_failures <- list()
    for (var_name in names(ct_reference)) {
      if (var_name %in% names(domain_df)) {
        valid_values <- ct_reference[[var_name]]
        actual_values <- domain_df[[var_name]][!is.na(domain_df[[var_name]])]
        invalid_values <- setdiff(actual_values, valid_values)

        if (length(invalid_values) > 0) {
          ct_failures[[var_name]] <- head(unique(invalid_values), 5)
        }
      }
    }

    if (length(ct_failures) > 0) {
      detail_msg <- paste(
        sapply(names(ct_failures), function(var) {
          sprintf("%s: %s", var, paste(ct_failures[[var]], collapse = ", "))
        }),
        collapse = "; "
      )
      checks <- rbind(checks, data.frame(
        check_id = "U10",
        description = "CT values validated against reference",
        result = "FAIL",
        detail = detail_msg,
        stringsAsFactors = FALSE
      ))
    } else {
      checks <- rbind(checks, data.frame(
        check_id = "U10",
        description = "CT values validated against reference",
        result = "PASS",
        detail = sprintf("Checked %d variable(s)", length(ct_reference)),
        stringsAsFactors = FALSE
      ))
    }
  } else {
    checks <- rbind(checks, data.frame(
      check_id = "U10",
      description = "CT values validated against reference",
      result = "PASS",
      detail = "No CT reference provided",
      stringsAsFactors = FALSE
    ))
  }

  # --- Domain-specific checks ---
  if (!is.null(domain_checks)) {
    if (!is.function(domain_checks)) {
      stop("`domain_checks` must be a function.", call. = FALSE)
    }

    domain_check_results <- domain_checks(domain_df, dm_ref)

    for (check in domain_check_results) {
      checks <- rbind(checks, data.frame(
        check_id = check$check_id,
        description = check$description,
        result = check$result,
        detail = check$detail,
        stringsAsFactors = FALSE
      ))
    }
  }

  # --- Determine verdict ---
  fail_count <- sum(checks$result == "FAIL")
  pass_count <- sum(checks$result == "PASS")
  warning_count <- sum(checks$result == "WARNING")

  verdict <- if (fail_count > 0) "FAIL" else "PASS"

  # --- Create summary ---
  summary_text <- sprintf(
    "%s validation: %s (%d PASS, %d FAIL, %d WARNING)",
    domain_code, verdict, pass_count, fail_count, warning_count
  )

  # --- If FAIL, stop with detailed message ---
  if (verdict == "FAIL") {
    failed_checks <- checks[checks$result == "FAIL", ]
    error_msg <- sprintf(
      "Domain %s validation FAILED:\n%s\n\nFailed checks:\n%s",
      domain_code,
      summary_text,
      paste(sprintf("  - %s: %s [%s]",
                   failed_checks$check_id,
                   failed_checks$description,
                   failed_checks$detail),
            collapse = "\n")
    )
    stop(error_msg, call. = FALSE)
  }

  # --- Return result ---
  list(
    verdict = verdict,
    checks = checks,
    summary = summary_text
  )
}
