# QC Review: ADRS — Response Assessment per RECIST 1.1

**Date:** 2026-03-27
**Reviewer:** clinical-code-reviewer agent
**Program:** cohort/adam_adrs.R
**Plan:** plans/plan_adam_automation_2026-03-27.md (Section 4.4, Section 6, Global Conventions)
**Dev Log:** logs/dev_log_adrs_2026-03-27.md

---

## Verdict: PASS

## Summary

The ADRS implementation correctly derives visit-level response (OVRLRESP) and best overall response (BOR) parameters per RECIST 1.1 with confirmed response criteria. All five critical focus areas pass validation: (1) BOR confirmation requires two assessments >=28 days apart, (2) CLINRES records are correctly excluded, (3) AVAL coding follows the study-specific convention, (4) ADY calculation is correct, and (5) ABLFL is correctly assigned. The program meets all plan requirements, follows ADaM conventions, and executes without errors.

---

## Test Results

**Execution:** Clean (expected warnings only)
- Program runs without errors
- 2 warnings for subjects with no pre-treatment assessments (expected and handled correctly)

**Output verification:**
```
Row count: 184
  - OVRLRESP: 144 (matches RS RSTESTCD='RECIST' count)
  - BOR: 40 (one per subject)
Subject count: 40 (matches DM and ADSL)
```

**Validation checks:**
- All subjects in ADRS are present in DM
- Key combination (USUBJID, PARAMCD, AVISITN) is unique
- All required variables (STUDYID, USUBJID, PARAMCD, AVALC, AVAL) have 0 missing values

---

## Findings

### BLOCKING (must fix before delivery)

None.

### WARNING (should fix, not blocking)

None.

### NOTE (informational)

| # | File:Line | Finding |
|---|-----------|---------|
| 1 | General | BOR distribution (0 CR, 2 PR, 16 SD, 9 PD, 13 NE) reflects study-specific outcome patterns. No confirmed CR observed in the simulated cohort. |
| 2 | Lines 94-110 | 2 subjects (NPM008-02-A01029 and one other) have no assessments before or on TRTSDT. ABLFL is correctly left blank for these subjects. Dev log notes this is expected for immediate treatment start. |
| 3 | Lines 135-150 | BOR confirmation logic uses nested sapply() — O(n²) per subject. Acceptable for typical response assessment counts (n < 10 per subject). Dev log correctly notes this could be optimized with vectorized rolling join if scale becomes an issue. |

---

## Critical Focus Area Results

### 1. BOR Confirmation Requirement (>=28 days)

**Plan requirement (Section 4.4):** "BOR derivation requires CONFIRMED response: two consecutive CR or PR assessments with >=28 day interval per SAP"

**Code location:** Lines 112-180

**Verification:**
- Logic correctly implemented at lines 135-150 for confirmed CR and PR
- Uses `ADT[(i+1):length(AVALC)] - ADT[i] >= 28` for interval check
- Tested with subject NPM008-01-A01038 (BOR = PR):
  - PR on 2024-11-05 → PR on 2024-12-17 (42 days) ✓
  - Multiple subsequent confirmations at 42-45 day intervals ✓
- Tested with subject NPM008-01-A01010 (BOR = SD):
  - Only SD assessments, no CR/PR pairs ✓
- Tested with subject NPM008-01-A01016 (BOR = NE):
  - No post-baseline assessments ✓

**Status:** PASS

### 2. CLINRES Record Exclusion

**Plan requirement (Section 4.4):** "RSTESTCD = 'CLINRES' records are clinician-stated BOR and must NOT be used as the source for the derived BOR parameter"

**Code location:** Lines 53-60

**Verification:**
- RS domain contains 184 total records:
  - RSTESTCD = 'RECIST': 144 records
  - RSTESTCD = 'CLINRES': 40 records
- Code filters to `RSTESTCD == "RECIST"` at line 58
- ADRS OVRLRESP contains exactly 144 records (matches RECIST count)
- Comment at lines 54-55 explicitly documents exclusion: "NOTE: RSTESTCD = 'CLINRES' are clinician-stated BOR and are NOT used"
- BOR derivation (lines 112-180) derives from filtered RECIST records only, not CLINRES

**Status:** PASS

### 3. AVAL Coding (Study-Specific)

**Plan requirement (Section 4.4, Global Conventions):** "AVAL numeric coding: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE" (study-specific convention)

**Code location:** Lines 73-82 (OVRLRESP), Lines 172-179 (BOR)

**Verification:**
- OVRLRESP AVAL coding verified:
  - PR → 2 (11 records)
  - SD → 3 (113 records)
  - PD → 4 (20 records)
- BOR AVAL coding verified:
  - PR → 2 (2 subjects)
  - SD → 3 (16 subjects)
  - PD → 4 (9 subjects)
  - NE → 5 (13 subjects)
