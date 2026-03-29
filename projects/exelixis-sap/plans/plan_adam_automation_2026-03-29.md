# Implementation Plan: ADaM Dataset Automation — NPM-008 Exelixis XB010-100

**Date:** 2026-03-29
**Status:** Ready — All blocking questions resolved; plan reviewed and hardened (2026-03-29)
**Requested by:** Brian Carter
**Study:** Exelixis XB010-100 (NPM-008) — NSCLC Real-World Evidence ECA

---

## 1. Executive Summary

This plan automates the development of six ADaM datasets for the NPM-008 study using a wave-based parallel execution strategy. Each dataset is implemented by an `r-clinical-programmer` agent following an 8-step workflow (RAG lookup, exploration, implementation, validation), then independently verified by a `clinical-code-reviewer` agent.

**Datasets:** ADLOT, ADBS, ADSL, ADRS, ADAE, ADTTE
**Total variables:** ~164 across 6 datasets
**Source domains:** 18 SDTM domains (XPT files in `projects/exelixis-sap/output-data/sdtm/`)
**Execution waves:** 4 waves, with parallelism in waves 1 and 3

```
Wave 1 [parallel]:  ADLOT + ADBS
Wave 2 [serial]:    ADSL (depends on ADLOT)
Wave 3 [parallel]:  ADRS + ADAE (depend on ADSL)
Wave 4 [serial]:    ADTTE (depends on ADSL + ADRS)
```

Each wave completes (implementation + QC pass) before the next wave begins.

---

## 2. Dataset Inventory

| Dataset | Variables | Source Domains | Dependencies | Wave | Row Granularity | Complexity |
|---------|-----------|----------------|--------------|------|-----------------|------------|
| ADLOT | 10 | EX, CM, EC, DM | None | 1 | One row per subject per line of therapy | HIGH — NPM LoT algorithm |
| ADBS | 9 | BS, DM | None | 1 | One row per biospecimen collection | LOW — direct mapping |
| ADSL | 101 | DM, MH, QS, SU, SC, LB, DS, EX, PR, TU, ADLOT | ADLOT | 2 | One row per subject | HIGH — 101 variables, complex derivations |
| ADRS | 13 | RS, DM | ADSL | 3 | One row per subject per response assessment + BOR record | MEDIUM — RECIST 1.1 BOR logic |
| ADAE | 20 | AE, HO, ADSL | ADSL | 3 | One row per adverse event | MEDIUM — HO linkage, TRTEMFL |
| ADTTE | 11 | RS, DM, ADSL | ADSL, ADRS | 4 | One row per subject per time-to-event parameter | MEDIUM — PFS/OS/DOR censoring rules |

---

## 3. Dependency Order

```
                    +---------+     +---------+
  Wave 1 (parallel) | ADLOT   |     | ADBS    |
                    +----+----+     +---------+
                         |
                         v
  Wave 2                +----+----+
                        | ADSL    |
                        +--+---+--+
                           |   |
                    +------+   +------+
                    v                  v
  Wave 3 (parallel) +---------+     +---------+
                    | ADRS    |     | ADAE    |
                    +----+----+     +---------+
                         |
                         v
  Wave 4                +---------+
                        | ADTTE   |
                        +---------+
```

**Critical path:** ADLOT --> ADSL --> ADRS --> ADTTE

ADBS, ADAE are off the critical path and do not block downstream datasets.

---

## 4. Per-Dataset Specifications

### 4.1 ADLOT — Line of Therapy

**Row granularity:** One row per subject per line of therapy (LOT)
**Expected output:** Multiple rows per subject who received multiple lines

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| EX | USUBJID, EXTRT, EXSTDTC, EXENDTC | Drug names and treatment dates for LOT construction |
| CM | USUBJID, CMTRT, CMSTDTC, CMENDTC, CMRSDISC | Concomitant meds, reason for discontinuation |
| EC | USUBJID, ECTRT, ECSTDTC, ECENDTC | Exposure as collected (may supplement EX) |
| DM | USUBJID, RFSTDTC, STUDYID | Subject identifiers and reference dates |

**Key derivations:**

| Variable | Derivation | Notes |
|----------|------------|-------|
| USUBJID | From DM | Key merge variable |
| STUDYID | From DM | |
| LOT | Row-number per USUBJID ordered by LOTSTDTC | Integer starting at 1 |
| LOTSTDTC | Earliest start date of drugs in the LOT | From NPM LoT algorithm grouping |
| LOTENDTC | Latest end date of drugs in the LOT | From NPM LoT algorithm grouping |
| REGIMEN | Concatenation of all unique EXTRT values within the LOT | Alphabetical sort, separated by ' + ' |
| LOTENDRSN | CM.CMRSDISC (new regimen) or DS.DSTERM (death/dropout) | **OPEN QUESTION: exact mapping rules** |
| INDEXFL | 'Y' if LOT drugs found in EX domain | Identifies the index (study) treatment line |
| LOTSTDT | Numeric SAS date of LOTSTDTC | `as.numeric(as.Date(LOTSTDTC))` |
| LOTENDT | Numeric SAS date of LOTENDTC | `as.numeric(as.Date(LOTENDTC))` |

**CDISC RAG queries to run:**
- ADaM ADLOT structure and required variables
- NPM Line of Therapy algorithm definition
- Controlled terminology for LOTENDRSN

**NPM LoT Algorithm — NSCLC parameters (resolved from SAP 2026-03-29):**

```
Window:          45 days  — drugs started within 45 days of line start date are grouped into same line
Treatment gap:  120 days  — gap of >120 days from ALL drugs in the line ends the current line
Switching:       'no'     — adding a new drug does NOT start a new line in NSCLC
Line start:      First valid antineoplastic administration date
Line end:        Latest of: last administration date
                          OR new drug added outside the 45-day window
                          OR >120-day gap from all drugs in line
                          OR death date
Index line:      The LOT whose drugs match the EX domain drugs (study treatment, ≥2L)
```

Add `# REVISIT: NPM LoT algorithm — NSCLC-specific parameters from SAP. See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R5` in the grouping logic block.

**Complexity flags:**
- **HIGH:** The NPM LoT algorithm is NSCLC-specific. All parameters above are confirmed from SAP. No additional user input required.
- The INDEXFL derivation requires matching LOT drugs against EX domain entries to identify which line corresponds to the index treatment.

---

### 4.2 ADBS — Biospecimen

**Row granularity:** One row per biospecimen collection event
**Expected output:** One or more rows per subject

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| BS | USUBJID, BSDTC, BSMETHOD, BSANTREG, BSHIST, BSSPEC | All biospecimen fields |
| DM | USUBJID, STUDYID, RFSTDTC | Subject identifiers |

**Key derivations:**

| Variable | Derivation | Notes |
|----------|------------|-------|
| USUBJID | From DM | |
| STUDYID | From DM | |
| BSDTC | From BS.BSDTC | Collection date (character ISO 8601) |
| BSDT | Numeric date of BSDTC | |
| BSTRT | From BS.BSMETHOD | Biopsy method |
| BSLOC | From BS.BSANTREG | Anatomical region |
| BSHIST | From BS.BSHIST | Histology result |
| BSSPEC | From BS.BSSPEC | Specimen type |
| ADY | BSDT - RFSTDTC + 1 (if >= RFSTDTC), else BSDT - RFSTDTC | Study day |

**CDISC RAG queries to run:**
- ADaM ADBS structure (if exists) or general ADaM BDS structure for biospecimen
- Controlled terminology for BSMETHOD, BSSPEC

**Complexity flags:**
- **LOW:** Mostly direct mappings from BS domain with standard date conversions.

---

### 4.3 ADSL — Subject-Level

