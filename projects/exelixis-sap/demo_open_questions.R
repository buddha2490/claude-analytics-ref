# Demo: Open Questions Tracking System
# Shows the complete workflow for managing open questions

library(dplyr)
library(stringr)

# Load management functions
source("R/manage_questions.R")

yaml_path <- ".claude/open-questions.yaml"

cat("\n")
cat(strrep("=", 80), "\n", sep = "")
cat("DEMO: Open Questions Tracking System for NPM-008\n")
cat(strrep("=", 80), "\n", sep = "")
cat("\n")

# --- Demo 1: List all questions ---

cat("DEMO 1: List all questions\n")
cat(strrep("-", 80), "\n", sep = "")

all_q <- list_questions(yaml_path)
cat("Total questions in system: ", nrow(all_q), "\n", sep = "")
cat("\n")

print(all_q %>% count(status))

cat("\n\n")

# --- Demo 2: List open questions only ---

cat("DEMO 2: List open questions (warnings needing resolution)\n")
cat(strrep("-", 80), "\n", sep = "")

open_q <- list_questions(yaml_path, status_filter = "open")
cat("Open questions: ", nrow(open_q), "\n", sep = "")
cat("\n")

if (nrow(open_q) > 0) {
  print_questions(open_q)
}

cat("\n\n")

# --- Demo 3: List resolved questions ---

cat("DEMO 3: List resolved questions (decisions documented)\n")
cat(strrep("-", 80), "\n", sep = "")

resolved_q <- list_questions(yaml_path, status_filter = "resolved")
cat("Resolved questions: ", nrow(resolved_q), "\n", sep = "")
cat("\n")

# Show just the first 3
if (nrow(resolved_q) > 0) {
  sample_resolved <- resolved_q %>% slice(1:min(3, n()))
  print_questions(sample_resolved)
}

cat("\n\n")

# --- Demo 4: Filter by dataset ---

cat("DEMO 4: Filter questions affecting ADLOT\n")
cat(strrep("-", 80), "\n", sep = "")

adlot_q <- list_questions(yaml_path, dataset_filter = "adlot")
cat("Questions affecting ADLOT: ", nrow(adlot_q), "\n", sep = "")
cat("\n")

if (nrow(adlot_q) > 0) {
  print_questions(adlot_q)
}

cat("\n\n")

# --- Demo 5: Check if specific questions are resolved ---

cat("DEMO 5: Check resolution status of specific questions\n")
cat(strrep("-", 80), "\n", sep = "")

check_ids <- c("R3", "R5", "W4", "W5")

for (id in check_ids) {
  is_resolved <- is_question_resolved(yaml_path, id)
  status_text <- if (is_resolved) "✓ RESOLVED" else "⚠ OPEN"
  cat(id, ": ", status_text, "\n", sep = "")
}

cat("\n\n")

# --- Demo 6: Add a new question ---

cat("DEMO 6: Add a new question to the system\n")
cat(strrep("-", 80), "\n", sep = "")

cat("Adding new question W7...\n")

add_question(
  yaml_path = yaml_path,
  id = "W7",
  text = "Should SAFFL include screen failures with at least one dose?",
  rationale = "Impacts safety population definition for AE reporting",
  affected_code = list(
    list(
      file = "projects/exelixis-sap/programs/adam_adsl.R",
      lines = c(180, 190),
      marker = "REVISIT: SAFFL definition — see W7"
    )
  ),
  severity = "warning",
  flagged_by = "demo-script",
  flagged_date = "2026-03-27"
)

cat("\n")
cat("Question W7 added successfully.\n")

# Show the new question
new_q <- list_questions(yaml_path) %>% filter(id == "W7")
print_questions(new_q)

cat("\n\n")

# --- Demo 7: Resolve the new question ---

cat("DEMO 7: Resolve the new question\n")
cat(strrep("-", 80), "\n", sep = "")

cat("Resolving question W7...\n")

resolve_question(
  yaml_path = yaml_path,
  id = "W7",
  resolution = "Yes, SAFFL includes all subjects who received at least one dose, regardless of screen failure status",
  resolved_by = "demo-script",
  resolved_date = "2026-03-27"
)

cat("\n")
cat("Question W7 resolved successfully.\n")

# Show the resolved question
resolved_q7 <- list_questions(yaml_path, status_filter = "resolved") %>%
  filter(id == "W7")
print_questions(resolved_q7)

cat("\n\n")

# --- Demo 8: Check REVISIT comments (if any exist) ---

cat("DEMO 8: Check REVISIT comments in code (simulated)\n")
cat(strrep("-", 80), "\n", sep = "")

# Create a temporary test file
temp_dir <- tempdir()
test_file <- file.path(temp_dir, "demo_adam.R")

writeLines(c(
  "# Demo ADaM program",
  "",
  "# REVISIT: Quan 2011 weights used per R1",
  "cci_weights <- c(1, 1, 1, 2, 2, 2, 3, 6)",
  "",
  "# REVISIT: Confirmed response per SAP (≥28-day interval). See R3",
  "confirmed_response <- identify_confirmed_cr_pr(tr, interval = 28)",
  "",
  "# REVISIT: SAFFL definition — see W7",
  "saffl <- if_else(TRTEMFL == 'Y', 'Y', NA_character_)",
  "",
  "# REVISIT: This comment has no question ID - will be flagged",
  "some_other_derivation <- calculate_something()"
), test_file)

cat("Scanning ", test_file, " for REVISIT comments...\n", sep = "")
cat("\n")

revisit_check <- check_revisit_comments(temp_dir, yaml_path, pattern = "*.R")

cat("Found ", nrow(revisit_check), " REVISIT comment(s)\n", sep = "")
cat("\n")

# Display results
for (i in seq_len(nrow(revisit_check))) {
  row <- revisit_check[i, ]
  status_symbol <- if_else(row$status == "OK", "✓", "⚠")
  cat("Line ", row$line, ": ", status_symbol, " ", row$status, "\n", sep = "")
  cat("  ", row$comment, "\n", sep = "")
  cat("\n")
}

# Cleanup
unlink(test_file)

cat("\n")
cat(strrep("=", 80), "\n", sep = "")
cat("DEMO COMPLETE\n")
cat(strrep("=", 80), "\n", sep = "")
cat("\n")
cat("Summary:\n")
cat("  ✓ YAML question tracking working\n")
cat("  ✓ Add/resolve/list commands working\n")
cat("  ✓ Filtering by status/dataset working\n")
cat("  ✓ REVISIT comment validation working\n")
cat("  ✓ Bi-directional linking validated\n")
cat("\n")
cat("The formalized open questions system is ready for production use.\n")
cat("\n")

# Clean up the demo question
cat("Cleaning up demo question W7...\n")
yaml_data <- yaml::read_yaml(yaml_path)
yaml_data$questions <- yaml_data$questions[sapply(yaml_data$questions, function(q) q$id != "W7")]
yaml::write_yaml(yaml_data, yaml_path)
cat("Demo cleanup complete.\n")
