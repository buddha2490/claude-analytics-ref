# Manage Open Questions
#
# Functions for managing the open questions tracking system (YAML format).
# Supports adding questions, resolving questions, listing questions, and
# checking for orphaned REVISIT comments in code.

library(yaml)
library(dplyr)
library(stringr)
library(tibble)
library(purrr)

# --- Add Question -----------------------------------------------------------

#' Add a new question to the open questions YAML
#'
#' @param yaml_path Path to open-questions.yaml file
#' @param id Question ID (e.g., "W7", "B1", "R9")
#' @param text The question text
#' @param rationale Why this question matters
#' @param affected_code List of affected code locations (file, lines, marker)
#' @param severity One of: "info", "warning", "blocking"
#' @param flagged_by Agent or user who raised the question
#' @param flagged_date Date flagged (YYYY-MM-DD)
#'
#' @return Invisible TRUE on success
#' @export
add_question <- function(yaml_path,
                         id,
                         text,
                         rationale,
                         affected_code = list(),
                         severity = "info",
                         flagged_by = "user",
                         flagged_date = Sys.Date()) {
  # --- Validate inputs ---
  if (!file.exists(yaml_path)) {
    stop("YAML file not found: ", yaml_path, call. = FALSE)
  }

  if (!is.character(id) || length(id) != 1) {
    stop("`id` must be a single string", call. = FALSE)
  }

  if (!severity %in% c("info", "warning", "blocking")) {
    stop("`severity` must be one of: info, warning, blocking", call. = FALSE)
  }

  # --- Load existing YAML ---
  yaml_data <- yaml::read_yaml(yaml_path)

  # Check for duplicate ID
  existing_ids <- map_chr(yaml_data$questions, ~ .x$id)
  if (id %in% existing_ids) {
    stop("Question ID '", id, "' already exists in ", yaml_path, call. = FALSE)
  }

  # --- Build new question ---
  new_question <- list(
    id = id,
    text = text,
    status = "open",
    severity = severity,
    rationale = rationale,
    affected_code = affected_code,
    flagged_by = flagged_by,
    flagged_date = as.character(flagged_date)
  )

  # --- Append to questions list ---
  yaml_data$questions <- c(yaml_data$questions, list(new_question))

  # --- Write back ---
  yaml::write_yaml(yaml_data, yaml_path)

  message("Added question ", id, " to ", yaml_path)
  invisible(TRUE)
}

# --- Resolve Question -------------------------------------------------------

#' Resolve an open question
#'
#' @param yaml_path Path to open-questions.yaml file
#' @param id Question ID to resolve
#' @param resolution The decision made
#' @param resolved_by Agent or user who resolved it
#' @param resolved_date Date resolved (YYYY-MM-DD)
#'
#' @return Invisible TRUE on success
#' @export
resolve_question <- function(yaml_path,
                              id,
                              resolution,
                              resolved_by = "user",
                              resolved_date = Sys.Date()) {
  # --- Validate inputs ---
  if (!file.exists(yaml_path)) {
    stop("YAML file not found: ", yaml_path, call. = FALSE)
  }

  # --- Load YAML ---
  yaml_data <- yaml::read_yaml(yaml_path)

  # Find question
  idx <- which(map_chr(yaml_data$questions, ~ .x$id) == id)
  if (length(idx) == 0) {
    stop("Question ID '", id, "' not found in ", yaml_path, call. = FALSE)
  }

  # --- Update question ---
  yaml_data$questions[[idx]]$status <- "resolved"
  yaml_data$questions[[idx]]$resolution <- resolution
  yaml_data$questions[[idx]]$resolved_by <- resolved_by
  yaml_data$questions[[idx]]$resolved_date <- as.character(resolved_date)

  # --- Write back ---
  yaml::write_yaml(yaml_data, yaml_path)

  message("Resolved question ", id, " in ", yaml_path)
  invisible(TRUE)
}

# --- List Questions ---------------------------------------------------------

#' List questions from the YAML file
#'
#' @param yaml_path Path to open-questions.yaml file
#' @param status_filter Filter by status: "open", "resolved", "deferred", or NULL for all
#' @param dataset_filter Filter by dataset name (searches affected_code file paths)
#'
#' @return Tibble with question details
#' @export
list_questions <- function(yaml_path,
                           status_filter = NULL,
                           dataset_filter = NULL) {
  # --- Validate inputs ---
  if (!file.exists(yaml_path)) {
    stop("YAML file not found: ", yaml_path, call. = FALSE)
  }

  # --- Load YAML ---
  yaml_data <- yaml::read_yaml(yaml_path)

  if (length(yaml_data$questions) == 0) {
    message("No questions found in ", yaml_path)
    return(tibble())
  }

  # --- Convert to tibble ---
  questions_df <- map_dfr(yaml_data$questions, function(q) {
    # Extract affected files
    affected_files <- if (!is.null(q$affected_code)) {
      map_chr(q$affected_code, ~ .x$file) %>% paste(collapse = "; ")
    } else {
      NA_character_
    }

    tibble(
      id = q$id,
      text = q$text,
      status = q$status,
      severity = q$severity %||% "info",
      resolution = q$resolution %||% NA_character_,
      affected_files = affected_files,
      flagged_by = q$flagged_by %||% NA_character_,
      flagged_date = q$flagged_date %||% NA_character_,
      resolved_by = q$resolved_by %||% NA_character_,
      resolved_date = q$resolved_date %||% NA_character_
    )
  })

  # --- Apply filters ---
  if (!is.null(status_filter)) {
    questions_df <- questions_df %>%
      filter(status == status_filter)
  }

  if (!is.null(dataset_filter)) {
    questions_df <- questions_df %>%
      filter(str_detect(affected_files, fixed(dataset_filter)))
  }

  return(questions_df)
}