**Row granularity:** One row per subject
**Expected output:** Exactly one row per USUBJID in DM

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| DM | USUBJID, STUDYID, SITEID, BRTHDTC, SEX, RACE, ETHNIC, RFSTDTC, RFENDTC, RFICDTC, ACTARMCD, DTHDTC, DTHFL, AGE, AGEU, COUNTRY | Demographics, reference dates, death. **Note:** DM does not contain ARM, ARMCD, or ACTARM — only ACTARMCD is available. |
| MH | USUBJID, MHTERM, MHDTC, MHCAT, MHBODSYS | Cancer diagnosis, staging, comorbidities |
| QS | USUBJID, QSTESTCD, QSSTRESN, VISIT | ECOG performance status |
| SU | USUBJID, SUTRT, SUSCAT | Smoking status |
| SC | USUBJID, SCTEST, SCSTRESN, SCSTRESC | Subject characteristics |
| LB | USUBJID, LBTESTCD, LBSTRESN, LBSTRESC, VISIT | Biomarker results |
| DS | USUBJID, DSDECOD, DSTERM, DSSTDTC | Disposition (death, dropout) |
| EX | USUBJID, EXTRT, EXSTDTC, EXENDTC | Treatment dates for index |
| PR | USUBJID, PRTRT, PRCAT, PRSTDTC | Prior therapies |
| TU | USUBJID, TUTESTCD, TULOC, TUSTRESC | Tumor/metastasis locations |
| ADLOT | USUBJID, LOT, INDEXFL, REGIMEN | Line of therapy for index and prior lines |

**Key derivation groups:**

**Treatment dates:**

| Variable | Derivation |
|----------|------------|
| TRTSDT | Numeric date of index treatment start (from EX or ADLOT where INDEXFL='Y') |
| TRTEDT | Numeric date of index treatment end |

**Age variables:**

| Variable | Derivation |
|----------|------------|
| AGENSCLC | Years between BRTHDTC and MH.MHDTC where MHCAT='PRIMARY CANCER DIAGNOSIS' |
| AGEINDEX | Years between BRTHDTC and RFSTDTC |
| AGEINDEXGRP | '<65' if AGEINDEX < 65, else '>=65' |

**Baseline assessments:**

| Variable | Derivation |
|----------|------------|
| ECOGBL | QS.QSSTRESN where QSTESTCD='ECOG' and VISIT='BASELINE' (or closest pre-index) |
| SMOKSTAT | SU.SUSCAT where SUTRT='TOBACCO' |
| HISTGRP | Derived histology grouping from MH where MHCAT='PRIMARY CANCER DIAGNOSIS' |

**Metastasis flags:**

| Variable | Derivation |
|----------|------------|
| BRAINMET | 'Y' if TU has TUTESTCD='METS' and TULOC contains 'BRAIN' |
| LIVERMET | 'Y' if TU has TUTESTCD='METS' and TULOC contains 'LIVER' |
| BONEMET | 'Y' if TU has TUTESTCD='METS' and TULOC contains 'BONE' |

**Biomarker flags (from LB at VISIT='BASELINE'):**

| Variable | Source filter | Derivation |
|----------|--------------|------------|
| EGFRMUT | LBTESTCD = 'EGFR' (or study-specific code) | 'Y'/'N' based on LBSTRESC |
| KRASMUT | LBTESTCD = 'KRAS' | 'Y'/'N' based on LBSTRESC |
| ALKMUT | LBTESTCD = 'ALK' | 'Y'/'N' based on LBSTRESC |
| (17+ more) | Various LBTESTCD values | Same pattern |

**Comorbidity flags (from MH.MHTERM lookups):**

| Variable | MH.MHTERM contains | Notes |
|----------|---------------------|-------|
| CADFL | Coronary artery terms | 'Y'/'N' |
| DIABFL | Diabetes terms | 'Y'/'N' |
| (13+ more) | Various condition terms | Same pattern |

**Charlson Comorbidity Index:**

| Variable | Derivation |
|----------|------------|
| CCISCORE | Weighted sum of comorbidity flags per Charlson algorithm |

**Staging variables:**

| Variable | Derivation |
|----------|------------|
| PATHSTAGEGRP | From MH where MHCAT relates to pathological staging |
| CLINSTAGEGRP | From MH where MHCAT relates to clinical staging |
| TNMSTAGET/N/M | Individual TNM components from MH |

**Treatment history:**

| Variable | Derivation |
|----------|------------|
| INDEXFL | From ADLOT — subject has index treatment line |
| PRIORLN | Count of LOT records with LOT < index LOT from ADLOT |
| NEOADJFL | 'Y' if neoadjuvant treatment found in PR/EX/CM |
| ADJUVFL | 'Y' if adjuvant treatment found in PR/EX/CM |

**CDISC RAG queries to run:**
- ADaM ADSL required variables and structure
- CDISC controlled terminology for SEX, RACE, ETHNIC
- ADaM date imputation conventions
- Charlson Comorbidity Index scoring weights
- TNM staging controlled terminology
- Biomarker result coding conventions

**Complexity flags:**
- **HIGH:** 101 variables with derivations spanning 11 source domains + ADLOT. See Section 5, Step 5 for the recommended modular implementation approach.
- **HIGH:** CCISCORE requires implementing the Charlson algorithm. **RESOLVED: Use Quan 2011 updated weights, derived from MH.MHTERM. Add a `# REVISIT: Quan 2011 weights used — see projects/exelixis-sap/artifacts/Open-questions-cdisc.md R1/R2` comment in the CCISCORE derivation block.**
- **MEDIUM:** Comorbidity flags require term-matching against MH.MHTERM — need to confirm the exact term lists.
- **MEDIUM:** Staging derivations depend on how TNM data is structured in MH.
- **NOTE:** DM does not contain ARM, ARMCD, or ACTARM — only ACTARMCD is present. Derive ARM/ACTARM from ACTARMCD using a lookup table if needed, or omit them if the spec does not require them.

⚠ **COMPLEXITY ALERT: 20 biomarker flags use identical pattern**

**Detected pattern:**
- Source: LB.LBSTRESC
- Operation: Pattern match for mutation status (ALTERED/NOT ALTERED/NOT TESTED)
- Parameters: Test code varies (EGFR, KRAS, ALK, ROS1, RET, MET, ERBB2, NTRK1, NTRK2, NTRK3, TP53, RB1, PDL1, MSI, TMB, ...)

**Recommend helper function:**

```r
create_biomarker_flag <- function(lb_data, test_code, var_name) {
  # Filter to baseline assessment for the specified test
  test_result <- lb_data %>%
    filter(LBTESTCD == test_code, LBBLFL == "Y") %>%
    select(USUBJID, LBSTRESC)

  # Create flag variable
  result <- test_result %>%
    mutate(
      !!var_name := case_when(
        LBSTRESC == "NOT ALTERED" ~ "N",
        LBSTRESC == "NOT TESTED" ~ NA_character_,
        str_detect(LBSTRESC, "ALTERED") ~ "Y",  # Catches "ALTERED" but not "NOT ALTERED"
        TRUE ~ NA_character_
      )
    ) %>%
    select(USUBJID, !!sym(var_name))

  return(result)
}
```

**Usage:**
```r
# Apply 20 times for all biomarker flags
egfr <- create_biomarker_flag(lb_bl, "EGFR", "EGFRMUT")
kras <- create_biomarker_flag(lb_bl, "KRAS", "KRASMUT")
alk <- create_biomarker_flag(lb_bl, "ALK", "ALK")
# ... (17 more)
```

**Benefits:**
- Single point of maintenance for pattern matching logic
- Easier to update if terminology changes (e.g., "POSITIVE" vs "ALTERED")
- Reduces cognitive load (20 derivations → 1 function + 20 calls)
- Fewer copy-paste errors

**Orchestration note:**
Programmer agent should implement helper function *first* (with tests), then apply 20 times.

