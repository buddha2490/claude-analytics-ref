#' Validate Data Contract Between Plan and SDTM Data
#'
#' Pre-flight check that validates SDTM structure against plan specifications
#' before code execution begins. Parses "Source variables" tables from the plan,
#' reads actual SDTM XPT files, and generates a structured discrepancy report.
#'
#' @param plan_path Character. Path to the plan markdown file.
#' @param sdtm_path Character. Path to directory containing SDTM XPT files.
#' @param domains Character vector. Optional. Specific domains to validate.
#'   If NULL (default), validates all domains mentioned in the plan.
#'
#' @return List with components:
#'   - `verdict`: "PASS" or "FAIL"
#'   - `issues`: data frame with columns: domain, variable, issue_type, message
#'   - `report`: formatted markdown report string
#'   - `summary`: named integer vector with counts by issue_type
#'
#' @examples
#' result <- validate_data_contract(
#'   plan_path = "projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md",
#'   sdtm_path = "projects/exelixis-sap/output-data/sdtm"
#' )
#' cat(result$report)
#'
#' @export
validate_data_contract <- function(plan_path, sdtm_path, domains = NULL) {
  # --- Validate inputs ---
  if (!is.character(plan_path) || length(plan_path) != 1) {
    stop("`plan_path` must be a single character string.", call. = FALSE)
  }
  if (!file.exists(plan_path)) {
    stop("Plan file not found: ", plan_path, call. = FALSE)
  }
  if (!is.character(sdtm_path) || length(sdtm_path) != 1) {
    stop("`sdtm_path` must be a single character string.", call. = FALSE)
  }
  if (!dir.exists(sdtm_path)) {
    stop("SDTM directory not found: ", sdtm_path, call. = FALSE)
  }

  # --- Parse plan for Source variables tables ---
  plan_text <- readLines(plan_path, warn = FALSE)

  # Extract all "Source variables:" sections
  source_var_sections <- extract_source_variable_tables(plan_text)

  if (length(source_var_sections) == 0) {
    warning("No 'Source variables:' tables found in plan.", call. = FALSE)
    return(list(
      verdict = "PASS",
      issues = data.frame(
        domain = character(),
        variable = character(),
        issue_type = character(),
        message = character(),

      ),
      report = "Data Contract Validation Report\n================================\n\nNo source variable tables found in plan.\n\nVERDICT: PASS (nothing to validate)\n",
      summary = integer()
    ))
  }

  # Filter domains if specified
  if (!is.null(domains)) {
    source_var_sections <- source_var_sections[names(source_var_sections) %in% toupper(domains)]
  }

  # --- Validate each domain ---
  issues <- list()

  for (domain_name in names(source_var_sections)) {
    domain_lower <- tolower(domain_name)
    xpt_file <- file.path(sdtm_path, paste0(domain_lower, ".xpt"))

    # Check if XPT file exists
    if (!file.exists(xpt_file)) {
      issues[[length(issues) + 1]] <- data.frame(
        domain = domain_name,
        variable = NA_character_,
        issue_type = "missing_file",
        message = paste0("XPT file not found: ", xpt_file),

      )
      next
    }

    # Read XPT file to get actual variables
    actual_data <- tryCatch(
      haven::read_xpt(xpt_file),
      error = function(e) {
        issues[[length(issues) + 1]] <<- data.frame(
          domain = domain_name,
          variable = NA_character_,
          issue_type = "read_error",
          message = paste0("Failed to read XPT: ", e$message),

        )
        return(NULL)
      }
    )

    if (is.null(actual_data)) next

    actual_vars <- names(actual_data)
    expected_vars <- source_var_sections[[domain_name]]

    # Check for missing variables
    missing_vars <- setdiff(expected_vars, actual_vars)
    if (length(missing_vars) > 0) {
      for (var in missing_vars) {
        # Try to find alternatives (common CDISC substitutions)
        alternative <- find_alternative_variable(var, actual_vars)

        if (!is.null(alternative)) {
          issues[[length(issues) + 1]] <- data.frame(
            domain = domain_name,
            variable = var,
            issue_type = "missing_with_alternative",
            message = paste0("Variable not found, but alternative exists: ", alternative),

          )
        } else {
          issues[[length(issues) + 1]] <- data.frame(
            domain = domain_name,
            variable = var,
            issue_type = "missing",
            message = "Variable listed in plan but not found in data",

          )
        }
      }
    }

    # Check for unexpected variables (informational only, not a failure)
    unexpected_vars <- setdiff(actual_vars, c(expected_vars, "STUDYID", "DOMAIN", "USUBJID"))
    if (length(unexpected_vars) > 5) {
      # Only report if many unexpected vars (might indicate wrong domain)
      issues[[length(issues) + 1]] <- data.frame(
        domain = domain_name,
        variable = paste(head(unexpected_vars, 3), collapse = ", "),
        issue_type = "info",
        message = paste0(length(unexpected_vars), " additional variables in data not mentioned in plan"),

      )
    }
  }

  # --- Combine issues ---
  issues_df <- if (length(issues) > 0) {
    do.call(rbind, issues)
  } else {
    data.frame(
      domain = character(),
      variable = character(),
      issue_type = character(),
      message = character(),

    )
  }

  # --- Generate report ---
  report <- generate_validation_report(issues_df, source_var_sections)

  # --- Determine verdict ---
  critical_issues <- issues_df$issue_type %in% c("missing", "missing_file", "read_error")
  verdict <- if (any(critical_issues)) "FAIL" else "PASS"

  # --- Summary counts ---
  summary_counts <- table(issues_df$issue_type)

  list(
    verdict = verdict,
    issues = issues_df,
    report = report,
    summary = summary_counts
  )
}

