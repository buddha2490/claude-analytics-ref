# Implementation Plan: Interactive HTML QA Reports for SDTM/ADaM
**Date:** 2026-03-29
**Status:** Draft
**Requested by:** Brian Carter

## 1. Overview

Build an interactive HTML-based QA reporting system for SDTM and ADaM datasets. The system will generate web-based reports with collapsible sections, interactive tables, and comprehensive variable summaries designed for internal QC reviewers performing variable-by-variable validation.

### Key Deliverables
1. Three specialized summary functions: `summarize_numeric()`, `summarize_character()`, `summarize_date()`
2. One intelligent wrapper function: `summarize_variable()`
3. Two main Quarto documents: `qa_sdtm.qmd` and `qa_adam.qmd`
4. Parameterized child template: `_qa_dataset.qmd`
5. Updated test execution scripts

## 2. Requirements

### Functional Requirements
- **Input**: Data frames or lists of data frames with XPT attributes preserved
- **Output**: HTML documents with interactive tables (DT or reactable)
- **Variable Type Detection**:
  - Numeric: Standard continuous variables
  - Character: Text and categorical variables
  - Date (numeric): Variables ending in "DT" (e.g., RFSTDTC → RFSTDT)
  - Date (character): Variables ending in "DTC" (e.g., RFSTDTC)
- **Summary Statistics**:
  - Numeric: N, Mean, SD, Median, Min, Max, n-missing
  - Character: N (%) for each level, including [Missing]
  - Date: Same as numeric but formatted as dates (YYYY-MM-DD)
- **Interactive Features**:
  - Collapsible sections by dataset
  - Searchable/filterable tables
  - Auto-generated table of contents from Quarto heading structure

### Non-Functional Requirements
- **Generalizability**: Functions accept any data frame with proper attributes
- **Performance**: Must handle 30-40 variables per dataset × 10+ datasets efficiently
- **Maintainability**: Clear separation of concerns between summary logic and presentation
- **CDISC Compliance**: Professional titles, labels, and footnotes per TFL standards

## 3. Current State Assessment

### Existing Implementation (`R/create_variable_summary_table.R`)
**Strengths:**
- Solid input validation pattern
- Proper handling of variable attributes (labels)
- Comprehensive missing value handling
- Good separation between character and numeric logic
- Complete Word document generation workflow with `officer` and `flextable`

**What We Keep:**
- Core summary logic (Mean/SD calculation, frequency tables, missing counts)
- Input validation pattern
- Variable attribute extraction
- The three-function structure: individual summaries + wrapper + document generator

**What We Change:**
- Replace `flextable` with `DT::datatable()` or `reactable::reactable()`
- Replace `officer` Word document generation with Quarto parameterized reports
- Extract summary functions into separate, more specialized implementations
- Add date variable detection and formatting
- Switch from page-break-separated Word sections to collapsible HTML sections

### Relevant Packages
**Currently used:**
- `dplyr`, `tidyr`, `tibble` — data manipulation (keep)
- `glue` — string interpolation (keep)
- `haven` — reading XPT with attributes (keep)
- `flextable`, `officer` — Word generation (remove)

**To add:**
- `DT` or `reactable` — interactive HTML tables
- `quarto` — document generation (already available via RStudio/CLI)

### Known Constraints
- XPT files are already generated and stored in `projects/exelixis-sap/output-data/{sdtm,adam}/`
- Variable attributes (labels, formats) must be preserved from XPT reads
- Reports must deploy to Posit Connect (HTML is ideal for this)

## 4. Proposed Design

### Architecture

```
Quarto Document (qa_sdtm.qmd)
├── Load all SDTM datasets from output-data/sdtm/
├── For each dataset:
│   └── Render _qa_dataset.qmd child template
│       ├── Dataset heading (##)
│       ├── Contents table (interactive DT)
│       ├── Variable heading (###) for each variable
│       └── summarize_variable(data, var_name) → HTML table
└── Auto-generated TOC from ## and ### structure
```

### Function Design

#### `summarize_numeric(data, var_name) → data.frame`
**Purpose:** Calculate summary statistics for a numeric variable.