**Additional note:**
Before implementing, run `/profile-data domain=LB variables=LBTESTCD,LBSTRESC` to verify actual terminology in the data. The March 28 run confirmed "ALTERED"/"NOT ALTERED" pattern, but always verify before coding.

---

### 4.4 ADRS — Response

**Row granularity:** One row per subject per tumor response assessment + one BOR summary row per subject
**Expected output:** Multiple rows per subject (visit-level responses + one BOR row)

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| RS | USUBJID, RSTESTCD, RSSTRESC, RSSTRESN, RSDTC, VISIT, VISITNUM, RSEVAL | Response assessments. **Filter to RSTESTCD = 'RECIST' for visit-level per-assessment records.** RSTESTCD = 'CLINRES' records are clinician-stated BOR and must NOT be used as the source for the derived BOR parameter (they may be used as a cross-validation check only). |
| DM | USUBJID, STUDYID | Identifiers |
| ADSL | USUBJID, TRTSDT | Index date for ADY calculation |

**Key derivations:**

| Variable | Derivation |
|----------|------------|
| PARAMCD | 'OVRLRESP' for per-visit overall response; 'BOR' for best overall response |
| PARAM | Full parameter description |
| AVALC | For OVRLRESP: RS.RSSTRESC (CR/PR/SD/PD/NE); For BOR: derived best response |
| AVAL | Numeric coding: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE |
| ADT | Numeric date of RS.RSDTC |
| ADY | ADT - ADSL.TRTSDT + 1 (or ADT - ADSL.TRTSDT if before index) |
| ABLFL | 'Y' for baseline assessment (last assessment before TRTSDT) |
| ANL01FL | 'Y' for records included in primary analysis |
| CNSR | Not applicable for ADRS (used in ADTTE) |

**BOR derivation logic (RECIST 1.1 — confirmed response required per SAP):**

SAP states: *"Both CR and PR will be confirmed based on RECIST1.1, and the minimum interval between 2 assessments should be no less than 4 weeks (28 days)."*

1. Collect all post-baseline OVRLRESP records per subject, ordered by ADT
2. **Confirmed CR:** Find any CR record where a second CR (or PR) record exists ≥28 days later. If found: BOR = CR
3. **Confirmed PR:** Find any PR record where a second PR (or CR) record exists ≥28 days later (and no confirmed CR). If found: BOR = PR
4. If SD present (and no confirmed CR/PR): BOR = SD
5. If only PD (and no SD/CR/PR): BOR = PD
6. If no evaluable post-baseline assessments: BOR = NE

Add `# REVISIT: Confirmed response per SAP (≥28-day interval). See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R3` in the BOR derivation block.

**CDISC RAG queries to run:**
- ADaM ADRS/BDS structure for oncology response
- RECIST 1.1 response criteria and BOR algorithm
- Controlled terminology for RS response values

**Complexity flags:**
- **MEDIUM:** BOR derivation requires careful ordering and confirmation logic.
- The AVAL numeric coding (1=CR through 5=NE) must be confirmed — this is a study-specific convention, not CDISC standard.

---

### 4.5 ADAE — Adverse Events

**Row granularity:** One row per adverse event
**Expected output:** One or more rows per subject (subjects with no AEs will not appear)

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| AE | USUBJID, AETERM, AEDECOD, AEBODSYS, AESTDTC, AEENDTC, AESER, AEREL, AESEV, AEACN, AEOUT, AESEQ | AE records |
| HO | USUBJID, HOTERM, HOSTDTC, HOENDTC, HOSEQ | Hospitalization linked to AE |
| ADSL | USUBJID, TRTSDT, TRTEDT | Treatment dates for TRTEMFL |

**Key derivations:**

| Variable | Derivation |
|----------|------------|
| AESTDT | Numeric date of AE.AESTDTC |
| AEENDT | Numeric date of AE.AEENDTC |
| ASTDY | AESTDT - ADSL.TRTSDT + 1 (or - if before) |
| AENDY | AEENDT - ADSL.TRTSDT + 1 (or - if before) |
| AEDUR | AEENDT - AESTDT + 1 (days) |
| TRTEMFL | 'Y' if AESTDT >= ADSL.TRTSDT |
| AEREL | Set if AE.AEREL == 'IO SACT' (study-specific relatedness) |
| HOSPDUR | Duration from HO domain: HOENDTC - HOSTDTC + 1, linked by AESEQ |
| CQ01NAM | Customized query name (if applicable) |
| AESEVN | Numeric severity: 1=MILD, 2=MODERATE, 3=SEVERE, 4=LIFE THREATENING, 5=DEATH |

**AE-HO linkage (RESOLVED):** The HO domain links to AE by `USUBJID` + `HO.HOHNKID == as.character(AE.AESEQ)`. The HOHNKID variable in HO stores the AE sequence number as a character string. Join as:
```r
ae %>% mutate(AESEQ_C = as.character(AESEQ)) %>%
  left_join(ho %>% select(USUBJID, HOHNKID, HOSTDTC, HOENDTC),
            by = c("USUBJID", "AESEQ_C" = "HOHNKID"))
```
HO columns available: STUDYID, DOMAIN, USUBJID, HOSEQ, HOTERM, HOSTDTC, HOENDTC, HOHNKID.

**CDISC RAG queries to run:**
- ADaM ADAE structure and required variables
- Treatment-emergent AE definition per ADaM-IG
- Controlled terminology for AESEV, AEOUT, AEREL

**Complexity flags:**
- **LOW:** HO domain linkage is resolved — direct key join on HOHNKID = AESEQ (see above).
- TRTEMFL logic is straightforward but must handle partial/missing AE start dates.

---

### 4.6 ADTTE — Time to Event

**Row granularity:** One row per subject per time-to-event parameter (PFS, OS, DOR)
**Expected output:** Up to 3 rows per subject (one per parameter)

**Source variables:**

| Domain | Variables | Purpose |
|--------|-----------|---------|
| RS | USUBJID, RSSTRESC, RSDTC | Progression date |
| DM | USUBJID, DTHDTC, DTHFL | Death date and flag |
| ADSL | USUBJID, TRTSDT, TRTEDT, RFENDTC | Index date, study end |
| ADRS | USUBJID, PARAMCD, AVALC, ADT | BOR and response dates for DOR |

**Key derivations:**

| PARAMCD | AVAL Derivation | CNSR Logic |
|---------|-----------------|------------|
| PFS | `min(progression_date, death_date, censor_date) - TRTSDT`, converted to months | 0 = progressed or died; 1 = censored at last disease assessment or data cutoff |
| OS | `min(death_date, censor_date) - TRTSDT`, converted to months | 0 = died; 1 = censored at last known alive date |
| DOR | `min(progression_date, death_date, censor_date) - first_response_date`, converted to months | 0 = progressed or died after response; 1 = censored; only for subjects with CR/PR |

**Common variables:**

| Variable | Derivation |
|----------|------------|
| STARTDT | ADSL.TRTSDT for PFS/OS; first response date for DOR |
| ADT | Event or censoring date |
| AVAL | (ADT - STARTDT + 1) / 30.4375 to convert days to months |
| CNSR | 0 = event occurred, 1 = censored |
| EVNTDESC | Description of event (e.g., 'PROGRESSIVE DISEASE', 'DEATH') |
| CNSDTDSC | Description of censoring reason (e.g., 'LAST DISEASE ASSESSMENT', 'LAST KNOWN ALIVE') |

**CDISC RAG queries to run:**
- ADaM ADTTE structure and required variables
- PFS censoring rules per FDA guidance
- OS censoring conventions
- DOR eligibility and censoring rules

**Complexity flags:**
- **MEDIUM:** Censoring rules for PFS are nuanced — must handle: (a) subjects who die without documented progression, (b) subjects lost to follow-up, (c) subjects who start new anticancer therapy before progression.
- DOR is only calculated for responders (CR/PR from ADRS) — requires filtering.
- Month conversion factor confirmed as 30.4375 — SAP explicitly specifies this for PFS, OS, and DOR.