#' Extract Source Variable Tables from Plan
#'
#' @param plan_text Character vector of plan lines
#' @return Named list where names are domains and values are character vectors of variables
#' @noRd
extract_source_variable_tables <- function(plan_text) {
  sections <- list()

  # Find all "**Source variables:**" headers
  source_var_lines <- grep("^\\*\\*Source variables:\\*\\*", plan_text)

  for (idx in source_var_lines) {
    # Find the table that follows (starts with | Domain | or |------)
    table_start <- NULL
    for (i in (idx + 1):min(idx + 10, length(plan_text))) {
      if (grepl("^\\|\\s*Domain", plan_text[i], ignore.case = TRUE)) {
        table_start <- i + 2  # Skip header and separator line
        break
      }
    }

    if (is.null(table_start)) next

    # Read table rows until we hit a blank line or non-table line
    table_end <- table_start
    while (table_end <= length(plan_text) && grepl("^\\|", plan_text[table_end])) {
      table_end <- table_end + 1
    }
    table_end <- table_end - 1

    # Parse table rows
    for (row_idx in table_start:table_end) {
      row <- plan_text[row_idx]
      parts <- strsplit(row, "\\|")[[1]]
      parts <- trimws(parts)
      parts <- parts[parts != ""]

      if (length(parts) >= 2) {
        domain <- toupper(parts[1])
        vars_string <- parts[2]

        # Extract variable names (comma-separated, may include spaces)
        vars <- strsplit(vars_string, ",")[[1]]
        vars <- trimws(vars)
        vars <- vars[vars != ""]

        sections[[domain]] <- unique(c(sections[[domain]], vars))
      }
    }
  }

  sections
}

#' Find Alternative Variable Name
#'
#' Check for common CDISC variable substitutions
#'
#' @param var Character. Missing variable name
#' @param actual_vars Character vector. Available variables
#' @return Character or NULL
#' @noRd
find_alternative_variable <- function(var, actual_vars) {
  # Common substitutions
  alternatives <- list(
    "MHDTC" = "MHSTDTC",
    "AEDTC" = "AESTDTC",
    "CMDTC" = "CMSTDTC",
    "EXDTC" = "EXSTDTC",
    "LBDTC" = "LBDTC",
    "QSDTC" = "QSDTC",
    "RSDTC" = "RSDTC",
    "QSSTRESN" = "QSORRES",  # Numeric vs character result
    "LBSTRESN" = "LBORRES"
  )

  if (var %in% names(alternatives)) {
    candidate <- alternatives[[var]]
    if (candidate %in% actual_vars) {
      return(candidate)
    }
  }

  # Try adding ST prefix (DTC -> STDTC pattern)
  if (grepl("DTC$", var) && !grepl("STDTC$", var)) {
    candidate <- sub("DTC$", "STDTC", var)
    if (candidate %in% actual_vars) {
      return(candidate)
    }
  }

  NULL
}

#' Generate Validation Report
#'
#' @param issues_df Data frame of issues
#' @param source_var_sections List of expected variables by domain
#' @return Character string (markdown formatted)
#' @noRd
generate_validation_report <- function(issues_df, source_var_sections) {
  lines <- character()

  lines <- c(lines, "Data Contract Validation Report")
  lines <- c(lines, "================================")
  lines <- c(lines, "")

  if (nrow(issues_df) == 0) {
    lines <- c(lines, "All domains validated successfully.")
    lines <- c(lines, "")
    lines <- c(lines, sprintf("Validated %d domain(s):", length(source_var_sections)))
    for (domain in names(source_var_sections)) {
      lines <- c(lines, sprintf("  \u2713 %s (%d variables)",
                               domain, length(source_var_sections[[domain]])))
    }
    lines <- c(lines, "")
    lines <- c(lines, "VERDICT: PASS")
    return(paste(lines, collapse = "\n"))
  }

  # Group issues by domain
  domains <- unique(issues_df$domain)

  for (domain in domains) {
    domain_issues <- issues_df[issues_df$domain == domain, ]

    lines <- c(lines, sprintf("DOMAIN: %s", domain))

    for (i in seq_len(nrow(domain_issues))) {
      issue <- domain_issues[i, ]

      symbol <- switch(issue$issue_type,
                      "missing" = "\u2717",  # ✗
                      "missing_file" = "\u2717",
                      "read_error" = "\u2717",
                      "missing_with_alternative" = "\u2713",  # ✓
                      "info" = "\u26A0",  # ⚠
                      "?")

      if (is.na(issue$variable)) {
        lines <- c(lines, sprintf("  %s %s", symbol, issue$message))
      } else {
        lines <- c(lines, sprintf("  %s %s: %s", symbol, issue$variable, issue$message))
      }
    }

    lines <- c(lines, "")
  }

  # Summary
  critical_count <- sum(issues_df$issue_type %in% c("missing", "missing_file", "read_error"))
  warning_count <- sum(issues_df$issue_type == "missing_with_alternative")
  info_count <- sum(issues_df$issue_type == "info")

  lines <- c(lines, "SUMMARY:")
  if (critical_count > 0) {
    lines <- c(lines, sprintf("  Critical issues: %d", critical_count))
  }
  if (warning_count > 0) {
    lines <- c(lines, sprintf("  Warnings: %d", warning_count))
  }
  if (info_count > 0) {
    lines <- c(lines, sprintf("  Informational: %d", info_count))
  }
  lines <- c(lines, "")

  verdict <- if (critical_count > 0) "FAIL" else "PASS"
  lines <- c(lines, sprintf("VERDICT: %s", verdict))

  if (verdict == "FAIL") {
    lines <- c(lines, "")
    lines <- c(lines, "ACTION REQUIRED: Resolve critical issues before proceeding with Wave 1.")
  }

  paste(lines, collapse = "\n")
}
