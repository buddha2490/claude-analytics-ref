# Plan: Build SDTM Validation Functions

**Date:** 2026-03-28
**Status:** PENDING
**Purpose:** Build reusable validation and logging functions required by the enhanced SDTM simulation plan
**Dependencies:** None (these are foundational utilities)
**Working directory:** `projects/exelixis-sap/`
**Study:** NPM-008 / Exelixis XB010-101 ECA

---

## 1. Overview

This plan specifies three reusable functions that will be used by all SDTM simulation programs:

1. `validate_sdtm_domain.R` — Universal + domain-specific validation
2. `validate_sdtm_cross_domain.R` — Post-execution cross-domain checks
3. `log_sdtm_result.R` — Structured logging utility

All functions go in `R/` (relative to project working directory). Each function gets a corresponding test file in `tests/`.

---

## 2. Function Specifications

### 2.1 validate_sdtm_domain.R

**Purpose:** Perform universal SDTM validation checks plus optional domain-specific checks. Called by every `sim_*.R` program before writing XPT output.

**File location:** `R/validate_sdtm_domain.R`

**Interface:**

```r
validate_sdtm_domain <- function(
  domain_df,           # data frame to validate
  domain_code,         # character: domain code (e.g., "AE")
  dm_ref,              # data frame: DM dataset for cross-checks
  expected_rows,       # numeric vector: c(min, max) row count range
  ct_reference = NULL, # optional named list of CT value vectors
  domain_checks = NULL # optional function(domain_df, dm_ref) for custom checks
)
```

**Returns:** A list with:
- `verdict`: "PASS" or "FAIL"
- `checks`: data frame with columns `check_id`, `description`, `result` ("PASS"/"FAIL"), `detail`
- `summary`: character string summarizing results

**Behavior:**
- Runs all universal checks (U1-U10)
- If `domain_checks` provided, runs custom checks
- If any check fails, verdict is "FAIL" and function calls `stop()` with detailed message
- If all checks pass, returns result list silently

**Universal Checks:**

| ID | Check | Failure action |
|----|-------|----------------|
| U1 | `DOMAIN` column value matches `domain_code` | `stop()` |
| U2 | `STUDYID` is constant and equals `"NPM008"` | `stop()` |
| U3 | `USUBJID` matches regex `^NPM008-\\d{2}-[A-Z]\\d{4}$` | `stop()` |
| U4 | All USUBJIDs exist in `dm_ref` (anti-join = 0 rows) | `stop()` |
| U5 | `--SEQ` is unique integer within each USUBJID (if SEQ column exists) | `stop()` |
| U6 | No NA in required variables (STUDYID, DOMAIN, USUBJID) | `stop()` |
| U7 | All `--DTC`/`--STDTC`/`--ENDTC` columns match ISO 8601 `^\d{4}-\d{2}-\d{2}` | `stop()` |
| U8 | Row count within `expected_rows` range | `warning()` if outside range |
| U9 | No fully duplicate rows | `stop()` |
| U10 | CT values validated against `ct_reference` (if provided) | `stop()` on invalid |

**CT Validation Detail (U10):**
- If `ct_reference` provided as named list (e.g., `list(AESEV = c("MILD", "MODERATE", "SEVERE"))`)
- For each name in `ct_reference`, check if corresponding column exists in `domain_df`
- If column exists, verify all non-NA values are in the reference vector
- Report any invalid values in the check detail

**Domain-specific checks:**
- Passed as a function that takes `(domain_df, dm_ref)` and returns a list of check results
- Each result is a list with `check_id`, `description`, `result`, `detail`
- Example:
```r
domain_checks <- function(df, dm_ref) {
  list(
    list(check_id = "D1", description = "Exactly 40 rows",
         result = if(nrow(df) == 40) "PASS" else "FAIL",
         detail = paste("Actual:", nrow(df))),
    list(check_id = "D2", description = "RFSTDTC < RFENDTC for all subjects",
         result = if(all(df$RFSTDTC < df$RFENDTC)) "PASS" else "FAIL",
         detail = "")
  )
}
```

**Implementation notes:**
- Use `dplyr::anti_join()` for U4
- Use `stringr::str_detect()` for regex checks
- SEQ column name is `{domain}SEQ` (e.g., AESEQ, CMSEQ)
- Date columns: find all columns ending in "DTC" using `str_detect(names(df), "DTC$")`
- For U9, use `any(duplicated(domain_df))` to check for full row duplication

---

### 2.2 validate_sdtm_cross_domain.R

**Purpose:** Perform cross-domain validation checks after all 18 domains are generated. This is a standalone script that reads all domain RDS files and produces a validation report.

**File location:** `R/validate_sdtm_cross_domain.R`

**Interface:**

```r
validate_sdtm_cross_domain <- function(
  sdtm_dir = "output-data/sdtm/",  # directory containing .rds files
  log_dir = "logs/"                # directory for output report
)
```