---

## 5. R-Clinical-Programmer Agent Workflow

Each `r-clinical-programmer` agent assigned to a dataset must follow these 8 steps in exact order. Do not skip steps.

### Step 1: Read the Plan and Set Up

Read this plan document (`plans/plan_adam_automation_2026-03-29.md`), focusing on the section for the assigned dataset. Understand:
- Source domains and variables
- All derivation rules
- Dependency datasets (read SDTM from `projects/exelixis-sap/output-data/sdtm/`, ADaM from `projects/exelixis-sap/output-data/adam/`)
- Open questions flagged for the dataset
- The global conventions in Section 5.5 (flag convention, path convention, data source convention)

**Directory setup:** Ensure output directories exist before writing:
```r
if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)
if (!dir.exists("QA reviews")) dir.create("QA reviews", recursive = TRUE)
```

### Step 2: Query CDISC RAG

Use `mcp__npm-rag-v1__query_documents` and `mcp__npm-rag-v1__lookup_variable` to look up:
- ADaM structure requirements for the dataset type (ADSL, BDS, OCCDS, ADTTE as applicable)
- Controlled terminology for coded variables
- CDISC-mandated derivation rules (e.g., study day calculation, TRTEMFL definition)
- Study-specific variable definitions from the NPM-008 data dictionary (source: `ADS`)

Log all queries and key results in the dev log.

### Step 3: Write Comment Header

Every program must begin with a structured comment block:

```r
# =============================================================================
# Program: projects/exelixis-sap/programs/adam_<dataset>.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: <DATASET> — <Description>
# Author: r-clinical-programmer agent
# Date: 2026-03-29
#
# Source Domains:
#   - DM: USUBJID, STUDYID, RFSTDTC, ...
#   - AE: AETERM, AESTDTC, ...
#   (list all source domains and key variables)
#
# CDISC References:
#   - ADaM-IG v1.3 Section X.X
#   - (any RAG results referenced)
#
# Dependencies:
#   - ADSL (projects/exelixis-sap/output-data/adam/adsl.xpt) — required for TRTSDT
#   (list upstream ADaM datasets)
# =============================================================================
```

### Step 4: Explore Source Data

Before writing derivations, load and explore every source domain:

```r
# --- Exploration (temporary — remove before final save) ----------------------
# Frequency tables, summary stats, value distributions for key variables
# This informs derivation decisions (e.g., what values exist in LBTESTCD)
```

Execute this code to understand:
- Available values in categorical variables (e.g., what LBTESTCD codes exist in LB)
- Date completeness (how many missing dates)
- Row counts and subject counts per domain
- Any unexpected data patterns

**Record findings in the dev log.** Then remove or comment out exploration code before final save.

### Step 5: Implement Derivations

Write the production code following these conventions:

**Package loading:**
```r
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)
# library(admiral)  # Use admiral derive_* functions where applicable
```

**Data reading:**
```r
# --- Read source data --------------------------------------------------------
dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
ae <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ae.xpt")
# ... etc.
```

**Derivation sections:** Organize code into clearly labeled sections:
```r
# --- Derive treatment-emergent flag ------------------------------------------
# --- Derive AE duration -----------------------------------------------------
# --- Merge hospitalization data ----------------------------------------------
```

**Admiral usage:** Use `admiral` derivation functions where they exist and are appropriate:
- `admiral::derive_vars_dt()` for date conversions
- `admiral::derive_vars_dy()` for study day calculations
- `admiral::derive_var_trtemfl()` for treatment-emergent flag
- `admiral::derive_param_tte()` for time-to-event parameters
- `admiral::derive_var_obs_number()` for sequence variables

If an admiral function does not exist for a derivation, implement it with base tidyverse.

**xportr attributes:** No metacore specification object exists for this study. Apply labels manually using `attr()` for all variables, then use `xportr_label()` with a metadata data frame:
```r
# --- Apply attributes and write XPT -----------------------------------------
# Build metadata frame for xportr
<dataset>_meta <- tibble::tibble(
  variable = c("STUDYID", "USUBJID", ...),
  label    = c("Study Identifier", "Unique Subject Identifier", ...),
  type     = c("character", "character", ...)
)

<dataset> <- <dataset> %>%
  xportr_label(metadata = <dataset>_meta, domain = "<DATASET>") %>%
  xportr_type(metadata = <dataset>_meta, domain = "<DATASET>")
```

**ADSL modular approach (recommended):** Because ADSL has ~101 variables across 11+ source domains, implement in clearly separated derivation blocks with intermediate checkpoints. Save progress with `saveRDS()` after each major section (demographics, biomarkers, comorbidities, staging) so partial work is not lost if a later section errors:
```r
# --- Demographics block → save checkpoint ---
adsl_demo <- dm %>% ...
saveRDS(adsl_demo, "projects/exelixis-sap/output-data/adam/.adsl_checkpoint_demo.rds")

# --- Biomarker block → save checkpoint ---
adsl_bio <- adsl_demo %>% left_join(...) %>% ...
saveRDS(adsl_bio, "projects/exelixis-sap/output-data/adam/.adsl_checkpoint_bio.rds")

# ... etc. Clean up checkpoint files after final save.
```

### Step 6: Execute Until Error-Free

Source the program and resolve all errors:
- Fix syntax errors, missing variables, incorrect joins
- Handle edge cases (missing dates, subjects with no records in a domain)
- Log each iteration cycle in the dev log (what failed, how it was fixed)

### Step 7: Validate Output

Run validation checks and log results:

```r
# --- Validation checks -------------------------------------------------------
# Row count
message("Row count: ", nrow(<dataset>))
message("Subject count: ", n_distinct(<dataset>$USUBJID))

# Key variable completeness
sapply(<dataset>[, key_vars], function(x) sum(is.na(x)))

# CDISC compliance: unique keys
stopifnot(!any(duplicated(<dataset>[, c("USUBJID", "<key>")])))

# Cross-domain consistency: all subjects in DM
stopifnot(all(<dataset>$USUBJID %in% dm$USUBJID))
```

### Step 8: Save Final Program and Dataset

```r
# Save dataset
haven::write_xpt(<dataset>, "projects/exelixis-sap/output-data/<dataset>.xpt")
```

Save the final R program to: `projects/exelixis-sap/programs/adam_<dataset>.R`
Save the dev log to: `projects/exelixis-sap/logs_2026-03-29/dev_log_<dataset>_2026-03-29.md`

### Global Conventions (All Datasets)

These conventions apply to every ADaM program. Agents must follow them without exception.

**Flag convention (Y/blank):** All flag variables (e.g., TRTEMFL, DTHFL, BRAINMET, INDEXFL, ANL01FL, ABLFL) must use `'Y'` / `NA_character_` (blank), **not** `'Y'` / `'N'`. This follows ADaM-IG standard. Use: `ifelse(condition, "Y", NA_character_)`. This applies across all 6 datasets.

**Path convention:** All file paths must be relative to the project root. Never use absolute paths (e.g., `/Users/.../projects/exelixis-sap/output-data/`). SDTM domains are in `projects/exelixis-sap/output-data/sdtm/` (e.g., `projects/exelixis-sap/output-data/sdtm/dm.xpt`). ADaM datasets are in `projects/exelixis-sap/output-data/adam/` (e.g., `projects/exelixis-sap/output-data/adam/adsl.xpt`). Programs are executed from the project root directory.

**Data source convention:** Read all source SDTM data from `.xpt` files only. Do **not** read `.rds` files — they contain simulation-internal latent variables (e.g., `bor`, `pfs_days`, `death_ind`) that would not exist in real SDTM data. ADaM derivations must be reproducible from SDTM XPT files alone.

