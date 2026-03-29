# =============================================================================
# Program:   sim_all.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Purpose:   Master orchestrator — sources all 19 domain sim programs in order
#            and prints a cross-domain summary table.
# Seed:      set.seed(42) — base seed; each domain overrides with its own seed
# Author:    r-clinical-programmer agent
# Date:      2026-03-27
# =============================================================================

library(tidyverse)
library(haven)

# --- Constants ----------------------------------------------------------------
# Defined here so they are available in the global environment when each
# domain script is sourced. Each domain script also defines these locally
# (they are identical), which is intentional and by design.

STUDYID    <- "NPM008"
N_SUBJECTS <- 40
STUDY_END  <- as.Date("2027-01-31")
SITES      <- c("01", "02", "03", "04", "05")

set.seed(42)

### Set relative path
if (basename(getwd()) !=  "exelixis-sap") {

  setwd("projects/exelixis-sap/")

}

# Load ct-reference data
# build_ct_reference.R lives in R/ (the reusable functions directory) and 
#   is a legitimate utility — it builds a static CDISC controlled           
#   terminology lookup table and saves it as ct_reference.rds. The SDTM     
#   simulation programs likely source this file to validate that generated
#   values fall within allowed CT codelists.  
source("R/build_ct_reference.R")



# --- Execution order ----------------------------------------------------------
# Per plan Section 2: DM first (subject spine), then dependent domains in
# dependency order. Each script overrides the base seed with its own offset.

domain_scripts <- c(
  "programs/sdtm/sim_dm.R",   # 01 — DM:  subject spine (all latent variables)
  "programs/sdtm/sim_ie.R",   # 02 — IE:  inclusion/exclusion criteria
  "programs/sdtm/sim_mh.R",   # 03 — MH:  medical history
  "programs/sdtm/sim_sc.R",   # 04 — SC:  subject characteristics
  "programs/sdtm/sim_su.R",   # 05 — SU:  substance use
  "programs/sdtm/sim_vs.R",   # 06 — VS:  vital signs
  "programs/sdtm/sim_lb.R",   # 07 — LB:  laboratory test results
  "programs/sdtm/sim_bs.R",   # 08 — BS:  biospecimen findings
  "programs/sdtm/sim_ex.R",   # 09 — EX:  exposure (treatment)
  "programs/sdtm/sim_ec.R",   # 10 — EC:  exposure as collected
  "programs/sdtm/sim_cm.R",   # 11 — CM:  concomitant medications
  "programs/sdtm/sim_pr.R",   # 12 — PR:  procedures
  "programs/sdtm/sim_qs.R",   # 13 — QS:  questionnaires / ECOG
  "programs/sdtm/sim_tu.R",   # 14 — TU:  tumor identification
  "programs/sdtm/sim_tr.R",   # 15 — TR:  tumor results (measurements)
  "programs/sdtm/sim_rs.R",   # 16 — RS:  response
  "programs/sdtm/sim_ae.R",   # 17 — AE:  adverse events
  "programs/sdtm/sim_ho.R",   # 18 — HO:  healthcare encounters (hospitalizations)
  "programs/sdtm/sim_ds.R"    # 19 — DS:  disposition
)

# --- Source each domain program -----------------------------------------------

message(strrep("=", 70))
message("NPM-008 / XB010-101  —  SDTM Simulation Orchestrator")
message(sprintf("Start time: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
message(sprintf("N subjects: %d  |  Study end: %s", N_SUBJECTS, STUDY_END))
message(strrep("=", 70))

for (script in domain_scripts) {
  domain_label <- toupper(sub(".*/sim_([a-z]+)\\.R", "\\1", script))
  message("\n", strrep("-", 60))
  message(sprintf("[%s] Sourcing: %s", domain_label, script))
  message(strrep("-", 60))

  source(script, echo = FALSE)
}

message("\n", strrep("=", 70))
message("All 19 domain scripts completed.")
message(strrep("=", 70))

# --- Build summary table ------------------------------------------------------
# Read each XPT from output-data/, count rows, and report.

xpt_files <- tibble::tibble(
  domain = c("DM","IE","MH","SC","SU","VS","LB","BS",
             "EX","EC","CM","PR","QS","TU","TR","RS","AE","HO","DS"),
  xpt    = tolower(c("DM","IE","MH","SC","SU","VS","LB","BS",
                     "EX","EC","CM","PR","QS","TU","TR","RS","AE","HO","DS"))
) %>%
  dplyr::mutate(
    filepath = file.path("output-data/sdtm", paste0(xpt, ".xpt"))
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
message("CROSS-DOMAIN SUMMARY  —  NPM-008 / XB010-101")
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
