#' Summarize Variable
#'
#' Wrapper function that routes to the appropriate summary function based on
#' variable type and naming convention. Variables ending in "DT" are treated
#' as dates, numeric/integer variables use numeric summary, and character/factor
#' variables use frequency tables.
#'
#' @param x Vector to summarize
#' @param var_name Character string for the variable name (used in output)
#'
#' @return A data frame with summary statistics appropriate for the variable type
#'
#' @export
summarize_variable <- function(x, var_name = "Variable") {
  # --- Validate inputs ---
  if (!is.character(var_name) || length(var_name) != 1) {
    stop("`var_name` must be a single character string.", call. = FALSE)
  }

  # --- Source required functions ---
  # These should be available if package is loaded, but source them for safety
  if (!exists("summarize_numeric")) {
    source(file.path(
      dirname(dirname(sys.frame(1)$ofile)),
      "R/summarize_numeric.R"
    ))
  }
  if (!exists("summarize_character")) {
    source(file.path(
      dirname(dirname(sys.frame(1)$ofile)),
      "R/summarize_character.R"
    ))
  }
  if (!exists("summarize_date")) {
    source(file.path(
      dirname(dirname(sys.frame(1)$ofile)),
      "R/summarize_date.R"
    ))
  }

  # --- Route based on variable name and type ---
  # Check if variable name ends with "DT" AND is character/Date (not numeric)
  # Numeric dates (SAS dates) should be treated as numeric
  if (stringr::str_ends(var_name, "DT") && (is.character(x) || lubridate::is.Date(x))) {
    return(summarize_date(x, var_name))
  }

  # Route based on variable type
  if (is.numeric(x) || is.integer(x)) {
    return(summarize_numeric(x, var_name))
  } else if (is.character(x) || is.factor(x)) {
    return(summarize_character(x, var_name))
  } else if (lubridate::is.Date(x)) {
    return(summarize_date(x, var_name))
  } else {
    stop(
      "Cannot summarize variable of type: ", class(x)[1],
      ". Supported types: numeric, integer, character, factor, Date.",
      call. = FALSE
    )
  }
}
