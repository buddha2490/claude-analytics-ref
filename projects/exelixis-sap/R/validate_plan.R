#' Validate ADaM Automation Plan
#'
#' Pre-flight check that scans an implementation plan for anti-patterns and
#' missing elements before execution begins.
#'
#' @param plan_path Character. Path to the plan markdown file.
#' @param data_path Character. Optional path to SDTM data directory. If provided,
#'   validates source domain availability.
#'
#' @return List with components:
#'   - `verdict`: Character. "PASS", "WARNING", or "BLOCKING"
#'   - `blocking`: Character vector of blocking issues
#'   - `warnings`: Character vector of warnings
#'   - `passes`: Character vector of successful checks
#'   - `report`: Character. Formatted report text
#'
#' @details
#' Validation checks:
#' 1. Complexity flags - datasets >40 variables without split/checkpoint strategy
#' 2. Pattern detection - >20 similar derivations without helper function note
#' 3. Execution strategy - HIGH complexity without checkpoints
#' 4. Open questions - unresolved questions flagged
#' 5. Dependency validation - missing dependency declarations
#'
#' @examples
#' \dontrun{
#' result <- validate_plan(
#'   "projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md"
#' )
#' cat(result$report)
#' }
#'
#' @export
validate_plan <- function(plan_path, data_path = NULL) {
  # --- Validate inputs -----------------------------------------------------------

  if (!is.character(plan_path) || length(plan_path) != 1) {
    stop("`plan_path` must be a single character string.", call. = FALSE)
  }

  if (!file.exists(plan_path)) {
    stop("Plan file not found: ", plan_path, call. = FALSE)
  }

  if (!is.null(data_path)) {
    if (!is.character(data_path) || length(data_path) != 1) {
      stop("`data_path` must be a single character string or NULL.", call. = FALSE)
    }
    if (!dir.exists(data_path)) {
      stop("Data directory not found: ", data_path, call. = FALSE)
    }
  }

  # --- Read and parse plan -------------------------------------------------------

  plan_lines <- readLines(plan_path, warn = FALSE)
  plan_text <- paste(plan_lines, collapse = "\n")

  # Initialize results
  blocking <- character(0)
  warnings <- character(0)
  passes <- character(0)

  # --- Check 1: Datasets >40 variables without split/checkpoint strategy --------

  # Extract dataset definitions (looking for patterns like "ADSL (101 variables)")
  dataset_pattern <- "(?:^|\\s)(AD[A-Z]{2,})\\s*\\(([0-9]+)\\s*variables\\)"
  dataset_matches <- gregexpr(dataset_pattern, plan_text, perl = TRUE)

  if (dataset_matches[[1]][1] != -1) {
    match_data <- regmatches(plan_text, dataset_matches)[[1]]

    for (match in match_data) {
      # Extract dataset name and variable count
      parts <- regmatches(match, regexec(dataset_pattern, match, perl = TRUE))[[1]]
      dataset_name <- parts[2]
      var_count <- as.integer(parts[3])

      if (var_count > 40) {
        # Check if split or checkpoint strategy is mentioned near this dataset
        # Extract context around this dataset (from dataset name to next ### or 200 chars)
        dataset_start <- regexpr(paste0("###\\s*", dataset_name), plan_text)

        if (dataset_start > 0) {
          # Get next 500 characters after dataset name as context
          context_end <- min(dataset_start + 500, nchar(plan_text))
          dataset_context <- substr(plan_text, dataset_start, context_end)

          has_strategy <- grepl(
            "split|checkpoint|part[0-9]|agent [0-9]",
            dataset_context,
            ignore.case = TRUE
          )
        } else {
          has_strategy <- FALSE
        }

        if (!has_strategy) {
          warnings <- c(
            warnings,
            sprintf(
              "%s has %d variables but no split/checkpoint strategy. Recommendation: Add checkpoints or consider splitting for datasets >40 variables.",
              dataset_name,
              var_count
            )
          )
        } else {
          passes <- c(
            passes,
            sprintf("%s (%d variables): Split/checkpoint strategy documented", dataset_name, var_count)
          )
        }
      }
    }
  }

  # --- Check 2: >20 similar derivations without helper function note ------------

  # Look for patterns indicating repeated derivations
  # Common patterns: multiple flag derivations, multiple mappings
  # Look for 5+ occurrences of "flag" or similar patterns
  flag_count <- stringr::str_count(plan_text, stringr::regex("\\bflag\\b", ignore_case = TRUE))
  biomarker_count <- stringr::str_count(plan_text, stringr::regex("\\bbiomarker\\b", ignore_case = TRUE))
  comorbid_count <- stringr::str_count(plan_text, stringr::regex("\\bcomorbid", ignore_case = TRUE))

  # Detect repeated patterns (5+ mentions suggests repetition)
  has_repeated_pattern <- (flag_count >= 5) || (biomarker_count >= 3) || (comorbid_count >= 3)

  if (has_repeated_pattern) {
    # Check if helper function is mentioned
    has_helper_note <- grepl(
      "helper function|create_.*_flag|abstraction|function\\(",
      plan_text,
      ignore.case = TRUE
    )

    if (!has_helper_note) {
      warnings <- c(
        warnings,
        "Plan contains repeated derivation patterns without helper function abstraction. Recommendation: Create helper functions for similar derivations to reduce code duplication."
      )
    } else {
      passes <- c(passes, "Repeated patterns: Helper function abstraction documented")
    }
  }

  # --- Check 3: HIGH complexity without checkpoints -----------------------------

  # Look for "HIGH" complexity markers
  high_complexity_pattern <- "(?i)complexity\\s*[:=]\\s*HIGH"

  if (grepl(high_complexity_pattern, plan_text, perl = TRUE)) {
    # Check if checkpoints are mentioned
    has_checkpoints <- grepl(
      "checkpoint|milestone|intermediate.*save|part[0-9]",
      plan_text,
      ignore.case = TRUE
    )

    if (!has_checkpoints) {
      warnings <- c(
        warnings,
        "Plan includes HIGH complexity dataset(s) without checkpoint strategy. Recommendation: Define checkpoints to validate intermediate results and reduce debugging complexity."
      )
    } else {
      passes <- c(passes, "HIGH complexity datasets: Checkpoint strategy documented")
    }
  }

  # --- Check 4: Unresolved open questions ----------------------------------------

  # Look for open questions section (case insensitive, flexible format)
  has_open_questions <- grepl("##.*open questions", plan_text, ignore.case = TRUE, perl = TRUE)

  if (has_open_questions) {
    # Extract the section using regex with dotall mode ((?s) makes . match newlines)
    # Match from "## Open Questions" to either next "##" or end of document
    open_q_pattern <- "(?si)##\\s*(?:[0-9]+\\.)?\\s*open questions.*?(?=\n##|\n---|$)"
    open_q_match <- regexpr(open_q_pattern, plan_text, perl = TRUE)

    if (open_q_match != -1) {
      open_q_section <- regmatches(plan_text, open_q_match)

      # Check for unresolved markers
      unresolved_indicators <- c(
        "\\[\\s*\\]",           # Unchecked checkbox [ ]
        "\\bTODO\\b",
        "\\bTBD\\b",
        "\\bPENDING\\b",
        "\\bUNRESOLVED\\b",
        "Status.*Open"
      )

      has_unresolved <- FALSE
      for (indicator in unresolved_indicators) {
        if (grepl(indicator, open_q_section, perl = TRUE)) {
          has_unresolved <- TRUE
          break
        }
      }

      if (has_unresolved) {
        blocking <- c(
          blocking,
          "Plan contains unresolved open questions. Action required: All questions must be resolved before implementation begins."
        )
      } else {
        passes <- c(passes, "Open questions: All resolved")
      }
    }
  }

  # --- Check 5: Missing dependency declarations ----------------------------------

  # Look for dataset definitions and check if dependencies are documented
  # Use a simpler pattern that doesn't consume the newline
  dataset_defs_pattern <- "###\\s+(AD[A-Z]{2,})"
  dataset_defs <- gregexpr(dataset_defs_pattern, plan_text, perl = TRUE)

  # Also check for ADaM dataset names in general (not just h3 headers)
  all_datasets <- unique(unlist(regmatches(plan_text, gregexpr("AD[A-Z]{2,}", plan_text))))

  # Check if waves or dependencies are documented
  has_waves <- grepl("Wave [0-9]|Phase [0-9]", plan_text, ignore.case = TRUE)
  has_dependencies <- grepl("Dependencies:|Depends on:|requires:", plan_text, ignore.case = TRUE)

  if (dataset_defs[[1]][1] != -1) {
    dataset_names <- regmatches(plan_text, dataset_defs)[[1]]
    dataset_names <- gsub(".*?(AD[A-Z]{2,}).*", "\\1", dataset_names)

    if (length(dataset_names) > 1 && !has_waves && !has_dependencies) {
      warnings <- c(
        warnings,
        sprintf(
          "Plan defines %d datasets but no dependency/wave structure documented. Recommendation: Define execution order to ensure foundation datasets (ADSL) are built before dependent datasets.",
          length(dataset_names)
        )
      )
    }
  } else if (length(all_datasets) > 1 && !has_waves && !has_dependencies) {
    # Found ADaM datasets but not in h3 headers - still check for dependency docs
    warnings <- c(
      warnings,
      sprintf(
        "Plan references %d datasets but no dependency/wave structure documented. Recommendation: Define execution order to ensure foundation datasets (ADSL) are built before dependent datasets.",
        length(all_datasets)
      )
    )
  }

  # If waves or dependencies documented, add pass
  if ((length(all_datasets) > 1 || dataset_defs[[1]][1] != -1) &&
      (has_waves || has_dependencies)) {
    passes <- c(passes, "Dataset dependencies: Documented with waves/dependencies")
  }

  # --- Check 6: Source data validation (if data_path provided) ------------------

  if (!is.null(data_path)) {
    # Extract source domains from plan - look for 2-letter uppercase codes
    # that appear near source/domain keywords
    # Simple approach: find all 2-letter uppercase codes, filter to known SDTM domains
    all_two_letter <- unique(unlist(regmatches(plan_text, gregexpr("\\b[A-Z]{2}\\b", plan_text))))

    # Filter to likely SDTM domains (exclude common abbreviations like ID, OR, IF, etc.)
    common_sdtm <- c("DM", "AE", "CM", "EX", "LB", "VS", "EG", "MH", "DS", "SV",
                     "QS", "EC", "EH", "FA", "IE", "IS", "PE", "PR", "SC", "SE",
                     "SU", "TA", "TD", "TE", "TI", "TS", "TV")
    source_domains <- all_two_letter[all_two_letter %in% common_sdtm]

    if (length(source_domains) > 0) {
      missing_domains <- character(0)

      for (domain in source_domains) {
        xpt_file <- file.path(data_path, paste0(tolower(domain), ".xpt"))
        if (!file.exists(xpt_file)) {
          missing_domains <- c(missing_domains, domain)
        }
      }

      if (length(missing_domains) > 0) {
        blocking <- c(
          blocking,
          sprintf(
            "Source domain(s) not found in data path: %s. Action required: Verify data path or update plan to reflect available domains.",
            paste(missing_domains, collapse = ", ")
          )
        )
      } else {
        passes <- c(passes, sprintf("Source domains: All %d domains found in data path", length(source_domains)))
      }
    }
  }

  # --- Determine overall verdict -------------------------------------------------

  verdict <- if (length(blocking) > 0) {
    "BLOCKING"
  } else if (length(warnings) > 0) {
    "WARNING"
  } else {
    "PASS"
  }

  # --- Format report -------------------------------------------------------------

  report_lines <- c(
    "Plan Validation Report",
    "======================",
    ""
  )

  if (length(passes) > 0) {
    for (pass in passes) {
      report_lines <- c(report_lines, paste0("\u2713 PASS: ", pass))
    }
    report_lines <- c(report_lines, "")
  }

  if (length(warnings) > 0) {
    for (warning in warnings) {
      report_lines <- c(report_lines, paste0("\u26A0 WARNING: ", warning))
    }
    report_lines <- c(report_lines, "")
  }

  if (length(blocking) > 0) {
    for (block in blocking) {
      report_lines <- c(report_lines, paste0("\u2717 BLOCKING: ", block))
    }
    report_lines <- c(report_lines, "")
  }

  # Summary
  report_lines <- c(
    report_lines,
    sprintf("VERDICT: %s", verdict)
  )

  if (verdict == "BLOCKING") {
    report_lines <- c(
      report_lines,
      sprintf("  %d BLOCKING issue(s), %d WARNING(s)", length(blocking), length(warnings)),
      "  Recommendation: Resolve blocking issues before proceeding"
    )
  } else if (verdict == "WARNING") {
    report_lines <- c(
      report_lines,
      sprintf("  %d WARNING(s)", length(warnings)),
      "  Recommendation: Review warnings and update plan if needed, then proceed"
    )
  } else {
    report_lines <- c(
      report_lines,
      "  All checks passed",
      "  Recommendation: Proceed with implementation"
    )
  }

  report_text <- paste(report_lines, collapse = "\n")

  # --- Return structured result --------------------------------------------------

  list(
    verdict = verdict,
    blocking = blocking,
    warnings = warnings,
    passes = passes,
    report = report_text
  )
}
