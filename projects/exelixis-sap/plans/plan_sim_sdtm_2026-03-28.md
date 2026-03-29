# SDTM Simulation Plan: NPM-008 / XB010-101 External Control Arm

**Date:** 2026-03-28
**Study:** Exelixis XB010-101 ECA — Metastatic NSCLC External Controls
**Protocol:** NPM-008
**Domains:** 18 (DM, IE, MH, SC, SU, VS, LB, BS, EX, EC, CM, PR, QS, TU, TR, RS, AE, HO, DS)
**Working Directory:** projects/exelixis-sap/

---
## 1. Architecture

### Folder layout
```
projects/exelixis-sap/
  programs/
    sim_all.R            Master orchestrator — runs all domains in order, writes XPTs
    sim_dm.R
    sim_ex.R
    sim_ec.R
    sim_cm.R
    sim_pr.R
    sim_su.R
    sim_ae.R
    sim_ds.R
    sim_ho.R
    sim_mh.R
    sim_ie.R
    sim_bs.R
    sim_lb.R
    sim_vs.R
    sim_qs.R
    sim_tu.R
    sim_tr.R
    sim_rs.R
    sim_sc.R
  output-data/sdtm/     All SDTM XPT files written here (create if not present)
    dm.xpt
    ex.xpt
    ec.xpt
    cm.xpt
    pr.xpt
    su.xpt
    ae.xpt
    ds.xpt
    ho.xpt
    mh.xpt
    ie.xpt
    bs.xpt
    lb.xpt
    vs.xpt
    qs.xpt
    tu.xpt
    tr.xpt
    rs.xpt
    sc.xpt
```

### Packages required
- tidyverse (dplyr, tidyr, lubridate, purrr, stringr)
- haven (write_xpt)
- xportr (apply labels, types, lengths before export)

### Reproducibility
- `sim_all.R` sets `set.seed(42)` before sourcing any domain program
- Each domain program uses its own seed derived as `set.seed(42 + domain_offset)` where domain_offset is the domain's position in the execution order (DM=1, EX=2, ... SC=18). This allows any single domain to be re-run in isolation reproducibly.

### Constants (define once in sim_all.R, pass to each domain function)
```
STUDYID    <- "NPM008"
N_SUBJECTS <- 40
STUDY_END  <- as.Date("2027-01-31")
SITES      <- c("01","02","03","04","05")  # 5 de-identified sites
```

---

## 2. Dependency Chain and Execution Order

Each domain program is a self-contained R script that reads upstream XPTs (or in-memory data frames passed by `sim_all.R`) and writes its own XPT. The orchestrator passes data frames between domains to avoid re-reading files.

| Order | Domain | Inputs required | Notes |
|-------|--------|-----------------|-------|
| 1 | DM | none | Subject spine; all other domains join to this |
| 2 | IE | DM | I/E criteria; documents eligibility met at baseline |
| 3 | MH | DM | Medical history / comorbidities / prior cancer history |
| 4 | SC | DM | Subject characteristics (education, income, marital status) |
| 5 | SU | DM | Tobacco use history |
| 6 | VS | DM | Vital signs at baseline and follow-up |
| 7 | LB | DM | Lab results (eligibility labs, genomics); genomic profile assigned here |
| 8 | BS | DM, LB | Biospecimen records linked to LB genomic tests |
| 9 | EX | DM | Index line of therapy exposure (treatment name, dates) |
| 10 | EC | DM, EX | Exposure as collected (individual administrations) |
| 11 | CM | DM, EX, LB | Prior and concomitant meds; prior LoTs depend on LB genomic profile |
| 12 | PR | DM, MH | Procedures (surgery, radiation) |
| 13 | QS | DM | Questionnaires (CCI, ECOG, patient history) |
| 14 | TU | DM, EX | Tumor identification at baseline (target + non-target lesions) |
| 15 | TR | DM, TU, EX | Tumor measurements at each RECIST visit |
| 16 | RS | DM, TR, EX | Disease response assessments derived from TR trajectory |
| 17 | AE | DM, EX | Adverse events within treatment window |
| 18 | HO | DM, AE | Hospitalizations linked to serious AEs |
| 19 | DS | DM, RS, AE | Disposition (death, progression, last known alive) |

`sim_all.R` sources each script in this order, storing results as named data frames. At the end it writes all XPTs.

---

---

## 3. Simulation Architecture
### 3.1 Outcome assignment (generated once per subject in DM)

Each subject is assigned these latent outcome variables when DM is built:

**BOR (Best Overall Response):**
Sample each subject's BOR from:
- PR: 18%
- CR: 0%
- SD: 40%
- PD: 35%
- NE: 7%

**PFS duration (days from index date):**
- Responders (PR/CR): sample from Weibull(shape=1.5, scale=210) — approximates median ~6 months among responders
- SD patients: sample from Exponential(rate = log(2)/150) — median ~5 months stable then PD
- PD patients: sample from Exponential(rate = log(2)/45) — early progressors, median ~6 weeks to PD
- NE patients: set PFS = 0 (never evaluable — small tumors, early dropout)
- Cap PFS at (STUDY_END - RFSTDTC) for administrative censoring

**OS duration (days from index date):**
- Generate from Weibull(shape=1.2, scale=450) targeting median ~365 days (12 months)
- For subjects with PFS < OS, OS > PFS (they survive past progression for some time)
- OS is independently drawn then constrained: OS >= PFS + runif(30, 120) for non-NE patients
- Cap OS at (STUDY_END - RFSTDTC) for administrative censoring
- Death indicator: subjects where OS < (STUDY_END - RFSTDTC) are deceased (DTHFL = "Y")

**Censoring:**
- PFS event indicator: 1 = progression or death occurred before STUDY_END; 0 = censored
- Approximately 30% of subjects should have OS censored at STUDY_END

**Date de-identification:**
- Each subject gets a per-patient shift drawn from Uniform(-14, 14) days
- This shift is applied uniformly to ALL dates for that subject
- Store the shift as a latent variable in DM (not exported) to apply consistently across domains

---

### 3.2 Seed Strategy

`sim_all.R` sets `set.seed(42)` before sourcing any domain program. Each domain program uses its own seed derived as `set.seed(42 + domain_offset)` where domain_offset is the domain's position in the execution order (DM=1, EX=2, ... DS=19). This allows any single domain to be re-run in isolation reproducibly.

---

### 3.3 Date De-identification

Each subject gets a per-patient shift drawn from Uniform(-14, 14) days. This shift is applied uniformly to ALL dates for that subject. Store the shift as a latent variable in DM (not exported) to apply consistently across domains.

---

### 3.4 Cross-Domain Consistency

Cross-domain consistency is maintained through the dependency chain (Section 2). Each domain reads upstream domains and ensures all subjects, dates, and relationships are consistent.

---
### 3.5: Reusable Validation Functions

Three validation functions are required to validate SDTM domain data before writing XPT files. These functions are implemented in:
- `R/validate_sdtm_domain.R`
- `R/validate_sdtm_cross_domain.R`
- `R/log_sdtm_result.R`

Per `plans/plan_build_validation_functions_2026-03-28.md`.

---

### validate_sdtm_domain()

**Purpose:** Universal + domain-specific validation called by every `sim_*.R` before `write_xpt()`.

**Interface:**
```r
validate_sdtm_domain(
  domain_df,           # data frame to validate
  domain_code,         # character: domain code (e.g., "AE")
  dm_ref,              # data frame: DM dataset for cross-checks
  expected_rows,       # numeric vector c(min, max)
  ct_reference = NULL, # named list of CT value vectors
  domain_checks = NULL # function for custom checks
)
```

**Universal checks (U1-U10):**

| ID | Check | Action |
|----|-------|--------|
| U1 | DOMAIN matches expected | stop() |
| U2 | STUDYID = "NPM008" | stop() |
| U3 | USUBJID format | stop() |
| U4 | All USUBJID in DM | stop() |
| U5 | --SEQ unique per subject | stop() |
| U6 | No NA in required vars | stop() |
| U7 | Date format ISO 8601 | stop() |
| U8 | Row count in range | warning() |
| U9 | No duplicate rows | stop() |
| U10 | CT values valid | stop() |

**Domain-specific checks:** For each domain (4.1-4.19), specify a validation closure that checks domain-specific business rules:

| Domain | Key checks |
|--------|-----------|
| DM | Exactly 40 rows; RFSTDTC < RFENDTC; DTHFL distribution ~70%; all latent vars non-NA |
| EX | EXSTDTC = RFSTDTC; EXENDTC >= EXSTDTC; valid drug names |
| AE | AESTDTC within [EXSTDTC, EXENDTC]; AESEV/AETOXGR mapping; min 1 AE per subject |
| TR | All TULNKID exist in TU; TRSTRESN >= 0; RECIST constraints per BOR |
| RS | BOR matches DM latent BOR for all 40 subjects |
| HO | Every HOHNKID maps to valid AESEQ; HOSTDTC >= AESTDTC |
| DS | 40 rows; DSDECOD="DEATH" iff DTHFL="Y"; DSDTC >= RFSTDTC |
| LB | Biomarker values consistent with DM latent vars (PDL1, EGFR, ALK) |
| TU | TARGET count matches DM.n_target_lesions; METS match DM mets flags |
| EC | ECSTDTC >= EXSTDTC; ECENDTC <= EXENDTC; cycle count matches route |
| CM | Prior therapy dates < EXSTDTC; n_prior_lots matches DM |
| IE | 10 criteria per subject; IECAT valid |
| MH | Prior conditions before EXSTDTC; valid MHTERM |
| SC | Screening dates before EXSTDTC |
| SU | 1 surgery record per subject with surgery flag |
| VS | All VSTESTCD valid; values in physiologic range |
| PR | Procedure dates within study period |
| QS | Baseline and follow-up assessments; valid QSTESTCD |
| BS | Specimen collection dates match LB biomarker dates |

---

### validate_sdtm_cross_domain()

**Purpose:** Post-execution validation after all 18 domains generated.

**Interface:**
```r
validate_sdtm_cross_domain(
  sdtm_dir = "output-data/sdtm/",
  log_dir = "logs/"
)
```

**Checks (X1-X13):**

| ID | Check | Severity |
|----|-------|----------|
| X1 | Referential integrity: all USUBJID in DM | BLOCKING |
| X2 | All domains have 40 distinct USUBJID | BLOCKING |
| X3 | No events before RFSTDTC (except MH, CM) | BLOCKING |
| X4 | No events after DTHDTC for deceased | BLOCKING |
| X5 | TU.TULNKID ↔ TR.TULNKID | BLOCKING |
| X6 | AE.AESEQ ↔ HO.HOHNKID | BLOCKING |
| X7 | BS.BSREFID ↔ LB dates | WARNING |
| X8 | DS DEATH = DM DTHFL | BLOCKING |
| X9 | DS.DSDTC = DM.DTHDTC | BLOCKING |
| X10 | RS BOR = DM BOR | BLOCKING |
| X11 | Domain cardinality | WARNING |
| X12 | SEQ uniqueness | BLOCKING |
| X13 | File inventory (18 XPT) | BLOCKING |

**Output:** Markdown report at `logs/cross_domain_validation_{date}.md`

---

### log_sdtm_result()

**Purpose:** Structured logging from within `sim_*.R` programs.

**Interface:**
```r
log_sdtm_result(
  domain_code, wave, row_count, col_count,
  validation_result, notes = NULL, log_dir = "logs/"
)
```

**Output:** Appends to `logs/sdtm_domain_log_{date}.md`

---


---

### 3.6: CT Pre-Flight Validation

Before Wave 0 execution, the orchestrator must:

1. Query CDISC RAG for these codelists:
   - SEX (C66731), RACE (C74457), ETHNIC (C66790)
   - AEOUT (C66768), AEACN (C66767), AEREL (C66769), AESEV (C66769)
   - DSDECOD (C66727), EXROUTE (C66729), EXDOSFRM (C66726)
   - VSTESTCD (C66741), LBTESTCD (C65047)
   - IECAT

2. Store results in `output-data/sdtm/ct_reference.rds` as named list

3. Each `sim_*.R` loads this file and passes relevant vectors to `validate_sdtm_domain()`

4. If RAG returns empty: log gap, fall back to training knowledge, flag as NOTE

**RAG note:** The CDISC RAG has CT definitions but NOT SDTM-IG variable specs. Use it only for CT lookups.

---

---

## 4. Per-Domain Simulation Specifications

---
### 4.1 DM — Demographics
**Structure:** One record per subject (N=40)

**USUBJID construction:** `paste0("NPM008-", SITEID, "-", SUBJID)`
- SITEID: sample from c("01","02","03","04","05") with equal probability
- SUBJID: 6-character alphanumeric ID, e.g., "A02834" — generate as paste0("A", formatC(seq(1001,1040), width=5, flag="0"))

| Variable | Type | Rule |
|----------|------|------|
| STUDYID | Char | "NPM008" |
| DOMAIN | Char | "DM" |
| USUBJID | Char | See above |
| SUBJID | Char | e.g., "A01001" through "A01040" |
| RFSTDTC | Char | Index date: sample from 2022-01-01 to 2025-06-30, then apply per-patient date shift. Format YYYY-MM-DD. Must equal first EXSTDTC. |
| RFENDTC | Char | RFSTDTC + PFS_days (if progressed) or RFSTDTC + OS_days (if deceased without progression flag). For censored: min(STUDY_END, last_assessment_date). Format YYYY-MM-DD. |
| RFICDTC | Char | RFSTDTC - runif(7, 30) days (consent precedes index date). Apply date shift. |
| DTHDTC | Char | If DTHFL="Y": RFSTDTC + OS_days. Apply date shift. Format YYYY-MM-DD. If alive: NA (missing). |
| DTHFL | Char | "Y" if deceased; NA if alive |
| SITEID | Char | "01" through "05" |
| BRTHDTC | Char | Year only: as.character(year(RFSTDTC) - AGE). Per de-id rules: year only, no month/day. |
| AGE | Num | rnorm(n, mean=64, sd=9) truncated to [18, 84] — NSCLC age distribution |
| AGEU | Char | "YEARS" |
| SEX | Char | sample(c("M","F"), prob=c(0.55,0.45)) — NSCLC is slightly male-predominant |
| RACE | Char | sample(c("WHITE","BLACK OR AFRICAN AMERICAN","ASIAN","AMERICAN INDIAN OR ALASKA NATIVE","NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER","MULTIPLE","NOT REPORTED","UNKNOWN"), prob=c(0.70,0.12,0.10,0.02,0.01,0.02,0.02,0.01)) |
| ETHNIC | Char | sample(c("NOT HISPANIC OR LATINO","HISPANIC OR LATINO","NOT REPORTED","UNKNOWN"), prob=c(0.80,0.10,0.06,0.04)) |
| ACTARMCD | Char | sample(c("1","2","3","4","5","6","7","8","9"), prob=c(0.30,0.20,0.15,0.10,0.08,0.07,0.04,0.04,0.02)) — represents line of therapy arm |
| COUNTRY | Char | "USA" |

**Latent variables stored in DM data frame (NOT exported to XPT):**
- `bor`: each subject's assigned BOR (CR/PR/SD/PD/NE)
- `pfs_days`: PFS in days from RFSTDTC
- `os_days`: OS in days from RFSTDTC
- `death_ind`: 1 if deceased, 0 if censored
- `date_shift`: per-patient integer shift (-14 to +14)
- `pdl1_status`: "HIGH" (≥50%), "LOW" (<50%, ≥1%), "NEGATIVE" (<1%) — drives prior therapy
- `egfr_status`: "ALTERED" or "NOT ALTERED" (prob 15% altered) — drives 1L therapy
- `alk_status`: "ALTERED" or "NOT ALTERED" (prob 5% altered)
- `kras_status`: "ALTERED" or "NOT ALTERED" (prob 25% altered)
- `n_target_lesions`: sample(2:5, size=n) — number of target lesions for TU/TR
- `n_prior_lots`: sample(1:3, size=n, prob=c(0.4, 0.4, 0.2)) — lines prior to index
- `ecog_bl`: sample(c(0,1), prob=c(0.45,0.55)) — baseline ECOG
- `metastatic_sites`: sample(1:5, prob=c(0.15,0.30,0.25,0.20,0.10))
- `brain_mets`: sample(c(TRUE,FALSE), prob=c(0.15,0.85))
- `liver_mets`: sample(c(TRUE,FALSE), prob=c(0.20,0.80))
- `bone_mets`: sample(c(TRUE,FALSE), prob=c(0.35,0.65))
- `de_novo_met`: sample(c(TRUE,FALSE), prob=c(0.55,0.45)) — de novo vs recurrent metastatic

