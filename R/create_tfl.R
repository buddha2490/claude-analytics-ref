#' Create a Regulatory-Ready TFL Table
#'
#' @description
#' Generates a formatted Table, Figure, or Listing (TFL) suitable for
#' regulatory submission. Accepts a display-ready analysis results dataset
#' (ARDS) and produces an RTF file with multi-line titles, column headers,
#' formatted table body, and multi-line footnotes.
#'
#' The ARDS should be a data frame already shaped for display — one row per
#' table row, one column per table column. The function handles all formatting,
#' headers, footers, and RTF document assembly.
#'
#' @param ards A data frame containing the display-ready table data. Column
#'   names are used as default headers unless overridden by \code{column_headers}.
#' @param titles Character vector. Each element becomes one centered title line
#'   at the top of the page. At least one title is required.
#' @param footnotes Character vector. Each element becomes one left-aligned
#'   footnote line below the table. Default is NULL (no footnotes).
#' @param output_file Character string. File path for RTF output (must end
#'   in .rtf). The output directory is created automatically if it does not exist.
#' @param column_headers Optional named character vector mapping column names to
#'   display labels, e.g., \code{c("trt01a" = "Treatment Group")}. Columns not
#'   listed are auto-converted from snake_case to Title Case.
#' @param page_orientation Character. Either "landscape" (default) or "portrait".
#' @param font Character. Font family for the table body. Default is "Courier New",
#'   which is standard for regulatory submissions.
#' @param font_size Numeric. Font size in points for the table body. Default is 9.
#' @param title_font_size Numeric. Font size in points for titles. Default is 10.
#'
#' @return Invisibly returns the output file path. Called for its side effect
#'   of writing an RTF file.
#'
#' @examples
#' library(tibble)
#'
#' # --- Build a display-ready ARDS ---
#' ards <- tibble(
#'   trt01a   = c("Placebo", "Drug 10mg", "Drug 20mg"),
#'   n        = c("86", "88", "85"),
#'   mean_sd  = c("12.3 (4.5)", "15.1 (3.8)", "18.7 (4.1)"),
#'   median   = c("12.0", "15.0", "19.0"),
#'   p_value  = c("", "0.023", "<0.001")
#' )
#'
#' # --- Generate the TFL ---
#' create_tfl(
#'   ards = ards,
#'   titles = c(
#'     "Table 14.1.1",
#'     "Summary of Primary Efficacy Endpoint",
#'     "Intent-to-Treat Population"
#'   ),
#'   footnotes = c(
#'     "SD = Standard Deviation.",
#'     "P-values from ANCOVA model adjusted for baseline.",
#'     "Program: t_14_1_1.R | Output: t_14_1_1.rtf"
#'   ),
#'   column_headers = c(
#'     "trt01a"  = "Treatment",
#'     "n"       = "N",
#'     "mean_sd" = "Mean (SD)",
#'     "median"  = "Median",
#'     "p_value" = "P-value"
#'   ),
#'   output_file = "output/t_14_1_1.rtf"
#' )
#'
#' @export
create_tfl <- function(ards,
                       titles,
                       footnotes = NULL,
                       output_file,
                       column_headers = NULL,
                       page_orientation = "landscape",
                       font = "Courier New",
                       font_size = 9,
                       title_font_size = 10) {

  # --- Load required packages -------------------------------------------------
  # huxtable and pharmaRTF share function names (align, bold, font_size, etc.)
  # so we must use package::function() notation throughout this function
  library(huxtable)
  library(pharmaRTF)

  # --- Validate inputs --------------------------------------------------------

  if (!is.data.frame(ards)) {
    stop("`ards` must be a data frame.", call. = FALSE)
  }

  if (nrow(ards) == 0) {
    stop("`ards` must contain at least one row.", call. = FALSE)
  }

  if (!is.character(titles) || length(titles) == 0) {
    stop("`titles` must be a character vector with at least one element.",
         call. = FALSE)
  }

  if (!is.character(output_file) || !grepl("\\.rtf$", output_file, ignore.case = TRUE)) {
    stop("`output_file` must be a character string ending in .rtf.", call. = FALSE)
  }

  if (!page_orientation %in% c("landscape", "portrait")) {
    stop('`page_orientation` must be "landscape" or "portrait".', call. = FALSE)
  }

  # --- Resolve column headers -------------------------------------------------
  # Auto-convert snake_case column names to Title Case for any column not
  # explicitly mapped in column_headers
  if (is.null(column_headers)) {
    display_names <- gsub("_", " ", names(ards))
    display_names <- tools::toTitleCase(display_names)
    column_headers <- setNames(display_names, names(ards))
  } else {
    missing_cols <- setdiff(names(ards), names(column_headers))
    if (length(missing_cols) > 0) {
      auto_names <- tools::toTitleCase(gsub("_", " ", missing_cols))
      column_headers <- c(column_headers, setNames(auto_names, missing_cols))
    }
  }

  # --- Build huxtable ---------------------------------------------------------
  # Convert all columns to character to ensure consistent formatting
  ards_char <- as.data.frame(lapply(ards, as.character), stringsAsFactors = FALSE)

  # Create the huxtable without automatic column names
  ht <- huxtable::as_hux(ards_char, add_colnames = FALSE)

  # Insert the formatted header row at the top
  header_values <- unname(column_headers[names(ards)])
  ht <- huxtable::insert_row(ht, header_values, after = 0)

  # --- Format the table -------------------------------------------------------

  # Set font and size for the entire table
  huxtable::font(ht) <- font
  huxtable::font_size(ht) <- font_size

  # Bold the header row
  huxtable::bold(ht)[1, ] <- TRUE

  # Borders: top of header, bottom of header, bottom of table
  huxtable::top_border(ht)[1, ] <- 0.5
  huxtable::bottom_border(ht)[1, ] <- 0.5
  huxtable::bottom_border(ht)[nrow(ht), ] <- 0.5

  # Left-align all content (standard for regulatory tables)
  huxtable::align(ht) <- "left"

  # Set table to full page width with evenly distributed columns
  huxtable::width(ht) <- 1
  huxtable::col_width(ht) <- rep(1 / ncol(ht), ncol(ht))

  # Remove internal cell padding for a tighter regulatory look
  huxtable::left_padding(ht) <- 2
  huxtable::right_padding(ht) <- 2
  huxtable::top_padding(ht) <- 1
  huxtable::bottom_padding(ht) <- 1

  # --- Assemble the RTF document ----------------------------------------------

  # Create the pharmaRTF document wrapper around the huxtable
  doc <- pharmaRTF::rtf_doc(ht)

  # Set page orientation
  doc <- pharmaRTF::set_orientation(doc, page_orientation)

  # Add each title as a separate centered, bold header line
  for (ttl in titles) {
    doc <- pharmaRTF::add_titles(
      doc,
      pharmaRTF::hf_line(ttl, align = "center", bold = TRUE,
                         font_size = title_font_size)
    )
  }

  # Add each footnote as a separate left-aligned footer line
  if (!is.null(footnotes) && length(footnotes) > 0) {
    for (fn in footnotes) {
      doc <- pharmaRTF::add_footnotes(
        doc,
        pharmaRTF::hf_line(fn, align = "left", font_size = font_size)
      )
    }
  }

  # --- Write RTF output -------------------------------------------------------

  # Create the output directory if it does not exist
  output_dir <- dirname(output_file)
  if (output_dir != "." && !dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Write the RTF file
  pharmaRTF::write_rtf(doc, file = output_file)

  message("TFL written to: ", output_file)

  return(invisible(output_file))
}