# --- Check REVISIT Comments -------------------------------------------------

#' Check for REVISIT comments in code and validate linkage to questions
#'
#' @param code_dir Directory containing R code files to scan
#' @param yaml_path Path to open-questions.yaml file
#' @param pattern File pattern to match (default: "*.R")
#'
#' @return Tibble with validation results
#' @export
check_revisit_comments <- function(code_dir,
                                    yaml_path,
                                    pattern = "*.R") {
  # --- Validate inputs ---
  if (!dir.exists(code_dir)) {
    stop("Directory not found: ", code_dir, call. = FALSE)
  }

  if (!file.exists(yaml_path)) {
    stop("YAML file not found: ", yaml_path, call. = FALSE)
  }

  # --- Load YAML ---
  yaml_data <- yaml::read_yaml(yaml_path)
  question_ids <- map_chr(yaml_data$questions, ~ .x$id)

  # --- Scan R files ---
  r_files <- list.files(code_dir, pattern = pattern, full.names = TRUE, recursive = TRUE)

  if (length(r_files) == 0) {
    message("No R files found matching pattern '", pattern, "' in ", code_dir)
    return(tibble())
  }

  # --- Extract REVISIT comments ---
  results <- map_dfr(r_files, function(file) {
    lines <- readLines(file, warn = FALSE)

    revisit_lines <- which(str_detect(lines, "REVISIT:"))

    if (length(revisit_lines) == 0) {
      return(tibble())
    }

    map_dfr(revisit_lines, function(line_num) {
      comment_text <- lines[line_num]

      # Extract question ID (pattern: R1, W4, B2, etc.)
      id_match <- str_extract(comment_text, "[RWB]\\d+")

      tibble(
        file = file,
        line = line_num,
        comment = str_trim(comment_text),
        question_id = id_match %||% NA_character_,
        has_id = !is.na(id_match),
        id_exists = !is.na(id_match) && id_match %in% question_ids
      )
    })
  })

  # --- Validate linkage ---
  if (nrow(results) > 0) {
    results <- results %>%
      mutate(
        status = case_when(
          !has_id ~ "WARNING: No question ID in REVISIT comment",
          !id_exists ~ paste0("ERROR: Question ID ", question_id, " not found in YAML"),
          TRUE ~ "OK"
        )
      )
  }

  return(results)
}

# --- Helper: Check if Question is Resolved ---------------------------------

#' Check if a specific question is resolved
#'
#' @param yaml_path Path to open-questions.yaml file
#' @param id Question ID
#'
#' @return TRUE if resolved, FALSE if open/deferred, error if not found
#' @export
is_question_resolved <- function(yaml_path, id) {
  if (!file.exists(yaml_path)) {
    stop("YAML file not found: ", yaml_path, call. = FALSE)
  }

  yaml_data <- yaml::read_yaml(yaml_path)

  idx <- which(map_chr(yaml_data$questions, ~ .x$id) == id)
  if (length(idx) == 0) {
    stop("Question ID '", id, "' not found in ", yaml_path, call. = FALSE)
  }

  return(yaml_data$questions[[idx]]$status == "resolved")
}

# --- Pretty Print Questions -------------------------------------------------

#' Print questions in a human-readable format
#'
#' @param questions_df Tibble from list_questions()
#'
#' @return Invisible NULL (prints to console)
#' @export
print_questions <- function(questions_df) {
  if (nrow(questions_df) == 0) {
    message("No questions to display")
    return(invisible(NULL))
  }

  for (i in seq_len(nrow(questions_df))) {
    q <- questions_df[i, ]

    cat("\n")
    cat("ID: ", q$id, " | Status: ", toupper(q$status), " | Severity: ", q$severity, "\n", sep = "")
    cat("Question: ", q$text, "\n", sep = "")

    if (!is.na(q$resolution)) {
      cat("Resolution: ", q$resolution, "\n", sep = "")
    }

    if (!is.na(q$affected_files)) {
      cat("Affected files: ", q$affected_files, "\n", sep = "")
    }

    cat(strrep("-", 80), "\n", sep = "")
  }

  invisible(NULL)
}
