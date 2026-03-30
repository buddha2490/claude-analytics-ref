# Human Validation Guide

**Purpose:** Manual quality control review of SDTM and ADaM datasets against study specifications and CDISC standards.

**Audience:** Clinical programmers, data managers, QC reviewers

**Prerequisites:**
- Automated CDISC validation report (generated via `/cdisc-data-validation`)
- Data profile report (`exelixis-dummy-data-report.html`)
- Study SAP (Statistical Analysis Plan)
- Data dictionary or SDTM/ADaM specification documents

---

## Important Note: Simulated Data Limitations

**The data in this study is randomly generated for demonstration purposes.** This means:

- ✅ Variable structure, naming, and data types should be CDISC-compliant
- ✅ Cross-domain relationships (USUBJID consistency) should be valid
- ✅ Date logic (RFSTDTC < RFENDTC, study days) should be mathematically correct
- ❌ Clinical plausibility is NOT guaranteed (e.g., 90-year-old with 2cm lesions may not be realistic)
- ❌ Frequencies may not match real-world disease patterns
- ❌ Treatment effects are artificial

**Your validation focus:** Structure, relationships, and CDISC compliance — not clinical realism.

---

## Validation Workflow

### Phase 1: Pre-Validation Review

1. **Review automated validation report** (`output-reports/cdisc-validation-report-<date>.html`)
   - Note any BLOCKING or WARNING findings
   - Understand which domains have issues before starting manual review
   - Use this as a checklist — don't re-check things the automation already verified

2. **Review data profile report** (`output-reports/exelixis-dummy-data-report.html`)
   - Get familiar with dataset structure
   - Note record counts and variable counts per domain
   - Identify which domains have the most variables or complexity

3. **Gather reference documents**
   - SAP or protocol synopsis
   - SDTM/ADaM specification documents (if available)
   - CDISC Implementation Guides (SDTM-IG, ADaM-IG)

---

## Phase 2: Domain-by-Domain Manual Review

Use this checklist for each domain. Open the XPT file in a dataset viewer (SAS Viewer, R, Python) and work through systematically.

### 2.1 Demographics (DM) — HIGHEST PRIORITY

**Why:** DM is the subject spine. Errors here propagate to all other domains.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| USUBJID | Format | Matches pattern `{STUDYID}-{SITEID}-{SUBJID}` (e.g., `NPM008-01-A1001`) |
| USUBJID | Uniqueness | No duplicates — run `table(dm$USUBJID)` or equivalent |
| SUBJID | Format | Typically numeric or alphanumeric ID within site |
| SITEID | Values | Match expected site numbers from protocol |
| RFSTDTC | Format | ISO 8601 (`YYYY-MM-DD`), no parsing errors |
| RFENDTC | Format | ISO 8601, all values ≥ RFSTDTC |
| RFICDTC | Logic | Should be before or equal to RFSTDTC (consent before first dose) |
| AGE | Range | Check min/max — flag if anyone <18 or >100 (depending on study) |
| AGEU | Consistency | Should be "YEARS" for all subjects |
| SEX | Values | Only "M" or "F" (CDISC CT C66732) |
| RACE | Values | Valid CDISC CT C74457 values (see automated report) |
| ETHNIC | Values | Valid CDISC CT C66790 values |
| COUNTRY | Consistency | Should match SITEID geography |
| DTHDTC | Logic | If present, should be ≥ RFSTDTC and ≤ data cut date |
| DTHFL | Consistency | If DTHDTC is non-missing, DTHFL should be "Y"; if missing, DTHFL should be missing |
| ARMCD, ARM | Protocol | Match planned treatment arms from SAP |
| ACTARMCD | Consistency | Should match ARMCD unless crossover/randomization failure occurred |

#### Cross-Checks

- [ ] Record count matches expected N (check against SAP)
- [ ] DTHFL="Y" count matches death frequency in DS domain (DSDECOD="DEATH")
- [ ] All RFSTDTC values fall within study enrollment window
- [ ] No subjects with RFENDTC before RFSTDTC (automated check should catch this)

---

### 2.2 Adverse Events (AE)

