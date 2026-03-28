# Enhancement 6 Implementation: Complexity Threshold Detection

**Date:** 2026-03-27
**Status:** ✓ COMPLETE
**Implementation Reference:** plan_workflow_enhancements_2026-03-28.md Section 5.1

---

## Summary

Updated the `feature-planner` agent to automatically detect when dataset specifications contain >15 similar derivations and recommend helper function abstraction.

## Changes Made

### 1. Updated `.claude/agents/feature-planner.md`

Added new section: **Complexity Analysis (ADaM Plans)** immediately before "Communication Style" section.

**Key components:**

- **Detection Algorithm**: 4-step process for identifying repetitive patterns
  1. Parse derivation descriptions from variable tables
  2. Group by pattern signature (same source + operation, different parameters)
  3. Count occurrences in each group
  4. If count > 15: Flag for complexity alert

- **COMPLEXITY ALERT Format**: Structured template for flagging high-complexity patterns
  - Detected pattern summary
  - Recommended helper function signature
  - Application example (× count)
  - Benefits list
  - Orchestration note

- **Concrete Example**: Biomarker flag pattern from ADSL (20 flags)
  - Complete `create_biomarker_flag()` function signature
  - Parameter details (test_code, positive_pattern, negative_pattern)
  - Application code showing 20 invocations + joins

- **Pattern Signatures Table**: Common patterns to watch for
  - Biomarker flags (pattern match on domain.variable for test_code)
  - Baseline values (filter where flag='Y')
  - Date derivations (parse + calculate relative to reference)
  - Severity grades (categorical mapping via lookup)

- **Orchestrator Integration**: 3-step workflow
  1. Programmer receives alert → implements helper function first
  2. Applies helper function for all flagged derivations
  3. Reviewer verifies implementation (not copy-paste)

### 2. Created Validation Test

**File:** `projects/exelixis-sap/tests/test-complexity-detection.R`

Tests the pattern detection algorithm:

- ✓ Identifies 20 biomarker flags from simulated ADSL derivations
- ✓ Correctly extracts pattern components (domain, variable, operation, parameter)
- ✓ Constructs function signature from pattern
- ✓ Handles non-repetitive derivations without false positives

**Test results:** All 3 test cases pass (10 assertions total)

---

## How It Works

When the feature-planner agent reviews a dataset specification:

1. **Parses variable derivation tables** to extract derivation logic descriptions

2. **Groups by pattern signature**:
   ```
   "Pattern match on LB.LBSTRESC for EGFR"
   "Pattern match on LB.LBSTRESC for KRAS"
   "Pattern match on LB.LBSTRESC for ALK"
   ...
   → All match signature: "Pattern match on LB.LBSTRESC for <TEST>"
   ```

3. **Counts occurrences**: 20 variables use this pattern

4. **Exceeds threshold** (>15): Adds COMPLEXITY ALERT to plan

5. **Recommends helper function**:
   ```r
   create_biomarker_flag <- function(lb_data, test_code, var_name,
                                     positive_pattern = "ALTERED",
                                     negative_pattern = "NOT ALTERED") {
     # Reusable logic
   }
   ```

6. **Orchestrator passes alert** to programmer agent

7. **Programmer implements helper function first**, then applies 20 times

8. **Reviewer verifies** helper function usage (not copy-paste)

---

## Example Output

When the planner detects the ADSL biomarker pattern, it adds this to the plan:

```markdown
⚠ COMPLEXITY ALERT: 20 biomarker flags use identical pattern

**Detected pattern:**
- Source: LB.LBSTRESC
- Operation: Pattern match on test result for specific test code
- Parameters: EGFR, KRAS, ALK, ROS1, RET, MET, ERBB2, NTRK1-3, BRAF, NRAS, PIK3CA, PDGFRA, KIT, FGFR1-3, DDR2, MAPK1

**Recommend helper function:**
[function signature and application code]

**Orchestration note:**
Programmer agent should implement helper function *first*, then apply 20 times.
```

---

## Success Criteria

✓ Planner agent definition includes complexity detection section
✓ Detection algorithm documented (4 steps)
✓ COMPLEXITY ALERT format standardized
✓ Biomarker flag example included (concrete code)
✓ Pattern signatures table provided (4 common patterns)
✓ Orchestrator integration specified (3-step workflow)
✓ Validation test created and passing (3 tests, 10 assertions)

---

## Expected Impact

**Problem addressed:** ADSL required 7 internal iterations because agent didn't start with helper function for 20 identical biomarker flag derivations.

**Solution:** Planner now detects this pattern upfront and explicitly recommends helper function in the plan.

**Expected outcome:**
- Programmer agent starts with abstraction (not copy-paste)
- Reduces internal iterations for high-complexity datasets
- Single point of maintenance for pattern logic
- Fewer opportunities for copy-paste errors

**Metric:** First-pass QC rate for datasets with >15 similar derivations should improve from 67% → >80%

---

## Testing

Run validation test:

```bash
cd /Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap
Rscript --vanilla tests/test-complexity-detection.R
```

Expected output:
```
✓ Pattern detection identified 20 similar derivations (threshold: 15)
✓ Successfully extracted pattern components and constructed function signature
✓ Non-repetitive derivations correctly identified (no false positives)
Test passed with 4 successes 🥳.
Test passed with 5 successes 🎉.
Test passed with 1 success 🎊.
```

---

## Next Steps

1. **Enhancement 7**: Implement `/validate-plan` command that uses this detection logic
2. **Integration test**: Run full ADaM automation with complexity detection active
3. **Measure**: Track whether first-pass QC rate improves for ADSL-like datasets

---

## References

- **Plan**: `projects/exelixis-sap/plans/plan_workflow_enhancements_2026-03-28.md` Section 5.1
- **Agent definition**: `.claude/agents/feature-planner.md` lines 120-251
- **Test**: `projects/exelixis-sap/tests/test-complexity-detection.R`
- **Original issue**: First iteration analysis (ADSL required 7 attempts)
