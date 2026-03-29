# =============================================================================
# Program:   run_all_adam.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Purpose:   Master orchestrator — sources all ADaM programs in dependency order
#            and prints a cross-domain summary table.
# Author:    r-clinical-programmer agent
# Date:      2026-03-29
# =============================================================================

library(tidyverse)
library(haven)

# --- Execution order ----------------------------------------------------------
# ADaM programs must run in dependency order:
# ADLOT → ADSL → {ADAE, ADRS, ADBS} → ADTTE

adam_scripts <- c(
  "programs/adam/adam_adlot.R",  # 01 — ADLOT: Lines of therapy (no dependencies)
  "programs/adam/adam_adsl.R",   # 02 — ADSL:  Subject-level analysis (requires ADLOT)
  "programs/adam/adam_adae.R",   # 03 — ADAE:  Adverse events (requires ADSL)
  "programs/adam/adam_adrs.R",   # 04 — ADRS:  Response (requires ADSL)
  "programs/adam/adam_adbs.R",   # 05 — ADBS:  Biospecimen (no ADaM dependencies)
  "programs/adam/adam_adtte.R"   # 06 — ADTTE: Time-to-event (requires ADSL, ADRS)
)

# --- Source each ADaM program -------------------------------------------------

message(strrep("=", 70))
message("NPM-008 / XB010-101  —  ADaM Derivation Orchestrator")
message(sprintf("Start time: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
message(strrep("=", 70))

for (script in adam_scripts) {
  domain_label <- toupper(sub(".*/adam_([a-z]+)\\.R", "\\1", script))
  message("\n", strrep("-", 60))
  message(sprintf("[%s] Sourcing: %s", domain_label, script))
  message(strrep("-", 60))

  source(script, echo = FALSE)
}

message("\n", strrep("=", 70))
message("All ADaM programs completed.")
message(strrep("=", 70))

# --- Build summary table ------------------------------------------------------
# Read each XPT from output-data/adam/, count rows, and report.

xpt_files <- tibble::tibble(
  domain = c("ADLOT", "ADSL", "ADAE", "ADRS", "ADBS", "ADTTE"),
  xpt    = tolower(c("ADLOT", "ADSL", "ADAE", "ADRS", "ADBS", "ADTTE"))
) %>%
  dplyr::mutate(
    filepath = file.path("output-data/adam", paste0(xpt, ".xpt"))
  )

summary_tbl <- xpt_files %>%
  dplyr::mutate(
    n_rows = purrr::map_int(filepath, function(f) {
      if (file.exists(f)) nrow(haven::read_xpt(f)) else NA_integer_
    }),
    file_exists = file.exists(filepath)
  ) %>%
  dplyr::select(Domain = domain, XPT_File = xpt, N_Rows = n_rows, File_Found = file_exists)

# --- Print summary ------------------------------------------------------------

message("\n", strrep("=", 70))
message("CROSS-DOMAIN SUMMARY  —  NPM-008 / XB010-101 ADaM")
message(strrep("=", 70))
print(summary_tbl, n = 30)
message(strrep("-", 70))
message(sprintf(
  "Total records: %s across %d domains",
  formatC(sum(summary_tbl$N_Rows, na.rm = TRUE), format = "d", big.mark = ","),
  sum(summary_tbl$File_Found)
))
message(strrep("=", 70))
message(sprintf("End time: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