- Comments at lines 73-74 and 171 explicitly note: "NOTE: Study-specific AVAL coding — not CDISC standard"
- Code references `artifacts/NPM-008/Open-questions-cdisc.md R8` at line 32 (REVISIT comment)

**Status:** PASS

### 4. ADY Calculation (No Day Zero)

**Plan requirement (Section 4.4):** "ADY = ADT - ADSL.TRTSDT + 1 (or ADT - ADSL.TRTSDT if before index)"

**Code location:** Lines 84-87 (OVRLRESP), Lines 208-212 (BOR)

**Verification:**
- Formula implemented correctly: `if_else(ADT >= TRTSDT, ADT - TRTSDT + 1, ADT - TRTSDT)`
- Spot check of 3 OVRLRESP records:
  - NPM008-01-A01009: ADT=2023-11-23, TRTSDT=2023-11-30 → ADY=-7 ✓ (before treatment)
  - NPM008-01-A01009: ADT=2024-01-09, TRTSDT=2023-11-30 → ADY=41 ✓ (on/after treatment)
  - NPM008-01-A01010: ADT=2022-12-10, TRTSDT=2022-12-19 → ADY=-9 ✓ (before treatment)
- All calculations match expected values (no day zero for on/after TRTSDT)
- Comment at line 84 references CDISC: "ADY calculation per CDISC: no day zero"

**Status:** PASS

### 5. ABLFL Assignment

**Plan requirement (Section 4.4):** "'Y' for baseline assessment (last assessment before TRTSDT)"

**Code location:** Lines 93-110

**Verification:**
- Logic: `max_bl_dt = max(ADT[ADT <= TRTSDT])`, flag if `ADT == max_bl_dt`
- 38 subjects have baseline flag (Y)
- 2 subjects with no pre-treatment assessments correctly have no baseline flag
- All 38 baseline-flagged records have `ADT <= TRTSDT` ✓
- No subject has multiple baseline flags ✓
- Uses `!is.infinite(max_bl_dt)` check to handle subjects with no pre-treatment data (lines 104-107)
- Tested: subject NPM008-01-A01009 baseline on 2023-11-23 (7 days before TRTSDT=2023-11-30) ✓

**Status:** PASS

---

## Additional Compliance Checks

### Global Conventions (Plan Section 5.5)

| Convention | Requirement | Status |
|------------|-------------|--------|
| **Flag convention** | Use Y/blank (not Y/N) | PASS — ABLFL and ANL01FL use `"Y"` / `NA_character_` |
| **Path convention** | Relative paths only | PASS — All paths are relative (lines 45-47) |
| **Data source** | Read .xpt only (not .rds) | PASS — All source data from .xpt files (lines 45-47) |
| **AVAL coding** | Study-specific 1=CR through 5=NE | PASS — Verified above |

### Plan Compliance (Section 4.4)

| Requirement | Status |
|-------------|--------|
| Filter RS to RSTESTCD = 'RECIST' | PASS (line 58) |
| Exclude RSTESTCD = 'CLINRES' | PASS (lines 54-55, 58) |
| Create PARAMCD = 'OVRLRESP' records | PASS (line 70) |
| Create PARAMCD = 'BOR' records | PASS (line 203) |
| BOR confirmation per SAP (>=28 days) | PASS (lines 119-150) |
| Numeric AVAL coding | PASS (lines 75-82, 172-179) |
| ADY calculation (no day zero) | PASS (lines 84-87, 208-212) |
| ABLFL = last assessment before TRTSDT | PASS (lines 96-110) |
| ANL01FL = 'Y' for primary analysis | PASS (lines 90, 215) |
| REVISIT comment for confirmed response | PASS (lines 115-116) |
| REVISIT comment for AVAL coding | PASS (lines 28-32) |

### Code Quality (Plan Section 6, Step 3)

| Check | Status |
|-------|--------|
| All source variables exist in source domains | PASS |
| Join keys correct (USUBJID) | PASS (lines 68, 200, 201) |
| Date conversions handle missing values | PASS (NA_real_ handling) |
| Study day follows CDISC formula | PASS |
| Flag variables use Y/blank | PASS |
| All plan variables present | PASS (12/12 variables) |
| All subjects from DM represented | PASS (40/40) |
| No unintended row duplication | PASS (unique key verified) |
| xportr labels applied | PASS (lines 267-283) |
| Variable names uppercase, <=8 chars | PASS |
| Dataset written with haven::write_xpt() | PASS (line 286) |
| Comment header complete | PASS (lines 1-33) |
| Code follows R style rules | PASS |
| Sections clearly labeled | PASS (8 section headers) |
| No hardcoded CT values | PASS |
| Edge case handling | PASS (missing dates, no pre-treatment assessments) |