---

### 4.2 IE — Inclusion/Exclusion Criteria
**Structure:** One record per criterion per subject. Use 5 inclusion + 5 exclusion criteria = 10 records per subject (N=400 total).

All subjects meet all inclusion criteria (IEORRES="YES" for IC, IEORRES="NO" for EC, since all subjects were enrolled).

| Variable | Rule |
|----------|------|
| STUDYID | "NPM008" |
| DOMAIN | "IE" |
| USUBJID | From DM |
| IESEQ | Integer 1–10 per subject |
| IETESTCD | Use these codes: IC01, IC02, IC03, IC04, IC05, EC01, EC02, EC03, EC04, EC05 |
| IETEST | IC01="Pathologically confirmed locally advanced or metastatic NSCLC"; IC02="Radiographically measurable disease"; IC03="ECOG performance score 0 or 1"; IC04="Received prior systemic anticancer therapy"; IC05="Age 18 or older"; EC01="Radiation therapy within 14 days prior to index date"; EC02="Untreated brain metastases"; EC03="Severe liver disease per Charlson Comorbidity Index"; EC04="Surgery in 4 weeks prior to index date"; EC05="Diagnosis of another malignancy in 2 years prior to index date" |
| IECAT | "INCLUSION" for IC01-IC05; "EXCLUSION" for EC01-EC05 |
| IEORRES | Inclusion criteria: "YES"; Exclusion criteria: "NO" (all subjects eligible) |
| IESTRESC | Same as IEORRES |
| IEDTC | RFICDTC from DM (consent date). Apply date shift. |

---

### 4.3 MH — Medical History
**Structure:** Variable records per subject. Categories: COMORBIDITY DIAGNOSES, CANCER DIAGNOSIS, TUMOR GRADE, HISTOLOGY, CLINICAL STAGING GROUP, PATHOLOGIC STAGING GROUP.

Every subject gets one CANCER DIAGNOSIS record (NSCLC primary). Additional comorbidity records generated based on CCI components. Typical subject: 2–5 MH records.

**NSCLC primary diagnosis record (all subjects):**

| Variable | Value |
|----------|-------|
| MHTERM | "Non-small cell lung cancer" |
| MHCAT | "CANCER DIAGNOSIS" |
| MHSTDTC | RFSTDTC - runif(90, 1460) days (diagnosed 3 months to 4 years before index). Apply date shift. |
| MHENDTC | NA (ongoing) |

**Comorbidity records (probabilistic per subject):**
Draw each comorbidity flag; if TRUE, create an MH record. Use CCI component probabilities for a 2L+ NSCLC population:

| MHTERM | Probability | MHCAT |
|--------|-------------|-------|
| "Coronary Artery Disease" | 0.15 | "COMORBIDITY DIAGNOSES" |
| "Congestive Heart Failure" | 0.08 | "COMORBIDITY DIAGNOSES" |
| "Peripheral Vascular Disease" | 0.10 | "COMORBIDITY DIAGNOSES" |
| "Cerebrovascular Disease" | 0.08 | "COMORBIDITY DIAGNOSES" |
| "Chronic Pulmonary Disease" | 0.20 | "COMORBIDITY DIAGNOSES" |
| "Diabetes Without Complications" | 0.18 | "COMORBIDITY DIAGNOSES" |
| "Diabetes With Complications" | 0.05 | "COMORBIDITY DIAGNOSES" |
| "Renal Disease" | 0.10 | "COMORBIDITY DIAGNOSES" |
| "Mild Liver Disease" | 0.05 | "COMORBIDITY DIAGNOSES" |
| "Rheumatic Disease" | 0.05 | "COMORBIDITY DIAGNOSES" |
| "Peptic Ulcer Disease" | 0.05 | "COMORBIDITY DIAGNOSES" |

MH dates: MHSTDTC = RFSTDTC - runif(30, 1095) days. Apply date shift.

**Histology record (all subjects):**

| Variable | Value |
|----------|-------|
| MHTERM | sample(c("Adenocarcinoma","Squamous Cell Carcinoma","Large Cell Carcinoma","NSCLC NOS"), prob=c(0.60,0.25,0.05,0.10)) |
| MHCAT | "HISTOLOGY" |
| MHSTDTC | Same as NSCLC diagnosis date |

**Staging record at initial diagnosis:**

| Variable | Value |
|----------|-------|
| MHTERM | sample(c("Stage IV","Stage IIIB","Stage IIIA"), prob=c(0.70,0.20,0.10)) |
| MHCAT | "CLINICAL STAGING GROUP" |
| MHSTDTC | Same as NSCLC diagnosis date |

All MH records: MHSEQ = sequential integer per subject.

---

### 4.4 SC — Subject Characteristics
**Structure:** 3 records per subject (EDUC, MARISTAT, INCOME). N=120 total.

| SCTESTCD | SCTEST | SCORRES values (with probabilities) |
|----------|--------|-------------------------------------|
| EDUC | "Highest level of education completed" | sample(c("Did not graduate High School","Graduated High School","Attended College or Technical School","Graduated from College or Technical School","Graduate Degree"), prob=c(0.10,0.25,0.25,0.25,0.15)) |
| MARISTAT | "Marital status" | sample(c("Married or Domestic Partner","Single","Divorced","Widowed","Separated","Unknown"), prob=c(0.50,0.15,0.15,0.12,0.03,0.05)) |
| INCOME | "Annual household income" | sample(c("Less than $25,000","$25,000 to less than $50,000","$50,000 to less than $75,000","$75,000 to less than $100,000","$100,000 or more","Prefer not to answer","Unknown"), prob=c(0.15,0.20,0.20,0.15,0.20,0.05,0.05)) |

SCSEQ: 1, 2, 3 per subject.
SCDTC: RFICDTC from DM.

---

### 4.5 SU — Substance Use
**Structure:** 1 record per subject (tobacco only). N=40.

NSCLC is strongly associated with smoking. Assign smoking status:
- Current smoker (40%): SUDOSE = runif(n, 5, 40) cigs/day; SUDUR = paste0("P", sample(10:40,1), "Y")
- Former smoker (45%): SUDOSE = 0 at time of consent; SUDUR = paste0("P", sample(5:35,1), "Y")
- Never smoker (15%): SUDOSE = 0; SUDUR = "P0Y"

| Variable | Value |
|----------|-------|
| STUDYID | "NPM008" |
| DOMAIN | "SU" |
| SUTRT | "CIGARETTES" |
| SUCAT | "TOBACCO" |
| SUPRESP | "Y" |
| SUDOSE | See above |
| SUDOSU | "CIGARETTES/DAY" |
| SUDUR | ISO 8601 duration e.g., "P20Y" |

Note: DOMAIN should be "SU" (the data dictionary has a typo showing "EX" — use "SU").

---

### 4.6 VS — Vital Signs
**Structure:** 9 vital sign tests × 2 visits (BASELINE, FOLLOWUP) = 18 records per subject. N=720 total.

Visits: BASELINE (RFSTDTC - 7 days), FOLLOWUP (RFSTDTC + 42 days = ~6 weeks).

| VSTESTCD | VSTEST | VSSTRESU | Baseline distribution | Follow-up |
|----------|--------|----------|-----------------------|-----------|
| HR | "Heart Rate" | "BPM" | rnorm(n, 78, 12) truncated [50,120] | baseline ± rnorm(0,5) |
| SYSBP | "Systolic Blood Pressure" | "mm Hg" | rnorm(n, 128, 15) truncated [90,180] | baseline ± rnorm(0,8) |
| DIABP | "Diastolic Blood Pressure" | "mm Hg" | rnorm(n, 78, 10) truncated [55,110] | baseline ± rnorm(0,6) |
| SPO2 | "SPO2" | "Percent oxygen" | rnorm(n, 96, 2) truncated [88,100] | baseline ± rnorm(0,1) |
| RESP | "Respirations" | "Breaths per minute" | rnorm(n, 17, 2) truncated [12,25] | baseline ± rnorm(0,1) |
| TEMP | "Temperature" | "Degrees Fahrenheit" | rnorm(n, 98.4, 0.5) truncated [97,100.5] | baseline ± rnorm(0,0.3) |
| HT | "Height" | "cm" | rnorm(n, 170, 10) truncated [150,200]. Set once; FOLLOWUP = baseline. |
| WT | "Weight" | "kg" | rnorm(n, 75, 15) truncated [45,130]. FOLLOWUP = baseline × rnorm(1, 0.97, 0.03) (slight weight loss) |
| BMI | "BMI" | "kg/m^2" | Derived: WT / (HT/100)^2 |