**Focus:** Event-level data quality and severity coding.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| AESEQ | Uniqueness | Within each USUBJID, AESEQ must be unique integers (1, 2, 3...) |
| AETERM | Content | Should be verbatim text (can be messy, not standardized) |
| AEDECOD | Consistency | Should be MedDRA preferred terms (standardized vs. AETERM) |
| AESTDTC | Format | ISO 8601 date |
| AEENDTC | Logic | If present, should be ≥ AESTDTC |
| AESEV | Values | Only "MILD", "MODERATE", "SEVERE" (CDISC CT C66769) |
| AESER | Values | Only "Y" or "" (empty string for non-serious) |
| AEREL | Values | Valid relationship-to-drug values (see automated report for CT) |
| AEACN | Values | Valid action taken values |
| AEOUT | Values | Valid outcome values (RECOVERED/RESOLVED, FATAL, etc.) |

#### Cross-Checks

- [ ] All USUBJID in AE exist in DM
- [ ] AESTDTC typically falls within RFSTDTC to RFENDTC (unless pre-treatment AE)
- [ ] Serious AEs (AESER="Y") have reasonable AESEV (not all MILD)
- [ ] AEOUT="FATAL" should correspond to subjects with DTHFL="Y" in DM
- [ ] No orphaned records (USUBJID not in DM)

#### Frequency Review

Open the data profile report and review AE frequency tables:

- **AEDECOD frequency:** Do the top 10 AEs look reasonable for the indication? (Note: simulated, so may not match real-world patterns)
- **AESEV distribution:** Should see more MILD than SEVERE (typically 60-70% mild)
- **AESER frequency:** Serious AEs should be <20% of all events in most studies
- **AEOUT distribution:** Most AEs should be RECOVERED/RESOLVED, small % FATAL

---

### 2.3 Exposure (EX)

**Focus:** Treatment administration consistency.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| EXTRT | Consistency | Should match planned treatment from DM.ARM |
| EXDOSE | Range | Dose values should match protocol (e.g., 40mg, 60mg, 240mg) |
| EXDOSU | Consistency | Units should be consistent (e.g., all "mg" or all "mg/kg") |
| EXDOSFRM | Values | Should match formulation in protocol (TABLET, INJECTION, etc.) |
| EXROUTE | Values | Valid CDISC CT route values (ORAL, INTRAVENOUS, etc.) |
| EXSTDTC | Logic | Should be ≥ RFSTDTC (first dose on or after reference start) |
| EXENDTC | Logic | Should be ≥ EXSTDTC |

#### Cross-Checks

- [ ] All USUBJID in EX exist in DM
- [ ] First EXSTDTC per subject should match or closely follow RFSTDTC
- [ ] EXTRT values match the ARM descriptions in DM
- [ ] Dose levels are consistent within each subject (unless dose escalation study)

---

### 2.4 Lab Results (LB)

**Focus:** Numeric result consistency and units.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| LBTESTCD | Values | Standard lab test codes (HGB, WBC, ALT, etc.) |
| LBTEST | Consistency | Test names should correspond to LBTESTCD (e.g., LBTESTCD="HGB" → LBTEST="Hemoglobin") |
| LBORRES | Format | Original result as collected (may be text with <, >, units) |
| LBORRESU | Consistency | Original units (g/dL, 10^9/L, etc.) |
| LBSTRESC | Format | Standardized result (numeric string or text like "NEGATIVE") |
| LBSTRESN | Type | Numeric standardized result |
| LBSTRESU | Consistency | Standardized units — should be consistent for each LBTESTCD across all records |
| LBDY | Logic | Study day relative to RFSTDTC — check sign (negative if before RFSTDTC) |

#### Cross-Checks

- [ ] LBSTRESN and LBSTRESU should be populated together (both missing or both present)
- [ ] Units for each test should be consistent (e.g., all HGB in g/dL, not a mix of g/dL and g/L)
- [ ] LBORRES and LBSTRESC should align (LBSTRESC should be cleaned/standardized version of LBORRES)
- [ ] Numeric ranges should be plausible (e.g., hemoglobin 6-18 g/dL, not 600)

#### Frequency Review

- **LBTESTCD distribution:** Should see multiple records per test per subject (baseline, on-treatment, end-of-treatment)
- **Missing LBSTRESN:** Some missingness expected (e.g., tests not performed, "NEGATIVE" results)

---

### 2.5 Subject-Level Analysis Dataset (ADSL)

**Focus:** Derived variables and population flags.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| SAFFL | Values | Only "Y" or "" (empty) — "Y" indicates subject in safety population |
| ITTFL | Values | Only "Y" or "" — "Y" indicates subject in ITT population |
| TRTP | Consistency | Planned treatment — should match DM.ARM |
| TRTPN | Consistency | Numeric treatment code — should correspond to TRTP (1=Treatment A, 2=Treatment B, etc.) |
| TRTSDT | Format | Numeric date (days since 1960-01-01) or Date type |
| TRTEDT | Logic | Should be ≥ TRTSDT |
| AGE, SEX, RACE | Consistency | Should match DM values exactly |