**Logic:**
```r
# Remove NAs for clean statistics
var_clean <- var_data[!is.na(var_data)]

# Calculate
n_obs <- length(var_clean)
mean_val <- mean(var_clean, na.rm = TRUE)
sd_val <- sd(var_clean, na.rm = TRUE)
median_val <- median(var_clean, na.rm = TRUE)
min_val <- min(var_clean, na.rm = TRUE)
max_val <- max(var_clean, na.rm = TRUE)
n_missing <- sum(is.na(var_data))

# Return data frame
tibble(
  Statistic = c("N", "Mean", "SD", "Median", "Min", "Max", "Missing"),
  Value = c(n_obs, mean_val, sd_val, median_val, min_val, max_val, n_missing)
)
```

**Returns:** Two-column data frame (Statistic, Value) suitable for passing to `DT::datatable()`.

#### `summarize_character(data, var_name) → data.frame`
**Purpose:** Calculate frequency table for character/factor variable.

**Logic:**
```r
# Frequency table
summary_df <- data %>%
  count(.data[[var_name]], name = "N") %>%
  mutate(
    Percent = round(N / sum(N) * 100, 1),
    `N (%)` = paste0(N, " (", Percent, "%)")
  ) %>%
  select(Category = 1, `N (%)`)

# Add missing row if applicable
if (any(is.na(data[[var_name]]))) {
  n_missing <- sum(is.na(data[[var_name]]))
  pct_missing <- round(n_missing / nrow(data) * 100, 1)
  missing_row <- tibble(
    Category = "[Missing]",
    `N (%)` = paste0(n_missing, " (", pct_missing, "%)")
  )
  summary_df <- bind_rows(summary_df, missing_row)
}

return(summary_df)
```

**Returns:** Two-column data frame (Category, N (%)) suitable for passing to `DT::datatable()`.

#### `summarize_date(data, var_name) → data.frame`
**Purpose:** Calculate summary statistics for a date variable, treating it as numeric but formatting output as dates.

**Logic:**
```r
# Same calculation as numeric
var_clean <- var_data[!is.na(var_data)]
n_obs <- length(var_clean)
min_val <- min(var_clean, na.rm = TRUE)
max_val <- max(var_clean, na.rm = TRUE)
median_val <- median(var_clean, na.rm = TRUE)
mean_val <- mean(var_clean, na.rm = TRUE)
n_missing <- sum(is.na(var_data))

# Format dates using as.Date() with origin
tibble(
  Statistic = c("N", "Min Date", "Max Date", "Median Date", "Mean Date", "Missing"),
  Value = c(
    as.character(n_obs),
    as.character(as.Date(min_val, origin = "1970-01-01")),
    as.character(as.Date(max_val, origin = "1970-01-01")),
    as.character(as.Date(median_val, origin = "1970-01-01")),
    as.character(as.Date(mean_val, origin = "1970-01-01")),
    as.character(n_missing)
  )
)
```

**Returns:** Two-column data frame (Statistic, Value) with dates formatted as YYYY-MM-DD.

#### `summarize_variable(data, var_name, dataset_name = NULL) → htmlwidget`
**Purpose:** Intelligent wrapper that detects variable type and delegates to the appropriate summary function, then renders as an interactive HTML table.

**Logic:**
```r
# --- Validate inputs
if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
if (!var_name %in% names(data)) stop("Variable `", var_name, "` not found in dataset.", call. = FALSE)

# --- Extract variable
var_data <- data[[var_name]]

# --- Detect type and delegate
if (endsWith(var_name, "DT")) {
  # Date variable (numeric, ends with "DT")
  summary_df <- summarize_date(data, var_name)
} else if (is.numeric(var_data)) {
  # Numeric variable
  summary_df <- summarize_numeric(data, var_name)
} else if (is.character(var_data) || is.factor(var_data)) {
  # Character/Factor variable
  summary_df <- summarize_character(data, var_name)
} else {
  stop("Unsupported variable type: ", class(var_data)[1], call. = FALSE)
}

# --- Render as interactive table
DT::datatable(
  summary_df,
  options = list(
    pageLength = 25,
    dom = 't',  # Hide search box and pagination for small tables
    ordering = FALSE
  ),
  rownames = FALSE,
  class = 'cell-border stripe'
)
```

**Returns:** DT htmlwidget object that renders directly in Quarto HTML output.

### Quarto Document Structure

#### Main Document: `qa_sdtm.qmd`