Apply date shift to VSDTC. All values rounded to 1 decimal place.

---

### 4.7 LB — Laboratory Test Results
**Structure:** Two categories of lab tests:
1. **Clinical labs** (eligibility labs): measured at BASELINE for all subjects
2. **Genomic/biomarker tests**: measured once (BASELINE), one record per test per subject

**Category 1 — Clinical labs at BASELINE (9 tests × 40 subjects = 360 records):**

| LBTESTCD | LBTEST | LBORRESU | Distribution (must meet eligibility thresholds) |
|----------|--------|----------|-------------------------------------------------|
| ANC | "Absolute Neutrophil Count (ANC)" | "x10^3/uL" | rnorm(n, 3.5, 0.8) truncated [1.5, 8.0] — eligibility: ≥1.5 |
| HEMOGL | "Hemoglobin" | "g/dL" | rnorm(n, 11.5, 1.5) truncated [9.0, 16.0] — eligibility: ≥9.0 |
| PLATELT | "Platelets" | "x10^3/uL" | rnorm(n, 220, 60) truncated [100, 500] — eligibility: ≥100 |
| ALT | "Alanine Aminotransferase (ALT)" | "U/L" | rnorm(n, 28, 12) truncated [8, 90] — for subjects with liver mets: truncated [8, 150]; eligibility: ≤3×ULN=105 (or ≤5×ULN=175 with liver mets) |
| AST | "Aspartate Aminotransferase (AST)" | "U/L" | rnorm(n, 30, 12) truncated [8, 90] — same liver mets rule as ALT |
| BILIRUB | "Total Bilirubin" | "mg/dL" | rnorm(n, 0.7, 0.25) truncated [0.2, 1.5] — eligibility: ≤1.5×ULN=1.5 |
| SCREAT | "Serum Creatinine" | "mg/dL" | rnorm(n, 0.9, 0.2) truncated [0.5, 2.0] — CrCl derived via Cockcroft-Gault ≥45 |
| ALBUM | "Albumin" | "g/dL" | rnorm(n, 3.8, 0.5) truncated [2.5, 5.0] |
| WBC | "White Blood Cell count (WBC)" | "x10^3/uL" | rnorm(n, 7.5, 2.0) truncated [2.5, 15.0] |

VISIT = "BASELINE"; LBDTC = RFSTDTC - runif(5,21) days. Apply date shift.
LBSPEC = "Blood"; LBMETHOD = "STANDARD CLINICAL"; LBSTAT = NA; LBRESTYP = NA.

**Category 2 — Genomic biomarker tests (1 record per test per subject):**

Each test is one record in LB with LBSPEC = "Tissue/Bone Marrow" (or "Blood" for ctDNA liquid biopsy), VISIT = "BASELINE".

Assign genomic profile to each subject using the latent variables from DM. Generate LBORRES from these:

| LBTESTCD | LBTEST | LBORRESU | LBORRES values |
|----------|--------|----------|----------------|
| PDL1SUM | "PD-L1 Summary" | "expression" | HIGH (pdl1_status="HIGH"), LOW (pdl1_status="LOW"), NEGATIVE (pdl1_status="NEGATIVE"), "Not Stated" (5%) |
| PDL1SC | "PD-L1 Score" | "percentage" | If HIGH: runif(50,100); if LOW: runif(1,49); if NEGATIVE: runif(0,1). Round to nearest integer. |
| PDL1TYPE | "PD-L1 Score Type" | "score type" | sample(c("TPS","CPS"), prob=c(0.70,0.30)) |
| EGFR | "EGFR Mutation Status" | "mutation status" | "ALTERED" (egfr_status="ALTERED"), "NOT ALTERED", "VUS" (2%), "NOT TESTED" (3%) |
| ALK | "ALK Rearrangement Status" | "mutation status" | "ALTERED" (alk_status="ALTERED"), "NOT ALTERED", "VUS" (1%), "NOT TESTED" (5%) |
| KRAS | "KRAS Mutation Status" | "mutation status" | "ALTERED" (kras_status="ALTERED"), "NOT ALTERED", "NOT TESTED" (5%) |
| MET | "MET Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.03,0.82,0.05,0.10)) |
| ROS1 | "ROS1 Rearrangement Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.02,0.85,0.03,0.10)) |
| TP53 | "TP53 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.45,0.45,0.05,0.05)) |
| NTRK1 | "NTRK 1 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.01,0.85,0.04,0.10)) |
| NTRK2 | "NTRK 2 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.01,0.85,0.04,0.10)) |
| NTRK3 | "NTRK 3 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.01,0.85,0.04,0.10)) |
| RB1 | "RB1 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.08,0.82,0.05,0.05)) |
| RET | "RET Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.02,0.85,0.03,0.10)) |
| ERBB2 | "ERBB2/HER2 Mutation Status" | "mutation status" | sample(c("ALTERED","NOT ALTERED","VUS","NOT TESTED"), prob=c(0.03,0.85,0.05,0.07)) |
| HER2IHC | "HER2 IHC" | "score" | sample(c("0","1+","2+","3+","QNS","Indeterminate"), prob=c(0.50,0.25,0.15,0.05,0.03,0.02)) |
| MSISTAT | "Microsatellite Instability Status (MSI)" | "status" | sample(c("MSS","MSI-HIGH","NOT TESTED"), prob=c(0.93,0.02,0.05)) |
| TMB | "Tumor Mutational Burden (TMB)" | "mut/Mb" | rnorm(n, 8, 5) truncated [1, 40]. Round to 1 decimal. |
| LOHSUM | "LOH Summary Statement" | "status" | sample(c("Low","High","Indeterminate","Not Stated"), prob=c(0.50,0.35,0.08,0.07)) |
| LOHSC | "LOH Score" | "percentage" | If LOHSUM="Low": runif(0,16); if "High": runif(16,50). Round to 1 decimal. |
| MMRMLH1 | "MMR MLH1 Expression Status" | "expression" | sample(c("Positive/Intact","Negative/Absent"), prob=c(0.97,0.03)) |
| MMRMSH2 | "MMR MSH2 Expression Status" | "expression" | sample(c("Positive/Intact","Negative/Absent"), prob=c(0.97,0.03)) |
| MMRMSH6 | "MMR MSH6 Expression Status" | "expression" | sample(c("Positive/Intact","Negative/Absent"), prob=c(0.97,0.03)) |
| MMRPMS2 | "MMR PMS2 Expression Status" | "expression" | sample(c("Positive/Intact","Negative/Absent"), prob=c(0.97,0.03)) |
| MMROVER | "Overall MMR expression" | "status" | "Proficient" if all 4 MMR proteins intact; "Deficient" if any absent |
| CORES | "Number of Cores" | "number of cores" | sample(2:8, replace=TRUE) |

LBNAM: sample from c("Foundation Medicine, Inc","Tempus Labs, Inc","Guardant Health","Caris Life Sciences","Neogenomics Laboratories, Inc") with equal probability.
LBDTC = RFSTDTC - runif(30,90) days (biopsy before index). Apply date shift.
LBSEQ: sequential integer per subject across all lab records.

---

### 4.8 BS — Biospecimen Findings
**Structure:** One record per biospecimen per subject. Subjects have 1–3 biospecimen records (tissue biopsy types).

Link to LB via BSREFID = LBREFID (a shared specimen ID). Since LB doesn't have LBREFID in the spec, create BSREFID as a generated alphanumeric ID and store in BS.