**ADRS AVAL numeric coding:** Use the study-specific convention: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE. This is intentional per the NPM-008 analysis plan (lower number = better response). Add a `# NOTE: Study-specific AVAL coding — not CDISC standard` comment where applied.

---

## 6. QA Reviewer Agent Workflow

Each `clinical-code-reviewer` agent assigned to a dataset must follow this process:

### Step 1: Read Plan and Implementation

1. Read this plan document, focusing on the assigned dataset section
2. Read the implemented program at `projects/exelixis-sap/programs/adam_<dataset>.R`
3. Read the dev log at `projects/exelixis-sap/logs_2026-03-29/dev_log_<dataset>_2026-03-29.md`

### Step 2: CDISC RAG Verification

Query the CDISC RAG server independently to verify:
- All variables have correct labels and types per ADaM standard
- Derivation logic matches CDISC-defined algorithms (e.g., study day, TRTEMFL)
- Controlled terminology values are valid
- Any non-standard variables are justified

### Step 3: Code Review Checklist

Check each item and record finding as BLOCKING / WARNING / NOTE:

**Correctness:**
- [ ] All source variables referenced actually exist in source domains
- [ ] Join keys are correct (USUBJID for cross-domain, appropriate compound keys within domain)
- [ ] Date conversions handle partial dates and missing values
- [ ] Study day calculation follows CDISC formula (no day zero)
- [ ] Numeric codings match specification (e.g., AVAL for response)
- [ ] Flag variables use 'Y'/blank (not 'Y'/'N') per ADaM convention — **unless spec says otherwise**

**Completeness:**
- [ ] All variables listed in the plan are present in the output
- [ ] All subjects from DM are represented (for ADSL) or appropriately filtered
- [ ] No unintended row duplication from joins

**Compliance:**
- [ ] xportr labels applied to all variables
- [ ] Variable names are uppercase, <= 8 characters
- [ ] Dataset written with `haven::write_xpt()`
- [ ] Comment header is complete and accurate

**Code quality:**
- [ ] Code follows R style rules (snake_case, tidyverse pipe, 2-space indent)
- [ ] Sections are clearly labeled with `# --- Section Name ---` headers
- [ ] No hardcoded values that should come from controlled terminology
- [ ] Error handling for edge cases (missing data, empty domains)

### Step 4: Execute and Verify

1. Source the program: `source("projects/exelixis-sap/programs/adam_<dataset>.R", chdir = FALSE)`
2. Verify it runs without errors or unexpected warnings
3. Load the output XPT and verify:
   - Row count matches expected granularity
   - Key variable distributions are reasonable
   - No unexpected NAs in required fields
   - Cross-domain consistency (all USUBJIDs in DM)

### Step 5: Produce QC Report

Save to `qa_2026-03-29/qa_adam_<dataset>_2026-03-29.md` with this structure:

```markdown
# QC Report: ADAM <DATASET>
**Date:** 2026-03-29
**Reviewer:** clinical-code-reviewer agent
**Program:** projects/exelixis-sap/programs/adam_<dataset>.R
**Plan:** plans/plan_adam_automation_2026-03-29.md

## Verdict: PASS / FAIL

## Summary
<1-3 sentence summary>

## Findings

### BLOCKING (must fix before approval)
- [ ] Finding description — location in code — recommended fix

### WARNING (should fix, not blocking)
- [ ] Finding description — location in code — recommendation

### NOTE (informational)
- Finding description

## Validation Results
- Row count: X
- Subject count: X
- Key variable completeness: (table)
- Execution: clean / warnings noted

## CDISC Compliance
- Variables verified against ADaM-IG: X/Y
- Non-standard variables: (list with justification status)
```

### After QC: Save Memories (if patterns identified)

After producing the QC report, if you identified patterns worth preserving, save them as memories to prevent repeating mistakes in future waves.

**Memory storage:** `.claude/agent-memory/`

**When to save memories:**

1. **Feedback memories** — save when:
   - You flagged an error pattern that could recur
   - You validated an approach that worked well
   - The programmer made a mistake you want to prevent in future waves

2. **Project memories** — save when:
   - Implementation revealed complexity not obvious from plan
   - You identified study-specific constraints
   - Algorithm required refactoring due to missing requirements

3. **Reference memories** — save when:
   - You discovered study-specific terminology (e.g., "ALTERED vs POSITIVE")
   - You identified domain quirks (e.g., "MH uses MHSTDTC not MHDTC")
   - Controlled terminology differs from CDISC standards

**Memory file format:**

```markdown
---
name: memory_name
description: One-line description for future searches
type: feedback | project | reference
---

[Lead with the rule/fact/finding]

**Why:** [The reason or incident that makes this important]

**How to apply:** [When and how to use this knowledge]
```

**After creating memory file:**
1. Update `.claude/agent-memory/MEMORY.md` index
2. Add one-line entry: `- [filename.md](filename.md) — description`

**Typical memories per wave:**
- Wave 1: 1-2 memories (algorithm complexity, domain quirks)
- Wave 2: 2-3 memories (terminology, patterns, conventions)
- Wave 3+: 0-1 memories (most patterns already captured)

Not every QC review requires new memories — only save patterns that are genuinely reusable.

---

## 7. Dev Log Template

Each `r-clinical-programmer` agent must maintain a log at `projects/exelixis-sap/logs_2026-03-29/dev_log_<dataset>_2026-03-29.md`:

```markdown
# Development Log: ADAM <DATASET>
**Date:** 2026-03-29
**Programmer:** r-clinical-programmer agent
**Program:** projects/exelixis-sap/programs/adam_<dataset>.R

## RAG Queries

### Query 1: <description>
- **Tool:** mcp__npm-rag-v1__query_documents / lookup_variable
- **Query:** "<exact query>"
- **Key results:** <summary of what was returned>
- **Decision:** <how this informed the implementation>

### Query 2: ...

## Exploration Findings

### <Domain> Domain
- Row count: X
- Subject count: X
- Key variable distributions:
  - <VAR>: <summary> (e.g., "LBTESTCD: 45 unique values, top 5: ...")
- Missing data: <VAR> has X% missing
- Notes: <anything unexpected>

## Derivation Decisions

### <Variable or derivation group>
- **Approach:** <what was implemented>
- **Rationale:** <why this approach, referencing RAG results or data exploration>
- **CT values used:** <list controlled terminology values selected>

## Iteration Log

### Iteration 1
- **Error/issue:** <description>
- **Root cause:** <what went wrong>
- **Fix:** <what was changed>

### Iteration 2 (if needed)
- ...

## Validation Results

- Final row count: X
- Final subject count: X
- Key variable completeness:
  | Variable | N | N Missing | % Complete |
  |----------|---|-----------|------------|
  | ... | | | |
- CDISC compliance checks: PASS/FAIL (details)
- Cross-domain consistency: PASS/FAIL
```

### Orchestration Log

The orchestrator (main conversation) must maintain a running log at `projects/exelixis-sap/logs_2026-03-29/orchestration_log_2026-03-29.md` that captures the full workflow. This log is the primary artifact for evaluating the end-to-end process after completion.

**The orchestrator must create and append to this log at each milestone.** Write the initial log before Wave 1 and append after each wave completes.

