#!/usr/bin/env Rscript
#' Demo: /validate-plan Command
#'
#' This script demonstrates the /validate-plan command by validating
#' the test plan with known issues.

source("../R/validate_plan.R")

cat("=======================================================\n")
cat(" /validate-plan Command Demonstration\n")
cat("=======================================================\n\n")

# --- Example 1: Plan with issues -------------------------------------------

cat("Example 1: Validating plan with known anti-patterns\n")
cat("---------------------------------------------------\n\n")

result1 <- validate_plan("test-plan-with-issues.md")
cat(result1$report)
cat("\n\n")

# --- Example 2: NPM-008 actual plan ----------------------------------------

cat("Example 2: Validating NPM-008 production plan\n")
cat("----------------------------------------------\n\n")

if (file.exists("../plans/plan_adam_automation_2026-03-27.md")) {
  result2 <- validate_plan("../plans/plan_adam_automation_2026-03-27.md")
  cat(result2$report)
} else {
  cat("NPM-008 plan not found (skipping)\n")
}

cat("\n\n")

# --- Example 3: With data path validation ----------------------------------

cat("Example 3: Validating with source data path\n")
cat("--------------------------------------------\n\n")

# This would check if source SDTM domains exist
# result3 <- validate_plan(
#   "test-plan-with-issues.md",
#   data_path = "../source-data"
# )
# cat(result3$report)

cat("(Requires source-data directory to be present)\n")

cat("\n=======================================================\n")
cat(" Summary\n")
cat("=======================================================\n")
cat("\nThe /validate-plan command performs pre-flight checks:\n")
cat("  1. Detects datasets >40 variables without strategy\n")
cat("  2. Flags repeated derivations needing abstraction\n")
cat("  3. Ensures HIGH complexity has checkpoints\n")
cat("  4. Blocks on unresolved open questions\n")
cat("  5. Validates dependency/wave structure\n")
cat("  6. Checks source domains exist (if data-path given)\n")
cat("\nUse this command before starting ADaM automation to\n")
cat("catch anti-patterns early and prevent wasted compute.\n\n")
