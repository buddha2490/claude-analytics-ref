#!/usr/bin/env Rscript
# Test the profile-data skill with realistic NPM-008 SDTM data

library(dplyr)
library(haven)

# Set working directory to script location
setwd("/Users/briancarter/Rdata/claude-analytics-ref")

# --- Create test data directory ---
data_dir <- "projects/exelixis-sap/data"
output_dir <- "projects/exelixis-sap/data-profiles"

dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Creating test SDTM datasets...")

# --- LB: Laboratory (Biomarkers) ---
set.seed(42)
lb_data <- tibble::tibble(
  STUDYID = "NPM-008",
  DOMAIN = "LB",
  USUBJID = rep(paste0("NPM-008-001-", sprintf("%03d", 1:40)), each = 10),
  LBSEQ = 1:400,
  LBTESTCD = rep(c("EGFR", "KRAS", "ALK", "BRAF", "PDL1",
                   "HER2", "ROS1", "MET", "RET", "NTRK"), 40),
  LBTEST = rep(c("EGFR Mutation Analysis", "KRAS Mutation Analysis",
                 "ALK Translocation", "BRAF Mutation", "PD-L1 Expression",
                 "HER2 Amplification", "ROS1 Fusion", "MET Amplification",
                 "RET Fusion", "NTRK Fusion"), 40),
  LBCAT = "BIOMARKER",
  LBMETHOD = "NGS",
  LBSTRESC = c(
    # EGFR: Use "ALTERED" terminology (not "POSITIVE")
    rep("ALTERED", 12), rep("NOT ALTERED", 25), rep("NOT TESTED", 3),
    # KRAS: Mixed terminology
    rep("DETECTED", 8), rep("NOT DETECTED", 32),
    # ALK: POSITIVE terminology
    rep("POSITIVE", 5), rep("NEGATIVE", 35),
    # BRAF: ALTERED terminology
    rep("ALTERED", 3), rep("NOT ALTERED", 37),
    # PD-L1: Numeric categories
    rep("HIGH", 15), rep("LOW", 18), rep("NEGATIVE", 7),
    # HER2
    rep("AMPLIFIED", 4), rep("NOT AMPLIFIED", 36),
    # ROS1
    rep("DETECTED", 2), rep("NOT DETECTED", 38),
    # MET
    rep("AMPLIFIED", 6), rep("NOT AMPLIFIED", 34),
    # RET
    rep("DETECTED", 1), rep("NOT DETECTED", 39),
    # NTRK
    rep("DETECTED", 3), rep("NOT DETECTED", 37)
  ),
  LBORRESU = "RESULT",
  LBDY = rep(1:10, 40)
)

# Add labels
attr(lb_data$STUDYID, "label") <- "Study Identifier"
attr(lb_data$DOMAIN, "label") <- "Domain Abbreviation"
attr(lb_data$USUBJID, "label") <- "Unique Subject Identifier"
attr(lb_data$LBSEQ, "label") <- "Sequence Number"
attr(lb_data$LBTESTCD, "label") <- "Lab Test or Examination Short Name"
attr(lb_data$LBTEST, "label") <- "Lab Test or Examination Name"
attr(lb_data$LBCAT, "label") <- "Category for Lab Test"
attr(lb_data$LBMETHOD, "label") <- "Method of Test or Examination"
attr(lb_data$LBSTRESC, "label") <- "Character Result/Finding in Std Format"
attr(lb_data$LBORRESU, "label") <- "Original Units"
attr(lb_data$LBDY, "label") <- "Study Day of Specimen Collection"

haven::write_xpt(lb_data, file.path(data_dir, "lb.xpt"))
message("Created LB.xpt (", nrow(lb_data), " records)")


# --- MH: Medical History ---
mh_data <- tibble::tibble(
  STUDYID = "NPM-008",
  DOMAIN = "MH",
  USUBJID = c(
    rep(paste0("NPM-008-001-", sprintf("%03d", 1:20)), each = 3),
    rep(paste0("NPM-008-001-", sprintf("%03d", 21:40)), each = 2)
  ),
  MHSEQ = 1:100,
  MHCAT = c(
    rep("PRIMARY DIAGNOSIS", 40),
    rep("RELEVANT MEDICAL HISTORY", 60)
  ),
  MHTERM = c(
    rep("Non-Small Cell Lung Cancer", 25),
    rep("Small Cell Lung Cancer", 15),
    rep("Hypertension", 20),
    rep("Type 2 Diabetes Mellitus", 15),
    rep("Chronic Obstructive Pulmonary Disease", 10),
    rep("Atrial Fibrillation", 15)
  ),
  MHSTDTC = as.character(
    seq.Date(as.Date("2022-01-01"), by = "week", length.out = 100)
  )
)

attr(mh_data$STUDYID, "label") <- "Study Identifier"
attr(mh_data$DOMAIN, "label") <- "Domain Abbreviation"
attr(mh_data$USUBJID, "label") <- "Unique Subject Identifier"
attr(mh_data$MHSEQ, "label") <- "Sequence Number"
attr(mh_data$MHCAT, "label") <- "Category for Medical History"
attr(mh_data$MHTERM, "label") <- "Reported Term for the Medical History"
attr(mh_data$MHSTDTC, "label") <- "Start Date/Time of Medical History Event"

haven::write_xpt(mh_data, file.path(data_dir, "mh.xpt"))
message("Created MH.xpt (", nrow(mh_data), " records)")