```markdown
# Orchestration Log: ADaM Automation — NPM-008
**Date:** 2026-03-29
**Plan:** plans/plan_adam_automation_2026-03-29.md

## Pre-Flight
- **Status:** PASS / FAIL
- **Domains checked:** 18/18 present
- **DM subjects:** 40
- **Packages:** all available
- **Notes:** <any issues>

## Wave 1: ADLOT + ADBS

### ADLOT
- **Agent spawned:** <timestamp or sequence>
- **Implementation status:** SUCCESS / FAIL (iteration count)
- **QC verdict:** PASS / FAIL
- **QC report:** qa_2026-03-29/qa_adam_adlot_2026-03-29.md
- **Fix cycles:** 0 / 1 / 2
- **Final row count:** X rows, X subjects
- **Program:** projects/exelixis-sap/programs/adam_adlot.R
- **Dataset:** projects/exelixis-sap/output-data/adam/adlot.xpt
- **Notes:** <any decisions, surprises, or deviations from plan>

### ADBS
- (same structure)

### Between-Wave Check
- **Status:** PASS / FAIL
- **Notes:** <cross-dataset consistency results>

## Wave 2: ADSL
(same structure per dataset)

## Wave 3: ADRS + ADAE
(same structure per dataset)

## Wave 4: ADTTE
(same structure per dataset)

## Final Summary
- **Total datasets:** X/6 completed
- **Total fix cycles:** X across all datasets
- **Datasets that required retry:** <list>
- **Unresolved issues escalated to user:** <list or "none">
- **Open questions encountered during implementation:** <list or "none">
```

---

## 8. Orchestration Guide

### Pre-Flight Validation (Run Before Wave 1)

Before spawning any agents, the orchestrator must run a comprehensive pre-flight check with three phases:

#### Phase 0: Validate Plan Structure

Run the plan validation command to check for anti-patterns, unresolved questions, and missing source data:

```r
# Load plan validation
source("R/validate_plan.R")

result <- validate_plan(
  plan_path = "plans/plan_adam_automation_2026-03-29.md",
  data_path = "output-data/sdtm"
)

cat("\n")
cat(result$report)
cat("\n")

# Check verdict
if (result$verdict == "BLOCKING") {
  stop("Plan validation FAILED with BLOCKING issues. Resolve before proceeding.", call. = FALSE)
} else if (result$verdict == "WARNING") {
  message("Plan validation passed with WARNINGS. Review before proceeding.")
} else {
  message("Plan validation PASSED.")
}
```

**Expected checks:**
- ✓ All source domains referenced in plan exist in data directory
- ✓ Open questions are resolved (no [ ] checkboxes, TODO, TBD markers)
- ⚠ ADSL complexity alert documented (101 variables)
- ⚠ Biomarker pattern alert documented (20 similar derivations)

**Verdict interpretation:**
- **PASS** → Proceed to Phase 1
- **WARNING only** → Log warnings, proceed to Phase 1
- **BLOCKING** → HALT, resolve issues, re-run validation

---

#### Phase 1: Profile Key Source Domains

Generate frequency tables for domains with terminology dependencies:

```r
# Load profiling function
source("R/profile_data.R")

# Profile LB domain - critical for biomarker flags
message("\nProfiling LB domain...")
profile_data(
  domain = "LB",
  variables = c("LBTESTCD", "LBSTRESC", "LBBLFL"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)

# Profile MH domain - critical for comorbidity flags and staging
message("\nProfiling MH domain...")
profile_data(
  domain = "MH",
  variables = c("MHCAT", "MHTERM"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)

# Profile QS domain - critical for ECOG baseline
message("\nProfiling QS domain...")
profile_data(
  domain = "QS",
  variables = c("QSTESTCD", "QSORRES", "QSBLFL"),
  data_path = "output-data/sdtm",
  output_path = "data-profiles"
)
```

**Profiles saved to:**
- `data-profiles/LB.md` — Verify "ALTERED"/"NOT ALTERED" terminology
- `data-profiles/MH.md` — Review comorbidity terms, staging values
- `data-profiles/QS.md` — Verify ECOG values, numeric vs character

**Review profiles before Wave 1** to catch terminology mismatches early.

---

#### Phase 2: Load Study Memories

Check for study-specific memories from previous runs:

```r
# Check for study-specific memories
memory_dir <- ".claude/agent-memory"
if (dir.exists(memory_dir)) {
  memory_files <- list.files(memory_dir, pattern = "\\.md$", full.names = TRUE)
  memory_files <- memory_files[!basename(memory_files) %in% c("MEMORY.md", "README.md")]

  if (length(memory_files) > 0) {
    message("\nFound ", length(memory_files), " memory file(s):")
    for (f in memory_files) {
      message("  - ", basename(f))
    }
    message("\nMemories will be automatically loaded by agents.")
  } else {
    message("\nNo study-specific memories found (first run).")
  }
} else {
  message("\nNo memory directory found (first run).")
}
```

**Expected memories (if available):**
- `xpt_flag_encoding.md` — ADaM Y/blank convention
- `npm008_biomarker_terminology.md` — ALTERED vs POSITIVE
- `lot_algorithm_complexity.md` — NPM LoT three-rule algorithm

Agents will automatically load these via `.claude/agent-memory/MEMORY.md`.

---

#### Phase 3: Basic Infrastructure Validation

```r
# --- Pre-flight validation (infrastructure) -----------------------------------
# 1. Required SDTM domains exist and are readable
required_domains <- c("dm", "ae", "bs", "cm", "ds", "ec", "ex", "ho",
                      "ie", "lb", "mh", "pr", "qs", "rs", "sc", "su",
                      "tr", "tu", "vs")
for (d in required_domains) {
  f <- file.path("projects/exelixis-sap/output-data/sdtm", paste0(d, ".xpt"))
  stopifnot(paste0(d, ".xpt exists") = file.exists(f))
}

# 2. DM has expected N subjects and columns
dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
stopifnot("DM has 40 subjects" = nrow(dm) == 40)
required_dm_cols <- c("STUDYID", "USUBJID", "RFSTDTC", "RFENDTC",
                      "DTHDTC", "DTHFL", "AGE", "SEX", "RACE",
                      "ETHNIC", "ACTARMCD", "BRTHDTC", "SITEID")
missing_cols <- setdiff(required_dm_cols, names(dm))
stopifnot("DM has all required columns" = length(missing_cols) == 0)

# 3. Required packages load
for (pkg in c("haven", "dplyr", "tidyr", "stringr", "lubridate",
              "xportr", "admiral", "purrr")) {
  stopifnot(paste0(pkg, " available") = requireNamespace(pkg, quietly = TRUE))
}

# 4. Output directories exist
if (!dir.exists("logs_2026-03-29")) dir.create("logs_2026-03-29", recursive = TRUE)
if (!dir.exists("qa_2026-03-29")) dir.create("qa_2026-03-29", recursive = TRUE)
if (!dir.exists("data-profiles")) dir.create("data-profiles", recursive = TRUE)

message("\n========================================")
message("All pre-flight phases PASSED")
message("========================================")
message("Ready for Wave 1")
```

**After pre-flight passes:** Create the orchestration log file at `projects/exelixis-sap/logs_2026-03-29/orchestration_log_2026-03-29.md` with the pre-flight results. Append to this log after each wave completes (see Section 7, Orchestration Log template).

### Retry Budget and Escalation

**Maximum 2 fix-reQC cycles per dataset.** If a dataset still FAILs after the programmer agent has addressed BLOCKING findings twice:
1. Pause the pipeline
2. Report to the user with: dataset name, unresolved findings, and the QA report path
3. Do not proceed to the next wave until user provides guidance

This prevents infinite loops that burn tokens without converging.

### Between-Wave Validation

After each wave completes and all datasets pass QC, run comprehensive validation checks:

```r
# --- Between-wave validation (run after Wave N QC passes) ---------------------
# Load validation functions
source("programs/between_wave_checks.R")
source("R/validate_referential_integrity.R")
source("R/validate_date_consistency.R")
source("R/validate_derived_variables.R")
source("R/validate_cross_domain.R")

# Run validation for completed wave
result <- run_between_wave_checks(
  wave_number = <N>,
  completed_datasets = c("<lowercase dataset names>"),
  data_path = "output-data/adam",
  auto_retry = TRUE
)

cat("\n")
cat("========================================\n")
cat("Wave ", <N>, " Validation: ", result$verdict, "\n")
cat("========================================\n")
```

