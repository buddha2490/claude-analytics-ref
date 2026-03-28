# Dataset Splitting Guide

## Overview

This guide documents the multi-agent dataset splitting workflow for high-complexity ADaM datasets (>40 variables). The splitting pattern parallelizes derivations across multiple programmer agents, then merges results for a single QC review.

## When to Use

**Automatic splitting threshold:** >40 variables

**Rationale:**
- ADSL at 101 variables required 7 internal iterations in first implementation
- Splitting at 40 (not 80) provides earlier intervention
- Each agent handles ~25-30 variables — manageable cognitive load
- Parallel execution reduces total wall-clock time

**Override:** Planner can skip splitting if dataset has low complexity despite high variable count (e.g., mostly simple flags with identical derivation logic).

## Workflow

### 1. Analysis Phase

The `orchestrate_dataset_split()` function analyzes the dataset specification:

```r
library(dplyr)

# Load dataset specification
spec <- list(
  dataset_name = "ADSL",
  variables = readr::read_csv("specs/adsl_variables.csv"),
  total_variables = 101
)

# Generate split plan
split_plan <- orchestrate_dataset_split(spec, threshold = 40)

if (split_plan$split_required) {
  message("Split into ", split_plan$n_agents, " agents")
  print(split_plan$merge_strategy)
}
```

### 2. Variable Grouping Logic

The orchestrator uses heuristics to group variables by derivation category:

| Group | Variable Patterns | Typical Source | Example Variables |
|-------|-------------------|----------------|-------------------|
| **Keys** | USUBJID, STUDYID | DM | USUBJID, STUDYID |
| **Demographics** | AGE, SEX, RACE, ETHNIC, COUNTRY, REGION, ARM | DM | AGE, SEX, RACE, ETHNIC, COUNTRY |
| **Biomarkers** | MUT, GENE, ALK, ROS1, PD-L1, KRAS, EGFR | LB | EGFRMUT, KRASMUT, ALK, ROS1MUT, PDL1 |
| **Comorbidities** | Disease codes, CCI, Charlson | MH | MYHIS, CVAIS, CONGHF, CCIGRP |
| **Baseline** | ECOG, KPS, _BL suffix | QS, SC | ECOG0, ECOG_BL, SMOKGRP |
| **Staging** | STAGE, TSTAGE, NSTAGE, MSTAGE, AJCC | TU, PR | TSTAGE, NSTAGE, MSTAGE, AJCCSTG |
| **Treatment** | LOT, TRTSEQ, PRIORX, PFSIND, OSIND | PR, EX | LOTSNUM, PFSIND, OSIND |
| **Dates** | DT, STDTC, ENDTC suffix | Various | RFSTDTC, RFENDTC, TRTSDT |
| **Other** | Uncategorized variables | Various | Study-specific flags |

**Balancing:** Groups are distributed across agents to achieve ~25-30 variables per agent using a greedy packing algorithm.

### 3. Agent Execution

Each agent receives:
- **Assigned variable groups**
- **Source data paths**
- **Required merge keys** (USUBJID, STUDYID — always included)
- **Checkpoint file path** (e.g., `adsl_part1.rds`)

**Agent workflow:**
1. Read source SDTM domains
2. Implement assigned derivations
3. Validate output structure
4. Write checkpoint RDS to `projects/exelixis-sap/output-data/`

**Constraints:**
- Each checkpoint must include USUBJID and STUDYID
- Column names must be unique across checkpoints (except merge keys)
- All checkpoints must have identical subject sets

### 4. Merge Phase

The orchestrator calls `merge_split_datasets()`:

```r
checkpoint_files <- c(
  "output-data/adsl_part1.rds",
  "output-data/adsl_part2.rds",
  "output-data/adsl_part3.rds",
  "output-data/adsl_part4.rds"
)

result <- merge_split_datasets(
  checkpoint_files = checkpoint_files,
  output_path = "data/adsl.xpt",
  merge_keys = c("USUBJID", "STUDYID")
)

print_validation_report(result$validation_report)
```

**Merge strategy:** Sequential `left_join()` by USUBJID + STUDYID

### 5. Validation Checks

The merge function performs these validations:

| Check | Requirement | Action on Failure |
|-------|-------------|-------------------|
| Subject consistency | All checkpoints have identical USUBJID sets | STOP |
| Column uniqueness | No duplicate columns (except merge keys) | STOP |
| Row count | Row count unchanged after merge | WARN |
| Missing data | No NAs introduced by join | WARN |
| Column count | Total columns = sum(parts) - (N-1)*keys | WARN |

**STOP:** Merge aborted with error message.
**WARN:** Warning issued, merge continues.

### 6. QC Review

A single reviewer agent reviews the **merged** ADSL output, not individual parts.

**Review scope:**
- All 101 variables in final dataset
- Cross-domain consistency
- Date logic
- Derivation correctness

## Example: ADSL Split (101 Variables → 4 Agents)

### Split Plan