| Variable | Value |
|----------|-------|
| BSREFID | Alphanumeric specimen ID, e.g., "BS-001-001" (site-subj-specimen) |
| BSTESTCD | "FFPEBL" for FFPE block; "FFPESL" for FFPE slides; "HE" for H&E slides |
| BSTEST | "FFPE block"; "FFPE slides"; "H&E slides" |
| BSSPEC | sample(c("Primary Tumor","Metastatic Tissue"), prob=c(0.60,0.40)) |
| BSANTREG | ICD-O3 code for lung primary: "C34.1" (upper lobe), "C34.2" (middle lobe), "C34.3" (lower lobe) — sample with prob c(0.40,0.10,0.50) |
| BSMETHOD | "FFPE" |
| BSHIST | sample(c("8140/3","8070/3","8012/3","8046/3"), prob=c(0.60,0.25,0.05,0.10)) — ICD-O3: adenocarcinoma, squamous cell, large cell, NSCLC NOS |
| BSDTC | Same as genomic LB LBDTC for this subject. Apply date shift. |

Each subject gets records for FFPEBL and FFPESL (always); HE is included 80% of subjects.

---

### 4.9 EX — Exposure (Index Line of Therapy)
**Structure:** One record per subject representing the index (≥2L) line of therapy. N=40.

Treatment name depends on PD-L1 status, EGFR/ALK status, and line of therapy (from DM latent variables):

**Treatment selection logic for index line:**
- If EGFR altered: "Osimertinib" (ORAL, 80mg)
- Else if ALK altered: "Alectinib" (ORAL, 600mg)
- Else if n_prior_lots == 1 (2L) and pdl1_status == "HIGH": sample(c("Pembrolizumab","Docetaxel"), prob=c(0.40,0.60))
- Else if n_prior_lots == 1 (2L): sample(c("Docetaxel","Pemetrexed","Docetaxel + Ramucirumab"), prob=c(0.40,0.30,0.30))
- If n_prior_lots >= 2 (3L+): sample(c("Docetaxel","Pemetrexed","Nivolumab"), prob=c(0.40,0.30,0.30))

| Variable | Value |
|----------|-------|
| STUDYID | "NPM008" |
| DOMAIN | "EX" |
| EXSEQ | 1 per subject |
| EXLNKID | "1" (index line) |
| EXTRT | Per treatment selection logic above |
| EXDOSTXT | Dose as text: Osimertinib "80", Alectinib "600", Pembrolizumab "200", Docetaxel "75", Pemetrexed "500", Ramucirumab "10", Nivolumab "240" |
| EXDOSU | Osimertinib/Alectinib: "mg"; IV drugs: "mg/m2" or "mg/kg" as appropriate; Ramucirumab: "mg/kg" |
| EXROUTE | Osimertinib/Alectinib: "ORAL"; others: "INTRAVENOUS" |
| EXADJ | Reason treatment ended: If pfs_days < os_days: sample(c("Progressive Disease","Adverse Event (Side Effects of Cancer Treatment)","Planned Therapy Completed"), prob=c(0.70,0.20,0.10)); if deceased: "Progressive Disease" |
| EXSTDTC | RFSTDTC (index date). Apply date shift. |
| EXENDTC | RFSTDTC + min(pfs_days, os_days) — end when progressed or died. For censored PFS: STUDY_END or last assessment. Apply date shift. |

---

### 4.10 EC — Exposure as Collected
**Structure:** Multiple records per subject — one per administration cycle. For IV drugs: 21-day cycles from EXSTDTC to EXENDTC. For oral drugs: one record (continuous dosing).

For subjects on oral therapy (Osimertinib, Alectinib): 1 EC record per subject.
For subjects on IV therapy: n_cycles = ceiling(treatment_days / 21), max 12 cycles.

| Variable | Value |
|----------|-------|
| ECLNKID | Same as EXLNKID = "1" |
| ECTRT | Same as EXTRT |
| ECDOSE | Numeric dose (same as EXDOSTXT) |
| ECDOSU | Same as EXDOSU |
| ECSTDTC | Cycle 1: EXSTDTC; Cycle k: EXSTDTC + (k-1)*21 |
| ECENDTC | Cycle k: ECSTDTC + 20 (21-day cycle); last cycle ends at EXENDTC |

ECSEQ: sequential integer per subject across all EC records.

---

### 4.11 CM — Concomitant/Prior Medications
**Structure:** Variable per subject. Two categories:
1. Prior lines of therapy (pre-index): n_prior_lots × 1-2 drugs per line
2. Concomitant supportive medications: 1–4 records per subject

**Prior lines of therapy rules:**
- All subjects had ≥1 prior line (since index is ≥2L)
- 1st line drugs determined by PDL1 status and EGFR/ALK (1L was before index):
  - If EGFR altered: "Osimertinib" or "Erlotinib" (1L EGFR-targeted)
  - If ALK altered: "Crizotinib" or "Lorlatinib" (1L ALK-targeted)
  - If PDL1 HIGH and no driver mutation: sample(c("Pembrolizumab","Carboplatin + Paclitaxel + Pembrolizumab"), prob=c(0.40,0.60))
  - Else: "Carboplatin + Paclitaxel + Pembrolizumab" or "Carboplatin + Pemetrexed + Pembrolizumab" (prob 0.50 each)
- If n_prior_lots >= 2: add a 2nd prior line (between 1L and index)
- CMSTDTC: start 1L = RFSTDTC - (n_prior_lots * runif(120,240)) days
- CMENDTC: each prior line ends when the next begins (or at index date for the most recent prior line)

**Concomitant supportive medications (1–4 per subject, independent of prior LoTs):**

| CMTRT | Probability | CMDOSU |
|-------|-------------|--------|
| "Ondansetron" | 0.50 | "mg" |
| "Dexamethasone" | 0.40 | "mg" |
| "Filgrastim" | 0.20 | "mcg" |
| "Metoprolol" | 0.25 | "mg" |
| "Lisinopril" | 0.20 | "mg" |
| "Atorvastatin" | 0.30 | "mg" |
| "Omeprazole" | 0.35 | "mg" |
| "Lorazepam" | 0.20 | "mg" |

CMSTDTC: within treatment window; CMENDTC: some ongoing (NA), some resolved. Apply date shift.
CMSEQ: sequential integer per subject.

---

### 4.12 PR — Procedures
**Structure:** Variable per subject. Categories: Surgery, Radiation, Surgery/pathology (specimen), Pathology only.

Not all subjects have procedures. About 50% have had radiation pre-index; 30% have had surgery.

| Variable | Rule |
|----------|------|
| PRTRT | If PRCAT="Radiation": "Radiation"; if Surgery: "Surgery" or "Biopsy" |
| PRCAT | sample(c("Surgery (no specimen)","Radiation","Surgery/pathology (specimen)","Pathology only (specimen)"), prob=c(0.10,0.35,0.25,0.30)) — only generate if subject had this procedure |
| PRLOC | ICD-O3 topography code: "C34.1", "C34.2", "C34.3" for lung (upper, middle, lower lobe) |
| PRSTDTC | Pre-index: RFSTDTC - runif(30, 730) days. Apply date shift. |
| PRENDTC | PRSTDTC + runif(0, 14) days (brief procedure). Apply date shift. |

PRSEQ: sequential per subject.

---

### 4.13 QS — Questionnaires
**Structure:** Multiple records per subject. Categories include Comorbidity Survey (CCI components), Patient History Form, Clinical Patient Questionnaire.

**Comorbidity Survey records (CCI items):**
For each of the 12 CCI-relevant conditions, one QS record per subject at BASELINE.
QSTESTCD = short code (max 6 chars): e.g., "CCI01" through "CCI12"
QSCAT = "Comorbidity Survey"
QSORRES = "Yes" or "No" — consistent with MH comorbidity flags
VISIT = "BASELINE"; QSDTC = RFICDTC

**ECOG record (all subjects, baseline):**
QSTESTCD = "ECOG", QSTEST = "Eastern Cooperative Oncology Group (ECOG) Performance Score"
QSCAT = "Medical Oncology"
QSORRES = as.character(ecog_bl) from DM latent variable
VISIT = "BASELINE"

**Smoking status record:**
QSTESTCD = "SMOKE", QSTEST = "Smoking status"
QSCAT = "Patient History Form"
QSORRES = "Current" / "Former" / "Never" per SU domain values

**Income + Education + Marital status records** (consistent with SC domain):
QSTESTCD = "INCOME", "EDUC", "MARISTAT"
QSCAT = "Clinical Patient Questionnaire"
QSORRES = same values as SC.SCORRES for this subject

