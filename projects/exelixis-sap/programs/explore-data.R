# =============================================================================
# Program:   explore-data.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Purpose:   Read all SDTM and ADaM XPT files into named lists for exploration
# Author:    r-clinical-programmer agent
# Date:      2026-03-29
# =============================================================================

library(haven)
library(testthat)

# =============================================================================
# SECTION 1: SDTM Datasets
# =============================================================================

message(strrep("=", 70))
message("SECTION 1: SDTM Datasets")
message(strrep("=", 70))

# --- Get list of SDTM XPT files -----------------------------------------------
sdtm_dir <- "projects/exelixis-sap/output-data/sdtm"
sdtm_files <- list.files(sdtm_dir, pattern = "\\.xpt$", full.names = TRUE)
sdtm_names <- tools::file_path_sans_ext(basename(sdtm_files))

message(sprintf("Found %d SDTM XPT files:", length(sdtm_files)))
message(paste("  -", sdtm_names, collapse = "\n"))

# --- Read SDTM datasets into named list ----------------------------------------
sdtm_list <- lapply(sdtm_files, function(f) {
  message(sprintf("Reading: %s", basename(f)))
  haven::read_xpt(f)
})

# Name the list elements
names(sdtm_list) <- sdtm_names

# --- Verify all files are represented ------------------------------------------
message("\n--- SDTM Verification ---")
testthat::expect_equal(
  sort(names(sdtm_list)),
  sort(sdtm_names),
  info = "All SDTM XPT files should be represented in the output list"
)
message(sprintf("✓ Verified: All %d SDTM files loaded into list", length(sdtm_list)))

# --- SDTM Summary --------------------------------------------------------------
message("\n--- SDTM Summary ---")
sdtm_summary <- data.frame(
  Domain = names(sdtm_list),
  N_Rows = sapply(sdtm_list, nrow),
  N_Cols = sapply(sdtm_list, ncol),
  row.names = NULL
)
print(sdtm_summary)
message(sprintf("Total SDTM records: %s", formatC(sum(sdtm_summary$N_Rows), format = "d", big.mark = ",")))

# =============================================================================
# SECTION 2: ADaM Datasets
# =============================================================================

message("\n", strrep("=", 70))
message("SECTION 2: ADaM Datasets")
message(strrep("=", 70))

# --- Get list of ADaM XPT files ------------------------------------------------
adam_dir <- "projects/exelixis-sap/output-data/adam"
adam_files <- list.files(adam_dir, pattern = "\\.xpt$", full.names = TRUE)
adam_names <- tools::file_path_sans_ext(basename(adam_files))

message(sprintf("Found %d ADaM XPT files:", length(adam_files)))
message(paste("  -", adam_names, collapse = "\n"))

# --- Read ADaM datasets into named list ----------------------------------------
adam_list <- lapply(adam_files, function(f) {
  message(sprintf("Reading: %s", basename(f)))
  haven::read_xpt(f)
})

# Name the list elements
names(adam_list) <- adam_names

# --- Verify all files are represented ------------------------------------------
message("\n--- ADaM Verification ---")
testthat::expect_equal(
  sort(names(adam_list)),
  sort(adam_names),
  info = "All ADaM XPT files should be represented in the output list"
)
message(sprintf("✓ Verified: All %d ADaM files loaded into list", length(adam_list)))

# --- ADaM Summary --------------------------------------------------------------
message("\n--- ADaM Summary ---")
adam_summary <- data.frame(
  Domain = names(adam_list),
  N_Rows = sapply(adam_list, nrow),
  N_Cols = sapply(adam_list, ncol),
  row.names = NULL
)
print(adam_summary)
message(sprintf("Total ADaM records: %s", formatC(sum(adam_summary$N_Rows), format = "d", big.mark = ",")))

# =============================================================================
# Final Summary
# =============================================================================

message("\n", strrep("=", 70))
message("FINAL SUMMARY")
message(strrep("=", 70))
message(sprintf("Total datasets loaded: %d (%d SDTM + %d ADaM)",
                length(sdtm_list) + length(adam_list),
                length(sdtm_list),
                length(adam_list)))
message(sprintf("Total records: %s",
                formatC(sum(sdtm_summary$N_Rows) + sum(adam_summary$N_Rows),
                        format = "d", big.mark = ",")))
message(strrep("=", 70))

# --- Access examples -----------------------------------------------------------
message("\n--- Access Examples ---")
message("Access SDTM datasets: sdtm_list$dm, sdtm_list$ae, etc.")
message("Access ADaM datasets: adam_list$adsl, adam_list$adae, etc.")
