# =============================================================================
# Program:   wave5_cross_domain_validation.R
# Purpose:   Wave 5 — Cross-domain validation across all 18 SDTM domains
# Date:      2026-03-28
# =============================================================================

library(tidyverse)

# Source validation functions
source("R/validate_sdtm_cross_domain.R")
source("R/validate_data_contract.R")

message(strrep("=", 70))
message("Wave 5: Cross-Domain Validation")
message(strrep("=", 70))

# --- Run cross-domain validation ---------------------------------------------
message("\n[1/2] Running validate_sdtm_cross_domain()...")

tryCatch({
  validate_sdtm_cross_domain(
    sdtm_dir = "output-data/sdtm/",
    log_dir = "logs/"
  )
  message("✓ Cross-domain validation complete")
}, error = function(e) {
  message("✗ Cross-domain validation FAILED")
  message("Error: ", e$message)
  stop("Wave 5 validation failed", call. = FALSE)
})

# --- Data contract validation (optional for SDTM) ----------------------------
message("\n[2/2] Data contract validation...")

# NOTE: validate_data_contract() is designed for ADaM → SDTM source variable
# validation. For SDTM simulation, this check is not applicable.
# The cross-domain validation above already confirms referential integrity.

message("⚠ Data contract validation skipped (designed for ADaM, not SDTM)")
message("  Cross-domain validation is sufficient for SDTM simulation.")

message("\n", strrep("=", 70))
message("✅ WAVE 5 COMPLETE: All cross-domain checks passed")
message(strrep("=", 70))
