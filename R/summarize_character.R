#' Summarize Character Variable
#'
#' Produces a frequency table for a character variable with counts and
#' percentages. Includes missing (NA) values.
#'
#' @param x Character vector to summarize
#' @param var_name Character string for the variable name (not used in output,
#'   kept for consistency with other summary functions)
#'
#' @return A data frame with columns: Value, N, (%). Ordered by descending
#'   frequency.
#'
#' @export
summarize_character <- function(x, var_name = "Variable") {
  # --- Validate inputs ---
  if (!is.character(x) && !is.factor(x)) {
    stop("`x` must be a character or factor vector.", call. = FALSE)
  }

  if (!is.character(var_name) || length(var_name) != 1) {
    stop("`var_name` must be a single character string.", call. = FALSE)
  }

  # --- Convert factor to character for consistent handling ---
  if (is.factor(x)) {
    x <- as.character(x)
  }

  # --- Build frequency table ---
  # Convert NA to explicit string for counting
  x_display <- ifelse(is.na(x), "(Missing)", x)

  freq_table <- tibble::tibble(Value = x_display) %>%
    dplyr::count(Value, name = "N") %>%
    dplyr::mutate(
      Percent = N / sum(N) * 100,
      `(%)` = sprintf("(%.1f%%)", Percent)
    ) %>%
    dplyr::arrange(dplyr::desc(N)) %>%
    dplyr::select(Value, N, `(%)`)

  freq_table
}