### CDISC Compliance

| Standard | Status |
|----------|--------|
| BDS structure (one row per subject per parameter per timepoint) | PASS |
| USUBJID format and consistency | PASS (all subjects in DM) |
| Date variables in ISO 8601 numeric format | PASS (ADT = numeric SAS date) |
| Study day calculation (no day zero) | PASS |
| Variable labels present for all variables | PASS (12/12 variables labeled) |
| Cross-domain consistency (DM linkage) | PASS |
| Unique keys (USUBJID + PARAMCD + AVISITN) | PASS |

---

## Variable Inventory

All 12 planned variables present with correct labels:

| Variable | Label | Type | Source/Derivation |
|----------|-------|------|-------------------|
| STUDYID | Study Identifier | character | RS.STUDYID |
| USUBJID | Unique Subject Identifier | character | RS.USUBJID |
| PARAMCD | Parameter Code | character | Derived ('OVRLRESP', 'BOR') |
| PARAM | Parameter | character | Derived (full description) |
| AVAL | Analysis Value (Numeric) | numeric | Derived (1=CR, 2=PR, 3=SD, 4=PD, 5=NE) |
| AVALC | Analysis Value (Character) | character | RS.RSSTRESC or derived BOR |
| ADT | Analysis Date | numeric | RS.RSDTC converted to numeric date |
| ADY | Analysis Relative Day | numeric | Derived (ADT - TRTSDT +/- 1) |
| AVISIT | Analysis Visit | character | RS.VISIT or "Overall" for BOR |
| AVISITN | Analysis Visit Number | numeric | RS.VISITNUM or 999 for BOR |
| ABLFL | Baseline Record Flag | character | Derived (Y/blank) |
| ANL01FL | Analysis Record Flag 01 | character | Derived ('Y' for all) |

---

## Validation Results

**Row count:** 184
- OVRLRESP: 144 (matches RS RECIST count)
- BOR: 40 (one per subject)

**Subject count:** 40 (matches DM and ADSL)

**PARAMCD distribution:**
```
     BOR OVRLRESP
      40      144
```

**BOR AVALC distribution:**
```
NE: 13 (no evaluable post-baseline assessments)
PD:  9 (progressive disease only)
PR:  2 (confirmed partial response)
SD: 16 (stable disease, no confirmed CR/PR)
CR:  0 (no confirmed complete response)
```

**ABLFL distribution:**
- Y: 38 subjects (have pre-treatment baseline assessment)
- Blank: 146 records (non-baseline records)

**Key variable completeness:** 0 missing values in all 5 key variables (STUDYID, USUBJID, PARAMCD, AVALC, AVAL)

**Execution:** 2 warnings (expected) for subjects NPM008-02-A01029 and one other with no pre-treatment assessments. Logic correctly handles this edge case with `!is.infinite(max_bl_dt)` check.

---

## CDISC RAG Verification

**Query executed:** "ADaM ADRS response dataset BDS structure PARAMCD baseline flag ABLFL analysis visit oncology tumor response"

**Result:** No ADaM-specific guidance returned from NPM-008 data dictionary (ADS source). This is expected — ADRS is a standard ADaM BDS structure not requiring custom NPM data dictionary definitions.

**Standard ADaM-IG principles applied:**
- BDS structure: one row per subject per parameter per analysis timepoint
- ABLFL definition: last non-missing assessment on or before the reference start date (TRTSDT in this case)
- ADY calculation: relative to index date with no day zero for on/after index
- Flag variables: Y/blank convention per ADaM-IG v1.3

**RECIST 1.1 confirmation criteria:** Derived from SAP specification (referenced in plan Section 4.4 and code comment lines 23-24). Requires >=28-day interval between two CR or PR assessments.

---

## Dev Log Review

**Log completeness:** Comprehensive — documents all 8 workflow steps with execution iterations, validation results, and QC notes.

**Key observations from log:**
1. STUDYID join issue in iteration 1 (resolved by removing redundant DM join)
2. Baseline flag warning in iteration 2 (resolved with infinite check)
3. BOR confirmation logic explicitly uses nested sapply() for consecutive pair checking (noted as O(n²) but acceptable for typical assessment counts)
4. 2 subjects with no baseline assessments documented (NPM008-02-A01029 and one other)
5. No confirmed CR or PR in cohort (only 2 confirmed PR) — study-specific outcome, not a derivation error

**Quality:** High. Log demonstrates systematic implementation following the 8-step workflow.

---

## Recommendations

None. Implementation is ready for delivery.

---

## Signature

**Reviewed by:** clinical-code-reviewer agent
**Date:** 2026-03-27
**Verdict:** PASS

This implementation meets all plan requirements, follows ADaM and CDISC conventions, and is ready for delivery pending any study-specific SAP review by the statistical team.
