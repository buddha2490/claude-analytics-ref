#' Create Variable Summary Table
#'
#' Creates a properly formatted flextable with descriptive statistics
#' for a single variable. Character variables get frequencies N (%),
#' continuous variables get Mean (SD).
#'
#' @param data Data frame containing the variable
#' @param var_name Character. Name of the variable to summarize
#' @param dataset_name Character. Name of the source dataset (e.g., "DM", "ADSL")
#' @return A flextable object ready for officer rendering
#'
#' @export
create_variable_summary_table <- function(data, var_name, dataset_name) {

  # Load flextable
  if (!requireNamespace("flextable", quietly = TRUE)) {
    stop("Package 'flextable' is required but not installed.", call. = FALSE)
  }

  # --- Validate inputs --------------------------------------------------------

  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }

  if (!var_name %in% names(data)) {
    stop("Variable `", var_name, "` not found in dataset.", call. = FALSE)
  }

  if (nrow(data) == 0) {
    stop("`data` must contain at least one row.", call. = FALSE)
  }

  # --- Extract variable and determine type ------------------------------------

  var_data <- data[[var_name]]
  var_label <- attr(var_data, "label")
  if (is.null(var_label) || var_label == "") {
    var_label <- var_name
  }

  is_character <- is.character(var_data) || is.factor(var_data)

  # --- Build summary data frame -----------------------------------------------

  if (is_character) {
    # Character/Factor: frequencies N (%)
    summary_df <- data %>%
      dplyr::count(.data[[var_name]], name = "N") %>%
      dplyr::mutate(
        Percent = round(N / sum(N) * 100, 1),
        `N (%)` = paste0(N, " (", Percent, "%)")
      ) %>%
      dplyr::select(Value = 1, `N (%)`)

    # Handle missing values
    if (any(is.na(data[[var_name]]))) {
      n_missing <- sum(is.na(data[[var_name]]))
      pct_missing <- round(n_missing / nrow(data) * 100, 1)
      missing_row <- tibble::tibble(
        Value = "[Missing]",
        `N (%)` = paste0(n_missing, " (", pct_missing, "%)")
      )
      summary_df <- dplyr::bind_rows(summary_df, missing_row)
    }

  } else {
    # Numeric: Mean (SD)
    var_clean <- var_data[!is.na(var_data)]

    if (length(var_clean) == 0) {
      summary_df <- tibble::tibble(
        Statistic = "Mean (SD)",
        Value = "All missing"
      )
    } else {
      mean_val <- mean(var_clean, na.rm = TRUE)
      sd_val <- sd(var_clean, na.rm = TRUE)
      n_val <- length(var_clean)
      n_missing <- sum(is.na(var_data))

      summary_df <- tibble::tibble(
        Statistic = c("N", "Mean (SD)", "Median", "Range", "Missing"),
        Value = c(
          as.character(n_val),
          sprintf("%.2f (%.2f)", mean_val, sd_val),
          sprintf("%.2f", median(var_clean, na.rm = TRUE)),
          sprintf("%.2f - %.2f", min(var_clean, na.rm = TRUE),
                  max(var_clean, na.rm = TRUE)),
          as.character(n_missing)
        )
      )
    }
  }

  # --- Create flextable -------------------------------------------------------

  ft <- flextable::flextable(summary_df)

  # Apply formatting based on variable type
  if (is_character) {
    # Character variable: 2 columns (Value, N (%))
    ft <- ft %>%
      flextable::bold(part = "header") %>%
      flextable::align(align = "center", part = "header") %>%
      flextable::align(j = 1, align = "left", part = "body") %>%
      flextable::align(j = 2, align = "center", part = "body") %>%
      flextable::border_outer(border = officer::fp_border(width = 2)) %>%
      flextable::border_inner_h(border = officer::fp_border(width = 1)) %>%
      flextable::width(j = 1, width = 4.5) %>%
      flextable::width(j = 2, width = 2.0)
  } else {
    # Numeric variable: 2 columns (Statistic, Value)
    ft <- ft %>%
      flextable::bold(part = "header") %>%
      flextable::align(align = "center", part = "header") %>%
      flextable::align(j = 1, align = "left", part = "body") %>%
      flextable::align(j = 2, align = "center", part = "body") %>%
      flextable::border_outer(border = officer::fp_border(width = 2)) %>%
      flextable::border_inner_h(border = officer::fp_border(width = 1)) %>%
      flextable::width(j = 1, width = 3.5) %>%
      flextable::width(j = 2, width = 3.0)
  }

  # Add title annotation as attribute for later use
  attr(ft, "variable_name") <- var_name
  attr(ft, "variable_label") <- var_label
  attr(ft, "dataset_name") <- dataset_name

  return(ft)
}


