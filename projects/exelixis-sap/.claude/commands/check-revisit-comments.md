# Check REVISIT Comments

**Command:** `/check-revisit-comments`

**Purpose:** Scan code files for REVISIT comments and validate their linkage to questions in open-questions.yaml.

**Usage:**

```bash
/check-revisit-comments [directory]
```

**Arguments:**

- `directory` (optional): Directory to scan for R files. Defaults to `programs/` if not specified.

**Examples:**

```bash
# Check all programs
/check-revisit-comments

# Check specific directory
/check-revisit-comments R/

# Check a specific file's directory
/check-revisit-comments programs/
```

**What this checks:**

1. **Finds all REVISIT comments** in R code files
2. **Extracts question IDs** from comments (R1, W4, B2, etc.)
3. **Validates each ID:**
   - ✓ OK: Question ID exists in YAML and is resolved
   - ⚠ WARNING: REVISIT comment has no question ID
   - ✗ ERROR: Question ID referenced but not found in YAML
   - ⚠ WARNING: Question ID exists but is still open/deferred

**Output Format:**

```
================================================================================
REVISIT Comment Validation Report
================================================================================

Directory: projects/exelixis-sap/programs/
YAML: .claude/open-questions.yaml

Scanning 12 R files...

--------------------------------------------------------------------------------
File: adam_adsl.R
  Line 345: # REVISIT: Quan 2011 weights used per R1
    Status: ✓ OK (R1 resolved)

  Line 420: # REVISIT: Neoadjuvant/adjuvant definition — see W5
    Status: ⚠ WARNING (W5 still open)

--------------------------------------------------------------------------------
File: adam_adlot.R
  Line 144: # REVISIT: Using raw CMRSDISC
    Status: ⚠ WARNING (No question ID in comment)

  Line 220: # REVISIT: See X99 for guidance
    Status: ✗ ERROR (Question X99 not found in YAML)

--------------------------------------------------------------------------------

Summary:
  Total REVISIT comments: 25
  ✓ Valid (resolved): 18
  ⚠ Warnings: 5 (3 open questions, 2 missing IDs)
  ✗ Errors: 2 (invalid question IDs)

VERDICT: 2 issues require attention before QC sign-off
```

**When to use:**

- **Before code review**: Ensure all REVISIT comments are properly documented
- **After resolving questions**: Verify affected code has been updated
- **Before final analysis cut**: Ensure no open questions remain in production code
- **During QC**: Validate traceability between decisions and implementations

**Validation Rules:**

| Scenario | Status | Action Required |
|----------|--------|-----------------|
| Comment has ID, question resolved | ✓ OK | None |
| Comment has ID, question open | ⚠ WARNING | Resolve question or defer implementation |
| Comment has no ID | ⚠ WARNING | Add question to YAML or remove comment |
| Comment has invalid ID | ✗ ERROR | Fix ID or add question to YAML |

**Notes:**

- REVISIT comments should include the question ID at the end (e.g., "per R1", "see W4")
- The command scans `.R` files recursively in the specified directory
- Pattern matched: `REVISIT:` followed by optional text and question ID `[RWB]\d+`
- Use this command as part of the code review checklist

---

## Implementation

```r
# Parse command arguments
args <- commandArgs(trailingOnly = TRUE)

# Load management functions
source("R/manage_questions.R")

# Default directory
scan_dir <- if (length(args) > 0) args[1] else "programs/"

if (!dir.exists(scan_dir)) {
  stop("Directory not found: ", scan_dir, call. = FALSE)
}

# Find open-questions.yaml
yaml_path <- ".claude/open-questions.yaml"
if (!file.exists(yaml_path)) {
  stop("open-questions.yaml not found at ", yaml_path, call. = FALSE)
}

# --- Run Validation ---

cat(strrep("=", 80), "\n", sep = "")
cat("REVISIT Comment Validation Report\n")
cat(strrep("=", 80), "\n", sep = "")
cat("\n")
cat("Directory: ", scan_dir, "\n", sep = "")
cat("YAML: ", yaml_path, "\n", sep = "")
cat("\n")

# Count R files
r_files <- list.files(scan_dir, pattern = "*.R", full.names = TRUE, recursive = TRUE)
cat("Scanning ", length(r_files), " R file(s)...\n", sep = "")
cat("\n")

# Check REVISIT comments
results <- check_revisit_comments(scan_dir, yaml_path)

if (nrow(results) == 0) {
  cat("No REVISIT comments found.\n")
  quit(save = "no", status = 0)
}

# Load question status for validation
all_questions <- list_questions(yaml_path)

# Enhance results with question status
results <- results %>%
  left_join(
    all_questions %>% select(id, status, resolution),
    by = c("question_id" = "id")
  ) %>%
  mutate(
    validation_status = case_when(
      status.y == "OK" ~ "OK",
      !has_id ~ "WARNING",
      !id_exists ~ "ERROR",
      status.x == "open" ~ "WARNING_OPEN",
      status.x == "deferred" ~ "WARNING_DEFERRED",
      TRUE ~ "OK"
    )
  )

# --- Display Results by File ---

current_file <- ""
for (i in seq_len(nrow(results))) {
  row <- results[i, ]

  # Print file header if new file
  if (row$file != current_file) {
    cat(strrep("-", 80), "\n", sep = "")
    cat("File: ", basename(row$file), "\n", sep = "")
    current_file <- row$file
  }

  # Print line and comment
  cat("  Line ", row$line, ": ", row$comment, "\n", sep = "")

  # Print status
  status_symbol <- switch(
    row$validation_status,
    "OK" = "✓",
    "WARNING" = "⚠",
    "WARNING_OPEN" = "⚠",
    "WARNING_DEFERRED" = "⚠",
    "ERROR" = "✗"
  )

  status_msg <- switch(
    row$validation_status,
    "OK" = paste0(row$question_id, " resolved"),
    "WARNING" = "No question ID in comment",
    "WARNING_OPEN" = paste0(row$question_id, " still open"),
    "WARNING_DEFERRED" = paste0(row$question_id, " deferred"),
    "ERROR" = paste0("Question ", row$question_id, " not found in YAML")
  )

  cat("    Status: ", status_symbol, " ", status_msg, "\n", sep = "")
  cat("\n")
}

# --- Summary ---

cat(strrep("-", 80), "\n", sep = "")
cat("\n")
cat("Summary:\n")

total <- nrow(results)
ok_count <- sum(results$validation_status == "OK")
warning_count <- sum(startsWith(results$validation_status, "WARNING"))
error_count <- sum(results$validation_status == "ERROR")

open_question_count <- sum(results$validation_status == "WARNING_OPEN")
missing_id_count <- sum(results$validation_status == "WARNING")

cat("  Total REVISIT comments: ", total, "\n", sep = "")
cat("  ✓ Valid (resolved): ", ok_count, "\n", sep = "")
cat("  ⚠ Warnings: ", warning_count, " (", open_question_count,
    " open questions, ", missing_id_count, " missing IDs)\n", sep = "")
cat("  ✗ Errors: ", error_count, " (invalid question IDs)\n", sep = "")
cat("\n")

# Verdict
issues_count <- warning_count + error_count
if (issues_count > 0) {
  cat("VERDICT: ", issues_count, " issue(s) require attention before QC sign-off\n", sep = "")
  quit(save = "no", status = 1)
} else {
  cat("VERDICT: All REVISIT comments are properly linked to resolved questions ✓\n")
  quit(save = "no", status = 0)
}
```
