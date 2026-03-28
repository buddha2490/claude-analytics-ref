# Orchestrator Integration Guide: Phase 1 Enhancements

**Date:** 2026-03-28
**Plan:** projects/exelixis-sap/plans/plan_workflow_enhancements_2026-03-28.md
**Purpose:** Integration patterns for Phase 1 workflow enhancements

---

## Overview

Phase 1 adds 5 enhancements to the ADaM automation workflow. This guide shows how the orchestrator integrates each enhancement into the wave-based execution.

---

## Pre-Wave 1: Validation & Profiling

### Step 1: Data Contract Validation

**When:** Before spawning any programmer agents
**Command:** `/validate-data-contract`

```r
# Orchestrator runs:
message("=== PRE-FLIGHT: Data Contract Validation ===")

validation_result <- system2(
  "Rscript",
  args = c("-e", sprintf("
    library(haven)
    library(dplyr)
    library(stringr)
    source('R/validate_data_contract.R')
    result <- validate_data_contract(
      plan_path = 'projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md',
      sdtm_path = 'projects/exelixis-sap/output-data/sdtm'
    )
    cat('VERDICT:', result$verdict, '\n')
    if (result$verdict == 'FAIL') quit(status = 1)
  ")),
  stdout = TRUE,
  stderr = TRUE
)

if (attr(validation_result, "status") == 1) {
  stop("Data contract validation FAILED. Resolve issues before proceeding.")
}

message("✓ Data contract validation PASSED")
```

**Output:** Markdown report saved to `projects/exelixis-sap/validation-reports/data-contract-<timestamp>.md`

**Action on FAIL:** HALT orchestration, report issues to user

---

### Step 2: Data Profiling

**When:** After contract validation passes, before Wave 1
**Command:** `/profile-data` for each source domain

```r
# Orchestrator runs profiling for all domains
message("=== PRE-FLIGHT: Data Profiling ===")

source_domains <- c("DM", "EX", "AE", "RS", "LB", "MH", "CM", "HO", "BS", "TU", "QS", "SU", "SC")

for (domain in source_domains) {
  message("Profiling ", domain, "...")

  system2(
    "Rscript",
    args = c("-e", sprintf("
      library(haven)
      library(dplyr)
      library(stringr)
      source('R/profile_data.R')
      profile_data(
        domain = '%s',
        data_path = 'projects/exelixis-sap/output-data/sdtm',
        output_path = 'projects/exelixis-sap/data-profiles'
      )
    ", domain))
  )
}

message("✓ Data profiling complete for ", length(source_domains), " domains")
```

**Output:** Profile files saved to `projects/exelixis-sap/data-profiles/<DOMAIN>.md`

**Usage:** Programmer agents reference profiles during Step 5 (Implement Derivations)

---

## Wave Execution: Memory-Aware Agent Spawning

### Before Spawning Programmer Agent

**When:** Start of each wave, before agent spawn
**Action:** Load relevant memories

```r
# Orchestrator checks memory system
memory_path <- "projects/exelixis-sap/.claude/agent-memory"

# Read MEMORY.md index
memory_index <- readLines(file.path(memory_path, "MEMORY.md"))

# Extract relevant memories for this dataset
relevant_memories <- c()
if (grepl("biomarker", dataset_name, ignore.case = TRUE)) {
  relevant_memories <- c(relevant_memories, "npm008_biomarker_terminology.md")
}
if (dataset_name == "ADLOT") {
  relevant_memories <- c(relevant_memories, "lot_algorithm_complexity.md")
}

# Pass to agent context
agent_prompt <- sprintf("
Before implementing %s, review these learnings from previous waves:
%s

Full memory index: %s/MEMORY.md
", dataset_name, paste(relevant_memories, collapse = "\n"), memory_path)

# Spawn agent with memory context
spawn_r_clinical_programmer(
  dataset = dataset_name,
  context = agent_prompt
)
```

---

## Between-Wave: Validation Checks

### After Wave Completion

**When:** After all datasets in a wave are QC-approved
**Action:** Run between-wave validation checks

```r
# Orchestrator runs validation
message("=== BETWEEN-WAVE: Validation Checks (Wave ", wave_num, ") ===")

# Source validation functions
source("R/validate_referential_integrity.R")
source("R/validate_cross_domain.R")
source("R/validate_date_consistency.R")
source("R/validate_derived_variables.R")

# Source study-specific orchestration
source("projects/exelixis-sap/programs/between_wave_checks.R")

# Run checks for this wave
results <- run_between_wave_checks(
  wave_number = wave_num,
  datasets = completed_datasets
)

# Check results
if (any(results$severity == "CRITICAL")) {
  message("⚠ CRITICAL issues found in Wave ", wave_num)

  # Auto-retry once (per Q2 decision)
  message("Attempting auto-retry...")

  # Re-run validation
  retry_results <- run_between_wave_checks(wave_num, completed_datasets)

  if (any(retry_results$severity == "CRITICAL")) {
    # Still failing, escalate to user
    stop("Between-wave validation failed after retry. User intervention required.")
  }

  message("✓ Auto-retry successful")
}

message("✓ Between-wave validation PASSED for Wave ", wave_num)
```

**Checks by Wave:**

**Wave 1 (ADLOT, ADBS):**
- Referential integrity (all USUBJIDs in DM)
- No additional cross-domain checks (no dependencies yet)