**Returns:** A list with:
- `verdict`: "PASS" or "FAIL" (FAIL if any BLOCKING findings)
- `findings`: data frame with columns `check_id`, `severity`, `description`, `result`, `detail`
- `report_path`: character path to the written markdown report

**Behavior:**
- Reads all 18 domain RDS files from `sdtm_dir`
- Runs checks X1-X13
- Writes structured markdown report to `{log_dir}/cross_domain_validation_{date}.md`
- Returns summary with verdict

**Cross-Domain Checks:**

| ID | Check | Severity |
|----|-------|----------|
| X1 | Referential integrity: every USUBJID in every domain exists in DM | BLOCKING |
| X2 | All domains have 40 distinct USUBJIDs | BLOCKING |
| X3 | Date coherence: no event dates before RFSTDTC (except MH, CM prior therapy) | BLOCKING |
| X4 | Date coherence: no event dates after DTHDTC for deceased subjects | BLOCKING |
| X5 | Key linkage: TU.TULNKID ↔ TR.TULNKID (no orphans) | BLOCKING |
| X6 | Key linkage: AE.AESEQ ↔ HO.HOHNKID (no orphans) | BLOCKING |
| X7 | Key linkage: BS.BSREFID ↔ LB specimen dates | WARNING |
| X8 | Outcome consistency: DS.DSDECOD="DEATH" iff DM.DTHFL="Y" | BLOCKING |
| X9 | Outcome consistency: DS.DSDTC matches DM.DTHDTC for deceased | BLOCKING |
| X10 | RECIST consistency: RS BOR matches DM latent BOR | BLOCKING |
| X11 | Cardinality: DM=40, DS=40, IE=~400, SU=40, EX=40 | WARNING |
| X12 | SEQ uniqueness: within each domain, --SEQ unique per USUBJID | BLOCKING |
| X13 | File inventory: all 18 XPT files exist in `sdtm_dir` | BLOCKING |

**Check Implementation Details:**

**X1:** For each domain (excluding DM), run `anti_join(domain, dm, by = "USUBJID")` and verify 0 rows.

**X2:** For each domain, compute `n_distinct(USUBJID)` and verify equals 40.

**X3:** For each domain except MH and CM, find all columns ending in "DTC". For each date column, verify no dates < corresponding subject's RFSTDTC. For MH and CM, allow dates before RFSTDTC (prior medical history and prior therapy).

**X4:** For deceased subjects (DM.DTHFL="Y"), verify no event dates after DM.DTHDTC across all domains. Deceased subjects should have no events after death date.

**X5:** Verify `all(TR$TULNKID %in% TU$TULNKID)` and `all(TU$TULNKID %in% TR$TULNKID)` — every tumor has responses, every response links to a tumor.

**X6:** Verify `all(HO$HOHNKID %in% AE$AESEQ)` — every healthcare encounter links to a valid AE sequence number.

**X7:** Verify BS.BSREFID values correspond to LB specimen collection dates. This is a WARNING because the link may be indirect.

**X8:** Check that `(DS$DSDECOD == "DEATH") == (DM$DTHFL == "Y")` for all subjects.

**X9:** For deceased subjects, verify `DS$DSDTC == DM$DTHDTC`.

**X10:** Compare RS best overall response (RSSTRESC where RSTESTCD="OVRLRESP") to DM latent variable `bor`. Must match for all 40 subjects.

**X11:** Check domain row counts: DM exactly 40, DS exactly 40, IE approximately 400 (10 per subject), SU exactly 40, EX exactly 40. Warn if out of expected range.

**X12:** For each domain with a SEQ variable, group by USUBJID and verify `n_distinct(--SEQ) == n()`.

**X13:** List expected XPT files (DM, IE, MH, SC, SU, VS, LB, BS, EX, EC, CM, PR, QS, TU, TR, RS, AE, HO, DS) and verify all exist.

**Report Format:**

```markdown
# Cross-Domain Validation Report: NPM-008 SDTM

**Date:** {date}
**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA
**Domains validated:** {count}
**SDTM directory:** {path}

## Summary

- Total checks: {n}
- BLOCKING findings: {n}
- WARNING findings: {n}
- **Verdict: PASS/FAIL**

## Findings

### BLOCKING

{table of BLOCKING findings}

### WARNING

{table of WARNING findings}

## Check Details

{detailed results for each X1-X13 check}
```

---

### 2.3 log_sdtm_result.R

**Purpose:** Utility function to write structured log entries from within `sim_*.R` programs. Appends to a shared machine validation log file.

**File location:** `R/log_sdtm_result.R`

**Interface:**

```r
log_sdtm_result <- function(
  domain_code,         # character: domain code (e.g., "DM")
  wave,                # integer: wave number
  row_count,           # integer: nrow(domain_df)
  col_count,           # integer: ncol(domain_df)
  validation_result,   # list returned from validate_sdtm_domain()
  notes = NULL,        # optional character vector of notes
  log_dir = "logs/"    # directory for log file
)
```

**Returns:** `NULL` (called for side effect of appending to log file)

