# QC Review: ADAE — Adverse Events Analysis Dataset

**Date:** 2026-03-27
**Reviewer:** clinical-code-reviewer agent
**Plan:** plans/plan_adam_automation_2026-03-27.md Section 4.5
**Program:** cohort/adam_adae.R
**Dev Log:** logs/dev_log_adae_2026-03-27.md

---

## Test Results

**Execution Status:** PASS (no errors or warnings)

**Validation Results:**
- Row count: 127 (all AE records)
- Subject count: 40 subjects
- Key variable completeness: 0 missing for USUBJID, AESEQ, AETERM, AESTDTC
- TRTEMFL distribution: 127 Y, 0 blank (all AEs are treatment-emergent)
- AESEVN distribution: 1=63, 2=45, 3=18, 4=1 (matches AESEV mapping)
- HOSPDUR summary: 10 AEs with hospitalization, range 4-15 days, mean 8.8 days
- Cross-domain consistency: All 40 subjects exist in DM
- Unique keys: No duplicate USUBJID + AESEQ combinations

---

## Findings

### BLOCKING (must fix before delivery)

**None.**

---

### WARNING (should fix, not a blocker)

| # | File:Line | Rule/Standard | Finding |
|---|-----------|--------------|---------|
| 1 | cohort/adam_adae.R:338 | Plan Section 4.5 | Plan references AEBODSYS and AEOUT in source variable table, but actual AE domain contains AESOC and AESHOSP. Implementation correctly uses actual column names, but plan should be updated to match reality. This is documentation consistency, not a code issue. |

---

### NOTE (style/improvement suggestions)

**None.** Code quality is excellent. All sections clearly labeled, comments explain rationale, and REVISIT annotations appropriately flag critical design decisions.

---

## Plan Compliance

Verified against plan Section 4.5 specifications:

**Source domains:**
- [x] AE: USUBJID, AETERM, AEDECOD, AESOC, AESTDTC, AEENDTC, AESER, AEREL, AESEV, AEACN, AESHOSP, AESEQ (header correctly documents actual columns)
- [x] HO: USUBJID, HOTERM, HOSTDTC, HOENDTC, HOSEQ, HOHNKID
- [x] ADSL: USUBJID, TRTSDT, TRTEDT

**Key derivations (all CORRECT):**
- [x] **AESTDT, AEENDT:** Numeric dates from character ISO 8601 dates — verified correct conversion
- [x] **ASTDY, AENDY:** Study days relative to TRTSDT using CDISC formula (no day zero) — **VERIFIED CORRECT**
  - Formula: `AESTDT >= TRTSDT: AESTDT - TRTSDT + 1; else AESTDT - TRTSDT`
  - Test case: AESTDT=19709, TRTSDT=19691 => ASTDY=19 (correct)
- [x] **AEDUR:** AEENDT - AESTDT + 1 — verified correct
- [x] **TRTEMFL:** 'Y' if AESTDT >= TRTSDT, else blank — **VERIFIED CORRECT**
  - Uses Y/blank convention (NA_character_), not Y/N per Global Conventions
  - Test case: AESTDT >= TRTSDT with TRTEMFL='Y' confirmed
- [x] **AESEVN:** Numeric severity mapping — **VERIFIED CORRECT**
  - 1=MILD (63 records), 2=MODERATE (45), 3=SEVERE (18), 4=LIFE THREATENING (1), 5=DEATH (0)
  - Mapping verified via cross-tabulation of AESEV vs AESEVN — 100% correct
- [x] **AE-HO linkage:** USUBJID + HO.HOHNKID = as.character(AE.AESEQ) — **VERIFIED CORRECT**
  - Implementation: `mutate(AESEQ_C = as.character(AESEQ))` then left join on `AESEQ_C = HOHNKID`
  - Test case: USUBJID=NPM008-02-A01006, AESEQ=1 linked to HO record with HOHNKID='1'
  - HOSPDUR calculated correctly as 9 days (2023-04-09 to 2023-04-17)
- [x] **HOSPDUR:** HOENDTC - HOSTDTC + 1 — **VERIFIED CORRECT**
  - Formula: `as.numeric(as.Date(HOENDTC) - as.Date(HOSTDTC)) + 1`
  - Test case verified above (9 days)

