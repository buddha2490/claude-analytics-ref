---
name: cohort-cascade
description: Use when building a feasibility cohort via sequential exclusion criteria. Governs the df → df1/df2/... → cohort pattern with cumulative exclusion flags.
---

# Cohort Exclusion Cascade Skill

This skill governs the coding pattern for all feasibility cohort programs. It is invoked whenever a program applies sequential inclusion/exclusion criteria to derive an analytic cohort.

## Core Pattern

Exclusions are applied **cumulatively** by mutating dummy flag variables onto successive data frames. The data is never filtered mid-cascade — this preserves the full dataset for diagnostics and attrition counts.

```
df          raw ADS pulled from Databricks
df1         df  + ex1 (exclusion flag for criterion 1)
df2         df1 + ex2 (exclusion flag for criterion 2)
df3         df2 + ex3 (...)
...
cohort      dfN with a single integer `exclusion` variable derived via case_when()
```

## Step Template

Each criterion follows this exact pattern:

```r
# --- Step N: Short description of criterion ----------------------------------

message("\n--- Step N: Short description ---")

dfN <- dfN_minus_1 %>%
  mutate(exN = ifelse(<condition_to_exclude>, 1, 0))

table(dfN$exN, useNA = "ifany")
```

Rules:
- **Flag encoding**: `1` = exclude, `0` = keep
- **Naming**: `df1`, `df2`, `df3`, ... (integer suffix, no skips)
- **One criterion per step** — do not combine multiple conditions into a single `exN` variable
- **Always follow each step with `table()`** using `useNA = "ifany"` to expose NAs that would silently be coded 0
- **`message()` headers** use the format `"\n--- Step N: Description ---"` with a leading newline for readability in the console

## Baseline Count (Step 0)

Always record a step-0 baseline before any exclusions:

```r
# --- Step 0: Baseline --------------------------------------------------------

message("\n--- Step 0: Baseline ---")

cases0 <- df %>%
  distinct(patientid) %>%
  nrow()

message("Baseline patients: ", cases0)
```

## Final Cohort Assembly

After all `exN` flags are applied, collapse to a single `exclusion` integer using `case_when()`. The value `99L` is the "keep" sentinel — patients who passed all criteria.

```r
# --- Analytic cohort ---------------------------------------------------------

cohort <- dfN %>%
  mutate(exclusion = case_when(
    ex1 == 1 ~ 1L,
    ex2 == 1 ~ 2L,
    ex3 == 1 ~ 3L,
    # ... one line per criterion
    TRUE     ~ 99L
  ))
```

Rules:
- Use integer literals (`1L`, `2L`, `99L`) — not doubles
- `case_when()` is evaluated in order, so earlier exclusions take precedence (first-exclusion-wins)
- `TRUE ~ 99L` must always be the last branch
- `99L` is the keep/cohort sentinel — never use it for an exclusion criterion

## Filter to Final Cohort

After building the `exclusion` variable and any downstream counts/tables that need the full exclusion column, filter to the analytic cohort:

```r
cohort <- cohort %>%
  dplyr::filter(exclusion == 99)
```

This line comes **after** attrition table construction — the full `cohort` with all exclusion values is needed for counting.

## Attrition Table Pattern

Build attrition counts from the pre-filter `cohort` (while all `exclusion` values are still present):

```r
criteria_labels <- tibble(
  exclusion = c(1L, 2L, 3L, ..., 99L),
  Row       = c("1", "2", "3", ..., "Cohort"),
  Criteria  = c(
    "Plain-language description of criterion 1 (exclusion direction)",
    "Plain-language description of criterion 2",
    # ...
    "Final analytic cohort"
  )
)

step_rows <- cohort %>%
  distinct(patientid, exclusion) %>%
  count(exclusion) %>%
  left_join(criteria_labels, by = "exclusion") %>%
  select(Row, Criteria, n)
```

- Write criteria labels as **exclusion-direction statements** (e.g., "Patients NOT diagnosed with SCLC") so the attrition table reads top-to-bottom as removals
- The `99L` row should be labeled `"Final analytic cohort"` and be the last row

## Patient Identifier

Always use `patientid` (not `USUBJID`). Count patients with `n_distinct(patientid)` — the ADS is long-form with multiple rows per patient. See the `ads-data` skill for full ADS structure details.

## Diagnostic Checks

After each step, verify the flag distribution:

```r
table(dfN$exN, useNA = "ifany")
```

Expected output for a valid step:
```
   0    1
8234  971
```

If all values are `0` or all are `1`, investigate before proceeding — the condition expression is likely wrong or the column name is incorrect.

## Exclusion Steps Using Nested JSON Columns

When an exclusion criterion requires data from a nested JSON column (e.g., `systemic_therapy`, `radiation_therapy`), parse the JSON into a separate patient-level vector, then join back via `patientid`:

```r
rt_patients <- dfN %>%
  select(patientid, radiation_therapy) %>%
  distinct(patientid, .keep_all = TRUE) %>%
  parse_json_col("radiation_therapy") %>%
  dplyr::filter(<RT condition>) %>%
  distinct(patientid) %>%
  pull(patientid)

dfN_plus_1 <- dfN %>%
  mutate(exN_plus_1 = ifelse(!patientid %in% rt_patients, 1, 0))
```

See the `ads-data` skill for `parse_json_col()` definition and the critical deduplicate-before-parsing rule.

## Full Program Skeleton

The data pull and `parse_json_col()` helper follow the `ads-data` skill. This skeleton starts after `df` is loaded:

```r
# =============================================================================
# Study:    <Study Name> (<Protocol Number>)
# Program:  cohort_<name>_<date>.R
# Date:     <YYYY-MM-DD>
# Author:   <Name>
# Purpose:  Sequential attrition table for the <cohort description>.
#           Assumes df is already loaded in the session (see ads-data skill).
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(jsonlite)
library(syhelpr)

# --- parse_json_col() defined per ads-data skill ---
# <include parse_json_col here if needed for nested column exclusions>

# --- Data pull per ads-data skill ---
df <- get_ads("<cohort>", type = "<enriched|essentials>") %>%
  collect()

# --- Step 0: Baseline --------------------------------------------------------

message("\n--- Step 0: Baseline ---")
cases0 <- df %>% distinct(patientid) %>% nrow()
message("Baseline patients: ", cases0)

# --- Step 1: <Criterion 1> ---------------------------------------------------

message("\n--- Step 1: <criterion description> ---")

df1 <- df %>%
  mutate(ex1 = ifelse(<exclude condition>, 1, 0))

table(df1$ex1, useNA = "ifany")

# --- Step 2: <Criterion 2> ---------------------------------------------------

message("\n--- Step 2: <criterion description> ---")

df2 <- df1 %>%
  mutate(ex2 = ifelse(<exclude condition>, 1, 0))

table(df2$ex2, useNA = "ifany")

# --- Analytic cohort ---------------------------------------------------------

cohort <- df2 %>%
  mutate(exclusion = case_when(
    ex1 == 1 ~ 1L,
    ex2 == 1 ~ 2L,
    TRUE     ~ 99L
  ))

# Build attrition table before filtering
# ... (see Attrition Table Pattern above)

cohort <- cohort %>%
  dplyr::filter(exclusion == 99)
```
