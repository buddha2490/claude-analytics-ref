# Resolve Open Question

**Command:** `/resolve-question`

**Purpose:** Mark an open question as resolved with a decision and rationale.

**Usage:**

```bash
/resolve-question <id> resolution="<decision made>" [rationale="<additional context>"]
```

**Arguments:**

- `<id>` (required): Question ID (e.g., R1, W4, B2)
- `resolution="..."` (required): The decision or answer to the question
- `rationale="..."` (optional): Additional context for why this decision was made (if not already in YAML)

**Examples:**

```bash
# Resolve a warning-level question
/resolve-question W4 resolution="Use raw CMRSDISC values; no CT mapping needed"

# Resolve with additional rationale
/resolve-question W5 resolution="Based on temporal relationship to surgery date" rationale="Confirmed with clinical team on 2026-03-27"

# Resolve a blocking question
/resolve-question B1 resolution="Use RECIST 1.1 confirmed response" rationale="Per SAP section 9.2"
```

**What this does:**

1. Loads `open-questions.yaml` from the current project
2. Finds the question with the specified ID
3. Updates status to "resolved"
4. Records the resolution text
5. Timestamps the resolution with current date
6. Records the resolver (agent or user)
7. Writes back to YAML
8. Displays confirmation message

**When to use:**

- When you have made a decision on an open question
- Before implementing code that depends on the question's answer
- After discussing with clinical team or reviewing SAP/protocol
- When updating affected code to remove REVISIT comments

**Notes:**

- The question must already exist in `open-questions.yaml` (use `/list-open-questions` to see all questions)
- Resolving a question does not automatically update affected code files — you must do that separately
- The `affected_code` section in the YAML will still point to the original code locations
- Use `/check-revisit-comments` after resolving to ensure all linked code comments are updated

---

## Implementation

```r
# Parse command arguments
args <- commandArgs(trailingOnly = TRUE)

# Load management functions
source("R/manage_questions.R")

# Extract ID (first positional arg)
if (length(args) < 1) {
  stop("Usage: /resolve-question <id> resolution='...'", call. = FALSE)
}

question_id <- args[1]

# Extract resolution (required named argument)
resolution_arg <- grep("^resolution=", args, value = TRUE)
if (length(resolution_arg) == 0) {
  stop("Missing required argument: resolution='...'", call. = FALSE)
}

resolution <- sub("^resolution=", "", resolution_arg)
resolution <- gsub("^['\"]|['\"]$", "", resolution)  # Strip quotes

# Extract rationale (optional named argument)
rationale_arg <- grep("^rationale=", args, value = TRUE)
rationale <- if (length(rationale_arg) > 0) {
  r <- sub("^rationale=", "", rationale_arg)
  gsub("^['\"]|['\"]$", "", r)
} else {
  NULL
}

# Find open-questions.yaml in project
yaml_path <- ".claude/open-questions.yaml"
if (!file.exists(yaml_path)) {
  stop("open-questions.yaml not found at ", yaml_path, call. = FALSE)
}

# Resolve the question
resolve_question(
  yaml_path = yaml_path,
  id = question_id,
  resolution = resolution,
  resolved_by = "claude-code",
  resolved_date = Sys.Date()
)

# If rationale was provided, append it to the resolution field
if (!is.null(rationale)) {
  yaml_data <- yaml::read_yaml(yaml_path)
  idx <- which(purrr::map_chr(yaml_data$questions, ~ .x$id) == question_id)
  yaml_data$questions[[idx]]$rationale <- paste(
    yaml_data$questions[[idx]]$rationale,
    "\n[Additional context]:", rationale
  )
  yaml::write_yaml(yaml_data, yaml_path)
}

# Display the updated question
cat("\n")
cat("Question ", question_id, " marked as RESOLVED\n", sep = "")
cat("Resolution: ", resolution, "\n", sep = "")
cat("\n")
cat("Next steps:\n")
cat("1. Update affected code files to implement this decision\n")
cat("2. Add REVISIT comments linking to ", question_id, "\n", sep = "")
cat("3. Run /check-revisit-comments to validate linkage\n")
```
