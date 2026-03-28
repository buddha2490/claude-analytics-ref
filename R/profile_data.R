#' Profile SDTM Domain Data
#'
#' Generates frequency tables and cross-tabulations for categorical variables
#' in an SDTM domain. Writes markdown output for reference during derivation.
#'
#' @param domain Character. SDTM domain code (e.g., "LB", "MH", "AE").
#' @param variables Character vector. Variables to profile. If NULL, profiles
#'   all categorical variables (character/factor + numeric with ≤20 unique values).
#' @param data_path Character. Path to directory containing SDTM XPT files.
#' @param output_path Character. Path to directory for markdown output.
#' @param top_n Integer. Maximum number of unique values to display per variable.
#'   Default: 50.
#'
#' @return List with components:
#'   - domain: Domain code
#'   - n_records: Total records
#'   - n_subjects: Unique subjects
#'   - variables_profiled: Character vector of profiled variables
#'   - output_file: Path to generated markdown file
#'   - warnings: Character vector of any warnings or unexpected patterns
#'
#' @examples
#' \dontrun{
#' profile_data(
#'   domain = "LB",
#'   variables = c("LBTESTCD", "LBSTRESC"),
#'   data_path = "projects/exelixis-sap/data",
#'   output_path = "projects/exelixis-sap/data-profiles"
#' )
#' }
#'
#' @export
profile_data <- function(domain,
                        variables = NULL,
                        data_path,
                        output_path,
                        top_n = 50) {

  # --- Validate inputs ---
  if (!is.character(domain) || length(domain) != 1) {
    stop("`domain` must be a single character string.", call. = FALSE)
  }

  if (!is.null(variables) && !is.character(variables)) {
    stop("`variables` must be a character vector or NULL.", call. = FALSE)
  }

  if (!is.character(data_path) || length(data_path) != 1) {
    stop("`data_path` must be a single character string.", call. = FALSE)
  }

  if (!dir.exists(data_path)) {
    stop("Data path does not exist: ", data_path, call. = FALSE)
  }

  if (!is.character(output_path) || length(output_path) != 1) {
    stop("`output_path` must be a single character string.", call. = FALSE)
  }

  if (!is.numeric(top_n) || top_n < 1) {
    stop("`top_n` must be a positive integer.", call. = FALSE)
  }

  # --- Load required packages ---
  suppressPackageStartupMessages({
    library(dplyr)
    library(haven)
    library(stringr)
    library(purrr)
  })

  # --- Read SDTM XPT file ---
  xpt_file <- file.path(data_path, paste0(tolower(domain), ".xpt"))

  if (!file.exists(xpt_file)) {
    stop("XPT file not found: ", xpt_file, call. = FALSE)
  }

  message("Reading: ", xpt_file)
  data <- haven::read_xpt(xpt_file)

  if (nrow(data) == 0) {
    stop("Domain ", domain, " contains zero records.", call. = FALSE)
  }

  # --- Identify categorical variables ---
  if (is.null(variables)) {
    # Auto-detect: character/factor + numeric with ≤20 unique values
    categorical_vars <- names(data)[sapply(data, function(x) {
      if (is.character(x) || is.factor(x)) {
        return(TRUE)
      }
      if (is.numeric(x)) {
        return(length(unique(x[!is.na(x)])) <= 20)
      }
      FALSE
    })]
    variables <- categorical_vars
  } else {
    # Validate user-specified variables
    missing_vars <- setdiff(variables, names(data))
    if (length(missing_vars) > 0) {
      stop("Variables not found in ", domain, ": ",
           paste(missing_vars, collapse = ", "), call. = FALSE)
    }
  }

  if (length(variables) == 0) {
    stop("No categorical variables found to profile in ", domain, call. = FALSE)
  }

  # --- Generate profile ---
  n_records <- nrow(data)
  n_subjects <- length(unique(data$USUBJID))

  # Create output directory
  if (!dir.exists(output_path)) {
    dir.create(output_path, recursive = TRUE)
    message("Created directory: ", output_path)
  }

  output_file <- file.path(output_path, paste0(domain, ".md"))

  # Initialize markdown output
  md_lines <- c(
    paste0("# Data Profile: ", domain),
    paste0("**Generated:** ", Sys.Date()),
    paste0("**Records:** ", format(n_records, big.mark = ",")),
    paste0("**Subjects:** ", format(n_subjects, big.mark = ",")),
    "",
    "---",
    ""
  )

  warnings_list <- character()

  # --- Profile each variable ---
  for (var in variables) {
    message("Profiling: ", var)

    var_label <- attr(data[[var]], "label")
    if (is.null(var_label)) var_label <- ""

    md_lines <- c(
      md_lines,
      paste0("## ", var),
      if (nzchar(var_label)) paste0("**Label:** ", var_label) else NULL,
      ""
    )

    # Frequency table
    freq_table <- data %>%
      dplyr::count(.data[[var]], name = "n") %>%
      dplyr::mutate(
        percent = .data$n / n_records * 100,
        percent_fmt = sprintf("%.1f%%", .data$percent)
      ) %>%
      dplyr::arrange(dplyr::desc(.data$n))

    n_unique <- nrow(freq_table)
    n_missing <- sum(is.na(data[[var]]))

    # Add header info
    md_lines <- c(
      md_lines,
      paste0("**Unique values:** ", n_unique),
      if (n_missing > 0) {
        paste0("**Missing values:** ", n_missing,
               " (", sprintf("%.1f%%", n_missing / n_records * 100), ")")
      } else NULL,
      ""
    )

    # Warning for high cardinality
    if (n_unique > top_n) {
      warning_msg <- paste0(
        var, " has ", n_unique, " unique values (showing top ", top_n, ")"
      )
      warnings_list <- c(warnings_list, warning_msg)
      md_lines <- c(
        md_lines,
        paste0("⚠ **High cardinality:** ", n_unique,
               " unique values (showing top ", top_n, ")"),
        ""
      )
    }

    # Truncate if needed
    freq_table_display <- freq_table %>%
      dplyr::slice_head(n = top_n)

    # Format table
    md_lines <- c(
      md_lines,
      "| Value | Count | Percent |",
      "|-------|-------|---------|"
    )

    for (i in seq_len(nrow(freq_table_display))) {
      value <- freq_table_display[[var]][i]
      if (is.na(value)) value <- "(Missing)"
      count <- format(freq_table_display$n[i], big.mark = ",")
      percent <- freq_table_display$percent_fmt[i]

      md_lines <- c(
        md_lines,
        paste0("| ", value, " | ", count, " | ", percent, " |")
      )
    }

    md_lines <- c(md_lines, "", "---", "")
  }

  # --- Generate cross-tabulations for related variables ---
  # Identify related variable pairs (same prefix or common patterns)
  crosstab_pairs <- identify_crosstab_pairs(variables)

  if (length(crosstab_pairs) > 0) {
    md_lines <- c(
      md_lines,
      "# Cross-Tabulations",
      ""
    )

    for (pair in crosstab_pairs) {
      var1 <- pair[1]
      var2 <- pair[2]

      message("Cross-tabulating: ", var1, " × ", var2)

      md_lines <- c(
        md_lines,
        paste0("## ", var1, " × ", var2),
        ""
      )

      # Generate cross-tab
      crosstab <- data %>%
        dplyr::count(.data[[var1]], .data[[var2]], name = "n") %>%
        dplyr::arrange(dplyr::desc(.data$n)) %>%
        dplyr::slice_head(n = 20)  # Limit to top 20 combinations

      md_lines <- c(
        md_lines,
        paste0("| ", var1, " | ", var2, " | Count |"),
        "|-------|-------|-------|"
      )

      for (i in seq_len(nrow(crosstab))) {
        val1 <- crosstab[[var1]][i]
        val2 <- crosstab[[var2]][i]
        if (is.na(val1)) val1 <- "(Missing)"
        if (is.na(val2)) val2 <- "(Missing)"
        count <- format(crosstab$n[i], big.mark = ",")

        md_lines <- c(
          md_lines,
          paste0("| ", val1, " | ", val2, " | ", count, " |")
        )
      }

      md_lines <- c(md_lines, "", "---", "")
    }
  }

  # --- Write output ---
  writeLines(md_lines, output_file)
  message("Profile written to: ", output_file)

  # --- Return summary ---
  list(
    domain = domain,
    n_records = n_records,
    n_subjects = n_subjects,
    variables_profiled = variables,
    output_file = output_file,
    warnings = if (length(warnings_list) > 0) warnings_list else NULL
  )
}


