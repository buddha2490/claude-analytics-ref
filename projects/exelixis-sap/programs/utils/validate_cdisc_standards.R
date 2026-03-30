# validate_cdisc_standards.R
#
# Purpose: Validate CDISC compliance for all domains in inventory
# Author: Claude (r-clinical-programmer agent)
# Date: 2026-03-29

# --- Setup ------------------------------------------------------------------

library(dplyr)
library(purrr)
library(stringr)
library(tibble)

# --- Load Inventory ---------------------------------------------------------

message("Loading CDISC inventory...")
inventory_path <- "output-data/cdisc_inventory.rds"
inventory <- readRDS(inventory_path)

# Flatten inventory structure (sdtm + adam sublists)
all_domains <- c(inventory$sdtm, inventory$adam)

message("Loaded ", length(all_domains), " domains from inventory (",
        length(inventory$sdtm), " SDTM, ",
        length(inventory$adam), " ADaM)")

# --- CDISC Reference Data ---------------------------------------------------

# Required variables by domain type
required_vars <- list(
  universal_sdtm = c("STUDYID", "DOMAIN", "USUBJID"),
  DM = c("STUDYID", "DOMAIN", "USUBJID", "SEX", "RACE", "ETHNIC", "RFSTDTC"),
  AE = c("STUDYID", "DOMAIN", "USUBJID", "AETERM", "AESTDTC", "AESEQ"),
  EX = c("STUDYID", "DOMAIN", "USUBJID", "EXTRT", "EXSTDTC"),
  universal_adam = c("STUDYID", "USUBJID")
)

# Controlled terminology (CDISC codelist references)
ct_values <- list(
  SEX = list(
    values = c("M", "F"),
    codelist = "C66732",
    type = "closed"
  ),
  RACE = list(
    values = c(
      "AMERICAN INDIAN OR ALASKA NATIVE",
      "ASIAN",
      "BLACK OR AFRICAN AMERICAN",
      "NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER",
      "NOT REPORTED",
      "OTHER",
      "UNKNOWN",
      "WHITE"
    ),
    codelist = "C74457",
    type = "closed"
  ),
  ETHNIC = list(
    values = c(
      "HISPANIC OR LATINO",
      "NOT HISPANIC OR LATINO",
      "NOT REPORTED",
      "UNKNOWN"
    ),
    codelist = "C66790",
    type = "closed"
  ),
  AESEV = list(
    values = c("MILD", "MODERATE", "SEVERE"),
    codelist = "C66769",
    type = "closed"
  )
)

# ADaM flag values (Y or empty)
adam_flag_pattern <- "(FL|FLG)$"  # Variables ending in FL or FLG

# --- Validation Functions ---------------------------------------------------

#' Check for required variables
check_required_vars <- function(domain_name, vars, dataset_type) {
  findings <- list()

  # Determine which required vars to check
  if (dataset_type == "SDTM") {
    check_vars <- required_vars$universal_sdtm

    # Add domain-specific requirements
    if (domain_name %in% names(required_vars)) {
      check_vars <- required_vars[[domain_name]]
    }
  } else {
    # ADaM
    check_vars <- required_vars$universal_adam

    # Add dataset-specific requirements if defined
    if (domain_name %in% names(required_vars)) {
      check_vars <- required_vars[[domain_name]]
    }
  }

  missing_vars <- setdiff(check_vars, vars)

  if (length(missing_vars) > 0) {
    findings[[length(findings) + 1]] <- data.frame(
      variable = paste(missing_vars, collapse = ", "),
      check = "Required Variable",
      severity = "BLOCKING",
      description = paste(
        "Missing required CDISC variables:",
        paste(missing_vars, collapse = ", ")
      ),
      actual = "Missing",
      expected = paste(check_vars, collapse = ", "),
      suggested_fix = "Add the required variables with appropriate derivations",

    )
  }

  findings
}