# --- QS: Questionnaires (ECOG) ---
qs_data <- tibble::tibble(
  STUDYID = "NPM-008",
  DOMAIN = "QS",
  USUBJID = rep(paste0("NPM-008-001-", sprintf("%03d", 1:40)), each = 4),
  QSSEQ = 1:160,
  QSCAT = "ECOG PERFORMANCE STATUS",
  QSTESTCD = "ECOG",
  QSTEST = "ECOG Performance Status",
  QSORRES = rep(c("0", "1", "1", "2"), 40),  # Character, not numeric
  QSSTRESC = rep(c("0", "1", "1", "2"), 40),
  QSDTC = as.character(rep(
    seq.Date(as.Date("2023-01-01"), by = "month", length.out = 4),
    40
  )),
  VISITNUM = rep(c(1, 2, 3, 4), 40),
  VISIT = rep(c("SCREENING", "CYCLE 1 DAY 1", "CYCLE 2 DAY 1", "CYCLE 3 DAY 1"), 40)
)

attr(qs_data$STUDYID, "label") <- "Study Identifier"
attr(qs_data$DOMAIN, "label") <- "Domain Abbreviation"
attr(qs_data$USUBJID, "label") <- "Unique Subject Identifier"
attr(qs_data$QSSEQ, "label") <- "Sequence Number"
attr(qs_data$QSCAT, "label") <- "Category for Questionnaire"
attr(qs_data$QSTESTCD, "label") <- "Questionnaire Test Short Name"
attr(qs_data$QSTEST, "label") <- "Questionnaire Test Name"
attr(qs_data$QSORRES, "label") <- "Result or Finding in Original Units"
attr(qs_data$QSSTRESC, "label") <- "Character Result/Finding in Std Format"
attr(qs_data$QSDTC, "label") <- "Date/Time of Collection"
attr(qs_data$VISITNUM, "label") <- "Visit Number"
attr(qs_data$VISIT, "label") <- "Visit Name"

haven::write_xpt(qs_data, file.path(data_dir, "qs.xpt"))
message("Created QS.xpt (", nrow(qs_data), " records)")


# --- Test the profile_data function ---
message("\n=== Testing profile_data function ===\n")

source("R/profile_data.R")

# Test 1: LB with specific variables (biomarker results)
message("\n--- Test 1: Profile LB biomarker variables ---")
result_lb <- profile_data(
  domain = "LB",
  variables = c("LBTESTCD", "LBSTRESC", "LBCAT", "LBMETHOD"),
  data_path = data_dir,
  output_path = output_dir
)

cat("\nLB Profile Results:\n")
cat("  Domain:", result_lb$domain, "\n")
cat("  Records:", result_lb$n_records, "\n")
cat("  Subjects:", result_lb$n_subjects, "\n")
cat("  Variables profiled:", paste(result_lb$variables_profiled, collapse = ", "), "\n")
cat("  Output file:", result_lb$output_file, "\n")
if (!is.null(result_lb$warnings)) {
  cat("  Warnings:", paste(result_lb$warnings, collapse = "; "), "\n")
}

# Test 2: MH with auto-detection
message("\n--- Test 2: Profile MH with auto-detection ---")
result_mh <- profile_data(
  domain = "MH",
  variables = NULL,  # Auto-detect
  data_path = data_dir,
  output_path = output_dir
)

cat("\nMH Profile Results:\n")
cat("  Domain:", result_mh$domain, "\n")
cat("  Records:", result_mh$n_records, "\n")
cat("  Subjects:", result_mh$n_subjects, "\n")
cat("  Variables profiled:", paste(result_mh$variables_profiled, collapse = ", "), "\n")
cat("  Output file:", result_mh$output_file, "\n")

# Test 3: QS (QSORRES is character, not numeric as plan might expect)
message("\n--- Test 3: Profile QS (ECOG) ---")
result_qs <- profile_data(
  domain = "QS",
  variables = c("QSCAT", "QSTESTCD", "QSORRES", "QSSTRESC", "VISIT"),
  data_path = data_dir,
  output_path = output_dir
)

cat("\nQS Profile Results:\n")
cat("  Domain:", result_qs$domain, "\n")
cat("  Records:", result_qs$n_records, "\n")
cat("  Subjects:", result_qs$n_subjects, "\n")
cat("  Variables profiled:", paste(result_qs$variables_profiled, collapse = ", "), "\n")
cat("  Output file:", result_qs$output_file, "\n")


# --- Display sample output ---
message("\n=== Sample Output: LB Profile (first 30 lines) ===\n")
lb_md <- readLines(result_lb$output_file)
cat(paste(head(lb_md, 30), collapse = "\n"))

message("\n\n=== Key Finding: Terminology Mismatch ===")
message("The LB profile shows biomarker results use mixed terminology:")
message("  - EGFR, BRAF: 'ALTERED' / 'NOT ALTERED'")
message("  - KRAS, ROS1, RET, NTRK: 'DETECTED' / 'NOT DETECTED'")
message("  - ALK: 'POSITIVE' / 'NEGATIVE'")
message("  - HER2, MET: 'AMPLIFIED' / 'NOT AMPLIFIED'")
message("  - PD-L1: 'HIGH' / 'LOW' / 'NEGATIVE'")
message("\nThis prevents assuming all biomarkers use 'POSITIVE'/'NEGATIVE' terminology!")

message("\n=== All profiles generated successfully ===")
message("Location: ", output_dir)
message("\nGenerated files:")
list.files(output_dir, pattern = "\\.md$", full.names = TRUE) %>%
  walk(~ cat("  -", .x, "\n"))