#' Identify Related Variable Pairs for Cross-Tabulation
#'
#' Identifies pairs of variables that are likely related based on naming
#' patterns (e.g., LBTESTCD + LBSTRESC, MHCAT + MHTERM).
#'
#' @param variables Character vector of variable names
#'
#' @return List of character vectors, each containing a pair of variable names
#'
#' @keywords internal
identify_crosstab_pairs <- function(variables) {
  pairs <- list()

  # Common SDTM patterns
  patterns <- list(
    c("TESTCD", "STRESC"),  # Test code + result
    c("TESTCD", "ORRES"),   # Test code + original result
    c("CAT", "TERM"),       # Category + term
    c("CAT", "DECOD"),      # Category + decoded term
    c("TRT", "DOSE"),       # Treatment + dose
    c("DOSE", "DOSU")       # Dose + dose unit
  )

  for (pattern in patterns) {
    # Find variables containing each pattern element
    vars_with_pattern1 <- grep(pattern[1], variables, value = TRUE)
    vars_with_pattern2 <- grep(pattern[2], variables, value = TRUE)

    if (length(vars_with_pattern1) > 0 && length(vars_with_pattern2) > 0) {
      # Match by domain prefix (first 2 chars)
      for (v1 in vars_with_pattern1) {
        prefix1 <- substr(v1, 1, 2)
        for (v2 in vars_with_pattern2) {
          prefix2 <- substr(v2, 1, 2)
          if (prefix1 == prefix2) {
            pairs <- c(pairs, list(c(v1, v2)))
          }
        }
      }
    }
  }

  # Remove duplicates
  unique(pairs)
}