#' Check variable naming conventions
check_naming_convention <- function(vars, domain_name, dataset_type) {
  findings <- list()

  # Check uppercase
  non_upper <- vars[vars != toupper(vars)]
  if (length(non_upper) > 0) {
    findings[[length(findings) + 1]] <- data.frame(
      variable = paste(non_upper, collapse = ", "),
      check = "Variable Naming",
      severity = "WARNING",
      description = "Variable names must be uppercase per CDISC standards",
      actual = paste(non_upper, collapse = ", "),
      expected = paste(toupper(non_upper), collapse = ", "),
      suggested_fix = "Convert variable names to uppercase",

    )
  }

  # Check length (≤8 chars for SDTM)
  if (dataset_type == "SDTM") {
    long_vars <- vars[nchar(vars) > 8]
    if (length(long_vars) > 0) {
      findings[[length(findings) + 1]] <- data.frame(
        variable = paste(long_vars, collapse = ", "),
        check = "Variable Naming",
        severity = "WARNING",
        description = "SDTM variable names must be ≤8 characters",
        actual = paste0(long_vars, " (", nchar(long_vars), " chars)", collapse = "; "),
        expected = "≤8 characters",
        suggested_fix = "Shorten variable names or verify they are valid CDISC standard names",

      )
    }
  }

  # Check domain prefix (SDTM only, and only for non-universal vars)
  if (dataset_type == "SDTM" && domain_name != "DM") {
    # Standard SDTM variables that do not require domain prefixes
    universal_vars <- c("STUDYID", "DOMAIN", "USUBJID")
    timing_vars <- c("VISIT", "VISITNUM", "VISITDY", "EPOCH")

    domain_specific <- setdiff(vars, c(universal_vars, timing_vars))
    prefix <- substr(domain_name, 1, 2)

    missing_prefix <- domain_specific[!grepl(paste0("^", prefix), domain_specific)]

    # Remove variables that start with standard suffixes (SEQ, etc.)
    missing_prefix <- missing_prefix[!missing_prefix %in% paste0(prefix, c("SEQ", "CAT", "SCAT"))]

    if (length(missing_prefix) > 0) {
      findings[[length(findings) + 1]] <- data.frame(
        variable = paste(missing_prefix, collapse = ", "),
        check = "Variable Naming",
        severity = "NOTE",
        description = paste0(
          "Domain-specific variables should typically start with '",
          prefix, "' prefix"
        ),
        actual = paste(missing_prefix, collapse = ", "),
        expected = paste0("Variables prefixed with '", prefix, "'"),
        suggested_fix = "Verify these are valid CDISC standard variables without domain prefix",

      )
    }
  }

  findings
}

#' Check variable types
check_variable_types <- function(domain_data, vars) {
  findings <- list()

  # Check *DTC variables are character
  dtc_vars <- vars[grepl("DTC$", vars)]
  for (var in dtc_vars) {
    if (var %in% names(domain_data)) {
      if (!is.character(domain_data[[var]])) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Variable Type",
          severity = "WARNING",
          description = "Date/time variables (*DTC) must be character, not parsed dates",
          actual = class(domain_data[[var]])[1],
          expected = "character",
          suggested_fix = paste0("Convert ", var, " to character with as.character()"),

        )
      }
    }
  }

  # Check *SEQ variables are numeric
  seq_vars <- vars[grepl("SEQ$", vars)]
  for (var in seq_vars) {
    if (var %in% names(domain_data)) {
      if (!is.numeric(domain_data[[var]])) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Variable Type",
          severity = "WARNING",
          description = "Sequence variables (*SEQ) must be numeric",
          actual = class(domain_data[[var]])[1],
          expected = "numeric or integer",
          suggested_fix = paste0("Convert ", var, " to numeric with as.numeric()"),

        )
      }
    }
  }

  # Check flag variables are character
  flag_vars <- vars[grepl(adam_flag_pattern, vars)]
  for (var in flag_vars) {
    if (var %in% names(domain_data)) {
      if (is.logical(domain_data[[var]])) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Variable Type",
          severity = "WARNING",
          description = "Flag variables must be character ('Y' or ''), not logical",
          actual = "logical (TRUE/FALSE)",
          expected = "character ('Y' or '')",
          suggested_fix = paste0(
            "Convert ", var, " to character: ",
            "mutate(", var, " = if_else(", var, ", 'Y', ''))"
          ),

        )
      }
    }
  }

  findings
}

#' Check variable labels
check_variable_labels <- function(domain_data, vars) {
  findings <- list()

  labels <- map_chr(vars, ~ {
    label <- attr(domain_data[[.x]], "label")
    if (is.null(label)) "" else label
  })

  empty_labels <- vars[labels == ""]

  if (length(empty_labels) > 0) {
    findings[[length(findings) + 1]] <- data.frame(
      variable = paste(empty_labels, collapse = ", "),
      check = "Variable Label",
      severity = "WARNING",
      description = "All variables should have labels for XPT transport",
      actual = "Empty label",
      expected = "Descriptive label",
      suggested_fix = "Add labels using attr(df$VAR, 'label') <- 'Label text'",

    )
  }

  findings
}