QSSEQ: sequential integer per subject.

---

### 4.14 TU — Tumor Identification
**Structure:** n_target_lesions TARGET lesions + 1-2 NON-TARGET lesions per subject at baseline. Plus one METS record per metastatic site.

**BASELINE TARGET lesion records:**
For each subject, generate n_target_lesions (2–5 from DM latent) target lesion records:

| Variable | Value |
|----------|-------|
| TULNKID | "T01", "T02", ... "T05" (for target lesions) |
| TUTESTCD | "TUASSESS" |
| TUTEST | "Tumor Identification" |
| TUORRES | "TARGET" |
| TULOC | sample from: "Lung","Liver","Bone","Brain","Adrenal Gland","Lymph Node","Chest Wall" weighted by metastatic pattern (lung always present; others per mets flags) |
| TUDIR | For lung: sample(c("Right Upper Lobe (RUL)","Right Middle Lobe (RML)","Right Lower Lobe (RLL)","Left Upper Lobe (LUL)","Left Lower Lobe (LLL)")); others: NA |
| TUMETHOD | sample(c("CT","PET/CT","MRI"), prob=c(0.70,0.20,0.10)) |
| VISITNUM | 1 |
| VISIT | "Baseline RECIST assessment" |
| TUDTC | RFSTDTC - runif(1, 28) days. Apply date shift. |

**NON-TARGET lesion records (1–2 per subject, 70% of subjects):**
Same structure; TUORRES = "NON-TARGET"; TULNKID = "NT01", "NT02"

**METS identification records (one per metastatic site for subjects with mets):**
TUTESTCD = "METS"; TUTEST = "First date of metastatic disease for cancer primary"
TUORRES = "METASTASIS"; TULOC = metastatic site (Brain if brain_mets=TRUE, etc.)

TUSEQ: sequential integer per subject.

---

### 4.15 TR — Tumor Results
**Structure:** n_target_lesions measurements per visit. Visits at baseline + every ~6 weeks until PFS event.

**Visit schedule (from RFSTDTC):**
- Baseline: RFSTDTC - 7 days (pre-index scan)
- Week 6: RFSTDTC + 42 days
- Week 12: RFSTDTC + 84 days
- Week 18: RFSTDTC + 126 days
- Week 24: RFSTDTC + 168 days
- Week 30: RFSTDTC + 210 days
- Week 36: RFSTDTC + 252 days
- After week 48: every 84 days (12+2 weeks)

Stop generating visit records when the visit date exceeds RFSTDTC + pfs_days (PFS event = progression).

**Lesion size trajectory by BOR:**
For each target lesion, baseline size = runif(15, 80) mm (measurable disease ≥10mm per RECIST).

BOR-driven size trajectories (multiplicative change per visit):

| BOR | Trajectory |
|-----|-----------|
| PR | Decrease 15–35% from prior visit for visits 1–3, then stable or slight increase until progression |
| CR | Decrease to 0 (or <5mm) by visit 2–3, remains 0 |
| SD | ±10% change per visit (random walk, bounded to not trigger PD) |
| PD | Increase 15–30% per visit from baseline |
| NE | Only baseline recorded; subject missed all follow-up visits |

Constraint: RECIST PD = ≥20% increase from nadir AND ≥5mm absolute increase. Ensure trajectory consistency.
Constraint: RECIST PR = ≥30% decrease from baseline. Ensure PR subjects achieve this by visit 2.
Round all sizes to 1 decimal place (mm).

TRLNKID links to TU.TULNKID. TRSEQ: sequential integer per subject.
Add ±3 day jitter to each visit date to reflect real-world scheduling. Apply date shift.

---

### 4.16 RS — Disease Response
**Structure:** One record per visit per subject for RECIST 1.1 assessment (same visit schedule as TR) + one record for clinician-stated BOR.

**RECIST 1.1 records (one per RECIST visit):**

| Variable | Value |
|----------|-------|
| RSTESTCD | "RECIST" |
| RSTEST | "RECIST 1.1" |
| RSCAT | "RECIST 1.1" |
| RSEVAL | "Independent" |
| RSORRES | Derive from TR: sum of target lesion sizes; compare to baseline and nadir to assign CR/PR/SD/PD/NE per RECIST rules |
| RSDTC | Same date as corresponding TR visit |

**RECIST response derivation rules:**
- Visit response = CR if all targets ≤5mm (or 0)
- Visit response = PR if sum decreased ≥30% from baseline sum
- Visit response = PD if sum increased ≥20% from nadir AND ≥5mm absolute increase
- Visit response = SD otherwise
- NE if no measurements recorded

**Clinician-stated BOR record (one per subject):**

| Variable | Value |
|----------|-------|
| RSTESTCD | "CLINRES" |
| RSTEST | "Clinician-Stated Best Overall Response" |
| RSCAT | "RECIST 1.1" |
| RSEVAL | "Physician" |
| RSORRES | bor from DM latent (CR/PR/SD/PD/NE) — note: BOR follows RECIST hierarchy applied to all visit assessments |
| RSDTC | RFSTDTC + pfs_days (date of response determination). Apply date shift. |

RSSEQ: sequential integer per subject.

---

### 4.17 AE — Adverse Events
**Structure:** Variable per subject. Average 2–4 AEs per subject. AE dates must fall within EX treatment window (EXSTDTC to EXENDTC).

Common NSCLC treatment AEs by drug class:

| AEDECOD | AECAT | Probability | Grades (distribution) |
|---------|-------|-------------|----------------------|
| "Diarrhea" | "SACT" | 0.35 | Grade 1: 50%, 2: 30%, 3: 15%, 4: 5% |
| "Fatigue" | "SACT" | 0.40 | Grade 1: 55%, 2: 35%, 3: 10%, 4: 0% |
| "Nausea" | "SACT" | 0.30 | Grade 1: 60%, 2: 30%, 3: 10%, 4: 0% |
| "Rash" | "SACT" | 0.25 | Grade 1: 50%, 2: 35%, 3: 14%, 4: 1% |
| "Hematologic Toxicities (neutropenia, etc)" | "SACT" | 0.25 | Grade 1: 20%, 2: 30%, 3: 35%, 4: 15% |
| "ILD/Pneumonitis" | "SACT" | 0.08 | Grade 1: 20%, 2: 40%, 3: 30%, 4: 10% |
| "Peripheral Neuropathy" | "SACT" | 0.20 | Grade 1: 55%, 2: 35%, 3: 10%, 4: 0% |
| "Hypoalbuminemia" | "SACT" | 0.15 | Grade 1: 60%, 2: 30%, 3: 10%, 4: 0% |
| "Constipation" | "SACT" | 0.20 | Grade 1: 60%, 2: 30%, 3: 10%, 4: 0% |
| "Edema" | "SACT" | 0.15 | Grade 1: 50%, 2: 35%, 3: 15%, 4: 0% |
| "Dyspnea" | "SACT" | 0.20 | Grade 1: 40%, 2: 40%, 3: 18%, 4: 2% |
| "Vomiting" | "SACT" | 0.20 | Grade 1: 55%, 2: 35%, 3: 10%, 4: 0% |

For IO-treated subjects (Pembrolizumab, Nivolumab): add ILD/Pneumonitis probability × 2; add QTc prolongation (prob 0.05).
For EGFR-targeted (Osimertinib): add Paronychia (prob 0.25) and Stomatitis/Mucositis (prob 0.20).

AETERM = AEDECOD (verbatim = coded for simulated data).
AEACN: Grade 1-2 → NA or "Treatment Held" (20%); Grade 3 → "Treatment Held" (50%) or "Treatment Discontinued" (30%); Grade 4 → "Treatment Discontinued" (70%) or "Treatment Held" (30%).
AESHOSP: Grade 3-4 → "Y" (40%); Grade 1-2 → "N".
AEREL: "IO SACT" for IO drugs; "non-IO SACT" for chemotherapy; "SACT" for unknown.
AESTDTC: uniform random within (EXSTDTC, EXENDTC). Apply date shift.
AEENDTC: AESTDTC + runif(5, 60) days; Grade 4 AEs may extend to death. Apply date shift.
AELNKID: integer link to EXSEQ.
AESEQ: sequential integer per subject.

