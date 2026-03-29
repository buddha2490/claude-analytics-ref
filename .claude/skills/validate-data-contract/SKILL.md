# validate-data-contract

**Version:** 1.0.0
**Status:** Active

## Description

Pre-flight validation that checks SDTM data structure against plan specifications before ADaM code execution begins. Prevents data structure mismatches (missing variables, type mismatches, alternative variable names) from causing downstream failures.

## When to Use

**Auto-invoked by orchestrator:**
- After loading an ADaM automation plan
- Before launching Wave 1 implementation agents

**User-invoked:**
- `/validate-data-contract plan=<path> sdtm-path=<path> [domains=<list>]`

**Examples:**
```
/validate-data-contract plan=projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md sdtm-path=projects/exelixis-sap/output-data/sdtm

/validate-data-contract plan=projects/study-x/plan_adam.md sdtm-path=projects/study-x/sdtm domains=DM,AE,EX
```

## What It Does

1. **Parses plan** for "Source variables:" tables
2. **Reads SDTM XPT files** from specified path
3. **Compares** expected vs actual columns
4. **Detects alternatives** (MHDTC → MHSTDTC, QSSTRESN → QSORRES)
5. **Reports discrepancies** with actionable guidance
6. **Returns verdict:** PASS or FAIL

## Validation Checks

For each domain listed in the plan:
- ✓ XPT file exists
- ✓ All expected variables present
- ✓ Alternative variables suggested if primary not found
- ℹ Unexpected variables flagged if many (informational only)

## Issue Types

| Type | Severity | Description |
|------|----------|-------------|
| `missing_file` | CRITICAL | XPT file not found → FAIL |
| `missing` | CRITICAL | Variable in plan not in data → FAIL |
| `read_error` | CRITICAL | Cannot read XPT file → FAIL |
| `missing_with_alternative` | WARNING | Variable not found, but alternative exists → PASS with warning |
| `info` | INFO | Informational note (many unexpected variables) → PASS |

## Report Format

```markdown
Data Contract Validation Report
================================

DOMAIN: MH
  ✗ MISSING: MHDTC (plan lists this but not found in data)
  ✓ FOUND ALTERNATIVE: MHSTDTC (consider updating plan)

DOMAIN: QS
  ✓ QSSTRESN: Variable not found, but alternative exists: QSORRES

SUMMARY:
  Critical issues: 0
  Warnings: 2

VERDICT: PASS
```

## Parameters

### Required
- `plan`: Path to ADaM automation plan (markdown file with "Source variables:" tables)
- `sdtm-path`: Path to directory containing SDTM XPT files

### Optional
- `domains`: Comma-separated list of domains to validate (default: all domains in plan)

## Implementation

The skill invokes the R function `validate_data_contract()` from `R/validate_data_contract.R`.

## Workflow Integration

### Orchestrator Usage

When an orchestrator agent is running a multi-wave ADaM automation:

1. **After loading plan:** Orchestrator calls this skill
2. **If FAIL verdict:** Orchestrator HALTS and reports issues to user
3. **If PASS verdict:** Orchestrator logs warnings (if any) and proceeds to Wave 1

### Example Orchestrator Code

```r
# Pre-flight validation
validation_result <- validate_data_contract(
  plan_path = "projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md",
  sdtm_path = "projects/exelixis-sap/output-data/sdtm"
)

cat(validation_result$report)

if (validation_result$verdict == "FAIL") {
  stop("Data contract validation failed. Resolve issues before proceeding.",
       call. = FALSE)
}

if (nrow(validation_result$issues) > 0) {
  message("Validation passed with warnings. Review before implementation:")
  print(validation_result$issues)
}
```

## Known Alternatives

The function detects these common CDISC variable substitutions:

| Expected | Alternative | Context |
|----------|-------------|---------|
| `MHDTC` | `MHSTDTC` | Medical history start date |
| `AEDTC` | `AESTDTC` | AE start date |
| `CMDTC` | `CMSTDTC` | Conmeds start date |
| `EXDTC` | `EXSTDTC` | Exposure start date |
| `QSSTRESN` | `QSORRES` | QS numeric result vs character |
| `LBSTRESN` | `LBORRES` | Lab numeric result vs character |

The function also applies pattern matching (e.g., `*DTC` → `*STDTC`).

## Error Handling

- **Invalid inputs:** Function stops with clear error message
- **Missing plan:** Stops with "Plan file not found"
- **Missing SDTM path:** Stops with "SDTM directory not found"
- **No source variable tables:** Returns PASS with informational message
- **XPT read errors:** Logged as `read_error` issue, continues to next domain

## Success Criteria

✓ Detects missing variables from plan
✓ Suggests alternatives (MHDTC → MHSTDTC)
✓ Returns FAIL for critical issues (missing files, missing variables)
✓ Returns PASS for warnings only (alternatives found)
✓ Generates formatted markdown report

## Testing

Test file: `tests/test-validate_data_contract.R`

Run tests:
```r
testthat::test_file("tests/test-validate_data_contract.R")
```

## Dependencies

- R packages: `haven` (for reading XPT files)
- Approved packages list: `approved-packages.md`

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-28 | Initial implementation |

## Related

- Enhancement: Plan Section 4.1 (Enhancement 1)
- Function: `R/validate_data_contract.R`
- Test: `tests/test-validate_data_contract.R`
- Orchestrator: Multi-wave ADaM automation workflow