**Behavior:**
- Appends to `{log_dir}/sdtm_domain_log_{date}.md` (creates if doesn't exist)
- Writes a section for this domain with timestamp
- Includes row/col counts, validation verdict, and notes
- Thread-safe (uses append mode, though parallel writes to same domain unlikely)

**Log Entry Format:**

```markdown
### {DOMAIN} — {timestamp}

- **Wave:** {wave}
- **Rows:** {row_count}
- **Columns:** {col_count}
- **Validation:** {verdict}
- **Checks:** {pass_count}/{total_count} PASS
- **Notes:**
  - {note 1}
  - {note 2}

{detailed check failures if any}

---
```

**Implementation notes:**
- Use `format(Sys.time(), "%Y-%m-%d %H:%M:%S")` for timestamp
- Use `cat(..., file = log_path, append = TRUE)` to append
- If log file doesn't exist, write a header first:
```markdown
# SDTM Domain Validation Log

**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA
**Date:** {date}

---
```

---

## 3. Testing Requirements

Each function requires a comprehensive test file following the `test-<function_name>.R` pattern.

### 3.1 test-validate_sdtm_domain.R

**File location:** `tests/test-validate_sdtm_domain.R`

**Test cases:**

1. **U1-U7 universal checks**: Create mock datasets that violate each check and verify `stop()` is called
2. **U8 row count warning**: Create dataset outside expected range, verify warning issued
3. **U9 duplicate detection**: Create dataset with duplicate rows, verify FAIL
4. **U10 CT validation**: Pass CT reference with valid/invalid values, verify behavior
5. **Domain checks**: Pass custom check function, verify it's executed and results incorporated
6. **PASS case**: Create fully valid dataset, verify PASS verdict and no stop()
7. **SEQ check**: Test domains with and without SEQ columns
8. **Date column detection**: Test that all *DTC columns are checked

**Mock data:**
- Create minimal DM reference with 3 subjects
- Create test domain datasets (valid and invalid variants)

### 3.2 test-validate_sdtm_cross_domain.R

**File location:** `tests/test-validate_sdtm_cross_domain.R`

**Test cases:**

1. **X1 referential integrity**: Create domain with USUBJID not in DM, verify BLOCKING
2. **X2 cardinality**: Create domain with <40 subjects, verify BLOCKING
3. **X3 date coherence**: Create event before RFSTDTC (non-MH), verify BLOCKING
4. **X4 post-death events**: Create event after DTHDTC for deceased, verify BLOCKING
5. **X5 TU↔TR linkage**: Create orphan TULNKID, verify BLOCKING
6. **X6 AE↔HO linkage**: Create orphan HOHNKID, verify BLOCKING
7. **X8-X9 death consistency**: Create mismatched death records, verify BLOCKING
8. **X10 RECIST consistency**: Create RS BOR ≠ DM BOR, verify BLOCKING
9. **X11 cardinality warnings**: Create domains with unexpected row counts, verify WARNING
10. **X13 file inventory**: Mock missing XPT file, verify BLOCKING
11. **PASS case**: Create complete valid dataset suite, verify PASS verdict

**Mock data:**
- Create temporary directory structure
- Write minimal RDS files for all 18 domains
- Use `withr::local_tempdir()` for test isolation

### 3.3 test-log_sdtm_result.R

**File location:** `tests/test-log_sdtm_result.R`

**Test cases:**

1. **Log file creation**: Verify log file created if doesn't exist with header
2. **Log entry format**: Verify section structure matches spec
3. **Append behavior**: Call twice, verify both entries present
4. **Notes handling**: Pass NULL notes and character vector, verify formatting
5. **Validation result parsing**: Pass different verdicts, verify correct reporting
6. **Timestamp format**: Verify timestamp matches expected format

**Test setup:**
- Use `withr::local_tempdir()` for isolated log directory
- Create mock validation result list
- Verify log file contents with `readLines()`

---

## 4. Implementation Order

1. **validate_sdtm_domain.R** (most critical, used by all programs)
   - Implement function
   - Write test file
   - Source and run tests to verify

2. **log_sdtm_result.R** (simple, no dependencies)
   - Implement function
   - Write test file
   - Source and run tests to verify

3. **validate_sdtm_cross_domain.R** (most complex, depends on all domains existing)
   - Implement function
   - Write test file with mocked domain files
   - Source and run tests to verify

---

## 5. Success Criteria

- [ ] All 3 function files exist in `R/`
- [ ] All 3 test files exist in `tests/`
- [ ] All tests pass when run with `testthat::test_file()`
- [ ] Functions can be sourced without errors
- [ ] Each function has complete roxygen documentation
- [ ] Code follows r-style.md conventions (snake_case, tidyverse pipe, section headers)
- [ ] No hardcoded paths (all paths relative to project working directory)

---

## 6. Notes

- These functions are foundational utilities for the enhanced SDTM simulation
- They must be implemented and tested BEFORE the updated SDTM plan is executed
- Once built, they will be used by all 18 `sim_*.R` programs
- The validation functions enforce CDISC compliance and prevent bad data from being written
