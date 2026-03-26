# Implementation Plan: Histology by Diagnosis Month Table (2025)

**Date:** 2026-03-26
**Status:** Draft
**Requested by:** User

## 1. Overview

Produce a formatted RTF table that cross-tabulates `histology_subgroup` (12 levels) by month of diagnosis for calendar year 2025. The table shows unique patient counts per cell, with all 12 calendar months represented as columns (Jan through Dec) even when a month has zero cases. Output is a huxtable rendered to RTF via pharmaRTF.

## 2. Requirements

### Functional

- **Data source:** Lung enriched ADS via `get_ads("lung", type = "enriched")`
- **Server-side filter:** `diagnosis_date >= "2025-01-01" & diagnosis_date < "2026-01-01"` pushed before `collect()` to minimize data transfer
- **Deduplication:** One row per patient -- keep earliest `diagnosis_date` per `patientid` (use `slice_min(diagnosis_date, n = 1, with_ties = FALSE)` after grouping by `patientid`)
- **Row variable:** `histology_subgroup` (12 levels)
- **Column variable:** Month extracted from `diagnosis_date`, labeled Jan--Dec in calendar order
- **Cell values:** Count of unique patients (integer)
- **Include all 12 months** as columns regardless of whether any patients fall in that month
- **Output format:** huxtable + pharmaRTF -> `output/histology_by_month_2025.rtf`

### Non-functional

- Standalone single program in `programs/`
- No reusable function file or test file needed (analysis script workflow per `r-code` skill)
- Must execute cleanly via `Rscript`

### Clarifications from Discussion

1. Use `histology_subgroup` (12-level variable), not `icdo3_histology_code`
2. Date-range filter on `diagnosis_date` (>= 2025-01-01, < 2026-01-01)
3. Month labels: abbreviated (Jan, Feb, ..., Dec), calendar order, all 12 present
4. Output: huxtable + pharmaRTF (RTF)
5. Deduplicate to unique patients, keeping earliest diagnosis per patient
6. Standalone program with server-side filtering

## 3. Current State Assessment

### Relevant Existing Patterns

- **`ads-data` skill:** Defines `get_ads()` usage, lazy evaluation, server-side filtering, and the `patientid` primary key convention
- **`databricks` skill:** Performance best practices -- filter before `collect()`, never pull full table when a subset suffices
- **`r-code` skill:** Analysis script workflow -- write, execute, fix, report
- **No existing programs** in `programs/` yet -- this will be the first

### Dependencies

| Package | Role |
|---------|------|
| `dplyr` | Data manipulation, deduplication, grouping, counting |
| `tidyr` | `pivot_wider()` + `complete()` to ensure all 12 months appear |
| `lubridate` | `month()` extraction with `label = TRUE, abbr = TRUE` |
| `forcats` | Ensure month factor levels are calendar-ordered |
| `huxtable` | Table formatting |
| `pharmaRTF` | RTF output |
| `syhelpr` | `get_ads()` |

All packages are on the approved list (tidyverse components + pharmaRTF + huxtable + syhelpr via pharmaverse).

### Known Constraints

- **Namespace conflict:** `huxtable::set_caption()` vs `pharmaRTF::set_caption()` -- must qualify with `package::` per `namespace-conflicts.md`
- The ADS is long-form (multiple rows per patient). Deduplication to one row per patient is mandatory before counting.

## 4. Proposed Design

### Program Structure

File: `programs/tfl_histology_by_month_2025.R`

```
Section 1: Header and library loading
Section 2: Data pull (server-side filtered, then collect)
Section 3: Deduplication (earliest diagnosis per patient)
Section 4: Derive month variable
Section 5: Cross-tabulation (group_by + count + pivot_wider with complete)
Section 6: Add total column
Section 7: Format as huxtable
Section 8: Write RTF via pharmaRTF
```

### Data Flow

```
get_ads("lung", "enriched")
  |> filter(diagnosis_date >= "2025-01-01", diagnosis_date < "2026-01-01")
  |> select(patientid, diagnosis_date, histology_subgroup)
  |> collect()
  |> group_by(patientid) |> slice_min(diagnosis_date) |> ungroup()
  |> mutate(dx_month = month(diagnosis_date, label = TRUE, abbr = TRUE))
  |> count(histology_subgroup, dx_month)
  |> complete(histology_subgroup, dx_month, fill = list(n = 0L))
  |> pivot_wider(names_from = dx_month, values_from = n, values_fill = 0L)
  |> add total column
  |> huxtable -> pharmaRTF -> RTF file
```

### Key Design Decisions