#' Create Dataset Contents Table
#'
#' Creates a contents table showing variable metadata (name, type, length,
#' format, label) from a data frame.
#'
#' @param data Data frame with variable attributes
#' @param dataset_name Character. Name of the dataset
#' @return A flextable object with dataset contents
#'
#' @export
create_contents_table <- function(data, dataset_name) {

  if (!requireNamespace("flextable", quietly = TRUE)) {
    stop("Package 'flextable' is required but not installed.", call. = FALSE)
  }

  # Extract metadata for each variable
  var_names <- names(data)
  contents_list <- list()

  for (var_name in var_names) {
    var_data <- data[[var_name]]

    # Get type
    var_type <- if (is.numeric(var_data)) {
      "Num"
    } else if (is.character(var_data)) {
      "Char"
    } else if (is.factor(var_data)) {
      "Char"
    } else {
      class(var_data)[1]
    }

    # Get length
    var_length <- attr(var_data, "width")
    if (is.null(var_length)) {
      if (is.character(var_data)) {
        var_length <- max(nchar(as.character(var_data)), na.rm = TRUE)
        if (!is.finite(var_length)) var_length <- 200
      } else {
        var_length <- 8
      }
    }

    # Get format
    var_format <- attr(var_data, "format.sas")
    if (is.null(var_format) || var_format == "") {
      var_format <- ""
    }

    # Get label
    var_label <- attr(var_data, "label")
    if (is.null(var_label) || var_label == "") {
      var_label <- ""
    }

    contents_list[[var_name]] <- data.frame(
      Variable = var_name,
      Type = var_type,
      Length = as.character(var_length),
      Format = var_format,
      Label = var_label,
      stringsAsFactors = FALSE
    )
  }

  # Combine into single data frame
  contents_df <- dplyr::bind_rows(contents_list)

  # Create flextable
  ft <- flextable::flextable(contents_df) %>%
    flextable::bold(part = "header") %>%
    flextable::align(align = "center", part = "header") %>%
    flextable::align(j = 1:5, align = "left", part = "body") %>%
    flextable::valign(valign = "top", part = "all") %>%
    flextable::border_outer(border = officer::fp_border(width = 2)) %>%
    flextable::border_inner_h(border = officer::fp_border(width = 1), part = "header") %>%
    flextable::border_inner_h(border = officer::fp_border(width = 1), part = "body") %>%
    flextable::width(j = 1, width = 1.2) %>%
    flextable::width(j = 2, width = 0.6) %>%
    flextable::width(j = 3, width = 0.6) %>%
    flextable::width(j = 4, width = 1.2) %>%
    flextable::width(j = 5, width = 3.4)

  return(ft)
}