**Variable selection:**
- [x] All 21 variables present: STUDYID, USUBJID, AESEQ, AETERM, AEDECOD, AESOC, AESTDTC, AEENDTC, AESTDT, AEENDT, ASTDY, AENDY, AEDUR, AESER, AEREL, AESEV, AESEVN, AEACN, AESHOSP, TRTEMFL, HOSPDUR
- [x] All variables have correct labels and types (verified via xportr metadata)

**Global Conventions (all PASS):**
- [x] Flag convention: TRTEMFL uses 'Y'/NA_character_ (not 'Y'/'N')
- [x] Path convention: All file paths are relative (cohort/output-data/*.xpt)
- [x] Data source convention: All source data read from .xpt files only (not .rds)

**CDISC Compliance:**
- [x] Variable names: All uppercase, all <= 8 characters
- [x] Variable labels: All 21 variables carry labels
- [x] Cross-domain consistency: All subjects exist in DM
- [x] Unique keys: USUBJID + AESEQ is unique (no duplicates)
- [x] Study day formula: Follows CDISC no-day-zero rule
- [x] xportr used for labels and types
- [x] Dataset written with haven::write_xpt()

**Code quality:**
- [x] R style rules: snake_case, tidyverse pipe (%>%), 2-space indent, section headers with `# --- Name ---`
- [x] Package loading: Uses library() not require(), all packages from approved list
- [x] Namespace conflicts: None present (no filter/lag/set_caption calls)
- [x] Comments: REVISIT annotations flag critical decisions (study day, flag convention, AE-HO linkage)
- [x] Header: Complete and accurate documentation of source domains and dependencies

---

## CDISC Compliance Detail

**RAG Verification:** Not required for this review. The plan specifications are comprehensive and include explicit CDISC references. All derivations match ADaM-IG conventions:
- TRTEMFL definition matches standard treatment-emergent flag logic
- Study day calculation follows SDTM/ADaM formula (no day zero)
- OCCDS structure for AE data (one row per event)
- Variable naming and labeling comply with ADaM-IG

**Controlled Terminology:** AESEV values (MILD, MODERATE, SEVERE, LIFE THREATENING, DEATH) are standard CDISC CT. AESEVN numeric coding (1-5) is a study-specific analysis variable, which is appropriate for ADaM.

---

## Summary

The ADAE implementation is production-ready. All five critical checks requested by the user have been verified correct:

1. **AE-HO linkage:** CORRECT — HOHNKID = as.character(AESEQ), verified via test case
2. **TRTEMFL derivation:** CORRECT — Y if AESTDT >= TRTSDT, uses Y/blank convention
3. **HOSPDUR calculation:** CORRECT — HOENDTC - HOSTDTC + 1, verified via test case
4. **AESEVN mapping:** CORRECT — 1=MILD, 2=MODERATE, 3=SEVERE, 4=LIFE THREATENING, 5=DEATH
5. **ASTDY/AENDY study days:** CORRECT — CDISC formula with no day zero, verified via test case

Additional checks all passed: relative paths, .xpt-only data sources, Y/blank flag convention, cross-domain consistency, unique keys, variable naming/labeling, code style, and execution without errors.

The only finding is a WARNING-level documentation inconsistency between the plan's source variable table (which lists AEBODSYS, AEOUT) and the actual AE domain (which contains AESOC, AESHOSP). The implementation correctly uses the actual column names, and the program header accurately documents what was used. This is a plan documentation issue, not a code defect.

**Verdict:** PASS

---

**Files reviewed:**
- Program: /Users/briancarter/Rdata/claude-analytics-ref/cohort/adam_adae.R
- Output: /Users/briancarter/Rdata/claude-analytics-ref/cohort/output-data/adae.xpt
- Dev log: /Users/briancarter/Rdata/claude-analytics-ref/logs/dev_log_adae_2026-03-27.md
- Plan: /Users/briancarter/Rdata/claude-analytics-ref/plans/plan_adam_automation_2026-03-27.md

**QC review completed:** 2026-03-27