---

### 4.18 HO — Healthcare Encounters
**Structure:** One record per hospitalization. Only for subjects with AESHOSP="Y" serious AEs. About 15–20% of subjects will have ≥1 hospitalization.

| Variable | Value |
|----------|-------|
| HOTERM | "AE-related hospitalization" |
| HOSTDTC | AESTDTC + runif(0,3) days (hospitalized at or shortly after AE onset). Apply date shift. |
| HOENDTC | HOSTDTC + runif(3, 14) days (hospitalization duration). Apply date shift. |

One HO record per qualifying AE (AESHOSP="Y").
HOSEQ: sequential integer per subject.

---

### 4.19 DS — Disposition
**Structure:** One record per subject. Final disposition at study end.

| BOR / Outcome | DSTERM | DSDECOD |
|---------------|--------|---------|
| Deceased | "Death" | "DEATH" |
| Lost to follow-up | "Lost to Follow-Up" | "LOST TO FOLLOW-UP" |
| Alive at study end | "Last Known Alive" | "COMPLETED" |
| In hospice | "In-Hospice" | "COMPLETED" |

Assign 70% deceased (matching ~30% OS censored → 70% events by study end for 40 patients, median OS 12 months).
Of alive subjects: 80% "Last Known Alive", 20% "In-Hospice".
DSDTC = DTHDTC if deceased; else RFSTDTC + os_days (last contact date). Apply date shift.
DSCAT = "DISPOSITION EVENT"
DSSEQ = 1 per subject.

---

---
## 5: Program Template

Each domain simulation program follows this structure:

```r
# =============================================================================
# sim_{domain}.R — {Domain Full Name}
# Study: NPM-008 / XB010-101 ECA
# Seed: 42 + {offset}
# Wave: {wave_number}
# Dependencies: {list_of_upstream_rds_files}
# Expected rows: {min}-{max}
# Working directory: projects/exelixis-sap/
# =============================================================================

set.seed(42 + {offset})

# --- Load dependencies -------------------------------------------------------
dm_full <- readRDS("output-data/sdtm/dm.rds")
# ... other upstream domains as needed

# --- Load CT reference (if applicable) ----------------------------------------
ct_ref <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Source validation functions ----------------------------------------------
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Generate domain data -----------------------------------------------------
# ... (domain-specific logic from plan section 4.X)

# --- Domain-specific validation closure ----------------------------------------
domain_checks <- function(df, dm_ref) {
  checks <- list()
  # ... domain-specific checks defined in Section 3.5
  checks
}

# --- Validate before writing ---------------------------------------------------
validation <- validate_sdtm_domain(
  domain_df      = {domain}_df,
  domain_code    = "{DOMAIN}",
  dm_ref         = dm_full,
  expected_rows  = c({min}, {max}),
  ct_reference   = ct_ref[c("{relevant_codelists}")],
  domain_checks  = domain_checks
)

# --- Write output (only if validation passes) ---------------------------------
haven::write_xpt({domain}_df, path = "output-data/sdtm/{domain}.xpt")
saveRDS({domain}_df, "output-data/sdtm/{domain}.rds")

# --- Log result ---------------------------------------------------------------
log_sdtm_result(
  domain_code       = "{DOMAIN}",
  wave              = {wave_number},
  row_count         = nrow({domain}_df),
  col_count         = ncol({domain}_df),
  validation_result = validation,
  notes             = c({notes})
)

message("sim_{domain}.R complete: ", nrow({domain}_df), " rows written")
```

**Template placeholders:**
- `{domain}`: lowercase domain code (e.g., "dm", "ae")
- `{DOMAIN}`: uppercase domain code (e.g., "DM", "AE")
- `{Domain Full Name}`: human-readable domain name (e.g., "Demographics", "Adverse Events")
- `{offset}`: domain offset for seed (1 for DM, 2 for IE, ..., 19 for DS)
- `{wave_number}`: wave number (0-4)
- `{list_of_upstream_rds_files}`: comma-separated list of dependencies (e.g., "dm.rds, ex.rds")
- `{min}`, `{max}`: expected row count range
- `{relevant_codelists}`: CT codelist names relevant to this domain (e.g., "SEX", "RACE")
- `{notes}`: optional notes for logging

---

---

## 6. Output Specifications

All SDTM XPT files are written to: `projects/exelixis-sap/output-data/sdtm/`

Each domain also saved as RDS for faster re-reading: `projects/exelixis-sap/output-data/sdtm/{domain}.rds`

Logs written to: `projects/exelixis-sap/logs/`

---
## 7: Orchestration Guide

### Wave Structure

Execution is organized into 6 waves. Each wave is a synchronization point: all domains in a wave run in parallel; the next wave starts only when ALL agents in the prior wave return SUCCESS.

**Wave assignments:**

```
Wave 0:  DM                                          (1 agent, sequential)
Wave 1:  IE, MH, SC, SU, VS, LB, PR, QS, TU, EX, DS  (11 agents, parallel)
Wave 2:  AE, BS, EC, CM                              (4 agents, parallel)
Wave 3:  HO, TR                                      (2 agents, parallel)
Wave 4:  RS                                           (1 agent, sequential)
Wave 5:  Cross-domain validation + data contract      (1 agent, sequential)
```

**Total agents spawned:** 1 + 11 + 4 + 2 + 1 + 1 = 20 agents

---

### Dependency Rationale

| Domain | Reads | Wave placement |
|--------|-------|----------------|
| DM | (none) | Wave 0 — foundation |
| IE, MH, SC, SU, VS, LB, PR, QS, TU, EX, DS | dm.rds only | Wave 1 — parallel after DM |
| AE, BS, EC, CM | dm.rds + one other (ex.rds or lb.rds) | Wave 2 — parallel after Wave 1 |
| HO, TR | dm.rds + domain from Wave 2 (ae.rds or tu.rds) | Wave 3 — parallel after Wave 2 |
| RS | dm.rds + tr.rds | Wave 4 — sequential after Wave 3 |

**Wave 1 domains (11):** All depend only on DM, so they can run in parallel once DM completes.
**Wave 2 domains (4):** AE/EC need EX; BS needs LB; CM needs EX+LB. All Wave 1 outputs available.
**Wave 3 domains (2):** HO needs AE; TR needs TU. All Wave 2 outputs available.
**Wave 4 domain (1):** RS needs TR. Must wait for Wave 3.
**Wave 5 (validation):** Reads all 18 domains. Must wait for Wave 4.

---

### Wave Gate Rules

1. A wave starts only when ALL agents in the prior wave return SUCCESS
2. Each agent runs its `sim_*.R`, which internally calls `validate_sdtm_domain()`
3. If any agent returns FAIL, orchestrator logs failure and HALTS — no subsequent waves
4. Between-wave checkpoint: log summary table of completed domains
5. Orchestrator uses **parallel Agent tool calls** within each wave (multiple Agent invocations in a single message)

---

### Wave 0 Extra Validation (DM Smoke Tests)

After DM completes, before proceeding to Wave 1, verify:
- AGE: mean in [60, 68], sd in [6, 12]
- SEX: M count in [18, 26] (target ~55%)
- RACE: WHITE count in [24, 32] (target ~70%)
- DTHFL="Y": count in [26, 30] (target ~70%)
- BOR: PR [5-10], SD [13-19], PD [11-17], NE [1-5]
- All latent variables non-NA
- RFSTDTC range: 2022-01-01 to 2025-06-30

These are tolerance checks, not exact matches. They catch catastrophic distribution errors early.

---

### Orchestration Instructions

**For the orchestrator (main conversation):**

1. **Pre-Flight (before Wave 0):**
   - Verify directory structure: `output-data/sdtm/`, `logs/` exist
   - Query CDISC RAG for CT references (Section 3.6)
   - Save CT reference to `output-data/sdtm/ct_reference.rds`
   - Log pre-flight results to orchestration log

2. **Wave 0: DM**
   - Spawn 1 r-clinical-programmer agent for DM
   - Pass: domain code, wave number, seed offset, expected rows, plan section reference
   - Agent produces: `dm.xpt`, `dm.rds`, dev log
   - Orchestrator runs DM smoke tests
   - If smoke tests FAIL: HALT and report
   - If PASS: proceed to Wave 1

