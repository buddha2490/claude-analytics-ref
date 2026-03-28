

#### Enhancement 1

**Current gap:** The RAG was queried for biomarker coding standards but returned CDISC *standards*, not *actual data value examples*. The agent searched for "POSITIVE" but the simulated data used "ALTERED".

**Root cause:** RAG contains:
- CDISC controlled terminology (general standards)
- NPM ADS data dictionary (variable definitions)
- But NOT: actual value distributions from this study's SDTM data

**Recommendations:**

#### A. Add Data Profiling Step
Insert a new step between "Explore Source Data" (Step 4) and "Implement Derivations" (Step 5):

```
Step 4.5: Profile Source Data and Update RAG
- Generate frequency tables for all categorical variables in source domains
- For LB: list all LBTESTCD values and their corresponding LBSTRESC patterns
- For MH: list all MHCAT values and their MHTERM patterns
- Write profiling output to projects/exelixis-sap/data-profiles/<domain>.md


#### Enchancement 2

### 2. Complexity Flags & Agent Routing

**Observed:** ADSL required 7 internal iterations before initial QC submission, despite the plan flagging it as "HIGH complexity — 101 variables" with a recommended modular approach.

**What happened:**
- Agent used checkpoints (5 RDS files) which helped
- But still struggled with 20+ biomarker flags using similar patterns
- Eventually created `create_biomarker_flag()` helper function (should have been first step)

**Recommendations:**

#### A. Complexity Threshold Skill
When a dataset specification includes >15 similar derivations (same pattern, different inputs):

```yaml
# Auto-detect pattern in plan:
# - EGFRMUT: Pattern match on LB.LBSTRESC for EGFR
# - KRASMUT: Pattern match on LB.LBSTRESC for KRAS
# - ... (18 more)

# Trigger rule:
if (count_similar_derivations > 15):
  recommend_helper_function = True
  suggest_function_signature()
```

**Expected output:**
```r
# Agent writes THIS first:
create_biomarker_flag <- function(lb_data, test_code, var_name) {
  # ... pattern matching logic ...
}

# THEN applies it 20 times:
egfr <- create_biomarker_flag(lb_bl, "EGFR", "EGFRMUT")
kras <- create_biomarker_flag(lb_bl, "KRAS", "KRASMUT")
# ...
```

#### B. Multi-Agent Dataset Splitting
For HIGH complexity datasets (>80 variables), consider splitting across multiple programmer agents:

**ADSL example:**
- Agent 1: Demographics + baseline assessments (30 variables)
- Agent 2: Biomarker flags (20 variables)
- Agent 3: Comorbidity flags + Charlson CCI (25 variables)
- Agent 4: Staging + treatment history (26 variables)
- Orchestrator: Merge results, apply labels, write XPT

**Constraints:**
- Each agent writes to a checkpoint file
- Orchestrator merges by USUBJID
- Single reviewer agent reviews the merged output

**Benefit:** Parallelizes the most complex dataset, reduces cognitive load per agent

#### C. `/validate-plan` Command
Pre-flight check that scans the plan for anti-patterns:

```bash
/validate-plan plan_adam_automation_2026-03-27.md
```

**Checks:**
- [ ] Any dataset with >100 variables? → Recommend splitting
- [ ] Any dataset with >20 similar derivations without abstraction note? → Recommend helper function
- [ ] Any dataset marked HIGH complexity but no checkpoint strategy? → Require checkpoints
- [ ] Any open questions without resolution? → Flag for user review
- [ ] Any source variables listed in plan but not in SDTM? → Flag mismatch



### 2. Complexity Flags & Agent Routing

**Observed:** ADSL required 7 internal iterations before initial QC submission, despite the plan flagging it as "HIGH complexity — 101 variables" with a recommended modular approach.

**What happened:**
- Agent used checkpoints (5 RDS files) which helped
- But still struggled with 20+ biomarker flags using similar patterns
- Eventually created `create_biomarker_flag()` helper function (should have been first step)

**Recommendations:**

#### A. Complexity Threshold Skill
When a dataset specification includes >15 similar derivations (same pattern, different inputs):

```yaml
# Auto-detect pattern in plan:
# - EGFRMUT: Pattern match on LB.LBSTRESC for EGFR
# - KRASMUT: Pattern match on LB.LBSTRESC for KRAS
# - ... (18 more)

