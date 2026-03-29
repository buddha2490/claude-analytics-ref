#' Summarize Numeric Variable
#'
#' Produces summary statistics for a numeric variable: N, mean, SD, median,
#' range, and missing count.
#'
#' @param x Numeric vector to summarize
#' @param var_name Character string for the variable name (used in output)
#'
#' @return A data frame with one row containing summary statistics
#'
#' @export
summarize_numeric <- function(x, var_name = "Variable") {
  # --- Validate inputs ---
  if (!is.numeric(x) && !is.integer(x)) {
    stop("`x` must be a numeric or integer vector.", call. = FALSE)
  }

  if (!is.character(var_name) || length(var_name) != 1) {
    stop("`var_name` must be a single character string.", call. = FALSE)
  }

  # --- Calculate statistics ---
  x_valid <- x[!is.na(x)]
  n_valid <- length(x_valid)
  n_missing <- sum(is.na(x))

  # Handle case where all values are missing
  if (n_valid == 0) {
    return(tibble::tibble(
      Variable = var_name,
      N = 0L,
      Mean = NA_real_,
      SD = NA_real_,
      Median = NA_real_,
      Min = NA_real_,
      Max = NA_real_,
      Missing = n_missing
    ))
  }

  # --- Build summary table ---
  tibble::tibble(
    Variable = var_name,
    N = n_valid,
    Mean = mean(x_valid, na.rm = TRUE),
    SD = sd(x_valid, na.rm = TRUE),
    Median = median(x_valid, na.rm = TRUE),
    Min = min(x_valid, na.rm = TRUE),
    Max = max(x_valid, na.rm = TRUE),
    Missing = n_missing
  )
}
