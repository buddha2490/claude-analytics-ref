# List Open Questions

**Command:** `/list-open-questions`

**Purpose:** Display questions from the open questions tracking system with optional filters.

**Usage:**

```bash
/list-open-questions [status=<status>] [dataset=<name>] [severity=<level>]
```

**Arguments:**

All arguments are optional. If none provided, lists all questions.

- `status=<status>`: Filter by status (open, resolved, deferred)
- `dataset=<name>`: Filter by affected dataset (e.g., ADSL, ADAE, ADTTE)
- `severity=<level>`: Filter by severity (info, warning, blocking)

**Examples:**

```bash
# List all open questions
/list-open-questions

# List only resolved questions
/list-open-questions status=resolved

# List open questions affecting ADLOT
/list-open-questions status=open dataset=ADLOT

# List all blocking questions
/list-open-questions severity=blocking

# List resolved questions for ADRS
/list-open-questions status=resolved dataset=ADRS
```

**Output Format:**

```
================================================================================
Open Questions Summary
================================================================================

Project: NPM-008 / Exelixis XB010-100
File: .claude/open-questions.yaml
Total questions: 12 (8 resolved, 3 open, 1 deferred)

Filters applied:
  Status: open
  Dataset: ADLOT

--------------------------------------------------------------------------------
ID: W4 | Status: OPEN | Severity: warning
Question: What are the controlled terminology values for LOTENDRSN?
Affected files: projects/exelixis-sap/programs/adam_adlot.R
Flagged by: clinical-code-reviewer on 2026-03-27
--------------------------------------------------------------------------------

1 question(s) displayed
```

**When to use:**

- At the start of implementing a new dataset (check for open questions affecting it)
- During code review to verify all questions are resolved
- To see what decisions have been made (filter by resolved)
- To track blocking issues that need resolution before proceeding
- To generate a question summary for stakeholder review

**Notes:**

- Questions are loaded from `.claude/open-questions.yaml` in the current project
- Dataset filter searches the `affected_code.file` paths (case-insensitive)
- The summary line shows counts by status for situational awareness
- Empty result sets display "No questions match the specified filters"

---

## Implementation

```r
# Parse command arguments
args <- commandArgs(trailingOnly = TRUE)

# Load management functions
source("R/manage_questions.R")

# Extract filters
status_filter <- NULL
dataset_filter <- NULL
severity_filter <- NULL

for (arg in args) {
  if (grepl("^status=", arg)) {
    status_filter <- sub("^status=", "", arg)
  } else if (grepl("^dataset=", arg)) {
    dataset_filter <- sub("^dataset=", "", arg)
  } else if (grepl("^severity=", arg)) {
    severity_filter <- sub("^severity=", "", arg)
  }
}

# Find open-questions.yaml
yaml_path <- ".claude/open-questions.yaml"
if (!file.exists(yaml_path)) {
  stop("open-questions.yaml not found at ", yaml_path, call. = FALSE)
}

# Load all questions for summary stats
all_questions <- list_questions(yaml_path)

# Apply filters
filtered_questions <- list_questions(
  yaml_path = yaml_path,
  status_filter = status_filter,
  dataset_filter = dataset_filter
)

# Apply severity filter if specified (not in main function)
if (!is.null(severity_filter)) {
  filtered_questions <- filtered_questions %>%
    filter(severity == severity_filter)
}

# --- Display Results ---

cat(strrep("=", 80), "\n", sep = "")
cat("Open Questions Summary\n")
cat(strrep("=", 80), "\n", sep = "")
cat("\n")

# Summary stats
status_counts <- all_questions %>%
  count(status) %>%
  arrange(status)

total_questions <- nrow(all_questions)
resolved_count <- sum(status_counts$n[status_counts$status == "resolved"])
open_count <- sum(status_counts$n[status_counts$status == "open"])
deferred_count <- sum(status_counts$n[status_counts$status == "deferred"])

cat("Project: NPM-008 / Exelixis XB010-100\n")
cat("File: ", yaml_path, "\n", sep = "")
cat("Total questions: ", total_questions,
    " (", resolved_count, " resolved, ",
    open_count, " open, ",
    deferred_count, " deferred)\n", sep = "")
cat("\n")

# Display active filters
if (!is.null(status_filter) || !is.null(dataset_filter) || !is.null(severity_filter)) {
  cat("Filters applied:\n")
  if (!is.null(status_filter)) cat("  Status: ", status_filter, "\n", sep = "")
  if (!is.null(dataset_filter)) cat("  Dataset: ", dataset_filter, "\n", sep = "")
  if (!is.null(severity_filter)) cat("  Severity: ", severity_filter, "\n", sep = "")
  cat("\n")
}

# Print questions
if (nrow(filtered_questions) == 0) {
  cat("No questions match the specified filters.\n")
} else {
  print_questions(filtered_questions)
  cat("\n", nrow(filtered_questions), " question(s) displayed\n", sep = "")
}
```