```yaml
---
title: "SDTM QA Report"
subtitle: "Variable-by-Variable Quality Review"
author: "Brian Carter"
date: "`r Sys.Date()`"
format:
  html:
    toc: true
    toc-depth: 3
    toc-location: left
    theme: cosmo
    code-fold: true
    embed-resources: true
---
```

**Body:**
```r
# Setup
library(tidyverse)
library(DT)
library(haven)
library(glue)

source("../../R/summarize_variable.R")

# Load all SDTM datasets
sdtm_files <- list.files(
  "output-data/sdtm",
  pattern = "\\.xpt$",
  full.names = TRUE
)
sdtm_names <- toupper(tools::file_path_sans_ext(basename(sdtm_files)))
sdtm <- lapply(sdtm_files, haven::read_xpt)
names(sdtm) <- sdtm_names

# Render child template for each dataset
for (dataset_name in names(sdtm)) {
  knitr::knit_child(
    "_qa_dataset.qmd",
    envir = environment(),
    quiet = TRUE
  ) %>% cat()
}
```

#### Child Template: `_qa_dataset.qmd`

```markdown
## `r dataset_name`

**Records:** `r nrow(sdtm[[dataset_name]])`
**Variables:** `r ncol(sdtm[[dataset_name]])`

### Dataset Contents

[Contents table code here using DT::datatable()]

### Variable Summaries

[Loop through each variable, create ### heading, render table]
```

**Detailed child logic:**
```r
dataset <- sdtm[[dataset_name]]
var_names <- names(dataset)

# Contents table
contents_df <- tibble(
  Variable = var_names,
  Type = sapply(var_names, function(v) {
    if (is.numeric(dataset[[v]])) "Num" else "Char"
  }),
  Label = sapply(var_names, function(v) {
    lbl <- attr(dataset[[v]], "label")
    if (is.null(lbl) || lbl == "") v else lbl
  })
)

DT::datatable(contents_df, options = list(pageLength = 50), rownames = FALSE)

# Variable summaries
for (var_name in var_names) {
  cat("\n\n###", var_name, "\n\n")

  var_label <- attr(dataset[[var_name]], "label")
  if (!is.null(var_label) && var_label != "") {
    cat("**Label:**", var_label, "\n\n")
  }

  print(summarize_variable(dataset, var_name, dataset_name))
}
```

### Interactive Table Implementation: DT vs reactable

**Recommendation: Use `DT`**

| Criterion | DT | reactable |
|-----------|-----|-----------|
| Ease of use | ✅ Simple API | ⚠️ More verbose |
| Search/filter | ✅ Built-in | ✅ Built-in |
| Collapsible | ❌ Not native (use Quarto sections) | ✅ Native row details |
| CRAN maturity | ✅ Stable, widely used | ✅ Stable |
| Pharma adoption | ✅ Common in clinical | ⚠️ Less common |
| Size | ⚠️ Larger bundle | ✅ Smaller |

**Decision:** Use `DT` for simplicity and pharma-industry familiarity. Implement collapsibility using Quarto's native section folding (details/summary HTML elements) rather than relying on table package features.

### Collapsible Sections Implementation

Use Quarto's built-in `.callout-note` or HTML `<details>` tags:

**Option 1: Quarto Callout (Recommended)**
```markdown
::: {.callout-note collapse="true"}
## Dataset: DM

[Contents and variable tables here]
:::
```

**Option 2: Raw HTML details tag**
```html
<details>
<summary><strong>Dataset: DM</strong></summary>

[Contents and variable tables here]

</details>
```

**Recommendation:** Use Quarto callout blocks — they're styled, accessible, and integrate with the document theme.

## 5. Enhancements (Beyond Original Request)

### Enhancement 1: Validation Flag Summary
**Description:** Add a summary count at the top of each dataset section showing how many variables have missing values, how many are 100% populated, and what percentage of records are complete across all variables.

**Rationale:** Gives reviewers an at-a-glance quality indicator before diving into variable-by-variable detail. Helps prioritize which datasets need closer scrutiny.

**Implementation:**
```r
# Calculate completeness metrics
n_vars <- ncol(dataset)
n_obs <- nrow(dataset)
missing_by_var <- sapply(names(dataset), function(v) sum(is.na(dataset[[v]])))
n_vars_with_missing <- sum(missing_by_var > 0)
n_vars_complete <- sum(missing_by_var == 0)
pct_records_complete <- round(
  sum(complete.cases(dataset)) / n_obs * 100, 1
)

cat("\n\n**Data Quality Summary:**\n")
cat("- Variables with missing values:", n_vars_with_missing, "/", n_vars, "\n")
cat("- Variables 100% complete:", n_vars_complete, "/", n_vars, "\n")
cat("- Records with complete data:", pct_records_complete, "%\n\n")
```

