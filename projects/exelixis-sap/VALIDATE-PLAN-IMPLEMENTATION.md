# `/validate-plan` Command Implementation

**Status:** Complete
**Date:** 2026-03-27
**Enhancement:** #7 from `plan_workflow_enhancements_2026-03-28.md`

## Overview

The `/validate-plan` command performs pre-flight checks on ADaM automation plans to detect anti-patterns and missing elements before code execution begins.

## Implementation

### Files Created

1. **R Function:** `projects/exelixis-sap/R/validate_plan.R`
   - Core validation logic
   - 6 distinct checks
   - Structured report generation
   - ~300 lines of code

2. **Command Definition:** `.claude/commands/validate-plan.md`
   - Usage documentation
   - Check descriptions
   - Output format specification
   - Orchestrator integration guidance

3. **Test Suite:** `projects/exelixis-sap/tests/test-validate_plan.R`
   - 18 test cases covering all validation checks
   - Input validation tests
   - Integration test with NPM-008 plan
   - ~400 lines of test code

4. **Demo Script:** `projects/exelixis-sap/tests/demo-validate-plan.R`
   - Interactive demonstration
   - Shows all validation checks in action

5. **Test Plan with Issues:** `projects/exelixis-sap/tests/test-plan-with-issues.md`
   - Synthetic plan containing known anti-patterns
   - Used for testing and demonstration

## Validation Checks

### 1. Datasets >40 Variables Without Strategy
**Threshold:** 40 variables (per user decision, not 80)
**Detection:** Parses dataset definitions for variable counts
**Action:** Warns if no split/checkpoint strategy mentioned

### 2. Repeated Derivations Without Helper Functions
**Detection:** Counts mentions of "flag", "biomarker", "comorbid" patterns
**Threshold:** 5+ flags or 3+ biomarkers/comorbidities
**Action:** Warns if no helper function documented

### 3. HIGH Complexity Without Checkpoints
**Detection:** Searches for "Complexity: HIGH" markers
**Action:** Warns if no checkpoint strategy mentioned

### 4. Unresolved Open Questions
**Detection:** Finds "## Open Questions" section, checks for:
- Unchecked checkboxes `[ ]`
- TODO, TBD, PENDING markers
**Action:** BLOCKING verdict - must resolve before proceeding

### 5. Missing Dependency Declarations
**Detection:** Finds multiple ADaM datasets without wave/dependency structure
**Action:** Warns if no "Wave", "Phase", or "Dependencies:" documented

### 6. Source Data Validation (Optional)
**Detection:** Extracts SDTM domain codes, checks for XPT files
**Action:** BLOCKING if required domains missing from data path

## Verdict Levels

| Verdict | Meaning | Orchestrator Action |
|---------|---------|---------------------|
| PASS | All checks passed | Proceed normally |
| WARNING | Non-blocking issues | Log warnings, proceed |
| BLOCKING | Critical issues | HALT, report to user |

## Test Results

All 18 tests pass successfully:

```
✓ Input validation (3 tests)
✓ Large datasets detection (3 tests)
✓ Repeated patterns detection (2 tests)
✓ HIGH complexity detection (2 tests)
✓ Unresolved questions detection (3 tests)
✓ Missing dependencies detection (3 tests)
✓ Source data validation (2 tests)
```

## Demonstration

Run `tests/demo-validate-plan.R` to see the command in action:

```bash
cd projects/exelixis-sap/tests
Rscript demo-validate-plan.R
```

Output shows:
1. Plan with 6 warnings + 1 blocking issue (test plan)
2. Plan that passes all checks (NPM-008 actual plan)

## Integration with Orchestrator

The command is designed to integrate into the multi-agent workflow:

```
Orchestrator:
  1. Load plan
  2. Run /validate-plan
  3. If BLOCKING:
     - HALT execution
     - Report issues to user
     - Request plan revision
  4. If WARNING:
     - Log warnings to QC report
     - Proceed with caution
  5. If PASS:
     - Proceed to Wave 1
```

## Key Design Decisions

### 40-Variable Threshold
User confirmed 40 variables (not 80) based on first iteration analysis where ADSL at 101 variables required 7 internal iterations.

### Regex Pattern Robustness
Used dotall mode `(?s)` for multi-line matching to ensure Open Questions section is correctly extracted across different markdown formatting styles.

### SDTM Domain Detection
Used a whitelist of common SDTM domains to avoid false positives from generic 2-letter codes.

### Report Format
Used Unicode symbols (✓ ⚠ ✗) for visual clarity in terminal output.

## Performance

- Validation completes in <1 second for typical plans
- No external dependencies beyond base R and readLines
- Memory efficient (full plan text fits in memory)

## Future Enhancements

Potential improvements not implemented in this version:

1. **Variable-level validation** - Compare plan's "Source variables" tables against actual SDTM XPT columns (covered by separate `/validate-data-contract` command)

2. **Controlled terminology checking** - Validate referenced term values against CDISC CT (could integrate with cdisc-rag MCP server)

3. **Cross-dataset consistency** - Check that USUBJID, STUDYID usage is consistent across datasets

4. **Derivation logic validation** - Parse derivation formulas for common errors

These are intentionally deferred to keep this enhancement focused and testable.

## Lessons Learned

1. **Regex debugging is iterative** - Initial patterns failed edge cases, required multiple refinements with debug scripts

2. **Test-driven development works** - Writing tests first clarified requirements and caught bugs early

3. **Simple patterns win** - Using whitelist for SDTM domains more robust than complex regex

4. **Documentation matters** - Command definition file is as important as the code itself for orchestrator integration

## Verification Against Plan Requirements

From `plan_workflow_enhancements_2026-03-28.md` Section 5.2 (Enhancement 7):

- ✅ Detects datasets >40 variables without strategy
- ✅ Detects >20 similar derivations without helper function note
- ✅ Detects HIGH complexity without checkpoints
- ✅ Detects unresolved open questions (BLOCKING)
- ✅ Detects missing dependency declarations
- ✅ Optional source data validation
- ✅ Returns structured report with actionable recommendations
- ✅ Catches all anti-patterns from first iteration analysis
- ✅ Completes in <10 seconds

All success criteria met.

## Usage Examples

### Basic validation
```bash
/validate-plan projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md
```

### With source data validation
```bash
/validate-plan projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md projects/exelixis-sap/source-data
```

### From R
```r
source("projects/exelixis-sap/R/validate_plan.R")
result <- validate_plan("path/to/plan.md")
cat(result$report)

# Check verdict programmatically
if (result$verdict == "BLOCKING") {
  stop("Plan has blocking issues")
}
```

## Files Modified

None. This is a purely additive enhancement.

## Backward Compatibility

No breaking changes. The command is new and does not affect existing workflows.

## Next Steps

1. ✅ Implementation complete
2. ✅ Tests passing
3. ✅ Demonstration script working
4. ⏭️ Integration into orchestrator workflow (future)
5. ⏭️ Add to automated QC checklist (future)

## Contact

For questions about this implementation, see:
- Plan: `projects/exelixis-sap/plans/plan_workflow_enhancements_2026-03-28.md`
- Code: `projects/exelixis-sap/R/validate_plan.R`
- Tests: `projects/exelixis-sap/tests/test-validate_plan.R`
- Demo: `projects/exelixis-sap/tests/demo-validate-plan.R`
