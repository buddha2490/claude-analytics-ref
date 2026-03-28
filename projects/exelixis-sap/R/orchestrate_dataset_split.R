#' Orchestrate Multi-Agent Dataset Splitting
#'
#' Analyzes dataset specification and determines if splitting across multiple
#' agents is beneficial. For high-complexity datasets (>40 variables), creates
#' a split plan with variable groupings and agent assignments.
#'
#' @param dataset_spec List containing dataset specification with:
#'   - `dataset_name`: Character, e.g., "ADSL"
#'   - `variables`: Data frame with columns: variable, label, derivation_logic, source_domains
#'   - `total_variables`: Integer, total count of variables
#' @param threshold Integer, variable count threshold for splitting (default 40)
#'
#' @return List with elements:
#'   - `split_required`: Logical, whether splitting is recommended
#'   - `n_agents`: Integer, number of agents to spawn (1 if no split)
#'   - `split_plan`: List of agent assignments (NULL if no split)
#'   - `merge_strategy`: Character, merge approach (NULL if no split)
#'
#' @examples
#' \dontrun{
#' # ADSL with 101 variables
#' spec <- list(
#'   dataset_name = "ADSL",
#'   variables = readr::read_csv("adsl_spec.csv"),
#'   total_variables = 101
#' )
#' plan <- orchestrate_dataset_split(spec, threshold = 40)
#' }
#'
#' @export
orchestrate_dataset_split <- function(dataset_spec, threshold = 40) {
  # --- Validate inputs --------------------------------------------------------
  if (!is.list(dataset_spec)) {
    stop("`dataset_spec` must be a list.", call. = FALSE)
  }

  required_fields <- c("dataset_name", "variables", "total_variables")
  missing_fields <- setdiff(required_fields, names(dataset_spec))
  if (length(missing_fields) > 0) {
    stop("`dataset_spec` missing required fields: ",
         paste(missing_fields, collapse = ", "), call. = FALSE)
  }

  if (!is.data.frame(dataset_spec$variables)) {
    stop("`dataset_spec$variables` must be a data frame.", call. = FALSE)
  }

  if (!is.numeric(threshold) || threshold <= 0) {
    stop("`threshold` must be a positive number.", call. = FALSE)
  }

  # --- Extract metadata -------------------------------------------------------
  dataset_name <- dataset_spec$dataset_name
  total_vars <- dataset_spec$total_variables
  variables_df <- dataset_spec$variables

  message("Analyzing dataset: ", dataset_name, " (", total_vars, " variables)")

  # --- Determine if split is needed -------------------------------------------
  if (total_vars <= threshold) {
    message("Split NOT required (", total_vars, " <= ", threshold, ")")
    return(list(
      split_required = FALSE,
      n_agents = 1,
      split_plan = NULL,
      merge_strategy = NULL
    ))
  }

  message("Split RECOMMENDED (", total_vars, " > ", threshold, ")")

  # --- Infer variable groupings -----------------------------------------------
  # Group variables by derivation category using heuristics
  grouped_vars <- .infer_variable_groups(variables_df, dataset_name)

  # --- Assign groups to agents ------------------------------------------------
  # Target ~25-30 variables per agent, balanced across agents
  agent_assignments <- .assign_groups_to_agents(grouped_vars, target_size = 30)

  # --- Build split plan -------------------------------------------------------
  split_plan <- lapply(seq_along(agent_assignments), function(i) {
    group_info <- agent_assignments[[i]]
    list(
      agent_id = paste0("agent_", LETTERS[i]),
      part_number = i,
      variable_groups = group_info$groups,
      variables = group_info$variables,
      variable_count = length(group_info$variables),
      checkpoint_file = paste0(tolower(dataset_name), "_part", i, ".rds"),
      required_keys = c("USUBJID", "STUDYID")
    )
  })

  # --- Build merge strategy ---------------------------------------------------
  merge_strategy <- paste0(
    "Sequential left_join by USUBJID + STUDYID:\n",
    paste(sapply(split_plan, function(x) {
      paste0("  - ", x$checkpoint_file, " (", x$variable_count, " variables)")
    }), collapse = "\n")
  )

  message("Split plan created: ", length(split_plan), " agents")

  return(list(
    split_required = TRUE,
    n_agents = length(split_plan),
    split_plan = split_plan,
    merge_strategy = merge_strategy
  ))
}