**Wave 2 (ADSL):**
- Referential integrity (all USUBJIDs in DM, all ADLOT USUBJIDs in ADSL)
- Date consistency (TRTSDT exists, TRTSDT ≤ TRTEDT)

**Wave 3 (ADRS, ADAE):**
- Referential integrity (all in ADSL)
- Date consistency (no TRTEMFL='Y' AE before TRTSDT)
- BOR cardinality (1 per subject)

**Wave 4 (ADTTE):**
- Referential integrity (all in ADSL)
- Cross-domain (DOR count matches CR/PR count in ADRS)
- Cardinality (≤3 records per subject: PFS, OS, DOR)

---

## Post-Wave: Memory Persistence

### After QC Review Completes

**When:** After clinical-code-reviewer agent produces QC report
**Action:** Reviewer saves memories

```r
# Reviewer agent checks:
# - Were there BLOCKING issues? → Save feedback memory
# - Did implementation reveal complexity? → Save project memory
# - Did we discover study-specific terminology? → Save reference memory

# Example workflow from reviewer:
if (blocking_issues_found) {
  # Create memory file
  memory_content <- sprintf("
---
name: issue_%s
description: %s
type: feedback
---

%s

**Why:** %s

**How to apply:** %s
  ", issue_id, short_desc, full_description, rationale, application_guidance)

  # Write memory
  write_file(
    memory_content,
    file.path("projects/exelixis-sap/.claude/agent-memory",
              paste0(issue_id, ".md"))
  )

  # Update index
  append_to_file(
    sprintf("- [%s](%s.md) — %s\n", issue_id, issue_id, short_desc),
    "projects/exelixis-sap/.claude/agent-memory/MEMORY.md"
  )
}
```

**Output:** New memory files in `projects/exelixis-sap/.claude/agent-memory/`

**Next wave:** Orchestrator loads these memories for subsequent programmer agents

---

## Complete Workflow Integration

### Orchestration Sequence

```
Pre-Wave 1:
  1. Run /validate-data-contract → PASS/FAIL
  2. Run /profile-data for all domains → Generate profiles
  3. If validation PASS: Proceed to Wave 1

Wave 1:
  4. Load memories (check MEMORY.md)
  5. Spawn programmer agents (ADLOT, ADBS) with memory context
  6. Programmer follows 9-step workflow (includes Step 4 checkpoint + Step 4.5 profiling reference)
  7. QC reviewer reviews
  8. If issues: Fix cycle (max 2)
  9. Save memories from QC learnings
  10. Run between-wave validation → PASS/FAIL/retry

Wave 2:
  11. Load memories (including Wave 1 learnings)
  12. Spawn programmer agent (ADSL) with memory context
  13. Agent references data profiles, runs Step 4 checkpoint
  14. QC → Fix → Memories → Between-wave validation

Wave 3 & 4: Repeat pattern
```

### Integration Points

| Enhancement | Integration Point | Orchestrator Action |
|-------------|-------------------|---------------------|
| Data Contract Validation | Pre-Wave 1 | Run command, check verdict, halt if FAIL |
| Data Profiling | Pre-Wave 1 | Run for all domains, generate profiles |
| Exploration Checkpoint | During programming | Agent follows (automatic, no orchestrator action) |
| Memory Persistence | Post-QC | Reviewer saves, orchestrator loads for next wave |
| Between-Wave Validation | Post-Wave | Run checks, auto-retry once, escalate if still failing |

---

## Error Handling

### Data Contract Validation Fails
```
Action: HALT
Message: "Data contract validation failed. Resolve these issues:\n<violations>"
User: Fix plan or SDTM data, re-run
```

### Between-Wave Validation Fails (First Attempt)
```
Action: AUTO-RETRY
Message: "Between-wave checks failed. Attempting auto-retry..."
Retry: Yes (1 attempt)
If still fails: ESCALATE to user
```

### Agent Checkpoint Fails
```
Action: HALT agent
Message: Agent logs "Data contract validation failed: Missing MHDTC"
Orchestrator: Reviews dev log, flags to user
User: Fix plan or data, restart wave
```

---

## Testing the Integration

### Manual Test Sequence

```bash
# 1. Test data contract validation
/validate-data-contract plan=projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md sdtm-path=projects/exelixis-sap/output-data/sdtm

# 2. Test data profiling
/profile-data domain=LB data-path=projects/exelixis-sap/output-data/sdtm output-path=projects/exelixis-sap/data-profiles

# 3. Spawn programmer with memory context
# (manually check agent loads memories)

# 4. Run between-wave validation
Rscript projects/exelixis-sap/programs/between_wave_checks.R
```

### Automated Test

Create `projects/exelixis-sap/tests/test-orchestration-integration.R` to verify:
- Data contract skill invocation
- Profile generation
- Memory loading
- Between-wave validation

---

## Configuration Files

No hooks required for Phase 1. All integration is orchestrator-driven (explicit function calls).

Future: Consider adding hooks for:
- Auto-profile on SDTM file changes
- Auto-validate on plan file changes
- Auto-run between-wave checks after XPT writes

---

## Success Criteria

✅ **Data contract validation** catches all first-iteration structure issues (MHDTC, QSSTRESN)
✅ **Data profiling** prevents terminology mismatches (ALTERED vs POSITIVE)
✅ **Exploration checkpoint** forces agents to validate before coding
✅ **Memory persistence** prevents repeating Wave 1 mistakes in Wave 3
✅ **Between-wave validation** catches logic errors before downstream consumption

All enhancements work together to increase first-pass QC rate from 67% → >80%.