```
ADSL (101 variables) → 4 agents

Agent A: Demographics + Baseline (30 variables)
├─ Keys: USUBJID, STUDYID
├─ Demographics: AGE, SEX, RACE, ETHNIC, COUNTRY, REGION
├─ Baseline: ECOG0, ECOG_BL, SMOKGRP, KPS_BL
└─ Output: adsl_part1.rds

Agent B: Biomarker Flags (20 variables + 2 keys)
├─ Keys: USUBJID, STUDYID
├─ Biomarkers: EGFRMUT, KRASMUT, ALK, ROS1MUT, PDL1, BRAFMUT, ...
├─ Helper function: create_biomarker_flag()
└─ Output: adsl_part2.rds

Agent C: Comorbidity Flags + Charlson (25 variables + 2 keys)
├─ Keys: USUBJID, STUDYID
├─ Comorbidities: MYHIS, CVAIS, CONGHF, DIA, RENAL, ...
├─ Charlson index: CCIGRP
├─ Helper function: create_comorbidity_flag()
└─ Output: adsl_part3.rds

Agent D: Staging + Treatment History (26 variables + 2 keys)
├─ Keys: USUBJID, STUDYID
├─ Staging: TSTAGE, NSTAGE, MSTAGE, AJCCSTG, HISTGRP
├─ Treatment: LOTSNUM, PFSIND, OSIND
└─ Output: adsl_part4.rds
```

### Merge Code

```r
# Read checkpoints
part1 <- readRDS("output-data/adsl_part1.rds")  # 30 columns
part2 <- readRDS("output-data/adsl_part2.rds")  # 22 columns (20 + 2 keys)
part3 <- readRDS("output-data/adsl_part3.rds")  # 27 columns (25 + 2 keys)
part4 <- readRDS("output-data/adsl_part4.rds")  # 28 columns (26 + 2 keys)

# Sequential merge
adsl <- part1 %>%
  left_join(part2, by = c("USUBJID", "STUDYID")) %>%
  left_join(part3, by = c("USUBJID", "STUDYID")) %>%
  left_join(part4, by = c("USUBJID", "STUDYID"))

# Expected: 30 + (22-2) + (27-2) + (28-2) = 101 columns ✓
```

### Validation Results

```
=== Merge Validation Report ===

✓ PASS - All checkpoints have identical USUBJID sets
     All 4 checkpoints have 40 subjects

✓ PASS - No duplicate column names (except merge keys)
     No duplicate columns found

✓ PASS - Row count unchanged after merge
     Expected: 40, Actual: 40

✓ PASS - No missing data introduced by join
     NAs before: 12, NAs after: 12

✓ PASS - Column count matches expected
     Expected: 101, Actual: 101

All validation checks passed.
```

## Integration with Orchestrator Workflow

The split pattern integrates at **Step 3 (Programmer Execution)** in the standard orchestrator workflow:

### Standard Workflow (No Split)

```
1. Planner creates plan
2. Orchestrator reads plan
3. Orchestrator spawns programmer agent
4. Programmer implements dataset
5. Orchestrator spawns reviewer agent
6. Reviewer QCs dataset
7. If PASS → next dataset; if FAIL → fix cycle
```

### Split Workflow (>40 Variables)

```
1. Planner creates plan with split strategy
2. Orchestrator reads plan
3a. Orchestrator calls orchestrate_dataset_split()
3b. Orchestrator spawns N programmer agents in parallel
3c. Each programmer writes checkpoint RDS
3d. Orchestrator calls merge_split_datasets()
3e. Orchestrator writes final XPT
4. Orchestrator spawns reviewer agent
5. Reviewer QCs MERGED dataset
6. If PASS → next dataset; if FAIL → fix cycle
```

## Performance Expectations

**ADSL example (101 variables):**

| Approach | Wall-Clock Time | Internal Iterations | Agent Hours |
|----------|-----------------|---------------------|-------------|
| Single agent | ~45 min | 7 iterations | 0.75h |
| 4-agent split | ~15 min | 1-2 iterations per agent | 1.0h total (parallel) |

**Trade-off:** Slightly higher total compute (4 agents × 15 min = 1h vs 45 min single), but **3x faster wall-clock time** due to parallelization.

## Troubleshooting

### Issue: Subject Set Mismatch

**Symptom:** Merge fails with "Subject sets differ across checkpoints"

**Cause:** One agent filtered subjects (e.g., exclusion criteria applied)

**Fix:** Ensure all agents work from the same base DM dataset without applying subject-level filters.

### Issue: Duplicate Columns

**Symptom:** Merge fails with "Duplicate columns detected"

**Cause:** Two agents derived the same variable

**Fix:** Review variable assignments in split plan — each variable should appear in exactly one part.

### Issue: Row Count Changed

**Symptom:** Warning "Row count changed during merge"

**Cause:** One agent created duplicate rows (e.g., one-to-many join)

**Fix:** Review join logic in the agent that created duplicates — likely missing aggregation.

### Issue: Missing Data Introduced

**Symptom:** Warning "Missing data counts changed during merge"

**Cause:** `left_join()` introduced NAs because subject in part1 missing from part2

**Fix:** This should not happen if subject sets are consistent. Re-check subject consistency validation.

## Future Enhancements

**Potential improvements:**

1. **Dynamic threshold:** Adjust split threshold based on derivation complexity, not just variable count
2. **Smart grouping:** Use machine learning to group variables by common derivation patterns
3. **Incremental merge:** Support merging parts as they complete (don't wait for all)
4. **Parallel QC:** Split QC review across multiple reviewer agents for very large datasets

---

**Related Files:**
- `R/orchestrate_dataset_split.R` — Split plan generation
- `R/merge_split_datasets.R` — Checkpoint merge and validation
- `tests/test-dataset_splitting.R` — Test suite

**Related Plan:**
- `plans/plan_workflow_enhancements_2026-03-28.md` (Section 5.3, Enhancement 8)
