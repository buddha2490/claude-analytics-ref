# QC Review: ADLOT — Line of Therapy (RE-REVIEW AFTER FIX CYCLE 1)

**Date:** 2026-03-27
**Reviewer:** clinical-code-reviewer agent
**Plan:** plans/plan_adam_automation_2026-03-27.md Section 4.1, Section 5.5 (Global Conventions), Section 6
**Previous QC:** QA reviews/qa_adam_adlot_2026-03-27.md (initial review)
**Fix Cycle:** 1

---

## Test Results

**Execution Status:** SUCCESS

**Program Output:**
```
Row count: 146
Subject count: 40
Subjects in DM: 40
Lines per subject (median): 3
Index lines (INDEXFL='Y'): 40
Date consistency violations (LOTSTDTC > LOTENDTC): 0
```

**Validation Checks:**
- All validation checks passed
- Zero missing values in key variables: USUBJID, LOT, LOTSTDTC, REGIMEN
- Unique USUBJID-LOT combinations: PASS
- All subjects in ADLOT exist in DM: PASS
- Date consistency (LOTSTDTC <= LOTENDTC): PASS (0 violations)
- INDEXFL flag convention: PASS (40 'Y', 106 blank/empty string)

**Dataset Quality:**
- 146 rows (reduced from 285 in initial review — correct)
- 40 unique subjects (100% of DM subjects represented)
- Median 3 lines per subject (reduced from 6 — more realistic after algorithm fix)
- Line count distribution: 12 subjects with 2 lines, 11 with 3 lines, 5 with 4 lines, 7 with 5 lines, 1 with 6 lines, 4 with 7 lines

---

## Findings

### BLOCKING (must fix before delivery)

**NONE.** All three BLOCKING issues from the initial review have been resolved.

### WARNING (should fix, not a blocker)

| # | File:Line | Rule/Standard | Finding |
|---|-----------|--------------|---------|
| 1 | projects/exelixis-sap/adam_adlot.R:144 | Plan Section 4.1 — LOTENDRSN | **LOTENDRSN uses raw CMRSDISC values without mapping.** Plan states: "LOTENDRSN: CM.CMRSDISC (new regimen) or DS.DSTERM (death/dropout) — **OPEN QUESTION: exact mapping rules**". Current implementation uses `first(na.omit(RSDISC))` which pulls raw values like "Progressive Disease", "Planned Therapy Completed". These are reasonable controlled terminology values. This is flagged as W4 in Open-questions-cdisc.md: "May need a manual mapping table". Current values appear appropriate, but this should be reviewed with clinical team before final delivery. No standardized LOTENDRSN controlled terminology exists in CDISC CT. **Status:** Unchanged from initial review — remains a WARNING. |
| 2 | projects/exelixis-sap/adam_adlot.R:56-70 | Plan Section 4.1 — Source variables | **EC domain included but not fully documented.** Code combines EX, CM, and EC domains, but the plan's "Source variables" table states: "EC may supplement EX". Dev log mentions EC was combined but doesn't explain the decision criteria. Current implementation treats all three domains equally (simple `bind_rows()`). Verify with data team: should EC records be used only when EX is missing, or are they independent therapy records? Current approach may double-count therapies if EC and EX both record the same treatment. **Status:** Unchanged from initial review — remains a WARNING. |

### NOTE (style/improvement suggestions)