#' Check controlled terminology
check_controlled_terminology <- function(domain_data, vars) {
  findings <- list()

  # Check each CT variable that exists in this domain
  for (var in names(ct_values)) {
    if (var %in% vars) {
      ct_spec <- ct_values[[var]]
      actual_values <- unique(domain_data[[var]])
      actual_values <- actual_values[!is.na(actual_values)]

      invalid_values <- setdiff(actual_values, ct_spec$values)

      if (length(invalid_values) > 0) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Controlled Terminology",
          severity = if (ct_spec$type == "closed") "BLOCKING" else "WARNING",
          description = paste0(
            "Invalid values for ", var, " (CDISC codelist ", ct_spec$codelist, ")"
          ),
          actual = paste(invalid_values, collapse = ", "),
          expected = paste(ct_spec$values, collapse = ", "),
          suggested_fix = paste0(
            "Remap invalid values to valid CDISC CT values for ", var
          ),

        )
      }
    }
  }

  # Check ADaM flags (if any)
  flag_vars <- vars[grepl(adam_flag_pattern, vars)]
  for (var in flag_vars) {
    if (var %in% names(domain_data) && is.character(domain_data[[var]])) {
      actual_values <- unique(domain_data[[var]])
      actual_values <- actual_values[!is.na(actual_values)]

      invalid_values <- setdiff(actual_values, c("Y", ""))

      if (length(invalid_values) > 0) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Controlled Terminology",
          severity = "WARNING",
          description = paste0(
            "ADaM flag variables should only contain 'Y' or '' (empty string)"
          ),
          actual = paste(invalid_values, collapse = ", "),
          expected = "'Y' or ''",
          suggested_fix = paste0(
            "Recode ", var, " to use 'Y' for TRUE and '' for FALSE"
          ),

        )
      }
    }
  }

  findings
}

#' Check date formats
check_date_formats <- function(domain_data, vars) {
  findings <- list()

  dtc_vars <- vars[grepl("DTC$", vars)]

  # ISO 8601 patterns
  # Full: YYYY-MM-DD or YYYY-MM-DDThh:mm:ss
  # Partial: YYYY-MM or YYYY
  iso_pattern <- "^\\d{4}(-\\d{2}(-\\d{2}(T\\d{2}:\\d{2}(:\\d{2})?)?)?)?$"

  for (var in dtc_vars) {
    if (var %in% names(domain_data)) {
      values <- domain_data[[var]]
      values <- values[!is.na(values) & values != ""]

      if (length(values) > 0) {
        invalid_dates <- values[!grepl(iso_pattern, values)]

        if (length(invalid_dates) > 0) {
          findings[[length(findings) + 1]] <- data.frame(
            variable = var,
            check = "Date Format",
            severity = "WARNING",
            description = paste0(
              var, " contains dates not in ISO 8601 format"
            ),
            actual = paste(head(invalid_dates, 5), collapse = ", "),
            expected = "YYYY-MM-DD or YYYY-MM-DDThh:mm:ss",
            suggested_fix = paste0("Reformat ", var, " to ISO 8601 standard"),

          )
        }

        # Note partial dates
        partial_dates <- values[grepl("^\\d{4}(-\\d{2})?$", values)]
        if (length(partial_dates) > 0) {
          findings[[length(findings) + 1]] <- data.frame(
            variable = var,
            check = "Date Format",
            severity = "NOTE",
            description = paste0(
              var, " contains ", length(partial_dates), " partial dates (YYYY or YYYY-MM)"
            ),
            actual = paste(head(partial_dates, 3), collapse = ", "),
            expected = "Full or partial ISO 8601 dates allowed",
            suggested_fix = "No action required - partial dates are valid per SDTM-IG",

          )
        }
      }
    }
  }

  findings
}