### Enhancement 2: Cross-Dataset Variable Comparison
**Description:** At the end of the report, generate a "Common Variables Across Datasets" table showing which variables (e.g., USUBJID, STUDYID) appear in multiple datasets and whether their attributes are consistent.

**Rationale:** Catches cross-domain inconsistencies (e.g., STUDYID labeled differently in DM vs AE). Critical for CDISC compliance.

**Implementation:**
```r
# After all datasets loaded
all_var_info <- map_dfr(names(sdtm), function(ds) {
  tibble(
    Dataset = ds,
    Variable = names(sdtm[[ds]]),
    Label = sapply(names(sdtm[[ds]]), function(v) attr(sdtm[[ds]][[v]], "label") %||% "")
  )
})

common_vars <- all_var_info %>%
  group_by(Variable) %>%
  filter(n() > 1) %>%
  arrange(Variable, Dataset)

DT::datatable(common_vars, options = list(pageLength = 50))
```

### Enhancement 3: Automatic Detection of CDISC Identifier Violations
**Description:** Check that `USUBJID` is unique within subjects, `--SEQ` variables are unique within USUBJID, and all domain keys exist in DM.

**Rationale:** Catches the most common CDISC compliance errors. Highlights these in red callout boxes at the top of each dataset section.

**Implementation:**
```r
# Check USUBJID uniqueness
if ("USUBJID" %in% names(dataset)) {
  n_unique <- n_distinct(dataset$USUBJID)
  n_total <- nrow(dataset)
  if (dataset_name == "DM" && n_unique != n_total) {
    cat("::: {.callout-warning}\n")
    cat("**CDISC Violation:** USUBJID is not unique in DM domain.\n")
    cat(":::\n\n")
  }
}

# Check --SEQ uniqueness
seq_var <- paste0(dataset_name, "SEQ")
if (seq_var %in% names(dataset) && "USUBJID" %in% names(dataset)) {
  dup_check <- dataset %>%
    group_by(USUBJID, .data[[seq_var]]) %>%
    filter(n() > 1)

  if (nrow(dup_check) > 0) {
    cat("::: {.callout-warning}\n")
    cat("**CDISC Violation:**", seq_var, "is not unique within USUBJID.\n")
    cat("Duplicates found:", nrow(dup_check), "records.\n")
    cat(":::\n\n")
  }
}
```

## 6. Risks and Mitigations

### Risk 1: DT Tables Don't Render in Quarto
**Likelihood:** Low
**Impact:** High
**Mitigation:**
- DT is designed for R Markdown/Quarto and widely used in pharma.
- If issues arise, fall back to `knitr::kable()` + `kableExtra` for HTML styling.
- Test rendering early in implementation (first task).

### Risk 2: Large Datasets Cause Browser Performance Issues
**Likelihood:** Medium (if datasets have 50+ variables)
**Impact:** Medium
**Mitigation:**
- Use `DT` options `pageLength = 25` and `scrollY = "400px"` to limit initial render.
- For contents tables with many variables, consider pagination.
- Embed resources (`embed-resources: true`) to avoid external dependencies but monitor file size.

### Risk 3: Date Variable Detection Fails for Non-Standard Names
**Likelihood:** Medium
**Impact:** Low
**Mitigation:**
- Current rule: `endsWith(var_name, "DT")` catches CDISC standard date variables.
- If project uses non-standard names, add a parameter to `summarize_variable()` to explicitly declare date variables: `date_vars = c("CUSTOM_DATE1", "CUSTOM_DATE2")`.
- Document the detection rule in function roxygen comments.

### Risk 4: Quarto Child Template Rendering Issues
**Likelihood:** Medium
**Impact:** Medium
**Mitigation:**
- Child templates in Quarto can be finicky with namespace/environment.
- Pass `envir = environment()` explicitly to `knitr::knit_child()`.
- Use `cat()` to output child results immediately.
- Test with a single dataset before looping through all.

## 7. Testing Strategy

### Unit Tests (testthat)

**File:** `tests/test-summarize_variable.R`