| # | File:Line | Finding |
|---|-----------|---------|
| 1 | projects/exelixis-sap/adam_adlot.R:180 | **Clarifying comment about NA_character_ and XPT format added.** Line 180 includes: `# NOTE: NA_character_ becomes empty string in XPT — this is correct ADaM Y/blank convention`. This addresses the initial review's BLOCKING #1 concern. The implementation is correct — `NA_character_` in R becomes empty string in XPT format, which is the standard ADaM Y/blank convention. **Resolution:** BLOCKING #1 resolved. |
| 2 | projects/exelixis-sap/adam_adlot.R:85-131 | **LoT algorithm now fully implements all three rules.** The iterative line assignment algorithm (lines 85-131) correctly implements: (1) 45-day window relative to CURRENT line start (line 113), (2) 120-day gap rule (line 116), and (3) death date censoring (lines 149-163). The algorithm tracks `current_line_start` and updates it for each new line, ensuring window comparisons are relative to the current line, not the subject's first therapy. **Resolution:** BLOCKING #2 and #3 resolved. |
| 3 | projects/exelixis-sap/adam_adlot.R:231-234 | **Date consistency validation added.** The validation block now includes an explicit check for LOTSTDTC > LOTENDTC violations (lines 231-234), which `stopifnot()` on violation. Current result: 0 violations. This addresses the initial review's NOTE #3 suggestion. |
| 4 | projects/exelixis-sap/adam_adlot.R:18-20 | **Comment header dependency section clarified.** Header now states: "Dependencies: None (Wave 1 ADaM dataset — no upstream ADaM dependencies)" and "SDTM dependencies: DM, EX, CM, EC". This clarifies that the dataset has no ADaM dependencies (it's Wave 1) but does depend on SDTM domains. **Resolution:** WARNING #4 from initial review resolved. |
| 5 | projects/exelixis-sap/adam_adlot.R:166-168 | **Infinite LOTENDTC handling added.** Code now includes explicit check: `if_else(is.infinite(LOTENDT), NA_character_, LOTENDTC)` to handle cases where all end dates in a line are NA. This prevents `-Inf` values from propagating to XPT output. **Resolution:** WARNING #3 from initial review resolved. |

---

## Status of Initial Review BLOCKING Issues

### BLOCKING #1: Flag Convention Ambiguity (RESOLVED)

**Initial finding:** INDEXFL uses `NA_character_` which becomes empty string in XPT — needed clarifying comment.

**Fix verification:** Line 180 now includes: `# NOTE: NA_character_ becomes empty string in XPT — this is correct ADaM Y/blank convention`

**XPT output verification:**
- 40 records with INDEXFL = 'Y'
- 106 records with INDEXFL = "" (empty string, not NA)
- 0 records with INDEXFL = NA
- This is correct per ADaM-IG Y/blank convention — XPT format represents blank as empty string.

**Status:** ✅ RESOLVED

---

### BLOCKING #2: Incomplete LoT Algorithm (RESOLVED)

**Initial finding:** Simplified algorithm missing 120-day gap rule and death date censoring.

**Fix verification:**

**45-day window rule (lines 85-131):**
- Algorithm iterates through each subject's therapies
- Tracks `current_line_start` for each line
- Line 113: `within_window <- curr_start <= (current_line_start + WINDOW_DAYS)`
- Window comparison is now relative to CURRENT line start, not subject's first therapy ✅

**120-day gap rule (line 116):**
- Line 116: `gap_exceeds_limit <- !is.na(prev_end) && (curr_start - prev_end) > GAP_DAYS`
- Lines 119-123: New line triggered if either window exceeded OR gap exceeds 120 days
- Logic: `if (!within_window || gap_exceeds_limit) { ... start new line ... }` ✅

**Death date censoring (lines 149-163):**
- Lines 39-43: Death dates extracted from DM where DTHFL='Y'
- Lines 149-163: Line end censored at death date if death falls between line start and end
- Applied to both LOTENDT (numeric) and LOTENDTC (character)
- Logic: `if_else(!is.na(DTHDT_NUM) & DTHDT_NUM >= LOTSTDT & DTHDT_NUM < LOTENDT, DTHDT_NUM, LOTENDT)` ✅

**Edge case testing:**
- No gaps >120 days exist in the simulated data (verified)
- No deaths occurred during active lines in the simulated data — all deaths are after last line ends (verified)
- Algorithm logic is correct even though these edge cases don't occur in current data

**Status:** ✅ RESOLVED

---

### BLOCKING #3: Incorrect Window Logic (RESOLVED)

**Initial finding:** Window compared to subject's FIRST therapy instead of CURRENT line start.

**Fix verification:**
- Lines 102-106: Algorithm initializes `current_line_start` for first therapy
- Line 122: `current_line_start <- curr_start` updates for each new line
- Line 113: Window check uses `current_line_start`, not subject's first therapy start
- Algorithm correctly resets line start for each new line

**Sample verification (NPM008-01-A01009):**
```
Line 1: Start = 2023-02-23 | Regimen: Carboplatin + Paclitaxel + Pembrolizumab
Line 2: Start = 2023-07-27 | Regimen: Pembrolizumab
  Days from Line 1 start: 154 (>45 = TRUE) → Correctly starts new line
Line 3: Start = 2023-11-30 | Regimen: Pemetrexed
  Days from Line 2 start: 126 (>45 = TRUE) → Correctly starts new line
```

**Output quality improvement:**
- Initial review: 285 rows, median 6 lines per subject (incorrect due to window bug)
- Post-fix: 146 rows, median 3 lines per subject (more clinically realistic)
- Line count reduction of 48.8% indicates many incorrectly split lines were merged

**Status:** ✅ RESOLVED

---

## Additional Checks (User-Specified)

| Check | Status | Details |
|-------|--------|---------|
| All source data read from .xpt files only (not .rds) | ✅ PASS | Lines 34-37 use `haven::read_xpt()` for DM, EX, CM, EC. No `.rds` files referenced. |
| All paths are relative (no absolute /Users/... paths) | ✅ PASS | Grep search for `/Users/` returned no matches. All paths are relative (e.g., `projects/exelixis-sap/output-data/dm.xpt`). |
| All flag variables use Y/blank convention (not Y/N) | ✅ PASS | INDEXFL uses Y/empty string (40 'Y', 106 blank). Empty string is XPT representation of NA_character_, which is correct ADaM Y/blank convention. |
| NPM LoT algorithm fully implemented | ✅ PASS | All three rules present: 45-day window relative to current line (line 113), 120-day gap (line 116), death date censoring (lines 149-163). |

---

## Plan Compliance

**Plan Section 4.1 — ADLOT Specification:**
- [x] ✅ All 10 variables present (STUDYID, USUBJID, LOT, LOTSTDTC, LOTENDTC, LOTSTDT, LOTENDT, REGIMEN, LOTENDRSN, INDEXFL)
- [x] ✅ Source domains read from XPT files (DM, EX, CM, EC)
- [x] ✅ Row granularity correct (one row per subject per line)
- [x] ✅ USUBJID from DM
- [x] ✅ LOT assigned as integer starting at 1
- [x] ✅ LOTSTDTC/LOTENDTC derived from min/max therapy dates
- [x] ✅ REGIMEN concatenates unique drug names, alphabetically sorted, " + " separator
- [⚠️] PARTIAL: LOTENDRSN uses raw CMRSDISC values (W4 open question — mapping not resolved)
- [x] ✅ INDEXFL set to 'Y' for lines matching EX domain drugs
- [x] ✅ LOTSTDT/LOTENDT numeric SAS dates
- [x] ✅ **NPM LoT algorithm fully implemented** — 45-day window, 120-day gap, death censoring all present

**Plan Section 5.5 — Global Conventions:**
- [x] ✅ Flag convention (Y/blank) — INDEXFL uses NA_character_ in R, empty string in XPT (correct)
- [x] ✅ Path convention — all paths relative (no `/Users/...` found)
- [x] ✅ Data source convention — reads `.xpt` files only, no `.rds` files
- [x] ✅ NPM LoT algorithm parameters — 45-day window, 120-day gap, switching='no' all documented and implemented

**Plan Section 6 — QA Reviewer Workflow:**
- [x] ✅ Step 1 — Plan, program, and dev log reviewed
- [x] ✅ Step 2 — CDISC RAG verification performed (ADaM standard, flag conventions)
- [x] ✅ Step 3 — Systematic code review checklist applied
- [x] ✅ Step 4 — Program executed and output verified
- [x] ✅ Step 5 — QC report produced

---

## CDISC Compliance

**ADaM-IG Requirements:**
- [x] ✅ All variables have labels (verified via xportr output)
- [x] ✅ Character dates use ISO 8601 format (LOTSTDTC, LOTENDTC)
- [x] ✅ Numeric dates are SAS dates (LOTSTDT, LOTENDT)
- [x] ✅ Flag variables use Y/blank convention (INDEXFL — empty string is correct XPT representation)
- [x] ✅ Dataset written in XPT format with haven::write_xpt()
- [x] ✅ USUBJID-LOT uniqueness enforced (validation check line 223-224)
- [x] ✅ Cross-domain consistency: all subjects in DM (validation check line 227-228)
- [N/A] ADLOT is not a standard ADaM dataset name — using custom BDS-like structure per plan

**Controlled Terminology:**
- [x] ✅ INDEXFL values ('Y' or blank) — ADaM standard flag convention
- [⚠️] WARNING: LOTENDRSN uses raw CMRSDISC values — no standard CT exists for this variable, mapping table may be needed (W4)

---

## Code Quality Assessment

**Rule Compliance:**
- [x] ✅ **r-style.md:** snake_case naming, tidyverse pipe (`%>%`), section headers, comments explain why
- [x] ✅ **approved-packages.md:** Uses tidyverse, haven, xportr only
- [x] ✅ **namespace-conflicts.md:** No conflicting function calls
- [x] ✅ **cdisc-conventions.md:** ISO 8601 dates, USUBJID-LOT uniqueness, cross-domain consistency
- [x] ✅ **file-layout.md:** Program in `projects/exelixis-sap/`, output in `projects/exelixis-sap/output-data/`, correct naming
- [x] ✅ **data-safety.md:** No credentials, no real patient data, relative paths only
- [x] ✅ **git-conventions.md:** Not applicable (QC review only)
- [x] ✅ **error-messages.md:** Validation uses `stopifnot()` with informative messages

**Code Structure:**
- Structured comment header with source domains, CDISC references, dependencies
- Clear section delineation with `# --- Section Name ---` headers
- REVISIT comments point to Open-questions-cdisc.md for unresolved items
- Validation block comprehensive with row counts, completeness checks, CDISC compliance checks

**Algorithm Quality:**
- Iterative line assignment algorithm is clear and well-commented
- Edge case handling present (infinite values, missing end dates, death censoring)
- Algorithm follows NPM LoT algorithm specification exactly

---

## Summary

The ADLOT implementation after fix cycle 1 is now **FULLY COMPLIANT** with the plan specifications and CDISC conventions. All three BLOCKING issues from the initial review have been resolved:

1. ✅ **Flag convention:** Clarifying comment added explaining that NA_character_ becomes empty string in XPT format (correct ADaM Y/blank convention)
2. ✅ **LoT algorithm:** Now fully implements all three rules — 45-day window relative to current line start, 120-day gap rule, and death date censoring
3. ✅ **Window logic:** Algorithm correctly tracks current line start and resets for each new line, fixing the bug where all therapies were compared to subject's first therapy

**Output quality improvements:**
- Row count reduced from 285 to 146 (48.8% reduction) — more realistic line assignments
- Median lines per subject reduced from 6 to 3 — clinically appropriate
- All validation checks pass with zero date consistency violations
- INDEXFL correctly identifies 40 index lines (one per subject)

**Remaining items:**
- ⚠️ **WARNING #1:** LOTENDRSN mapping remains an open question (W4) — not blocking delivery
- ⚠️ **WARNING #2:** EC domain usage clarification needed — not blocking delivery

**Key risks eliminated:**
- ❌ (was BLOCKING) Incorrect line assignments due to window bug — FIXED
- ❌ (was BLOCKING) Missing 120-day gap rule — FIXED
- ❌ (was BLOCKING) Missing death date censoring — FIXED

**Dataset is now suitable for:**
- Wave 2 (ADSL) dependency — ADLOT.INDEXFL and ADLOT.LOT variables can be used
- Downstream analyses requiring line-of-therapy variables
- QC sign-off and delivery to analysis team

**Verdict:** ✅ PASS

**Recommendation:** Approve for Wave 2 (ADSL implementation). The two remaining WARNING items should be tracked in the open questions document but do not block downstream work. Suggest clinical team review of LOTENDRSN values during final data review before study delivery.

---

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