#' Check missing values in required variables
check_missing_values <- function(domain_data, vars, domain_name) {
  findings <- list()

  # USUBJID must have zero missing
  if ("USUBJID" %in% vars) {
    n_missing <- sum(is.na(domain_data$USUBJID) | domain_data$USUBJID == "")

    if (n_missing > 0) {
      findings[[length(findings) + 1]] <- data.frame(
        variable = "USUBJID",
        check = "Missing Values",
        severity = "BLOCKING",
        description = "USUBJID must not have missing values",
        actual = paste0(n_missing, " missing values"),
        expected = "0 missing values",
        suggested_fix = "Investigate and fix missing USUBJID values",

      )
    }
  }

  # Define variables exempt from high missingness warnings
  # These variables are expected to be sparse in oncology studies
  sparse_variable_patterns <- c(
    # Death-related variables
    "^DTH",
    # Biomarker variables (mutations and fusions)
    "MUT$", "FUS$", "^ALK$", "^ROS1",
    # Metastasis site flags
    "MET$",
    # Comorbidity flags
    "^CAD", "^DIAB", "^COPD", "^RENAL", "^PVD",
    # Hospitalization
    "^HOSP",
    # Baseline flags in time-to-event datasets
    "^ABLFL$", "^INDEXFL$",
    # Event/censoring descriptions
    "EVNTDESC$", "CNSDTDSC$"
  )

  # Check high missingness (>20%) on any variable
  for (var in vars) {
    if (var %in% names(domain_data)) {
      # Skip if this variable matches any sparse variable pattern
      is_sparse <- any(sapply(sparse_variable_patterns, function(pattern) {
        grepl(pattern, var)
      }))

      if (is_sparse) next

      n_missing <- sum(is.na(domain_data[[var]]) |
                       (is.character(domain_data[[var]]) & domain_data[[var]] == ""))
      pct_missing <- n_missing / nrow(domain_data) * 100

      if (pct_missing > 20) {
        findings[[length(findings) + 1]] <- data.frame(
          variable = var,
          check = "Missing Values",
          severity = "WARNING",
          description = paste0(
            var, " has high missingness (", round(pct_missing, 1), "%)"
          ),
          actual = paste0(n_missing, " missing (", round(pct_missing, 1), "%)"),
          expected = "<20% missing",
          suggested_fix = paste0(
            "Review derivation logic for ", var, " - verify high missingness is expected"
          ),

        )
      }
    }
  }

  findings
}

#' Check cross-domain consistency (SDTM only)
check_cross_domain <- function(sdtm_domains_list) {
  findings <- list()

  # Get DM USUBJID as reference
  dm_data <- sdtm_domains_list$DM
  if (is.null(dm_data)) {
    return(list(
      data.frame(
        variable = "DM",
        check = "Cross-Domain Consistency",
        severity = "BLOCKING",
        description = "DM domain not found - cannot validate cross-domain consistency",
        actual = "DM domain missing",
        expected = "DM domain present",
        suggested_fix = "Generate DM domain before other SDTM domains",

      )
    ))
  }

  # Extract data from the structure
  dm_df <- dm_data$data
  dm_usubjid <- unique(dm_df$USUBJID)
  dm_studyid <- unique(dm_df$STUDYID)

  # Check each non-DM SDTM domain
  sdtm_domain_names <- setdiff(names(sdtm_domains_list), "DM")

  for (domain_name in sdtm_domain_names) {
    domain_data <- sdtm_domains_list[[domain_name]]$data

    # Check USUBJID exists in DM
    domain_usubjid <- unique(domain_data$USUBJID)
    missing_subjects <- setdiff(domain_usubjid, dm_usubjid)

    if (length(missing_subjects) > 0) {
      findings[[length(findings) + 1]] <- data.frame(
        variable = "USUBJID",
        check = "Cross-Domain Consistency",
        severity = "BLOCKING",
        description = paste0(
          domain_name, " contains USUBJID values not found in DM"
        ),
        actual = paste(head(missing_subjects, 5), collapse = ", "),
        expected = "All USUBJID in DM",
        suggested_fix = paste0(
          "Ensure all subjects in ", domain_name, " exist in DM domain"
        ),

      )
    }

    # Check STUDYID consistency
    domain_studyid <- unique(domain_data$STUDYID)
    if (!all(domain_studyid %in% dm_studyid)) {
      findings[[length(findings) + 1]] <- data.frame(
        variable = "STUDYID",
        check = "Cross-Domain Consistency",
        severity = "BLOCKING",
        description = paste0(
          domain_name, " has inconsistent STUDYID with DM"
        ),
        actual = paste(domain_studyid, collapse = ", "),
        expected = paste(dm_studyid, collapse = ", "),
        suggested_fix = paste0(
          "Ensure ", domain_name, " uses same STUDYID as DM"
        ),

      )
    }
  }

  findings
}