Test coverage:
1. `summarize_numeric()`:
   - Standard numeric variable with no NAs
   - Variable with some NAs
   - Variable that is 100% NA
2. `summarize_character()`:
   - Character variable with multiple levels
   - Variable with NAs
   - Factor variable (should behave identically to character)
3. `summarize_date()`:
   - Date variable (numeric origin date)
   - Verify date formatting (YYYY-MM-DD)
4. `summarize_variable()` wrapper:
   - Correctly routes to `summarize_numeric()` for numeric
   - Correctly routes to `summarize_character()` for character
   - Correctly routes to `summarize_date()` for "*DT" variables
   - Errors appropriately for unsupported types
   - Errors appropriately for missing variable names

### Integration Tests

**File:** `projects/exelixis-sap/test-qa-html-render.R`

Test workflow:
1. Load a single SDTM dataset (DM)
2. Call `summarize_variable()` on 3-5 variables of different types
3. Verify that returned object is a `htmlwidget` (DT table)
4. Render a minimal Quarto document with one dataset using the child template
5. Verify HTML file is created and openable in browser

### Validation Approach

**Manual QC Checklist:**
- [ ] Numeric summaries match SAS PROC MEANS output (spot-check 3 variables)
- [ ] Character frequencies match SAS PROC FREQ output (spot-check 3 variables)
- [ ] Date formatting is correct (YYYY-MM-DD, not numeric)
- [ ] Missing counts are accurate (compare to `PROC MEANS NMISS` or `PROC FREQ MISSING`)
- [ ] Interactive features work (search, sort, collapse)
- [ ] TOC navigation works in HTML output
- [ ] Titles/subtitles/footnotes are professional and CDISC-compliant
- [ ] Report deploys successfully to Posit Connect

## 8. Orchestration Guide

### Task Breakdown

| Task | Agent | Priority | Dependencies | Description |
|------|-------|----------|--------------|-------------|
| T1 | r-clinical-programmer | P1 | None | Implement `summarize_numeric()`, `summarize_character()`, `summarize_date()` in `R/summarize_variable.R` with full roxygen2 documentation and input validation |
| T2 | r-clinical-programmer | P1 | T1 | Implement `summarize_variable()` wrapper function with type detection logic and DT rendering |
| T3 | r-clinical-programmer | P1 | T1 | Write comprehensive unit tests in `tests/test-summarize_variable.R` covering all functions and edge cases |
| T4 | r-clinical-programmer | P2 | T2, T3 | Create Quarto child template `projects/exelixis-sap/_qa_dataset.qmd` with contents table and variable loop |
| T5 | r-clinical-programmer | P2 | T4 | Create main Quarto document `projects/exelixis-sap/qa_sdtm.qmd` that loads SDTM datasets and renders child template for each |
| T6 | r-clinical-programmer | P2 | T4 | Create main Quarto document `projects/exelixis-sap/qa_adam.qmd` (parallel to T5 but for ADaM datasets) |
| T7 | r-clinical-programmer | P2 | T2 | Create integration test script `projects/exelixis-sap/test-qa-html-render.R` to validate end-to-end rendering |
| T8 | r-clinical-programmer | P3 | T5, T6, T7 | Implement Enhancement 1 (validation flag summary) in child template |
| T9 | r-clinical-programmer | P3 | T5, T6 | Implement Enhancement 2 (cross-dataset variable comparison) at end of main Quarto docs |
| T10 | r-clinical-programmer | P3 | T5, T6 | Implement Enhancement 3 (CDISC identifier violation detection) in child template |
| T11 | clinical-code-reviewer | P2 | T1-T7 | Independent QC review of core implementation against plan. Run unit tests and integration tests. Produce QC report. |
| T12 | clinical-code-reviewer | P3 | T8-T10, T11 | Independent QC review of enhancements. Verify CDISC compliance checks are accurate. Produce final QC report. |

### Execution Sequence

**Phase 1: Core Functions (T1-T3)**
- Implement all summary functions in a single file `R/summarize_variable.R`
- Each function must be independently tested before proceeding
- Validate that DT rendering works in an R console session

**Phase 2: Quarto Documents (T4-T7)**
- Start with child template (T4) — easier to debug in isolation
- Render a single dataset manually before automating the loop
- Create SDTM and ADaM main docs in parallel (T5, T6)
- Integration test (T7) verifies that rendering completes without errors

