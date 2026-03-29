# --- Generate CDISC Validation Report -------------------------------------------
#
# Purpose: Create a static Quarto report from CDISC validation findings
# Input:   projects/exelixis-sap/output-data/cdisc_validation_findings.rds
# Output:  projects/exelixis-sap/output-reports/cdisc-validation-report-2026-03-29.qmd
#

library(tidyverse)
library(conflicted)

# Resolve namespace conflicts
conflicts_prefer(dplyr::filter, .quiet = TRUE)
conflicts_prefer(dplyr::lag, .quiet = TRUE)

# --- Load Findings ---------------------------------------------------------------

findings_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/cdisc_validation_findings.rds"
findings_data <- readRDS(findings_path)

summary_df <- findings_data$summary
details_list <- findings_data$details
rag_queries <- findings_data$rag_queries

message("Loaded findings for ", nrow(summary_df), " datasets")

# --- Helper Functions ------------------------------------------------------------

# Format a table as markdown
format_md_table <- function(df) {
  if (nrow(df) == 0) return("*No data*\n")

  # Build header
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(df)), collapse = " | "), " |")

  # Build rows
  rows <- df %>%
    mutate(across(everything(), ~ replace_na(as.character(.), ""))) %>%
    mutate(across(everything(), ~ str_replace_all(., "\\|", "\\\\|"))) %>%
    mutate(across(everything(), ~ str_replace_all(., "\n", " "))) %>%
    pmap_chr(~ paste0("| ", paste(c(...), collapse = " | "), " |"))

  paste(c(header, separator, rows), collapse = "\n")
}

# Extract all findings into a flat data frame
extract_all_findings <- function(details_list) {
  names(details_list) %>%
    map_dfr(~ {
      domain <- .x
      findings <- details_list[[domain]]$findings
      if (is.null(findings) || nrow(findings) == 0) {
        return(tibble())
      }
      findings %>%
        mutate(domain = domain, .before = 1)
    })
}

all_findings <- extract_all_findings(details_list)

# --- Compute Summary Statistics --------------------------------------------------

total_datasets <- nrow(summary_df)
total_blocking <- sum(summary_df$blocking, na.rm = TRUE)
total_warning <- sum(summary_df$warnings, na.rm = TRUE)
total_note <- sum(summary_df$notes, na.rm = TRUE)

# Group required changes by theme
required_changes <- all_findings %>%
  filter(severity == "BLOCKING") %>%
  mutate(
    theme = case_when(
      str_detect(check, "(?i)missing|required") ~ "Missing Variables",
      str_detect(check, "(?i)type|class|numeric") ~ "Type Errors",
      str_detect(check, "(?i)controlled terminology|CT|codelist") ~ "CT Violations",
      str_detect(check, "(?i)date|format|ISO") ~ "Date Format Issues",
      str_detect(check, "(?i)NA|null|empty") ~ "Missing Values",
      TRUE ~ "Other"
    )
  ) %>%
  arrange(theme, domain) %>%
  group_by(theme) %>%
  mutate(item_num = row_number()) %>%
  ungroup()

# Overall statistics table
overall_stats <- summary_df %>%
  mutate(
    status_icon = case_when(
      status == "BLOCKING" ~ "🔴 BLOCKING",
      status == "WARNING" ~ "⚠️ WARNING",
      TRUE ~ "✅ PASS"
    )
  ) %>%
  select(
    Domain = domain,
    Records = records,
    Variables = variables,
    Blocking = blocking,
    Warnings = warnings,
    Notes = notes,
    Status = status_icon
  )

# --- Build QMD Content -----------------------------------------------------------

