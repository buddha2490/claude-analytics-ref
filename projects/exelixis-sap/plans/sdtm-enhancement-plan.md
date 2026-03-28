# SDTM Simulation Enhancement Plan

**Date:** 2026-03-28
**Status:** READY — specification for updating the SDTM simulation plan
**Original plan:** `plans/plan_sim_sdtm_2026-03-25.md`
**Output plan:** `plans/plan_sim_sdtm_2026-03-28.md` (to be generated)
**Dependencies:** `plans/plan_build_validation_functions_2026-03-28.md` (functions must be built first)
**Study:** NPM-008 / Exelixis XB010-101 ECA — Metastatic NSCLC External Controls
**Working directory:** `projects/exelixis-sap/`

---

## Overview

This document specifies how to update the original SDTM simulation plan. It is NOT an implementation guide — it tells an agent how to produce an updated plan document.

The original plan (`plan_sim_sdtm_2026-03-25.md`) produced working programs but lacked validation, logging, and parallel execution. This enhancement plan specifies what sections to add, preserve, or replace in the plan document to incorporate those improvements.

**Process flow:**
1. Build validation functions per `plan_build_validation_functions_2026-03-28.md` (FIRST)
2. Use this enhancement plan to generate `plan_sim_sdtm_2026-03-28.md` (SECOND)
3. Execute the updated plan to regenerate all 18 domains (THIRD)

---

## 1. What Must NOT Change

The following elements of the original plan are correct and must be preserved exactly as written:

- **Study parameters**: STUDYID="NPM008", N_SUBJECTS=40, 5 sites, STUDY_END=2027-01-31
- **Domain list**: All 18 domains (DM, IE, MH, SC, SU, VS, LB, BS, EX, EC, CM, PR, QS, TU, TR, RS, AE, HO, DS)
- **Seed strategy**: Base seed 42, domain offsets 42+1 through 42+19
- **Outcome distributions**: BOR (18% PR, 40% SD, 35% PD, 7% NE), PFS/OS Weibull/Exponential
- **Per-domain specifications**: Sections 4.1–4.19 (variable lists, distributions, derivation logic)
- **Date de-identification**: Per-subject shifts (-14 to +14 days)
- **Genomic profile assignments**: PDL1, EGFR, ALK, KRAS, TP53, etc.
- **Ambiguities table**: Section 8 assumptions remain valid

Do not rewrite these sections. Copy them verbatim from the original plan.

---

## 2. Plan Document Changes

The agent must make the following additions and replacements to the original plan structure:

### 2.1 Add Section 3.5: "Reusable Validation Functions"

Add a new section after the existing Section 3.4 (or renumber as appropriate) that specifies the three validation functions built per `plan_build_validation_functions_2026-03-28.md`:

**Content to include:**

#### validate_sdtm_domain()

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

#### validate_sdtm_cross_domain()

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

#### log_sdtm_result()

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

### 2.2 Add Section 3.6: "CT Pre-Flight Validation"

Add a section specifying controlled terminology validation strategy:

**Content:**

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

### 2.3 Replace Section 7: "Orchestration Guide"

Replace the sequential execution section with a 6-wave parallel structure:

**Wave structure:**

```
Wave 0:  DM                                          (1 agent, sequential)
Wave 1:  IE, MH, SC, SU, VS, LB, PR, QS, TU, EX, DS  (11 agents, parallel)
Wave 2:  AE, BS, EC, CM                              (4 agents, parallel)
Wave 3:  HO, TR                                      (2 agents, parallel)
Wave 4:  RS                                           (1 agent, sequential)
Wave 5:  Cross-domain validation + data contract      (1 agent, sequential)
```

**Dependency rationale:**

| Domain | Reads | Wave placement |
|--------|-------|----------------|
| DM | (none) | Wave 0 — foundation |
| IE, MH, SC, SU, VS, LB, PR, QS, TU, EX, DS | dm.rds only | Wave 1 — parallel after DM |
| AE, BS, EC, CM | dm.rds + one other (ex.rds or lb.rds) | Wave 2 — parallel after Wave 1 |
| HO, TR | dm.rds + domain from Wave 2 (ae.rds or tu.rds) | Wave 3 — parallel after Wave 2 |
| RS | dm.rds + tr.rds | Wave 4 — sequential after Wave 3 |