#' Infer Variable Groups
#'
#' Uses heuristics to group variables by derivation category.
#'
#' @param variables_df Data frame with columns: variable, label, derivation_logic, source_domains
#' @param dataset_name Character, dataset name for context
#'
#' @return List of groups, each with: group_name, variables, source_domains
#'
#' @keywords internal
.infer_variable_groups <- function(variables_df, dataset_name) {
  # Ensure required columns exist
  if (!"variable" %in% names(variables_df)) {
    stop("variables_df must contain 'variable' column.", call. = FALSE)
  }

  # Add source_domains if missing (for simpler test cases)
  if (!"source_domains" %in% names(variables_df)) {
    variables_df$source_domains <- NA_character_
  }

  # Initialize groups list
  groups <- list()

  # --- Key variables (always first group) ---
  key_vars <- c("USUBJID", "STUDYID")
  key_matches <- variables_df$variable %in% key_vars
  if (any(key_matches)) {
    groups$keys <- list(
      group_name = "Keys",
      variables = variables_df$variable[key_matches],
      source_domains = "DM"
    )
  }

  # --- Demographics ---
  demo_pattern <- "^(AGE|SEX|RACE|ETHNIC|COUNTRY|REGION|ARM|ACTARM|TRT)"
  demo_matches <- grepl(demo_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(demo_matches)) {
    groups$demographics <- list(
      group_name = "Demographics",
      variables = variables_df$variable[demo_matches],
      source_domains = "DM"
    )
  }

  # --- Biomarker flags ---
  biomarker_pattern <- "(MUT|GENE|ALK|ROS1|PD-?L1|KRAS|EGFR|BRAF|NTRK)"
  biomarker_matches <- grepl(biomarker_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(biomarker_matches)) {
    groups$biomarkers <- list(
      group_name = "Biomarkers",
      variables = variables_df$variable[biomarker_matches],
      source_domains = "LB"
    )
  }

  # --- Comorbidity flags ---
  comorbid_pattern <- "(MYHIS|CVAIS|CONGHF|DIA|RENAL|HEPAT|COPD|CCI|CHARLSON)"
  comorbid_matches <- grepl(comorbid_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(comorbid_matches)) {
    groups$comorbidities <- list(
      group_name = "Comorbidities",
      variables = variables_df$variable[comorbid_matches],
      source_domains = "MH"
    )
  }

  # --- Baseline assessments ---
  baseline_pattern <- "(ECOG|KPS|_BL$|BASE)"
  baseline_matches <- grepl(baseline_pattern, variables_df$variable, ignore.case = TRUE) &
    !key_matches & !demo_matches
  if (any(baseline_matches)) {
    groups$baseline <- list(
      group_name = "Baseline Assessments",
      variables = variables_df$variable[baseline_matches],
      source_domains = "QS, SC"
    )
  }

  # --- Staging ---
  staging_pattern <- "(STAGE|TSTAGE|NSTAGE|MSTAGE|AJCC|HIST)"
  staging_matches <- grepl(staging_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(staging_matches)) {
    groups$staging <- list(
      group_name = "Staging",
      variables = variables_df$variable[staging_matches],
      source_domains = "TU, PR"
    )
  }

  # --- Treatment history ---
  treatment_pattern <- "(LOT|TRTSEQ|PRIORX|PFSIND|OSIND)"
  treatment_matches <- grepl(treatment_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(treatment_matches)) {
    groups$treatment <- list(
      group_name = "Treatment History",
      variables = variables_df$variable[treatment_matches],
      source_domains = "PR, EX"
    )
  }

  # --- Dates ---
  date_pattern <- "(DT$|STDTC|ENDTC|RFSTDTC|RFENDTC)"
  date_matches <- grepl(date_pattern, variables_df$variable, ignore.case = TRUE) & !key_matches
  if (any(date_matches)) {
    groups$dates <- list(
      group_name = "Dates",
      variables = variables_df$variable[date_matches],
      source_domains = "DM, various"
    )
  }

  # --- Uncategorized (everything else) ---
  categorized <- Reduce(`|`, list(key_matches, demo_matches, biomarker_matches,
                                   comorbid_matches, baseline_matches, staging_matches,
                                   treatment_matches, date_matches))
  uncategorized <- !categorized
  if (any(uncategorized)) {
    groups$other <- list(
      group_name = "Other Variables",
      variables = variables_df$variable[uncategorized],
      source_domains = "Various"
    )
  }

  return(groups)
}


#' Assign Groups to Agents
#'
#' Distributes variable groups across agents to balance workload.
#'
#' @param grouped_vars List of variable groups
#' @param target_size Integer, target variables per agent
#'
#' @return List of agent assignments
#'
#' @keywords internal
.assign_groups_to_agents <- function(grouped_vars, target_size = 30) {
  # Calculate total variables
  total_vars <- sum(sapply(grouped_vars, function(g) length(g$variables)))

  # Estimate number of agents needed
  n_agents <- ceiling(total_vars / target_size)

  # Initialize agent assignments
  agents <- vector("list", n_agents)
  for (i in seq_len(n_agents)) {
    agents[[i]] <- list(groups = character(), variables = character())
  }

  # Sort groups by size (descending) for better packing
  group_sizes <- sapply(grouped_vars, function(g) length(g$variables))
  sorted_groups <- grouped_vars[order(group_sizes, decreasing = TRUE)]

  # Keys must always be in every agent assignment
  key_vars <- c("USUBJID", "STUDYID")

  # Assign groups to agents using greedy algorithm
  agent_sizes <- rep(0, n_agents)

  for (group_name in names(sorted_groups)) {
    group <- sorted_groups[[group_name]]
    group_size <- length(group$variables)

    # Special handling for "Other" group if it's very large
    # Split it across multiple agents instead of assigning to one
    if (group$group_name == "Other Variables" && group_size > target_size) {
      # Distribute "Other" variables across agents that have capacity
      other_vars <- setdiff(group$variables, key_vars)
      vars_per_agent <- ceiling(length(other_vars) / n_agents)

      for (i in seq_len(n_agents)) {
        start_idx <- (i - 1) * vars_per_agent + 1
        end_idx <- min(i * vars_per_agent, length(other_vars))

        if (start_idx <= length(other_vars)) {
          chunk <- other_vars[start_idx:end_idx]
          agents[[i]]$groups <- c(agents[[i]]$groups, paste0(group$group_name, " (part ", i, ")"))
          agents[[i]]$variables <- unique(c(
            key_vars,
            agents[[i]]$variables,
            chunk
          ))
          agent_sizes[i] <- length(agents[[i]]$variables)
        }
      }
    } else {
      # Find agent with smallest current size
      target_agent <- which.min(agent_sizes)

      # Assign group to agent
      agents[[target_agent]]$groups <- c(agents[[target_agent]]$groups, group$group_name)
      agents[[target_agent]]$variables <- unique(c(
        key_vars,  # Always include keys
        agents[[target_agent]]$variables,
        group$variables
      ))

      agent_sizes[target_agent] <- length(agents[[target_agent]]$variables)
    }
  }

  return(agents)
}