**Validation coverage by wave:**

| Wave | Datasets Complete | Validation Checks |
|------|-------------------|-------------------|
| 1 | ADLOT, ADBS | Row/subject counts (basic) |
| 2 | ADSL | Referential integrity (ADSL vs DM) |
| 3 | ADRS, ADAE | Referential integrity (vs ADSL), Date consistency (TRTEMFL vs TRTSDT), BOR cardinality |
| 4 | ADTTE | Referential integrity (vs ADSL), Cross-domain consistency (DOR vs responders from ADRS) |

**Example usage:**

```r
# After Wave 2 (ADSL) passes QC
result <- run_between_wave_checks(
  wave_number = 2,
  completed_datasets = c("adsl"),
  data_path = "output-data/adam",
  auto_retry = TRUE
)

# Expected checks:
# ✓ ADSL vs DM referential integrity
# ✓ All 40 subjects from DM present in ADSL
# ✓ No orphan records

# After Wave 3 (ADRS + ADAE) passes QC
result <- run_between_wave_checks(
  wave_number = 3,
  completed_datasets = c("adsl", "adrs", "adae"),
  data_path = "output-data/adam",
  auto_retry = TRUE
)

# Expected checks:
# ✓ ADRS vs ADSL referential integrity
# ✓ ADAE vs ADSL referential integrity
# ✓ TRTEMFL logic: All AEs with TRTEMFL='Y' have AESTDT >= TRTSDT
# ✓ BOR cardinality: Exactly 1 BOR record per subject
```

**Verdict interpretation:**
- **PASS** → Proceed to next wave
- **WARNING** → Review warnings, proceed if acceptable
- **FAIL + auto_retry=TRUE** → Orchestrator recommends re-running wave
- **FAIL + auto_retry=FALSE** → HALT, escalate to user

**Append results to orchestration log.**

### Spawning Sequence

**Wave 1 — Spawn in parallel:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 1a. Implement ADLOT | `r-clinical-programmer` | This plan (Section 4.1) | `projects/exelixis-sap/programs/adam_adlot.R`, `projects/exelixis-sap/output-data/adam/adlot.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adlot_2026-03-29.md` |
| 1b. Implement ADBS | `r-clinical-programmer` | This plan (Section 4.2) | `projects/exelixis-sap/programs/adam_adbs.R`, `projects/exelixis-sap/output-data/adam/adbs.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adbs_2026-03-29.md` |

**Wave 1 QC — Spawn after 1a/1b complete:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 1c. QC ADLOT | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adlot.R` + dev log | `qa_2026-03-29/qa_adam_adlot_2026-03-29.md` |
| 1d. QC ADBS | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adbs.R` + dev log | `qa_2026-03-29/qa_adam_adbs_2026-03-29.md` |

**Gate:** Both 1c and 1d must PASS before proceeding. If FAIL, loop the programmer agent to fix BLOCKING findings, then re-QC. Max 2 fix-reQC cycles per dataset (see Retry Budget above).

**Wave 2 — Spawn after Wave 1 passes:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 2a. Implement ADSL | `r-clinical-programmer` | This plan (Section 4.3) + `projects/exelixis-sap/output-data/adam/adlot.xpt` | `projects/exelixis-sap/programs/adam_adsl.R`, `projects/exelixis-sap/output-data/adam/adsl.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adsl_2026-03-29.md` |

**Wave 2 QC:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 2b. QC ADSL | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adsl.R` + dev log | `qa_2026-03-29/qa_adam_adsl_2026-03-29.md` |

**Gate:** 2b must PASS before proceeding. Run between-wave consistency check. Max 2 fix-reQC cycles (see Retry Budget above).

**Wave 3 — Spawn in parallel after Wave 2 passes:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 3a. Implement ADRS | `r-clinical-programmer` | This plan (Section 4.4) + `projects/exelixis-sap/output-data/adam/adsl.xpt` | `projects/exelixis-sap/programs/adam_adrs.R`, `projects/exelixis-sap/output-data/adam/adrs.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adrs_2026-03-29.md` |
| 3b. Implement ADAE | `r-clinical-programmer` | This plan (Section 4.5) + `projects/exelixis-sap/output-data/adam/adsl.xpt` | `projects/exelixis-sap/programs/adam_adae.R`, `projects/exelixis-sap/output-data/adam/adae.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adae_2026-03-29.md` |

**Wave 3 QC:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 3c. QC ADRS | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adrs.R` + dev log | `qa_2026-03-29/qa_adam_adrs_2026-03-29.md` |
| 3d. QC ADAE | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adae.R` + dev log | `qa_2026-03-29/qa_adam_adae_2026-03-29.md` |

**Gate:** 3c must PASS before Wave 4. 3d is not blocking for Wave 4. Run between-wave consistency check. Max 2 fix-reQC cycles (see Retry Budget above).

**Wave 4 — Spawn after Wave 3 ADRS passes:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 4a. Implement ADTTE | `r-clinical-programmer` | This plan (Section 4.6) + `projects/exelixis-sap/output-data/adam/adsl.xpt` + `projects/exelixis-sap/output-data/adam/adrs.xpt` | `projects/exelixis-sap/programs/adam_adtte.R`, `projects/exelixis-sap/output-data/adam/adtte.xpt`, `projects/exelixis-sap/logs_2026-03-29/dev_log_adtte_2026-03-29.md` |

**Wave 4 QC:**

| Task | Agent | Input | Output |
|------|-------|-------|--------|
| 4b. QC ADTTE | `clinical-code-reviewer` | Plan + `projects/exelixis-sap/programs/adam_adtte.R` + dev log | `qa_2026-03-29/qa_adam_adtte_2026-03-29.md` |

### Agent Instructions Template

When spawning each `r-clinical-programmer` agent, provide:

```
Implement the <DATASET> ADaM dataset for the NPM-008 study.

Read the plan at: plans/plan_adam_automation_2026-03-29.md — Section 4.X, Section 5 (workflow),
and the "Global Conventions" subsection at the end of Section 5.
Follow the 8-step R-Clinical-Programmer Agent Workflow exactly.

CRITICAL RULES:
- Read ALL source SDTM data from .xpt files ONLY (never .rds files)
- Use RELATIVE paths only (e.g., "projects/exelixis-sap/output-data/sdtm/dm.xpt")
- Flag variables must use Y/blank (NA_character_), not Y/N
- Create projects/exelixis-sap/logs_2026-03-29/ directory if it does not exist before writing dev log
- Check projects/exelixis-sap/artifacts/Open-questions-cdisc.md for resolved decisions before implementing

Source data is in: projects/exelixis-sap/output-data/sdtm/ (SDTM XPT files) and projects/exelixis-sap/output-data/adam/ (ADaM XPT files)
[If dependent on upstream ADaM]: Read <upstream>.xpt from projects/exelixis-sap/output-data/adam/

Save program to: projects/exelixis-sap/programs/adam_<dataset>.R
Save dataset to: projects/exelixis-sap/output-data/adam/<dataset>.xpt
Save dev log to: projects/exelixis-sap/logs_2026-03-29/dev_log_<dataset>_2026-03-29.md
```

When spawning each `clinical-code-reviewer` agent, provide:

```
QC review the <DATASET> ADaM implementation for NPM-008.

Read the plan at: plans/plan_adam_automation_2026-03-29.md — Section 4.X, Section 6,
and the "Global Conventions" subsection at the end of Section 5.
Read the program at: projects/exelixis-sap/programs/adam_<dataset>.R
Read the dev log at: projects/exelixis-sap/logs_2026-03-29/dev_log_<dataset>_2026-03-29.md
Follow the QA Reviewer Agent Workflow in Section 6.

