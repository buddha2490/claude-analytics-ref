# Dataset Splitting Demo
# Demonstrates the orchestrate_dataset_split() and merge_split_datasets() workflow

library(dplyr)

source("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/R/orchestrate_dataset_split.R")
source("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/R/merge_split_datasets.R")

# --- Example 1: Small dataset (no split) --------------------------------------
message("\n=== Example 1: Small Dataset (No Split) ===\n")

small_spec <- list(
  dataset_name = "ADAE",
  variables = data.frame(
    variable = c("USUBJID", "STUDYID", "AESEQ", "AEDECOD", "AESTDTC", "AEENDTC"),
    label = c("Subject ID", "Study ID", "AE Sequence", "AE Term", "AE Start", "AE End")
  ),
  total_variables = 6
)

result <- orchestrate_dataset_split(small_spec, threshold = 40)
cat("Split required:", result$split_required, "\n")
cat("Number of agents:", result$n_agents, "\n\n")


# --- Example 2: Large dataset (split) -----------------------------------------
message("\n=== Example 2: Large Dataset (Split into Multiple Agents) ===\n")

# Simulate ADSL with 101 variables
# Calculate total: 2 + 8 + 15 + 20 + 10 + 12 + 15 + 9 = 91 base variables
# Need 10 more to reach 101
adsl_variables <- data.frame(
  variable = c(
    "USUBJID", "STUDYID",
    # Demographics (8)
    "AGE", "SEX", "RACE", "ETHNIC", "COUNTRY", "REGION", "ARM", "ACTARM",
    # Biomarkers (15)
    "EGFRMUT", "KRASMUT", "ALK", "ROS1MUT", "PDL1", "BRAFMUT", "METMUT",
    "NTRKMUT", "RET", "HER2", "TMBHIGH", "MSI", "PDL1TPS", "PDL1CPS", "PDL1IC",
    # Comorbidities (20)
    "MYHIS", "CVAIS", "CONGHF", "DIA", "DIAWC", "RENAL", "HEPAT", "COPD",
    "RHEUMAT", "PEPULC", "LIVDIS", "DIABETES", "HEMIPARA", "SOLIDTUM", "LEUKEMIA",
    "LYMPHOMA", "LIVER", "AIDS", "CCIGRP", "CCIVAL",
    # Baseline (10)
    "ECOG0", "ECOG_BL", "SMOKGRP", "SMOKHIST", "KPS_BL", "WEIGHT_BL", "HEIGHT_BL",
    "BMI_BL", "BSA_BL", "CREAT_BL",
    # Staging (12)
    "TSTAGE", "NSTAGE", "MSTAGE", "AJCCSTG", "HISTGRP", "HISTOLOGY", "GRADE",
    "LATERALITY", "TUMORSIZE", "LYMPHNODES", "METASITES", "METCOUNT",
    # Treatment (15)
    "LOTSNUM", "PFSIND", "OSIND", "BORTFL", "SAFFL", "ITTFL", "PPROTFL",
    "TRTSEQ", "PRIORX", "PRIORSURG", "PRIORRAD", "PRIORIO", "PRIORCHEMO",
    "PRIORTARG", "PRIORIMM",
    # Dates (9)
    "RFSTDTC", "RFENDTC", "TRTSDT", "TRTEDT", "DTHDT", "LSTALVDT",
    "RANDDT", "SCREENDT", "ENRLDT",
    # Additional variables to reach 101 (10)
    paste0("VAR", 1:10)
  ),
  label = paste("Variable", 1:101),
  source_domains = c(
    rep("DM", 2),
    rep("DM", 8),
    rep("LB", 15),
    rep("MH", 20),
    rep("QS, SC", 10),
    rep("TU, PR", 12),
    rep("PR, EX", 15),
    rep("DM, various", 9),
    rep("Various", 10)
  )
)

large_spec <- list(
  dataset_name = "ADSL",
  variables = adsl_variables,
  total_variables = 101
)

result <- orchestrate_dataset_split(large_spec, threshold = 40)

cat("Split required:", result$split_required, "\n")
cat("Number of agents:", result$n_agents, "\n\n")

cat("Split plan:\n")
for (i in seq_along(result$split_plan)) {
  agent <- result$split_plan[[i]]
  cat(sprintf("  %s (%s):\n", agent$agent_id, agent$checkpoint_file))
  cat(sprintf("    - Variables: %d\n", agent$variable_count))
  cat(sprintf("    - Groups: %s\n", paste(agent$variable_groups, collapse = ", ")))
  cat("\n")
}

cat("Merge strategy:\n")
cat(result$merge_strategy, "\n\n")


# --- Example 3: Simulated merge -----------------------------------------------
message("\n=== Example 3: Simulated Merge ===\n")

# Create temporary checkpoint files
temp_dir <- tempfile()
dir.create(temp_dir)

# Simulate 3 subjects
subjects <- data.frame(
  USUBJID = c("NPM008-001-001", "NPM008-001-002", "NPM008-001-003"),
  STUDYID = c("NPM008", "NPM008", "NPM008")
)

# Part 1: Demographics
part1 <- subjects %>%
  mutate(
    AGE = c(65, 72, 58),
    SEX = c("M", "F", "M"),
    RACE = c("WHITE", "ASIAN", "WHITE")
  )
saveRDS(part1, file.path(temp_dir, "adsl_part1.rds"))
cat("Created part1:", ncol(part1), "columns\n")

# Part 2: Biomarkers
part2 <- subjects %>%
  mutate(
    EGFRMUT = c("Y", "N", "Y"),
    KRASMUT = c("N", "Y", "N"),
    ALK = c("N", "N", "N")
  )
saveRDS(part2, file.path(temp_dir, "adsl_part2.rds"))
cat("Created part2:", ncol(part2), "columns\n")

# Part 3: Staging
part3 <- subjects %>%
  mutate(
    TSTAGE = c("T2", "T3", "T1"),
    NSTAGE = c("N1", "N0", "N2"),
    MSTAGE = c("M0", "M0", "M1")
  )
saveRDS(part3, file.path(temp_dir, "adsl_part3.rds"))
cat("Created part3:", ncol(part3), "columns\n\n")

# Merge checkpoints
checkpoint_files <- c(
  file.path(temp_dir, "adsl_part1.rds"),
  file.path(temp_dir, "adsl_part2.rds"),
  file.path(temp_dir, "adsl_part3.rds")
)

output_path <- file.path(temp_dir, "adsl_merged.xpt")

merge_result <- merge_split_datasets(
  checkpoint_files = checkpoint_files,
  output_path = output_path
)

cat("\nMerged dataset dimensions:", nrow(merge_result$merged_data),
    "rows ×", ncol(merge_result$merged_data), "columns\n\n")

# Print validation report
all_passed <- print_validation_report(merge_result$validation_report)

# Show merged data
cat("\nMerged data (first 3 rows):\n")
print(head(merge_result$merged_data, 3))

# Clean up
unlink(temp_dir, recursive = TRUE)

message("\n=== Demo Complete ===\n")
