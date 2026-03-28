# Validate Plan Command

Pre-flight check for ADaM automation plans. Scans the implementation plan for anti-patterns and missing elements before execution begins.

## Usage

```bash
/validate-plan <plan-file> [data-path]
```

**Arguments:**
- `<plan-file>`: Path to the plan markdown file (required)
- `[data-path]`: Optional path to SDTM data directory for source domain validation

**Examples:**

```bash
/validate-plan projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md

/validate-plan projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md projects/exelixis-sap/source-data
```

## What It Checks

### 1. Complexity Flags
- **Datasets >40 variables without split/checkpoint strategy**
  - Detects large datasets that may require splitting across multiple agents
  - Threshold based on first iteration analysis (ADSL at 101 variables required 7 iterations)
  - Recommendation: Add checkpoint strategy or consider multi-agent splitting

### 2. Pattern Detection
- **>20 similar derivations without helper function abstraction**
  - Flags repeated patterns (biomarker flags, comorbidity flags)
  - Recommendation: Create helper functions to reduce code duplication
  - Example: `create_biomarker_flag(domain, testcd)` for 20+ biomarker flags

### 3. Execution Strategy
- **HIGH complexity without checkpoints**
  - Ensures high-complexity datasets have defined checkpoint/validation strategy
  - Prevents "big bang" approach that makes debugging difficult
  - Recommendation: Define checkpoints for intermediate validation

### 4. Open Questions
- **Unresolved questions detected**
  - Scans for unchecked checkboxes `[ ]`, TODO, TBD, PENDING markers
  - **BLOCKING**: Implementation cannot proceed with unresolved questions
  - Action required: Resolve all questions before starting

### 5. Dependency Validation
- **Missing dependency/wave structure for multi-dataset plans**
  - Ensures execution order is clear (ADSL before ADRS, etc.)
  - Recommendation: Document waves or explicit dependencies
  - Prevents building dependent datasets before foundation datasets

### 6. Source Data Validation (if data-path provided)
- **Source domains referenced in plan but not found in data directory**
  - Validates all source domains (DM, AE, EX, etc.) exist as XPT files
  - **BLOCKING**: Cannot proceed if required source data missing
  - Action required: Verify data path or update plan

## Output Format

```
Plan Validation Report
======================

✓ PASS: Dataset dependencies: Documented with waves/dependencies
✓ PASS: Open questions: All resolved

⚠ WARNING: ADSL has 101 variables but no split/checkpoint strategy
  Recommendation: Add checkpoints or consider splitting for datasets >40 variables

⚠ WARNING: Plan contains repeated derivation patterns without helper function abstraction
  Recommendation: Create helper functions for similar derivations

✗ BLOCKING: Plan contains unresolved open questions
  Action required: All questions must be resolved before implementation begins

VERDICT: BLOCKING
  1 BLOCKING issue(s), 2 WARNING(s)
  Recommendation: Resolve blocking issues before proceeding
```

## Verdict Levels

| Verdict | Meaning | Action |
|---------|---------|--------|
| **PASS** | All checks passed | Proceed with implementation |
| **WARNING** | Non-blocking issues found | Review warnings, update plan if needed, then proceed |
| **BLOCKING** | Critical issues found | MUST resolve before implementation starts |

## Orchestrator Integration

When integrated into the multi-agent workflow:

1. **Orchestrator loads plan**
2. **Orchestrator runs `/validate-plan`**
3. **If BLOCKING verdict:**
   - HALT execution
   - Report issues to user
   - Wait for plan revision
4. **If WARNING verdict:**
   - Log warnings
   - Proceed with caution
   - Flag warnings in final report
5. **If PASS verdict:**
   - Proceed to Wave 1
   - No intervention needed

## Technical Implementation

This command invokes the R function `validate_plan()` from `projects/exelixis-sap/R/validate_plan.R`.

**Process:**

1. Parse plan markdown to extract:
   - Dataset definitions and variable counts
   - Source domain references
   - Complexity markers
   - Open questions section
   - Dependency/wave structure

2. Run validation checks (see "What It Checks" above)

3. Generate structured report with:
   - Passes (✓) - things that look good
   - Warnings (⚠) - non-blocking but worth reviewing
   - Blocking (✗) - must fix before proceeding

4. Return verdict: PASS / WARNING / BLOCKING

## When to Use

- **Before starting implementation** - catches issues before any code is written
- **After plan revisions** - validates changes resolved previous issues
- **As part of orchestrator workflow** - automated pre-flight check
- **During QC review** - validates plan meets quality standards

## Success Criteria

A plan should pass validation (or have only acceptable warnings) before implementation begins. This prevents:

- Wasted compute on datasets >40 variables without strategy
- Code duplication from repeated patterns
- Data structure mismatches (MHDTC vs MHSTDTC)
- Building datasets in wrong order (ADRS before ADSL)
- Silent errors from unresolved ambiguities

## Related Commands

- `/validate-data-contract` - Validates actual SDTM data matches plan expectations (variable-level)
- `/profile-data` - Generates frequency tables for categorical variables
- `/plan` - Creates implementation plan (planner agent)

## Notes

- Validation is **static analysis** of the plan document only
- Does not execute code or read actual data (unless data-path provided for domain validation)
- Complements `/validate-data-contract` which does deep variable-level validation
- Fast: typically completes in <5 seconds
- Can be run multiple times as plan evolves