1. **`select()` server-side** before `collect()` -- only pull the three columns needed (`patientid`, `diagnosis_date`, `histology_subgroup`). This minimizes data transfer per the Databricks skill.

2. **`slice_min()` for deduplication** rather than `distinct()` -- `distinct(patientid, .keep_all = TRUE)` does not guarantee which row is kept. `slice_min(diagnosis_date, n = 1, with_ties = FALSE)` explicitly keeps the earliest diagnosis, which is the user's stated requirement.

3. **`complete()` before `pivot_wider()`** -- ensures all 12 months and all histology levels appear in the final table even with zero counts. The month factor levels (Jan through Dec) must be set explicitly to guarantee calendar ordering regardless of which months have data.

4. **Total column** -- add a row-wise sum as the rightmost column for quick reference.

5. **Total row** -- add a column-wise sum as the bottom row showing monthly totals across all histology subgroups.

### Error Handling

- Validate that `histology_subgroup` and `diagnosis_date` exist in the collected data
- Validate that at least one row remains after filtering (stop with informative message if zero)
- Report patient count and row count after dedup via `message()`

### huxtable Formatting

- Bold header row and histology subgroup column
- Right-align all numeric columns
- Left-align histology subgroup label column
- Add a table title: "Table X: New Diagnoses by Histology Subgroup and Month of Diagnosis (2025)"
- Set column widths proportionally (wider for histology label, narrow for month counts)
- Bold the Total row

## 5. Enhancements (Beyond Original Request)

1. **Total column and total row:** Add a "Total" column (row sums) and a "Total" row (column sums) to the table for at-a-glance totals. This is standard practice for cross-tabulation TFLs.

2. **Row ordering by frequency:** Sort histology subgroups by descending total count rather than alphabetically, so the most common histologies appear first. This makes the table more immediately informative. (Can be toggled to alphabetical if preferred.)

3. **Console summary:** Print a brief summary to the console after writing the RTF -- total unique patients, number of histology subgroups with non-zero counts, and the output file path. This aids verification during interactive use.

## 6. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `histology_subgroup` has unexpected levels (more or fewer than 12) | Do not hardcode levels. Derive from data. Report actual level count in console summary. |
| `diagnosis_date` may be `NA` or unparseable for some patients | Filter out `NA` dates after collect and report how many were dropped via `message()` |
| Month factor ordering could go wrong if locale differs | Explicitly set factor levels to `month.abb` (built-in R constant: Jan, Feb, ..., Dec) |
| huxtable/pharmaRTF `set_caption()` conflict | Qualify with `package::` per project rules |
| Zero patients in the 2025 date range | `stop()` with informative message if zero rows after filter |

## 7. Testing Strategy

This is a standalone analysis script, so no separate test file is required per the `r-code` skill's analysis script workflow. Validation consists of:

- **Execution test:** The program must run end-to-end via `Rscript` without errors
- **Row count check:** Console output reports total unique patients; verify this is reasonable
- **Column check:** Verify all 12 month columns appear in the output huxtable
- **Zero-fill check:** Confirm that months with no data show `0` rather than `NA`
- **RTF output check:** Verify `output/histology_by_month_2025.rtf` is created and non-empty
- **Dedup check:** Console output confirms patient count before and after deduplication

## 8. Orchestration Guide

| # | Task | Agent | Priority | Dependencies | Description |
|---|------|-------|----------|--------------|-------------|
| 1 | Implement program | r-clinical-programmer | P1 | None | Write `programs/tfl_histology_by_month_2025.R` following this plan. Use the `ads-data` skill for the data pull pattern and `databricks` skill for server-side filtering. Use the `r-code` skill's analysis script workflow (write, execute, fix, report). Ensure `output/` directory exists before writing RTF. |
| 2 | Review implementation | code-reviewer | P2 | Task 1 | Verify: (a) server-side filter is applied before `collect()`, (b) dedup uses `slice_min()` not `distinct()`, (c) all 12 months appear as columns, (d) `huxtable::set_caption()` / `pharmaRTF::set_caption()` are namespace-qualified, (e) program executes without errors, (f) RTF output exists and is well-formatted. Produce QC report. |

### Skills the Implementer Should Leverage

| Skill | Why |
|-------|-----|
| `ads-data` | `get_ads()` call pattern, `select()` before `collect()`, `patientid` as primary key |
| `databricks` | Server-side filtering best practices, lazy evaluation, `collect()` placement |
| `r-code` | Analysis script workflow (write -> execute -> fix -> report) |

### Files to Create

| File | Purpose |
|------|---------|
| `programs/tfl_histology_by_month_2025.R` | The analysis program |
| `output/histology_by_month_2025.rtf` | The formatted RTF output (generated by the program) |