**Wave gate rules:**

1. A wave starts only when ALL agents in the prior wave return SUCCESS
2. Each agent runs its `sim_*.R`, which internally calls `validate_sdtm_domain()`
3. If any agent returns FAIL, orchestrator logs failure and HALTS — no subsequent waves
4. Between-wave checkpoint: log summary table of completed domains
5. Orchestrator uses **parallel Agent tool calls** within each wave (multiple Agent invocations in a single message)

**Wave 0 extra validation (DM smoke tests):**

After DM completes, before proceeding to Wave 1, verify:
- AGE: mean in [60, 68], sd in [6, 12]
- SEX: M count in [18, 26] (target ~55%)
- RACE: WHITE count in [24, 32] (target ~70%)
- DTHFL="Y": count in [26, 30] (target ~70%)
- BOR: PR [5-10], SD [13-19], PD [11-17], NE [1-5]
- All latent variables non-NA
- RFSTDTC range: 2022-01-01 to 2025-06-30

These are tolerance checks, not exact matches. They catch catastrophic distribution errors early.

**Orchestration instructions:**

- Spawn r-clinical-programmer agents for each domain within a wave
- Pass the domain code and wave number to each agent
- Each agent produces: XPT/RDS output + dev log
- Orchestrator logs progress after each wave
- On failure: diagnose which domain failed, allow targeted rerun

---

### 2.4 Add Section 9: "Logging & QA Artifacts"

Add a section specifying all logs and reports to be produced:

**Required artifacts:**

| Artifact | Path | Written by |
|----------|------|-----------|
| Orchestration log | `logs/orchestration_log_sdtm_{date}.md` | Orchestrator (main conversation) |
| Per-domain dev logs | `logs/dev_log_sim_{domain}_{date}.md` | r-clinical-programmer agents |
| Machine validation log | `logs/sdtm_domain_log_{date}.md` | `log_sdtm_result()` calls |
| Cross-domain validation | `logs/cross_domain_validation_{date}.md` | `validate_sdtm_cross_domain()` |
| Data contract validation | `logs/data_contract_validation_{date}.md` | `validate_data_contract()` |
| Consolidated QA report | `QA Anlyses/qa_sdtm_{date}.md` | clinical-code-reviewer agent |

**Orchestration log format:**

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

**Per-domain dev log format:**

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

### 2.5 Update Program Template

Replace the existing `sim_*.R` template with this structure:

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

---

## 3. Agent Execution Instructions

An agent reading this enhancement plan must:

1. **Read the original plan** (`plan_sim_sdtm_2026-03-25.md`) in full
2. **Read this enhancement plan** to understand what changes to make
3. **Preserve** all sections listed in "What Must NOT Change" (Section 1)
4. **Add** new sections per Section 2.1, 2.2, 2.4 above
5. **Replace** Section 7 per Section 2.3 above
6. **Update** program template per Section 2.5 above
7. **Write** a single, complete, self-contained plan file at `plans/plan_sim_sdtm_2026-03-28.md`

**Do NOT:**
- Ask clarifying questions — all decisions are specified here
- Implement the plan — only write the plan document
- Change domain specifications (Sections 4.1-4.19)
- Change seed strategy, study parameters, or output paths

The new plan replaces the original for execution purposes. It should be executable by an orchestrator following the wave structure.

---

## 4. Success Criteria for Plan Document

The generated plan is complete when it includes:

- [ ] All preserved content from original plan (study params, domain specs, seeds, distributions)
- [ ] New Section 3.5: Reusable Validation Functions (full specs)
- [ ] New Section 3.6: CT Pre-Flight Validation
- [ ] Replaced Section 7: 6-wave orchestration with gate rules and DM smoke tests
- [ ] New Section 9: Logging & QA Artifacts (all 6 artifact types specified)
- [ ] Updated program template with validation/logging integrated
- [ ] Clear wave assignments for all 18 domains
- [ ] Domain-specific validation checks for each domain (in Section 3.5)
- [ ] Between-wave checkpoint instructions
- [ ] Parallel Agent call instructions for orchestrator

---

*This enhancement plan is the authoritative specification for updating the SDTM simulation plan. The output should be a complete, executable plan document that incorporates validation, logging, and parallel execution without changing the core simulation logic.*