#' Create Dataset Variable Summary Report
#'
#' Creates a comprehensive Word document report with summary tables for all
#' variables in a dataset. Starts with a contents table, then includes
#' individual variable summaries with page breaks between them. Each variable
#' gets its own title and footnote.
#'
#' @param data Data frame to summarize
#' @param dataset_name Character. Name of the dataset (e.g., "DM", "ADSL")
#' @param output_dir Character. Directory for output file. Defaults to
#'   "output-reports"
#' @param author Character. Report author name. Defaults to system user.
#'
#' @return Invisibly returns the output file path
#'
#' @export
create_dataset_summary_report <- function(data,
                                          dataset_name,
                                          output_dir = "output-reports",
                                          author = Sys.info()["user"]) {

  # Load required packages
  if (!requireNamespace("officer", quietly = TRUE)) {
    stop("Package 'officer' is required but not installed.", call. = FALSE)
  }
  if (!requireNamespace("flextable", quietly = TRUE)) {
    stop("Package 'flextable' is required but not installed.", call. = FALSE)
  }
  if (!requireNamespace("glue", quietly = TRUE)) {
    stop("Package 'glue' is required but not installed.", call. = FALSE)
  }

  # --- Validate inputs --------------------------------------------------------

  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }

  if (nrow(data) == 0) {
    stop("`data` must contain at least one row.", call. = FALSE)
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("Created output directory: ", output_dir)
  }

  # --- Get all variable names -------------------------------------------------

  var_names <- names(data)
  message("Generating summary report for ", dataset_name,
          " (", length(var_names), " variables)")

  # --- Create contents table --------------------------------------------------

  message("  Creating dataset contents table...")
  contents_table <- create_contents_table(data, dataset_name)

  # --- Create individual variable tables --------------------------------------

  table_list <- list()

  for (var_name in var_names) {
    tryCatch({
      ft <- create_variable_summary_table(data, var_name, dataset_name)
      table_list[[var_name]] <- ft
      message("  Created summary for: ", var_name)
    }, error = function(e) {
      warning("Failed to create summary for ", var_name, ": ",
              e$message, call. = FALSE)
    })
  }

  if (length(table_list) == 0) {
    stop("No variable summaries were successfully created.", call. = FALSE)
  }

  # --- Create Word document with officer --------------------------------------

  doc <- officer::read_docx()

  # Add main document title
  doc <- doc %>%
    officer::body_add_par(
      glue::glue("Data Quality Report: {dataset_name}"),
      style = "heading 1"
    ) %>%
    officer::body_add_par(
      glue::glue("Dataset: {dataset_name} | Variables: {length(var_names)} | Observations: {nrow(data)}"),
      style = "Normal"
    ) %>%
    officer::body_add_par(" ", style = "Normal")

  # Add contents table
  doc <- doc %>%
    officer::body_add_par("Dataset Contents", style = "heading 2") %>%
    flextable::body_add_flextable(contents_table) %>%
    officer::body_add_break()

  # --- Add each variable summary with page breaks -----------------------------

  for (i in seq_along(table_list)) {
    ft <- table_list[[i]]
    var_name <- attr(ft, "variable_name")
    var_label <- attr(ft, "variable_label")

    # Determine variable type from data
    var_data <- data[[var_name]]
    var_type <- if (is.numeric(var_data)) {
      "Numeric"
    } else if (is.character(var_data) || is.factor(var_data)) {
      "Character"
    } else {
      class(var_data)[1]
    }

    # Add variable title
    doc <- doc %>%
      officer::body_add_par(
        glue::glue("Variable: {var_name}"),
        style = "heading 2"
      ) %>%
      officer::body_add_par(
        glue::glue("Label: {var_label}"),
        style = "Normal"
      ) %>%
      officer::body_add_par(" ", style = "Normal")

    # Add the summary table
    doc <- flextable::body_add_flextable(doc, ft)

    # Add footnote
    doc <- doc %>%
      officer::body_add_par(" ", style = "Normal") %>%
      officer::body_add_par(
        glue::glue("Type: {var_type} | Dataset: {dataset_name} | Generated: {Sys.Date()} by {author}"),
        style = "Normal"
      )

    # Add page break (except after last variable)
    if (i < length(table_list)) {
      doc <- officer::body_add_break(doc)
    }
  }

  # --- Write output file ------------------------------------------------------

  output_file <- file.path(
    output_dir,
    glue::glue("{dataset_name}_variable_summary_{Sys.Date()}.docx")
  )

  print(doc, target = output_file)

  message("\nReport written to: ", output_file)

  invisible(output_file)
}
