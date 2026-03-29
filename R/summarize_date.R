#' Summarize Date Variable
#'
#' Produces a summary for date variables (those ending in "DT"). Shows earliest
#' date, latest date, range in days, and missing count.
#'
#' @param x Character or Date vector to summarize (will be parsed as dates)
#' @param var_name Character string for the variable name (used in output)
#'
#' @return A data frame with one row containing date summary statistics
#'
#' @export
summarize_date <- function(x, var_name = "Variable") {
  # --- Validate inputs ---
  if (!is.character(var_name) || length(var_name) != 1) {
    stop("`var_name` must be a single character string.", call. = FALSE)
  }

  # --- Parse dates if character ---
  if (is.character(x)) {
    x_date <- lubridate::ymd(x, quiet = TRUE)
  } else if (lubridate::is.Date(x)) {
    x_date <- x
  } else {
    stop("`x` must be a character or Date vector.", call. = FALSE)
  }

  # --- Calculate statistics ---
  x_valid <- x_date[!is.na(x_date)]
  n_valid <- length(x_valid)
  n_missing <- sum(is.na(x_date))

  # Handle case where all values are missing
  if (n_valid == 0) {
    return(tibble::tibble(
      Variable = var_name,
      `Earliest Date` = NA_character_,
      `Latest Date` = NA_character_,
      `Range (days)` = NA_integer_,
      `N Non-Missing` = 0L,
      Missing = n_missing
    ))
  }

  # --- Build summary table ---
  earliest <- min(x_valid, na.rm = TRUE)
  latest <- max(x_valid, na.rm = TRUE)
  range_days <- as.integer(latest - earliest)

  tibble::tibble(
    Variable = var_name,
    `Earliest Date` = as.character(earliest),
    `Latest Date` = as.character(latest),
    `Range (days)` = range_days,
    `N Non-Missing` = n_valid,
    Missing = n_missing
  )
}