# --- Main Validation Loop ---------------------------------------------------

message("Running CDISC validation checks...")

summary_results <- list()
detailed_results <- list()

# Validate each domain
for (domain_name in names(all_domains)) {
  message("  Validating ", domain_name, "...")

  domain_obj <- all_domains[[domain_name]]
  domain_data <- domain_obj$data

  # Determine dataset type from which list it came from
  dataset_type <- if (domain_name %in% names(inventory$sdtm)) "SDTM" else "ADaM"

  vars <- names(domain_data)
  domain_findings <- list()

  # Run all checks
  domain_findings <- c(
    domain_findings,
    check_required_vars(domain_name, vars, dataset_type),
    check_naming_convention(vars, domain_name, dataset_type),
    check_variable_types(domain_data, vars),
    check_variable_labels(domain_data, vars),
    check_controlled_terminology(domain_data, vars),
    check_date_formats(domain_data, vars),
    check_missing_values(domain_data, vars, domain_name)
  )

  # Combine findings into data frame
  if (length(domain_findings) > 0) {
    findings_df <- bind_rows(domain_findings)
  } else {
    findings_df <- data.frame(
      variable = character(),
      check = character(),
      severity = character(),
      description = character(),
      actual = character(),
      expected = character(),
      suggested_fix = character(),

    )
  }

  # Count by severity
  n_blocking <- sum(findings_df$severity == "BLOCKING")
  n_warnings <- sum(findings_df$severity == "WARNING")
  n_notes <- sum(findings_df$severity == "NOTE")

  # Determine overall status
  status <- if (n_blocking > 0) {
    "BLOCKING"
  } else if (n_warnings > 0) {
    "WARNING"
  } else {
    "PASS"
  }

  # Store summary
  summary_results[[domain_name]] <- data.frame(
    domain = domain_name,
    records = nrow(domain_data),
    variables = ncol(domain_data),
    blocking = n_blocking,
    warnings = n_warnings,
    notes = n_notes,
    status = status,

  )

  # Store detailed findings
  detailed_results[[domain_name]] <- list(
    findings = findings_df
  )
}

# Run cross-domain checks (SDTM only)
message("  Running cross-domain consistency checks...")
cross_domain_findings <- check_cross_domain(inventory$sdtm)

if (length(cross_domain_findings) > 0) {
  # Add cross-domain findings to summary
  # These are domain-agnostic, so we'll add them to a special "CROSS_DOMAIN" entry
  detailed_results[["CROSS_DOMAIN"]] <- list(
    findings = bind_rows(cross_domain_findings)
  )

  # Update summary with cross-domain status
  cross_blocking <- sum(detailed_results$CROSS_DOMAIN$findings$severity == "BLOCKING")
  cross_warnings <- sum(detailed_results$CROSS_DOMAIN$findings$severity == "WARNING")

  summary_results[["CROSS_DOMAIN"]] <- data.frame(
    domain = "CROSS_DOMAIN",
    records = NA_integer_,
    variables = NA_integer_,
    blocking = cross_blocking,
    warnings = cross_warnings,
    notes = 0L,
    status = if (cross_blocking > 0) "BLOCKING" else if (cross_warnings > 0) "WARNING" else "PASS",

  )
}

# --- Combine Results --------------------------------------------------------

summary_df <- bind_rows(summary_results)

# No RAG queries were used in this validation (all checks are rule-based)
rag_queries_df <- data.frame(
  query = character(),
  result_summary = character(),

)

validation_findings <- list(
  summary = summary_df,
  details = detailed_results,
  rag_queries = rag_queries_df
)

# --- Save Results -----------------------------------------------------------

output_path <- "output-data/cdisc_validation_findings.rds"
saveRDS(validation_findings, output_path)

message("\n✓ CDISC validation complete")
message("  Findings saved to: ", output_path)
message("\nSummary:")
message("  Total domains validated: ", nrow(summary_df))
message("  BLOCKING issues: ", sum(summary_df$blocking, na.rm = TRUE))
message("  WARNING issues: ", sum(summary_df$warnings, na.rm = TRUE))
message("  NOTE issues: ", sum(summary_df$notes, na.rm = TRUE))
message("  Overall status: ",
        if (any(summary_df$status == "BLOCKING", na.rm = TRUE)) "BLOCKING"
        else if (any(summary_df$status == "WARNING", na.rm = TRUE)) "WARNING"
        else "PASS")