**Phase 3: Enhancements (T8-T10)**
- These are optional but high-value
- Can be implemented incrementally after core is working
- Each enhancement should be in its own clearly marked code section

**Phase 4: QC Review (T11-T12)**
- Reviewer runs all tests independently
- Reviewer manually inspects generated HTML for correctness
- Reviewer compares spot-check statistics to SAS output if available
- Reviewer verifies CDISC compliance of enhancements

### Agent-Specific Notes

**For r-clinical-programmer:**
- Follow the r-code skill workflow: write function → write test → source both → validate
- Use the existing `create_variable_summary_table.R` as a reference but DO NOT modify it (preserve Word generation capability)
- All new code goes in `R/summarize_variable.R`
- Test interactively in RStudio to verify DT tables render before writing Quarto docs
- When creating Quarto docs, render them manually first (`quarto render qa_sdtm.qmd`) before considering the task complete

**For clinical-code-reviewer:**
- This is a deliverable that QC reviewers will use, so review with extra scrutiny
- Verify statistical correctness — spot-check mean/SD/min/max against manual calculation
- Check for off-by-one errors in missing counts
- Verify date formatting uses correct origin
- Confirm that CDISC identifier checks (Enhancement 3) use correct logic per `cdisc-conventions.md`
- HTML output must be professional and publication-ready

## 9. File Locations and Naming

```
claude-analytics-ref/
├── R/
│   ├── summarize_variable.R              # New file: all four summary functions
│   └── create_variable_summary_table.R   # Existing file: DO NOT MODIFY
├── tests/
│   └── test-summarize_variable.R         # New file: unit tests
└── projects/exelixis-sap/
    ├── programs/
    │   ├── sdtm/                          # SDTM simulation programs (sim_*.R)
    │   ├── adam/                          # ADaM derivation programs (adam_*.R)
    │   └── utils/                         # Utility and validation scripts
    ├── _qa_dataset.qmd                    # New file: child template
    ├── qa_sdtm.qmd                        # New file: main SDTM report
    ├── qa_adam.qmd                        # New file: main ADaM report
    ├── test-qa-html-render.R              # New file: integration test
    ├── qa-data-analysis.R                 # Existing file: DO NOT MODIFY (Word generation)
    ├── test-qa-single.R                   # Existing file: DO NOT MODIFY
    └── output-reports/
        ├── qa_sdtm.html                   # Generated output
        └── qa_adam.html                   # Generated output
```

## 10. Implementation Notes

### Key Design Decisions

1. **Separate summary functions instead of one monolithic function:** Easier to test, debug, and extend. Each function has a single responsibility.

2. **Return data frames from summary functions, not htmlwidgets:** Separation of concerns. Summary logic is pure computation, rendering is presentation. Makes unit testing simpler (can use `expect_equal()` on data frames).

3. **Type detection in the wrapper:** Keeps summary functions focused. The wrapper handles the "which function to call" logic.

4. **DT over reactable:** Simpler API, better pharma adoption, more mature ecosystem. Collapsibility handled by Quarto, not the table package.

5. **Child template pattern:** Avoids copy-paste between SDTM and ADaM reports. Single source of truth for dataset rendering logic.

6. **Quarto over R Markdown:** Modern successor to R Markdown with better HTML theming, easier TOC configuration, and better cross-format support (future-proofs for PDF if needed).

### Compatibility with Existing Code

- The existing `create_variable_summary_table.R` and Word generation scripts (`qa-data-analysis.R`, `test-qa-single.R`) are **preserved unchanged**.
- Users can continue to generate Word documents using the existing workflow.
- The new HTML workflow is a parallel track, not a replacement.
- Both workflows can coexist — HTML for internal QC review, Word for final deliverables.

### Deployment to Posit Connect

Once HTML reports are generated, deployment is straightforward:

```r
# Using rsconnect package
library(rsconnect)

rsconnect::deployDoc(
  "projects/exelixis-sap/qa_sdtm.qmd",
  appTitle = "SDTM QA Report",
  server = "connect.company.com"
)
```

Quarto HTML reports with `embed-resources: true` are self-contained and deploy as a single file. No external dependencies required.

---

**End of Implementation Plan**

**Next Steps:**
1. User review and approval of this plan
2. Spawn `r-clinical-programmer` agent with Task T1
3. Proceed through orchestration guide sequentially
