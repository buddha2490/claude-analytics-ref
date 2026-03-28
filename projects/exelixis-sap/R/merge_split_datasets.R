#' Merge Split Dataset Checkpoints
#'
#' Reads checkpoint RDS files from multiple agents working on a split dataset,
#' merges them by USUBJID, validates consistency, and writes the final XPT.
#'
#' @param checkpoint_files Character vector of RDS file paths to merge
#' @param output_path Character, path for final XPT file (e.g., "data/adsl.xpt")
#' @param merge_keys Character vector, columns to merge on (default: c("USUBJID", "STUDYID"))
#'
#' @return List with elements:
#'   - `merged_data`: The final merged data frame
#'   - `validation_report`: List of validation checks and results
#'   - `output_path`: Path where XPT was written
#'
#' @examples
#' \dontrun{
#' checkpoint_files <- c(
#'   "output-data/adsl_part1.rds",
#'   "output-data/adsl_part2.rds",
#'   "output-data/adsl_part3.rds",
#'   "output-data/adsl_part4.rds"
#' )
#' result <- merge_split_datasets(checkpoint_files, "data/adsl.xpt")
#' }
#'
#' @export
merge_split_datasets <- function(checkpoint_files,
                                  output_path,
                                  merge_keys = c("USUBJID", "STUDYID")) {
  # --- Validate inputs --------------------------------------------------------
  if (!is.character(checkpoint_files) || length(checkpoint_files) < 2) {
    stop("`checkpoint_files` must be a character vector with at least 2 files.",
         call. = FALSE)
  }

  if (!is.character(output_path) || length(output_path) != 1) {
    stop("`output_path` must be a single character string.", call. = FALSE)
  }

  if (!is.character(merge_keys) || length(merge_keys) == 0) {
    stop("`merge_keys` must be a non-empty character vector.", call. = FALSE)
  }

  # Check all files exist
  missing_files <- checkpoint_files[!file.exists(checkpoint_files)]
  if (length(missing_files) > 0) {
    stop("Checkpoint files not found: ",
         paste(missing_files, collapse = ", "), call. = FALSE)
  }

  message("Merging ", length(checkpoint_files), " checkpoint files...")

  # --- Read checkpoint files --------------------------------------------------
  checkpoints <- lapply(checkpoint_files, function(file) {
    message("  Reading: ", basename(file))
    data <- readRDS(file)

    # Validate structure
    if (!is.data.frame(data)) {
      stop("Checkpoint file does not contain a data frame: ", file, call. = FALSE)
    }

    # Validate merge keys present
    missing_keys <- setdiff(merge_keys, names(data))
    if (length(missing_keys) > 0) {
      stop("Checkpoint missing merge keys (", paste(missing_keys, collapse = ", "),
           "): ", file, call. = FALSE)
    }

    return(data)
  })

  # --- Pre-merge validation ---------------------------------------------------
  validation_report <- list()

  # Check 1: All checkpoints have same subject set
  subject_sets <- lapply(checkpoints, function(df) sort(unique(df$USUBJID)))
  reference_subjects <- subject_sets[[1]]

  subject_consistency <- sapply(seq_along(subject_sets)[-1], function(i) {
    setequal(subject_sets[[i]], reference_subjects)
  })

  validation_report$subject_consistency <- list(
    check = "All checkpoints have identical USUBJID sets",
    passed = all(subject_consistency),
    details = if (all(subject_consistency)) {
      paste("All", length(checkpoints), "checkpoints have", length(reference_subjects), "subjects")
    } else {
      paste("Subject set mismatch detected between checkpoints")
    }
  )

  if (!validation_report$subject_consistency$passed) {
    stop("Subject sets differ across checkpoints. Cannot merge.", call. = FALSE)
  }

  # Check 2: No duplicate columns (except merge keys)
  all_columns <- unlist(lapply(checkpoints, names))
  # Keep duplicates but exclude merge keys
  all_columns_no_keys <- all_columns[!all_columns %in% merge_keys]
  duplicate_columns <- unique(all_columns_no_keys[duplicated(all_columns_no_keys)])

  validation_report$column_uniqueness <- list(
    check = "No duplicate column names (except merge keys)",
    passed = length(duplicate_columns) == 0,
    details = if (length(duplicate_columns) == 0) {
      "No duplicate columns found"
    } else {
      paste("Duplicate columns:", paste(duplicate_columns, collapse = ", "))
    }
  )

  if (!validation_report$column_uniqueness$passed) {
    stop("Duplicate columns detected across checkpoints: ",
         paste(duplicate_columns, collapse = ", "), call. = FALSE)
  }

  # --- Perform merge ----------------------------------------------------------
  message("Merging checkpoints...")
  merged_data <- checkpoints[[1]]

  for (i in seq_along(checkpoints)[-1]) {
    checkpoint <- checkpoints[[i]]

    # Columns to keep from this checkpoint (excluding merge keys already in merged_data)
    new_columns <- setdiff(names(checkpoint), merge_keys)

    merged_data <- merged_data %>%
      dplyr::left_join(
        checkpoint %>% dplyr::select(dplyr::all_of(c(merge_keys, new_columns))),
        by = merge_keys
      )

    message("  Merged checkpoint ", i, ": ", length(new_columns), " new columns")
  }

  # --- Post-merge validation --------------------------------------------------

  # Check 3: Row count unchanged
  expected_rows <- nrow(checkpoints[[1]])
  actual_rows <- nrow(merged_data)

  validation_report$row_count <- list(
    check = "Row count unchanged after merge",
    passed = actual_rows == expected_rows,
    details = paste0("Expected: ", expected_rows, ", Actual: ", actual_rows)
  )

  if (!validation_report$row_count$passed) {
    warning("Row count changed during merge. Expected ", expected_rows,
            ", got ", actual_rows, call. = FALSE)
  }

  # Check 4: No missing data introduced
  na_counts_before <- sum(sapply(checkpoints, function(df) sum(is.na(df))))
  na_counts_after <- sum(is.na(merged_data))

  validation_report$missing_data <- list(
    check = "No missing data introduced by join",
    passed = na_counts_after == na_counts_before,
    details = paste0("NAs before: ", na_counts_before, ", NAs after: ", na_counts_after)
  )

  if (!validation_report$missing_data$passed) {
    warning("Missing data counts changed during merge. Before: ", na_counts_before,
            ", After: ", na_counts_after, call. = FALSE)
  }

  # Check 5: Expected column count
  total_columns_expected <- sum(sapply(checkpoints, ncol)) -
    (length(checkpoints) - 1) * length(merge_keys)
  actual_columns <- ncol(merged_data)

  validation_report$column_count <- list(
    check = "Column count matches expected",
    passed = actual_columns == total_columns_expected,
    details = paste0("Expected: ", total_columns_expected, ", Actual: ", actual_columns)
  )

  if (!validation_report$column_count$passed) {
    warning("Column count mismatch. Expected ", total_columns_expected,
            ", got ", actual_columns, call. = FALSE)
  }

  # --- Write output -----------------------------------------------------------
  message("Writing merged dataset to: ", output_path)

  # Create output directory if needed
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("  Created output directory: ", output_dir)
  }

  # Write XPT
  haven::write_xpt(merged_data, output_path)

  message("Merge complete: ", nrow(merged_data), " rows × ",
          ncol(merged_data), " columns")

  # --- Return results ---------------------------------------------------------
  return(list(
    merged_data = merged_data,
    validation_report = validation_report,
    output_path = output_path
  ))
}


#' Print Validation Report
#'
#' Pretty-prints the validation report from merge_split_datasets.
#'
#' @param validation_report List, validation report from merge_split_datasets
#'
#' @export
print_validation_report <- function(validation_report) {
  if (!is.list(validation_report)) {
    stop("`validation_report` must be a list.", call. = FALSE)
  }

  message("\n=== Merge Validation Report ===\n")

  for (check_name in names(validation_report)) {
    check <- validation_report[[check_name]]
    status <- if (check$passed) "\u2713 PASS" else "\u2717 FAIL"
    message(status, " - ", check$check)
    message("     ", check$details, "\n")
  }

  all_passed <- all(sapply(validation_report, function(x) x$passed))
  if (all_passed) {
    message("All validation checks passed.\n")
  } else {
    message("Some validation checks failed. Review details above.\n")
  }

  return(invisible(all_passed))
}