3. **Wave 1: 11 domains**
   - Spawn 11 r-clinical-programmer agents in parallel (single message with 11 Agent tool calls)
   - Each agent gets: domain code, wave number, seed offset, expected rows, plan section reference
   - Wait for all 11 to complete
   - Log between-wave checkpoint: domains completed, validation status
   - If any FAIL: HALT
   - If all PASS: proceed to Wave 2

4. **Wave 2: 4 domains**
   - Spawn 4 r-clinical-programmer agents in parallel
   - Same pattern as Wave 1
   - Proceed to Wave 3 if all PASS

5. **Wave 3: 2 domains**
   - Spawn 2 r-clinical-programmer agents in parallel
   - Same pattern
   - Proceed to Wave 4 if all PASS

6. **Wave 4: RS**
   - Spawn 1 r-clinical-programmer agent
   - Same pattern
   - Proceed to Wave 5 if PASS

7. **Wave 5: Cross-Domain Validation**
   - Run `validate_sdtm_cross_domain()` function
   - If data contract validator exists: run `validate_data_contract()`
   - Log results to orchestration log
   - If BLOCKING issues: HALT and report
   - If PASS: mark overall execution SUCCESS

8. **Final Summary:**
   - Write summary table to orchestration log: domain, wave, rows, validation, duration
   - Report overall verdict: PASS/FAIL

---

---

---

## 8. CDISC Compliance Checklist

The r-clinical-programmer must verify each domain satisfies:

- [ ] **Variable names**: uppercase only, max 8 characters
- [ ] **DOMAIN variable**: 2-char uppercase abbreviation, constant within domain
- [ ] **STUDYID**: constant "NPM008" across all records
- [ ] **USUBJID consistency**: every USUBJID in non-DM domains must exist in DM
- [ ] **--SEQ variables**: unique integers within each USUBJID per domain (1 to nrow per subject)
- [ ] **ISO 8601 dates**: all --DTC variables formatted YYYY-MM-DD; partial dates (year only for BRTHDTC) are allowed
- [ ] **--DY variables**: if any domain needs study day, calculate as: on/after RFSTDTC: as.numeric(date - rfstdtc) + 1; before RFSTDTC: as.numeric(date - rfstdtc)
- [ ] **xportr pipeline**: before haven::write_xpt(), run xportr::xportr_label(), xportr::xportr_type(), xportr::xportr_length() using a metadata spec data frame
- [ ] **haven::write_xpt()**: write to `projects/exelixis-sap/output-data/sdtm/<domain>.xpt` in lowercase
- [ ] **No real patient data**: all values are simulated; set.seed() used for reproducibility
- [ ] **Date shift applied consistently**: every date for a subject uses the same shift value
- [ ] **All required variables present**: STUDYID, DOMAIN, USUBJID, --SEQ at minimum per domain

---

---

## 9. Ambiguities and Assumptions

The following variables have ambiguous or missing specifications in the data dictionary. The programmer should apply these assumptions:

| Variable | Ambiguity | Assumption |
|----------|-----------|------------|
| DM.ACTARMCD | Values listed as "1"-"9" with no description | Treat as index line number (1=1L, 2=2L, etc.) — set to n_prior_lots + 1 |
| SU.DOMAIN | Data dictionary shows "EX" which appears to be a typo | Use "SU" (correct CDISC domain abbreviation) |
| CM.CMRSDISC | Values include cancer response terms but this is a reason for discontinuation | For prior LoTs: "Progressive Disease" or "Planned Therapy Completed"; for supportive care: "Planned Therapy Completed" |
| LB.LBNAM | This is the laboratory name field | Assign per subject consistently (one primary genomics lab per subject) |
| QS — ECOG | ECOG is in QS but also appears in SC via derived ECOG variables | Encode ECOG in QS (questionnaire) and also optionally in SC if needed for ADaM derivation |
| BS.BSREFID | No explicit link back to LB in the spec | Generate a shared specimen ID and store in both BS.BSREFID and as a comment in LB metadata |
| RS.RSTESTCD "RESIST 1.1" | Data dictionary has a typo ("RESIST") | Use the correct spelling "RECIST" in RSTESTCD and RSTEST |
| HO link to AE | No explicit link variable in HO spec | Add HOHNKID (or HOFKNKID) as a custom linkage variable pointing to AE.AESEQ; flag this as a study-specific addition |

---

---

## 10: Logging & QA Artifacts

All logs and reports produced during SDTM simulation execution.

**Required artifacts:**

| Artifact | Path | Written by |
|----------|------|-----------|
| Orchestration log | `logs/orchestration_log_sdtm_{date}.md` | Orchestrator (main conversation) |
| Per-domain dev logs | `logs/dev_log_sim_{domain}_{date}.md` | r-clinical-programmer agents |
| Machine validation log | `logs/sdtm_domain_log_{date}.md` | `log_sdtm_result()` calls |
| Cross-domain validation | `logs/cross_domain_validation_{date}.md` | `validate_sdtm_cross_domain()` |
| Data contract validation | `logs/data_contract_validation_{date}.md` | `validate_data_contract()` |
| Consolidated QA report | `QA Analyses/qa_sdtm_{date}.md` | clinical-code-reviewer agent |

---

### Orchestration Log Format

```markdown
# Orchestration Log: SDTM Simulation — NPM-008

**Date:** {date}
**Plan:** plans/plan_sim_sdtm_{date}.md

## Pre-Flight

- CT reference: {codelist_count} codelists, {gap_count} gaps
- Directory structure: verified
- Packages: {list} — all available

## Wave 0: DM

- Agent spawned: {timestamp}
- Implementation: SUCCESS/FAIL
- Validation: PASS/FAIL ({check_count} checks)
- DM smoke tests: PASS/FAIL
- Row count: 40
- Duration: {seconds}s

## Wave 1: IE, MH, SC, SU, VS, LB, PR, QS, TU, EX, DS (11 parallel)

### {DOMAIN}
- Status: SUCCESS/FAIL
- Validation: PASS/FAIL
- Row count: {actual} (expected: {min}-{max})
- Fix cycles: {n}

### Between-Wave Check
- Wave 1: {pass_count}/11 PASS
- Cumulative: {total_pass}/{total_attempted}

## Wave 2: AE, BS, EC, CM (4 parallel)
...

## Wave 3: HO, TR (2 parallel)
...

## Wave 4: RS
...

## Wave 5: Cross-Domain Validation
- Cross-domain: PASS/FAIL ({blocking} BLOCKING, {warning} WARNING)
- Data contract: PASS/FAIL

## Summary Table

| Domain | Wave | Rows | Cols | Validation | Fix Cycles | Duration |
|--------|------|------|------|------------|------------|----------|

## Final Verdict

- Total domains: {n}/18
- Total fix cycles: {n}
- First-pass successes: {n}/18
- Cross-domain: PASS/FAIL
- Data contract: PASS/FAIL
- **Overall: PASS/FAIL**
```

---

### Per-Domain Dev Log Format

Each r-clinical-programmer agent writes:

```markdown
# Development Log: sim_{DOMAIN}

**Date:** {date}
**Domain:** {DOMAIN} ({full_name})
**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA
**Agent:** r-clinical-programmer
**Wave:** {wave_number}
**Seed:** 42 + {offset} = {seed}

## 1. Plan Review
- Requirements from plan section 4.X
- Key variables, expected row count, dependencies
- Upstream domains required: {list}

## 2. CDISC RAG Queries
- CT lookups: {codelists_checked}
- Findings: {values_confirmed_or_gaps}

## 3. Implementation Notes
- Approach taken
- Deviations from plan (if any, with rationale)
- Errors encountered and fixes applied
- Internal iteration count: {n}

## 4. Validation Results
- Universal checks: {pass_count}/{total_count} PASS
- Domain-specific checks: {pass_count}/{total_count} PASS
- CT compliance: {codelists_checked} — PASS/FAIL
- Row count: {actual} (expected: {min}-{max})
- **Verdict: PASS/FAIL**

## 5. Output
- XPT: output-data/sdtm/{domain}.xpt — {rows} rows, {cols} cols
- RDS: output-data/sdtm/{domain}.rds — {rows} rows, {cols} cols
```

---

---

*End of plan. This plan is sufficient to implement all 18 domains with validation, logging, and parallel execution.*