#### Derived Baseline Variables

Many ADSL variables are derived (e.g., baseline ECOG, baseline tumor burden). For each:

- [ ] Check variable label — should describe what it represents
- [ ] Review frequency distribution — does it match expected baseline characteristics?
- [ ] If numeric, check min/max/median — flag if outside plausible range

#### Cross-Checks

- [ ] Record count should match DM (one row per subject)
- [ ] All USUBJID in ADSL should exist in DM
- [ ] SAFFL="Y" count should be ≤ total N (safety population is typically all treated)
- [ ] ITTFL="Y" count should be ≤ SAFFL (ITT is typically subset of safety)

---

### 2.6 Adverse Events Analysis Dataset (ADAE)

**Focus:** Derived flags and treatment-emergent logic.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| TRTEMFL | Values | Only "Y" or "" — "Y" indicates treatment-emergent AE |
| AOCCFL | Values | Only "Y" or "" — "Y" indicates first occurrence of AE |
| AOCCSFL | Values | Only "Y" or "" — "Y" indicates first occurrence within preferred term |
| ASEV | Consistency | Should match AESEV from SDTM AE domain |
| AREL | Consistency | Should match AEREL from SDTM AE domain |
| TRTA | Consistency | Actual treatment received — should match ADSL.TRTP for most subjects |

#### Cross-Checks

- [ ] Record count should match SDTM AE
- [ ] All USUBJID in ADAE should exist in ADSL
- [ ] TRTEMFL logic: check a few subjects manually — AEs with AESTDTC ≥ TRTSDT should have TRTEMFL="Y"
- [ ] AOCCFL: within each subject, only one record per AEDECOD should have AOCCFL="Y"

---

### 2.7 Time-to-Event Analysis Dataset (ADTTE)

**Focus:** Censoring logic and event definitions.

#### Variables to Verify

| Variable | Check | What to Look For |
|----------|-------|------------------|
| PARAMCD | Values | Event type codes (e.g., PFS, OS, DOR) |
| PARAM | Consistency | Event descriptions should correspond to PARAMCD |
| AVAL | Type | Numeric — time in months or days |
| CNSR | Values | 0 (event) or 1 (censored) — binary numeric |
| EVNTDESC | Content | Should describe the event for non-censored records (CNSR=0) |
| CNSDTDSC | Content | Should describe censoring reason for censored records (CNSR=1) |
| STARTDT | Logic | Start date for time calculation (usually TRTSDT) |
| ADT | Logic | Analysis date (event or censoring date) |

#### Cross-Checks

- [ ] AVAL should equal (ADT - STARTDT) converted to appropriate units (months/days)
- [ ] If CNSR=0, EVNTDESC should be non-missing; if CNSR=1, CNSDTDSC should be non-missing
- [ ] For OS (overall survival), CNSR=0 should align with DTHFL="Y" in ADSL
- [ ] For PFS (progression-free survival), CNSR=0 should align with progression events in ADRS

#### Frequency Review

- **PARAMCD distribution:** Should have equal counts per subject (1 record per subject per parameter)
- **Event vs censored:** Check event rate (e.g., 60-80% events for PFS, 50-70% for OS)

---

## Phase 3: Cross-Domain Consistency Checks

After reviewing individual domains, validate relationships across datasets.

### 3.1 Universal Checks

Apply to all domain pairs:

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| USUBJID consistency | All USUBJID in non-DM domains should exist in DM | 100% match — no orphans |
| STUDYID consistency | All domains should have the same STUDYID value | Single value across all domains |

**How to check in R:**
```r
dm <- haven::read_xpt("output-data/sdtm/dm.xpt")
ae <- haven::read_xpt("output-data/sdtm/ae.xpt")

# Check for orphaned records in AE
orphans <- ae %>% anti_join(dm, by = "USUBJID")
nrow(orphans)  # Should be 0
```

### 3.2 Date Range Checks

Events should generally fall within the subject's study period:

| Domain | Date Variable | Check |
|--------|---------------|-------|
| AE | AESTDTC | Should be ≥ DM.RFSTDTC and ≤ DM.RFENDTC + 30 days (allow for follow-up) |
| EX | EXSTDTC | Should be ≥ DM.RFSTDTC and ≤ DM.RFENDTC |
| LB | LBDTC | Should be ≥ DM.RFICDTC (can have screening labs before RFSTDTC) |
| VS | VSDTC | Should be ≥ DM.RFICDTC |

**Note:** Some pre-treatment events (screening AEs, baseline labs) may fall before RFSTDTC — this is valid.

### 3.3 Derived Variable Consistency (SDTM → ADaM)

Spot-check that ADaM variables are correctly derived from SDTM:

| ADaM Variable | Source | Check |
|---------------|--------|-------|
| ADSL.AGE | DM.AGE | Should match exactly |
| ADSL.SEX | DM.SEX | Should match exactly |
| ADSL.TRTSDT | First EX.EXSTDTC per subject | Should match |
| ADAE.AEDECOD | AE.AEDECOD | Should match |
| ADAE.TRTEMFL | Derived from AE.AESTDTC vs ADSL.TRTSDT | Manually verify 2-3 subjects |

---

## Phase 4: Data Profile Report Review

Open `output-reports/exelixis-dummy-data-report.html` and work through systematically.

### 4.1 Summary Statistics

For each numeric variable:

- [ ] **N**: Does it match expected sample size or subset?
- [ ] **Mean/Median**: Are they in plausible range?
- [ ] **Min/Max**: Flag extreme outliers (e.g., age 200, dose 99999)
- [ ] **Missing count**: Is missingness expected? (See automated validation whitelist)

### 4.2 Frequency Tables

For each character variable:

- [ ] **Top values**: Do they align with protocol expectations?
- [ ] **Spelling/format**: Check for inconsistencies (e.g., "Male" vs "M")
- [ ] **Unexpected values**: Flag anything not in CDISC CT or protocol

### 4.3 Date Range Tables

For each date variable:

- [ ] **Earliest/Latest**: Are they within study period?
- [ ] **Range**: Does the span make sense? (e.g., study dates spanning 3 years)
- [ ] **Missing count**: Flag if required dates are missing

---

## Phase 5: SAP Alignment Check

**Goal:** Confirm datasets support all planned analyses in the SAP.

### 5.1 Population Definitions

| SAP Population | ADSL Flag | Check |
|----------------|-----------|-------|
| Safety | SAFFL="Y" | Count matches expected N |
| Intent-to-Treat (ITT) | ITTFL="Y" | Count matches expected N |
| Per-Protocol | PPROTFL="Y" | If applicable |
| Efficacy Evaluable | EFFEVALFL="Y" | If applicable |

### 5.2 Primary Endpoint

Find the primary endpoint in the SAP (e.g., PFS, ORR, OS). Verify:

- [ ] Endpoint is represented in ADTTE or ADRS
- [ ] PARAMCD matches SAP definition
- [ ] Event/response criteria are implemented correctly
- [ ] Baseline and post-baseline records are flagged appropriately

### 5.3 Secondary Endpoints

For each secondary endpoint:

- [ ] Variable exists in appropriate ADaM dataset
- [ ] Derivation logic matches SAP specification
- [ ] All required subgroups can be identified (e.g., by biomarker status)

### 5.4 Baseline Characteristics

SAP Table 14.1.1 (Demographics and Baseline Characteristics) typically includes:

- Age, Sex, Race, Ethnicity → ADSL
- ECOG performance status → ADSL (baseline flag)
- Disease stage → ADSL
- Prior therapies → Derived from CM or treatment history domain

Verify all variables needed for this table exist in ADSL.

---

## Phase 6: Documentation and Sign-Off

### 6.1 Validation Log

Create or update `validation-log.md` with:

```markdown
# Validation Log — NPM-008 / XB010-101

## Date: <today>
## Reviewer: <your name>
## Datasets Validated: SDTM (19 domains), ADaM (6 datasets)

### Summary
- Automated validation: PASS (0 BLOCKING, 10 WARNINGS)
- Manual validation: PASS / PASS WITH EXCEPTIONS
- SAP alignment: VERIFIED

### Findings
1. [Issue description]
   - Severity: BLOCKING / WARNING / NOTE
   - Location: <domain>.<variable>
   - Action taken: <fix applied or justification>

2. ...



### 6.2 Checklist Summary

- [ ] Phase 1: Pre-validation review completed
- [ ] Phase 2: Domain-by-domain review completed (all domains)
- [ ] Phase 3: Cross-domain consistency checks completed
- [ ] Phase 4: Data profile report reviewed
- [ ] Phase 5: SAP alignment verified
- [ ] Phase 6: Validation log updated and signed

---

## Common Issues and How to Resolve

### Issue 1: Missing Required Variables

**Symptom:** Automated validation reports BLOCKING — required variable not in dataset.

**Resolution:**
1. Confirm variable is truly required per CDISC IG (check IG section)
2. If required, update SDTM/ADaM program to derive the variable
3. If not applicable to this study, document justification in validation log

### Issue 2: Invalid Controlled Terminology Values

**Symptom:** Automated validation reports BLOCKING — invalid CT value.

**Resolution:**
1. Check CDISC CT codelist ID (e.g., C74457 for RACE)
2. Use `/ct-lookup RACE` to see valid values
3. Update simulation program or data derivation to use correct values
4. Re-run data generation and validation

### Issue 3: High Missingness on Required Variables

**Symptom:** Automated validation reports WARNING — >20% missing on required variable.

**Resolution:**
1. Determine if variable is truly required (check CDISC IG "Core" designation)
2. If Required, investigate derivation logic — why are values missing?
3. If Expected (e.g., death date in ongoing study), document in validation log
4. If Permissible, add variable to missingness whitelist in validation script

### Issue 4: Date Logic Errors

**Symptom:** AESTDTC before RFSTDTC, or RFENDTC before RFSTDTC.

**Resolution:**
1. Review date derivation logic in simulation programs
2. Check for off-by-one errors in date calculations
3. Ensure date_shift is applied consistently across domains
4. Re-run data generation

### Issue 5: USUBJID Mismatches (Orphaned Records)

**Symptom:** Records in AE/EX/LB with USUBJID not found in DM.

**Resolution:**
1. Check if DM was generated correctly (should have 40 subjects)
2. Check if domain programs are reading the correct DM.rds file
3. Ensure USUBJID format is consistent (case-sensitive, no leading/trailing spaces)
4. Re-run domain program that has orphaned records

---

## Tools and Resources

### R Commands for Manual Checks

```r
# Load datasets
dm <- haven::read_xpt("output-data/sdtm/dm.xpt")
ae <- haven::read_xpt("output-data/sdtm/ae.xpt")
adsl <- readRDS("output-data/adam/adsl.rds")

# Check uniqueness of USUBJID in DM
n_distinct(dm$USUBJID) == nrow(dm)  # Should be TRUE

# Check for orphaned AE records
ae %>% anti_join(dm, by = "USUBJID")  # Should return 0 rows

# Check RFSTDTC < RFENDTC
dm %>% filter(as.Date(RFSTDTC) >= as.Date(RFENDTC))  # Should return 0 rows

# Check AESEQ uniqueness within subject
ae %>%
  group_by(USUBJID) %>%
  summarize(n = n(), n_unique_seq = n_distinct(AESEQ)) %>%
  filter(n != n_unique_seq)  # Should return 0 rows

# Check ADSL population flags
adsl %>% count(SAFFL, ITTFL)

# Check ADTTE event vs censored distribution
adtte %>% count(PARAMCD, CNSR)
```

### External Resources

- **CDISC SDTM Implementation Guide:** https://www.cdisc.org/standards/foundational/sdtm
- **CDISC ADaM Implementation Guide:** https://www.cdisc.org/standards/foundational/adam
- **CDISC Controlled Terminology:** https://www.cdisc.org/standards/terminology
- **FDA Study Data Technical Conformance Guide:** https://www.fda.gov/industry/study-data-standards-resources/study-data-standards-resources

### Project-Specific Files

- Automated validation report: `output-reports/cdisc-validation-report-<date>.html`
- Data profile report: `output-reports/exelixis-dummy-data-report.html`
- SDTM simulation programs: `programs/sdtm/sim_*.R`
- ADaM derivation programs: `programs/adam/adam_*.R`
- Validation scripts: `programs/utils/validate_cdisc_standards.R`

---

## Questions or Issues?

If you encounter validation issues not covered in this guide:

1. Check the automated validation report first — it may already flag the issue
2. Review CDISC Implementation Guides for the relevant domain
3. Use `/ct-lookup <variable>` to check controlled terminology
4. Consult with senior clinical programmer or data manager
5. Document any unresolved issues in the validation log with justification

---

**Document Version:** 1.0
**Last Updated:** 2026-03-29
**Author:** Clinical Programming Team