qmd_content <- glue::glue('
---
title: "CDISC Data Validation Report"
subtitle: "Exelixis SAP Study — SDTM and ADaM Datasets"
author: "Automated Validation"
date: "2026-03-29"
format:
  html:
    toc: true
    toc-depth: 3
    toc-location: left
    number-sections: true
    theme: cosmo
    embed-resources: true
---

# Abstract

This report presents CDISC validation findings for {total_datasets} datasets ({paste(sort(unique(all_findings$domain)), collapse = ", ")}). The validation identified **{total_blocking} BLOCKING issues**, **{total_warning} warnings**, and **{total_note} informational notes**. Key issues include missing required variables (STUDYID, --SEQ), type mismatches (expected numeric, found character), controlled terminology violations (SEX, RACE values), and date format inconsistencies (non-ISO 8601 formats). The datasets require correction of all BLOCKING findings before they can be considered CDISC-compliant.

# Source Report

- **Input Profile Report:** `projects/exelixis-sap/output-reports/exelixis-dummy-data-report.html`
- **Date Generated:** 2026-03-29
- **Findings Input:** `projects/exelixis-sap/output-data/cdisc_validation_findings.rds`

# Summary of Required Changes

The following BLOCKING issues must be resolved:

')

# Add required changes by theme
if (nrow(required_changes) > 0) {
  theme_sections <- required_changes %>%
    group_by(theme) %>%
    summarise(
      content = paste0(
        "## ", first(theme), "\n\n",
        paste0(
          item_num, ". **", domain, "**: ", description,
          if_else(!is.na(suggested_fix) & suggested_fix != "",
                  paste0(" → *", suggested_fix, "*"),
                  ""),
          collapse = "\n"
        ),
        "\n"
      ),
      .groups = "drop"
    )

  qmd_content <- paste0(
    qmd_content,
    paste(theme_sections$content, collapse = "\n")
  )
} else {
  qmd_content <- paste0(qmd_content, "*No BLOCKING issues found.*\n\n")
}

# Add overall statistics
qmd_content <- paste0(
  qmd_content,
  "\n# Overall Statistics\n\n",
  format_md_table(overall_stats),
  "\n\n"
)

# --- Individual Dataset Reports --------------------------------------------------

qmd_content <- paste0(qmd_content, "# Individual Dataset Reports\n\n")

for (domain_name in summary_df$domain) {
  # Get summary stats
  domain_summary <- summary_df %>%
    filter(domain == domain_name)

  record_count <- domain_summary$records
  var_count <- domain_summary$variables
  blocking <- domain_summary$blocking
  warning <- domain_summary$warnings
  note <- domain_summary$notes

  verdict <- if (blocking > 0) "🔴 BLOCKING" else if (warning > 0) "⚠️ WARNING" else "✅ PASS"

  qmd_content <- paste0(
    qmd_content,
    "## ", domain_name, "\n\n",
    "- **Records:** ", record_count, "\n",
    "- **Variables:** ", var_count, "\n",
    "- **Verdict:** ", verdict, "\n\n"
  )

  # Get findings for this domain
  findings <- details_list[[domain_name]]$findings

  # Findings table
  if (!is.null(findings) && nrow(findings) > 0) {
    findings_table <- findings %>%
      select(variable, check, severity, description, actual, expected, suggested_fix) %>%
      mutate(
        variable = replace_na(variable, ""),
        actual = str_trunc(replace_na(actual, ""), 50),
        expected = str_trunc(replace_na(expected, ""), 50),
        suggested_fix = str_trunc(replace_na(suggested_fix, ""), 100)
      )

    qmd_content <- paste0(
      qmd_content,
      "### Findings\n\n",
      format_md_table(findings_table),
      "\n\n"
    )
  } else {
    qmd_content <- paste0(
      qmd_content,
      "### Findings\n\n*No findings for this domain.*\n\n"
    )
  }

  qmd_content <- paste0(qmd_content, "---\n\n")
}

# --- RAG Reference Log -----------------------------------------------------------

rag_log <- tribble(
  ~Query, ~Result,
  "CDISC SDTM required variables all domains STUDYID DOMAIN USUBJID SEQ", "Found domain abbreviation codelist and general observation classes",
  "CDISC SDTM variable naming convention uppercase 8 characters domain prefix suffix", "Found domain abbreviation codelist with naming rules",
  "SDTM date format ISO 8601 DTC variables YYYY-MM-DD partial dates", "Found Date Imputation Flag codelist (D, M, Y values)",
  "CDISC controlled terminology SEX RACE ETHNIC codelist values", "Found Race (C74457), Ethnic Group (C66790), Sex of Participants (C66732) codelists",
  "ADaM analysis flags Y empty string missing value handling SAFFL ITTFL population flag", "Found ADaM Basic Data Structure Subclass codelist",
  "SDTM DM demographics domain required variables USUBJID RFSTDTC SEX RACE ETHNIC STUDYID", "Found Subject Characteristic Test Name codelist",
  "SDTM AE adverse events required variables AETERM AEDECOD AESEV AESER AEREL AESEQ AESTDTC", "Found general observation classes and event domain descriptions",
  "SDTM EX exposure required variables EXTRT EXDOSE EXDOSEU EXSTDTC EXROUTE", "Found general observation classes and interventions domain",
  "CDISC controlled terminology AESEV AESER AEREL adverse event severity seriousness relationship", "Found Severity/Intensity Scale for AEs (C66769): MILD, MODERATE, SEVERE",
  "ADaM ADSL subject level analysis dataset required variables SAFFL ITTFL TRTP TRTPN USUBJID", "Found Subject Level Analysis Dataset definition in General Observation Class"
)

qmd_content <- paste0(
  qmd_content,
  "# RAG Reference Log\n\n",
  "The following RAG queries were executed during validation rule development:\n\n",
  format_md_table(rag_log),
  "\n\n",
  "---\n\n",
  "*Report generated by automated CDISC validation pipeline on ", Sys.Date(), "*\n"
)

# --- Write QMD File --------------------------------------------------------------

output_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-reports/cdisc-validation-report-2026-03-29.qmd"
writeLines(qmd_content, output_path)

message("✓ QMD file written to: ", output_path)
message("✓ Ready to render with: quarto render ", output_path)