# Trigger rule:
if (count_similar_derivations > 15):
  recommend_helper_function = True
  suggest_function_signature()
```

**Expected output:**
```r
# Agent writes THIS first:
create_biomarker_flag <- function(lb_data, test_code, var_name) {
  # ... pattern matching logic ...
}

# THEN applies it 20 times:
egfr <- create_biomarker_flag(lb_bl, "EGFR", "EGFRMUT")
kras <- create_biomarker_flag(lb_bl, "KRAS", "KRASMUT")
# ...
```

#### B. Multi-Agent Dataset Splitting
For HIGH complexity datasets (>80 variables), consider splitting across multiple programmer agents:

**ADSL example:**
- Agent 1: Demographics + baseline assessments (30 variables)
- Agent 2: Biomarker flags (20 variables)
- Agent 3: Comorbidity flags + Charlson CCI (25 variables)
- Agent 4: Staging + treatment history (26 variables)
- Orchestrator: Merge results, apply labels, write XPT

**Constraints:**
- Each agent writes to a checkpoint file
- Orchestrator merges by USUBJID
- Single reviewer agent reviews the merged output

**Benefit:** Parallelizes the most complex dataset, reduces cognitive load per agent

#### C. `/validate-plan` Command
Pre-flight check that scans the plan for anti-patterns:

```bash
/validate-plan plan_adam_automation_2026-03-27.md
```

**Checks:**
- [ ] Any dataset with >100 variables? → Recommend splitting
- [ ] Any dataset with >20 similar derivations without abstraction note? → Recommend helper function
- [ ] Any dataset marked HIGH complexity but no checkpoint strategy? → Require checkpoints
- [ ] Any open questions without resolution? → Flag for user review
- [ ] Any source variables listed in plan but not in SDTM? → Flag mismatch

### 3. Source Data Exploration Phase

**Issues stemmed from assumptions about data structure:**

| Assumption | Reality | Impact |
|------------|---------|--------|
| MH has `MHDTC` | MH has `MHSTDTC` | Error in iteration 1, fixed |
| QS has `QSSTRESN` | QS has `QSORRES` (character) | Required type conversion |
| EC domain supplements EX when missing | EC domain may be independent records | W2 in ADLOT QC report |

**Root cause:** Plan's "Source variables" tables listed *expected* variables, not *actual* variables from the SDTM data.

**Recommendations:**

#### A. Elevate Step 4 (Explore Source Data)
Make it a **required checkpoint** where the agent must:

1. List all available columns in each source domain
2. Compare actual columns to plan's "Source variables" table
3. Flag any mismatches *before* writing derivation code
4. Require user confirmation if critical variables are missing

**Implementation:**
```r
# Step 4 checkpoint code:
plan_vars <- c("USUBJID", "MHDTC", "MHTERM", "MHCAT")  # From plan
actual_vars <- names(mh)

missing_vars <- setdiff(plan_vars, actual_vars)
extra_vars <- setdiff(actual_vars, plan_vars)

if (length(missing_vars) > 0) {
  stop("Plan lists variables not in MH: ", paste(missing_vars, collapse=", "),
       "\nActual MH variables: ", paste(actual_vars, collapse=", "))
}
```

This forces the agent to **reconcile plan vs reality** before proceeding.

#### B. Data Contract Validation Skill
Create a `/validate-data-contract` skill that parses the plan and validates SDTM structure:

```bash
/validate-data-contract plan=plan_adam_automation_2026-03-27.md sdtm-path=projects/exelixis-sap/output-data/sdtm/
```

**Process:**
1. Parse all "Source variables" tables from the plan
2. Read each referenced SDTM XPT file
3. Generate a discrepancy report:
   - Missing variables (in plan, not in data)
   - Unexpected variables (in data, not in plan)
   - Type mismatches (plan expects numeric, data has character)
4. Halt if any CRITICAL variables are missing

**Expected output:**
```
Data Contract Validation Report
================================

