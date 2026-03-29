#' Extract Dataset Metadata
#'
#' Extracts variable-level metadata from a dataset including name, type,
#' length, format, and label. Works with datasets read from XPT files
#' using haven::read_xpt().
#'
#' @param dataset A data frame (typically from haven::read_xpt)
#'
#' @return A data frame with columns: Variable, Type, Length, Format, Label
#'
#' @export
extract_dataset_metadata <- function(dataset) {
  # --- Validate inputs ---
  if (!is.data.frame(dataset)) {
    stop("`dataset` must be a data frame.", call. = FALSE)
  }

  # --- Extract metadata for each variable ---
  var_names <- names(dataset)

  metadata <- data.frame(
    Variable = var_names,
    Type = character(length(var_names)),
    Length = integer(length(var_names)),
    Format = character(length(var_names)),
    Label = character(length(var_names)),
    stringsAsFactors = FALSE
  )

  for (i in seq_along(var_names)) {
    var <- dataset[[var_names[i]]]

    # Get type
    if (is.numeric(var)) {
      metadata$Type[i] <- "Num"
    } else if (is.character(var)) {
      metadata$Type[i] <- "Char"
    } else if (is.factor(var)) {
      metadata$Type[i] <- "Factor"
    } else if (inherits(var, "Date")) {
      metadata$Type[i] <- "Date"
    } else if (inherits(var, "POSIXct") || inherits(var, "POSIXlt")) {
      metadata$Type[i] <- "DateTime"
    } else {
      metadata$Type[i] <- class(var)[1]
    }

    # Get length
    if (is.character(var)) {
      # For character variables, use max string length
      metadata$Length[i] <- max(nchar(var, keepNA = FALSE), na.rm = TRUE)
      if (is.infinite(metadata$Length[i])) metadata$Length[i] <- 0
    } else {
      # For numeric/other types, use 8 as default
      metadata$Length[i] <- 8
    }

    # Get format
    format_attr <- attr(var, "format.sas")
    if (!is.null(format_attr)) {
      metadata$Format[i] <- format_attr
    } else {
      metadata$Format[i] <- ""
    }

    # Get label
    label_attr <- attr(var, "label")
    if (!is.null(label_attr)) {
      metadata$Label[i] <- label_attr
    } else {
      metadata$Label[i] <- ""
    }
  }

  return(metadata)
}