ADDITIONAL CHECKS (verify these explicitly):
- All source data read from .xpt files only (not .rds)
- All paths are relative (no absolute /Users/... paths)
- All flag variables use Y/blank convention (not Y/N)
- ADRS AVAL coding follows study-specific convention (1=CR through 5=NE)

Save QC report to: qa_2026-03-29/qa_adam_<dataset>_2026-03-29.md
```

---

## 9. Output File Map

| Type | File | Created by |
|------|------|------------|
| **Programs** | | |
| ADLOT program | `projects/exelixis-sap/programs/adam_adlot.R` | r-clinical-programmer |
| ADBS program | `projects/exelixis-sap/programs/adam_adbs.R` | r-clinical-programmer |
| ADSL program | `projects/exelixis-sap/programs/adam_adsl.R` | r-clinical-programmer |
| ADRS program | `projects/exelixis-sap/programs/adam_adrs.R` | r-clinical-programmer |
| ADAE program | `projects/exelixis-sap/programs/adam_adae.R` | r-clinical-programmer |
| ADTTE program | `projects/exelixis-sap/programs/adam_adtte.R` | r-clinical-programmer |
| **Datasets** | | |
| ADLOT | `projects/exelixis-sap/output-data/adam/adlot.xpt` | r-clinical-programmer |
| ADBS | `projects/exelixis-sap/output-data/adam/adbs.xpt` | r-clinical-programmer |
| ADSL | `projects/exelixis-sap/output-data/adam/adsl.xpt` | r-clinical-programmer |
| ADRS | `projects/exelixis-sap/output-data/adam/adrs.xpt` | r-clinical-programmer |
| ADAE | `projects/exelixis-sap/output-data/adam/adae.xpt` | r-clinical-programmer |
| ADTTE | `projects/exelixis-sap/output-data/adam/adtte.xpt` | r-clinical-programmer |
| **Dev Logs** | | |
| ADLOT log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adlot_2026-03-29.md` | r-clinical-programmer |
| ADBS log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adbs_2026-03-29.md` | r-clinical-programmer |
| ADSL log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adsl_2026-03-29.md` | r-clinical-programmer |
| ADRS log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adrs_2026-03-29.md` | r-clinical-programmer |
| ADAE log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adae_2026-03-29.md` | r-clinical-programmer |
| ADTTE log | `projects/exelixis-sap/logs_2026-03-29/dev_log_adtte_2026-03-29.md` | r-clinical-programmer |
| **QA Reports** | | |
| ADLOT QA | `qa_2026-03-29/qa_adam_adlot_2026-03-29.md` | clinical-code-reviewer |
| ADBS QA | `qa_2026-03-29/qa_adam_adbs_2026-03-29.md` | clinical-code-reviewer |
| ADSL QA | `qa_2026-03-29/qa_adam_adsl_2026-03-29.md` | clinical-code-reviewer |
| ADRS QA | `qa_2026-03-29/qa_adam_adrs_2026-03-29.md` | clinical-code-reviewer |
| ADAE QA | `qa_2026-03-29/qa_adam_adae_2026-03-29.md` | clinical-code-reviewer |
| ADTTE QA | `qa_2026-03-29/qa_adam_adtte_2026-03-29.md` | clinical-code-reviewer |
| **Orchestration Log** | | |
| Workflow log | `projects/exelixis-sap/logs_2026-03-29/orchestration_log_2026-03-29.md` | orchestrator (main conversation) |

---

## 10. Risks and Open Questions

> **Open questions tracker:** `projects/exelixis-sap/artifacts/Open-questions-cdisc.md` — all decisions and open items are maintained there. Programmers must check that file before implementing any derivation listed below.

### BLOCKING — Must Resolve Before Coding

| # | Question | Dataset | Impact | Status |
|---|----------|---------|--------|--------|
| 1 | **NPM LoT Algorithm:** What are the exact rules for grouping drugs into lines of therapy? | ADLOT | Cannot implement ADLOT (and therefore ADSL) without this | **RESOLVED (2026-03-29 SAP review):** Window=45 days, gap=120 days, switching='no' for NSCLC. See Section 4.1 and open-questions-cdisc.md R5. |
| 2 | **RECIST 1.1 Confirmation Requirement:** Does BOR require confirmed response (two consecutive CR or PR assessments) or is a single best assessment sufficient? | ADRS | Changes BOR derivation logic significantly | **RESOLVED (2026-03-29 SAP review):** Confirmed response required — ≥28-day interval between two CR/PR assessments per SAP. See Section 4.4 and open-questions-cdisc.md R3. |
| 3 | **Charlson Comorbidity Index Version:** Original 1987 Charlson weights or updated Quan 2011 weights? Are we using ICD-10 codes from MH.MHTERM or MedDRA preferred terms for CCI category mapping? | ADSL | Affects CCISCORE values | **RESOLVED:** Use Quan 2011 updated weights; derive from MH.MHTERM. Add `# REVISIT:` comment in code. See open-questions-cdisc.md R1/R2. |

### WARNING — Should Clarify Before or During Coding

| # | Question | Dataset | Impact |
|---|----------|---------|--------|
| 4 | **Biomarker LBTESTCD Values:** What are the exact LBTESTCD codes for the 20+ biomarkers (EGFR, KRAS, ALK, etc.) in the simulated LB data? Agent can discover via exploration, but a spec would be faster. | ADSL | Agent can work around this by exploring LB data |
| ~~5~~ | ~~**AE-HO Linkage Key**~~ | ~~ADAE~~ | **RESOLVED:** HO links to AE via `HOHNKID = as.character(AESEQ)`. See Section 4.5 and open-questions-cdisc.md R6. |
| 6 | **LOTENDRSN Mapping:** Exact mapping from CM.CMRSDISC and DS.DSTERM values to LOTENDRSN categories | ADLOT | May need manual mapping table |
| ~~7~~ | ~~**Month Conversion Factor**~~ | ~~ADTTE~~ | **RESOLVED — moved to R4** |
| ~~8~~ | ~~**Flag Convention (Y/blank vs Y/N)**~~ | ~~All~~ | **RESOLVED:** Use Y/blank (ADaM standard). See Global Conventions in Section 5 and open-questions-cdisc.md R7. |
| 9 | **ADBS ADaM Compliance:** ADBS is not a standard ADaM dataset name. Should it follow BDS structure, or is it a custom dataset with its own spec? | ADBS | Affects structure and required variables |
| 10 | **Neoadjuvant/Adjuvant Flag Logic:** What defines neoadjuvant vs adjuvant treatment? Is it based on temporal relationship to surgery (from PR domain), or on specific treatment categories? | ADSL | Affects NEOADJFL and ADJUVFL derivations |

### NOTE — Low Risk

| # | Note | Dataset |
|---|------|---------|
| 11 | Admiral package may not have functions for all NPM-008 specific derivations (ADLOT, CCISCORE). Fallback to tidyverse is expected. Admiral is installed and available. | ADLOT, ADSL |
| 12 | Simulated data may have cleaner patterns than real-world data. Derivations should still handle edge cases (missing dates, subjects with no records) defensively. | All |
| ~~13~~ | ~~`projects/exelixis-sap/logs_2026-03-29/` directory does not exist~~ — **RESOLVED:** Pre-flight validation and Step 1 now create `projects/exelixis-sap/logs_2026-03-29/` and `qa_2026-03-29/` directories automatically. | All |
| ~~14~~ | ~~ADRS AVAL numeric coding~~ — **RESOLVED:** Confirmed as intentional study-specific convention (1=CR through 5=NE). See Global Conventions in Section 5 and open-questions-cdisc.md R8. | ADRS |
| 15 | **DM does not contain ARM, ARMCD, or ACTARM** — only ACTARMCD is available. ADSL programs must derive ARM/ACTARM from ACTARMCD if needed, or omit them. | ADSL |