DOMAIN: MH
  ✗ MISSING: MHDTC (plan lists this but not found in data)
  ✓ FOUND ALTERNATIVE: MHSTDTC (consider updating plan)

DOMAIN: QS
  ⚠ TYPE MISMATCH: QSSTRESN
    - Plan expects: numeric
    - Data contains: character (QSORRES)
    - Recommendation: Use QSORRES with as.numeric() conversion

DOMAIN: EC
  ⚠ USAGE UNCLEAR: Plan says "may supplement EX"
    - 200 records in EC
    - 180 records in EX
    - Overlap: 120 USUBJID-date combinations in both
    - Recommendation: Clarify usage rule before proceeding

VERDICT: 2 issues require resolution before Wave 1
```

This prevents agents from guessing about data structure.

#### C. Pre-Flight Check in Orchestrator
Before spawning programmer agents, the orchestrator should:

```r
# Pre-flight validation:
1. Check all SDTM XPT files listed in plan exist
2. Check DM has expected column count (18 in this study)
3. Check DM has expected subject count (40 in this study)
4. Run data contract validation
5. If any checks fail: HALT and report to user
```

Only proceed to Wave 1 if pre-flight is GREEN.

### 5. Between-Wave Validation

**Current approach:**
```
Between-Wave Check: PASS
- adsl: 40 rows, 40 subjects — OK
- adae: 127 rows, 40 subjects — OK
```

This caught **zero issues**, suggesting checks are too shallow.

**Recommendations:**

#### A. Referential Integrity Checks
```r
# Current: Only check subject count
nrow(adsl) == 40  # PASS

# Enhanced: Check referential integrity
all(adae$USUBJID %in% adsl$USUBJID)  # All ADAE subjects exist in ADSL
all(adsl$USUBJID %in% dm$USUBJID)    # All ADSL subjects exist in DM
```

#### B. Date Consistency Checks
```r
# Check: No treatment-emergent AE before treatment start
adae_with_adsl <- adae %>%
  left_join(adsl %>% select(USUBJID, TRTSDT), by = "USUBJID")

violations <- adae_with_adsl %>%
  filter(TRTEMFL == 'Y', AESTDT < TRTSDT)

if (nrow(violations) > 0) {
  stop("Found ", nrow(violations), " AEs marked TRTEMFL='Y' but AESTDT < TRTSDT")
}
```

#### C. Derived Variable Spot-Checks
```r
# Check: TRTEMFL logic
adae_check <- adae %>%
  left_join(adsl %>% select(USUBJID, TRTSDT, TRTEDT), by = "USUBJID") %>%
  mutate(
    expected_trtemfl = if_else(AESTDT >= TRTSDT, 'Y', NA_character_),
    mismatch = (TRTEMFL != expected_trtemfl) |
               (is.na(TRTEMFL) != is.na(expected_trtemfl))
  )

if (sum(adae_check$mismatch, na.rm = TRUE) > 0) {
  warning("Found ", sum(adae_check$mismatch, na.rm = TRUE),
          " TRTEMFL derivation mismatches")
}
```

#### D. Cross-Domain Consistency Checks
```r
# Check: DOR only for responders
adtte_dor <- adtte %>% filter(PARAMCD == 'DOR')
adrs_bor <- adrs %>% filter(PARAMCD == 'BOR', AVALC %in% c('CR', 'PR'))

if (nrow(adtte_dor) != nrow(adrs_bor)) {
  stop("DOR records (", nrow(adtte_dor), ") does not match CR/PR count (",
       nrow(adrs_bor), ")")
}
```

#### E. Automated Between-Wave Checks Script
Create `projects/exelixis-sap/programs/between_wave_checks.R`:

```r
# Usage: source("projects/exelixis-sap/programs/between_wave_checks.R")
# Run after each wave completes

run_between_wave_checks <- function(wave_number, datasets) {
  message("Running Wave ", wave_number, " validation checks...")

  # Referential integrity
  # Date consistency
  # Derived variable spot-checks
  # Cross-domain consistency

  # Return: list of violations
}

# Hook integration:
# Set a hook in settings.json that runs this after each wave
```
