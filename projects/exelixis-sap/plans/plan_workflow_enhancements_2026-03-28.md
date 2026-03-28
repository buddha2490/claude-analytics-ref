# Implementation Plan: ADaM Workflow Enhancements
**Date:** 2026-03-28
**Status:** Ready for Implementation
**Requested by:** Brian Carter
**Study Context:** NPM-008 / Exelixis XB010-100
**Last Updated:** 2026-03-27

---

## Revision History

| Date | Status | Changes |
|------|--------|---------|
| 2026-03-28 | Draft | Initial plan created with 9 enhancements and 4 open questions |
| 2026-03-27 | Ready | All questions resolved: Q1 (markdown only), Q2 (auto-retry), Q3 (40-var split), Q4 (study-specific memory) |

---

## 1. Executive Summary

This plan implements systematic enhancements to the multi-agent ADaM automation workflow based on lessons learned from the first iteration (6 datasets, 67% first-pass QC rate, 0 escalations).

**Goal:** Increase first-pass QC rate from 67% to >80% through better data validation, complexity routing, and memory persistence.

**Scope:** 9 discrete enhancements spanning skills, commands, and agent modifications. Recommended phasing: 5 enhancements in Phase 1 (foundation), 4 in Phase 2 (optimization).

**Expected outcomes:**
- Prevent data structure mismatches (MHDTC vs MHSTDTC, POSITIVE vs ALTERED)
- Reduce internal iterations for high-complexity datasets (ADSL required 7 attempts)
- Automate pattern detection and helper function suggestions
- Build institutional memory to prevent repeating mistakes
- Strengthen between-wave validation to catch logic errors early

---

## 2. Background

### 2.1 First Iteration Results

The first iteration demonstrated a production-ready workflow:

| Metric | Value | Assessment |
|--------|-------|------------|
| First-pass QC rate | 67% (4/6 datasets) | Excellent for complex ADaM |
| Fix cycles per dataset | 0.33 average | Very low |
| Escalations to user | 0 | Perfect — agents self-corrected |
| Documentation completeness | 3,400 lines | Thorough audit trail |

See: `projects/exelixis-sap/first-iteration-analysis.md` for full details.

### 2.2 Key Issues Identified

**Data structure mismatches:**
- Plan listed MHDTC, actual data contained MHSTDTC
- Plan expected QSSTRESN (numeric), data contained QSORRES (character)
- Impact: Early iteration failures, wasted compute

**Terminology mismatches:**
- RAG returned "POSITIVE"/"DETECTED" as biomarker standards
- Actual data used "ALTERED"/"NOT ALTERED"
- Impact: 100% blank biomarker flags (silently wrong, caught in QC)

**Complexity handling:**
- ADSL (101 variables) required 7 internal iterations
- Agent eventually created helper function but should have started with it
- 20+ biomarker flags used identical patterns without abstraction

**Shallow validation:**
- Between-wave checks only verified subject counts
- Missed opportunities to catch referential integrity, date consistency, derivation logic errors

**No memory persistence:**
- Patterns learned in Wave 1 not applied in Wave 3
- Same mistakes could repeat across datasets or studies

### 2.3 Why These Improvements Matter

**Clinical programming context:**
- Real studies have 200+ subjects, 12+ ADaM datasets
- Errors in foundation datasets (ADSL) cascade downstream
- Manual QC review costs ~2-4 hours per dataset
- Documentation gaps delay regulatory submission

**Workflow ROI:**
- 10% QC rate improvement → ~2 hours saved per study
- Data profiling → prevents silent errors (blank flags, wrong joins)
- Memory persistence → prevents repeating mistakes across studies
- Complexity routing → reduces rework for large datasets

---

## 3. Enhancement Breakdown

### Enhancement 1: Data Contract Validation

**What it does:**
Pre-flight check that validates SDTM structure against plan specifications before code execution begins.

**Technical approach:**
New command: `/validate-data-contract`

**Implementation steps:**

1. **Create command file** `.claude/commands/validate-data-contract.md`:
   - Parse "Source variables" tables from the plan document
   - Read referenced SDTM XPT files from specified path
   - Compare plan expectations vs actual data structure
   - Generate structured discrepancy report
   - Return PASS/FAIL verdict with actionable guidance

2. **Validation checks**:
   ```
   For each domain in plan:
     - Check XPT file exists
     - Check all listed variables exist in XPT
     - Check data types match expectations (numeric vs character)
     - Identify alternative variables if primary not found (e.g., MHSTDTC when MHDTC expected)
     - Flag usage ambiguities (e.g., "EC may supplement EX" — check actual overlap)
   ```

3. **Report format**:
   ```markdown
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

4. **Orchestrator integration**:
   - Orchestrator runs `/validate-data-contract` after loading plan
   - If verdict is FAIL: HALT and report discrepancies to user
   - If verdict is PASS: Proceed to Wave 1

**Dependencies:** None — standalone command

**Success criteria:**
- Command successfully parses plan tables and reads XPT files
- Detects all mismatches from first iteration (MHDTC, QSSTRESN)
- Returns actionable guidance (not just "error: missing column")
- Prevents agent execution when critical variables missing

**Priority:** HIGH — prevents most data structure errors

---

### Enhancement 2: Mandatory Source Data Exploration Checkpoint

**What it does:**
Elevates Step 4 (Explore Source Data) to a required checkpoint where agents must reconcile plan expectations with actual data before writing derivation code.

**Technical approach:**
Modify `r-code` skill to enforce exploration checkpoint for ADaM programs.

**Implementation steps:**

1. **Update `.claude/skills/r-code.md`**:
   Add ADaM-specific exploration requirements:
   ```markdown
   ## Step 4.5: Reconcile Plan vs Data (ADaM only)

   Before implementing derivations, verify:

   1. List all available columns in each source domain
   2. Compare actual columns to plan's "Source variables" table
   3. Flag mismatches in a comment block
   4. If critical variables missing: STOP and report to orchestrator

   Template:
   ```r
   # --- Data Contract Validation ---
   plan_vars <- c("USUBJID", "MHDTC", "MHTERM", "MHCAT")  # From plan
   actual_vars <- names(mh)

   missing_vars <- setdiff(plan_vars, actual_vars)
   extra_vars <- setdiff(actual_vars, plan_vars)

   if (length(missing_vars) > 0) {
     stop("Plan lists variables not in MH: ", paste(missing_vars, collapse=", "),
          "\nActual MH variables: ", paste(actual_vars, collapse=", "),
          "\nREVISIT: Update plan or use alternative variables")
   }

   message("Data contract OK: All ", length(plan_vars), " expected variables found in MH")
   ```
   ```

2. **Checkpoint enforcement**:
   - Agent must execute this code block before derivations
   - Orchestrator checks dev log for "Data contract OK" message
   - If missing: Orchestrator requests agent add checkpoint

3. **Orchestrator workflow**:
   ```
   After agent completes Step 4:
     - Check dev log for "Data contract OK" messages
     - Count domains validated
     - If count < expected domains from plan: Request checkpoint completion
     - Only proceed to Step 5 (Implement Derivations) after validation
   ```

**Dependencies:** Enhancement 1 (data contract command provides reference template)

**Success criteria:**
- Agent code includes contract validation block before derivations
- Validation catches all first-iteration mismatches
- Agent halts with actionable message when variables missing
- Dev log contains validation confirmations

**Priority:** HIGH — forces plan-vs-reality reconciliation

---

### Enhancement 3: Data Profiling Skill

**What it does:**
Auto-generates frequency tables for categorical variables, providing concrete examples of actual data values to prevent terminology mismatches (POSITIVE vs ALTERED).

**Technical approach:**
New skill: `/profile-data`

**Implementation steps:**

1. **Create skill file** `.claude/skills/profile-data.md`:
   ```markdown
   # Data Profiling Skill

   Auto-generates value frequency tables for specified domains and variables.

   ## Usage

   ```bash
   /profile-data domain=LB variables=LBTESTCD,LBSTRESC
   /profile-data domain=MH variables=MHCAT,MHTERM --top-n=20
   ```

   ## Process

   1. Read specified SDTM XPT file
   2. For each variable:
      - Generate frequency table (count, percent)
      - Show top N values (default: all unique values, max 50)
      - Flag high-cardinality variables (>100 unique values)
   3. Write profiling output to `projects/exelixis-sap/data-profiles/<domain>.md`
   4. Return summary with key findings

   ## Output Format

   ```markdown
   # Data Profile: LB (Laboratory)
   **Generated:** 2026-03-28
   **Records:** 450
   **Subjects:** 40

   ## LBTESTCD (Test Code)

   | Value | Count | Percent | Description |
   |-------|-------|---------|-------------|
   | EGFR  | 40    | 8.9%    | EGFR Mutation Analysis |
   | KRAS  | 40    | 8.9%    | KRAS Mutation Analysis |
   | ALK   | 40    | 8.9%    | ALK Translocation |
   | ...   | ...   | ...     | ... |

   ## LBSTRESC (Result String)

   ### For LBTESTCD = EGFR

   | Value       | Count | Percent |
   |-------------|-------|---------|
   | ALTERED     | 12    | 30%     |
   | NOT ALTERED | 25    | 62.5%   |
   | NOT TESTED  | 3     | 7.5%    |

   ⚠ **Note:** Values use "ALTERED" not "POSITIVE" — verify pattern matching logic
   ```
   ```

2. **R implementation** (`projects/exelixis-sap/R/profile_data.R`):
   ```r
   profile_data <- function(domain, variables, data_path, top_n = 50) {
     # Read XPT
     # Generate freq tables
     # Write markdown output
     # Return key findings
   }
   ```

3. **Storage and lifecycle** (per Q1 resolution):
   - Profiles saved to `projects/<study-name>/data-profiles/<domain>.md`
   - Generated during Step 4.5 (after data exploration)
   - Used during Step 5 (derivation) for actual value reference
   - NOT added to RAG — kept as markdown reference only
   - Regenerated only if source data changes
   - Persisted for audit trail

4. **Workflow integration**:
   - Orchestrator runs `/profile-data` for all domains listed in plan *before* spawning programmer agents
   - Profiling outputs saved to `projects/exelixis-sap/data-profiles/`
   - Agents reference profiles during implementation

**Dependencies:** None — standalone skill

**Success criteria:**
- Skill generates accurate frequency tables for LB, MH, QS domains
- Markdown output is human-readable and agent-parseable
- Identifies "ALTERED" vs "POSITIVE" terminology in LB
- Prevents first-iteration biomarker flag error

**Priority:** HIGH — prevents silent terminology errors

---

### Enhancement 4: Memory Persistence After QC

**What it does:**
Automatically saves feedback, project, and reference memories after each QC cycle to prevent repeating mistakes.

**Technical approach:**
Modify `clinical-code-reviewer` agent to write memories after producing QC report.

**Implementation steps:**

1. **Update `.claude/agents/clinical-code-reviewer.md`**:
   Add memory persistence instructions:
   ```markdown
   ## After Producing QC Report

   If this is the first QC cycle for the study, or if you identified a pattern worth preserving:

   1. **Feedback memories** — save when:
      - You flagged an error pattern that could recur (e.g., XPT flag encoding assumptions)
      - You validated an approach that worked well (e.g., checkpoint usage for high-complexity datasets)

   2. **Project memories** — save when:
      - Implementation revealed complexity not obvious from plan (e.g., LoT algorithm requires iterative approach)
      - You identified study-specific constraints (e.g., Charlson weights decision)

   3. **Reference memories** — save when:
      - You discovered study-specific terminology (e.g., ALTERED vs POSITIVE for biomarkers)
      - You identified domain quirks (e.g., MH uses MHSTDTC not MHDTC)

   Use the standard memory format with frontmatter.
   ```

2. **Example memories to save** (based on first iteration):

   **Feedback memory** — `xpt_flag_encoding.md`:
   ```markdown
   ---
   name: xpt_flag_encoding
   description: Verify XPT flag encoding before assuming Y/N pattern
   type: feedback
   ---

   When reviewing ADaM datasets, always check how NA_character_ is encoded in XPT output.

   **Why:** ADSL QC initially flagged "empty string" for flags as a potential error, but this is correct ADaM convention — haven::write_xpt() converts NA_character_ to empty string per CDISC XPT format.

   **How to apply:** Before flagging "empty string" as an error in XPT output:
   1. Check if the R code uses NA_character_ (correct)
   2. Verify haven::write_xpt() was used (converts correctly)
   3. Only flag if R code uses "" directly (incorrect)
   ```

   **Project memory** — `lot_algorithm_complexity.md`:
   ```markdown
   ---
   name: lot_algorithm_complexity
   description: NPM LoT algorithm requires three distinct rules, iterative approach
   type: project
   ---

   ADLOT required algorithm refactoring due to missing 120-day gap rule and death date censoring. Initial implementation used simplified window-only logic.

   **Why:** NPM LoT algorithm for NSCLC has three independent termination rules: 45-day window (for grouping), 120-day gap (for line end), and death date (censoring). All three must be evaluated.

   **How to apply:** When implementing LoT derivations in future NPM studies:
   - Use iterative line assignment (not vectorized grouping)
   - Track current_line_start for each line (window is relative to THIS line, not first therapy)
   - Evaluate all three termination conditions in each iteration
   - Add explicit validation for date consistency (LOTSTDTC <= LOTENDTC)

   See: projects/exelixis-sap/adam_adlot.R lines 85-131 for reference implementation
   ```

   **Reference memory** — `npm008_biomarker_terminology.md`:
   ```markdown
   ---
   name: npm008_biomarker_terminology
   description: NPM-008 LB domain uses ALTERED/NOT ALTERED for mutation status
   type: reference
   ---

   LB biomarker values in NPM-008 use "ALTERED"/"NOT ALTERED"/"NOT TESTED"/"VUS", not the CDISC standard "POSITIVE"/"DETECTED"/"NEGATIVE".

   **Pattern matching rules:**
   - ALTERED → Y (mutation present)
   - NOT ALTERED → N (wild-type)
   - NOT TESTED → NA (not evaluated)
   - VUS → NA (variant of unknown significance)

   **Check order matters:** Must check "NOT ALTERED" and "NOT TESTED" BEFORE "ALTERED" to avoid substring matching bugs.

   Applies to: EGFRMUT, KRASMUT, ALK, ROS1MUT, RETMUT, METMUT, ERBB2MUT, NTRK1FUS, NTRK2FUS, NTRK3FUS in ADSL and any future biomarker-related datasets.
   ```

3. **Orchestrator usage**:
   - Before spawning programmer agent for Wave N:
     - Load relevant memories from previous waves
     - Pass as context: "Review these learnings from earlier waves: ..."
   - Programmer agent checks memories before implementing similar patterns

**Dependencies:** None — uses existing memory system

**Success criteria:**
- Reviewer agent saves 2-3 memories per QC cycle
- Memories follow standard frontmatter format
- Memories are specific enough to prevent recurrence (not vague "be careful with dates")
- Orchestrator successfully loads and passes memories to downstream agents

**Priority:** MEDIUM — builds institutional knowledge over time

---

### Enhancement 5: Enhanced Between-Wave Validation

**What it does:**
Implements rigorous cross-dataset checks after each wave completes to catch logic errors before downstream datasets consume incorrect inputs.

**Technical approach:**
New R script with automated validation suite, called by orchestrator.

**Implementation steps:**

1. **Create validation script** `projects/exelixis-sap/programs/between_wave_checks.R`:
   ```r
   run_between_wave_checks <- function(wave_number, completed_datasets, data_path) {
     message("Running Wave ", wave_number, " validation checks...")

     violations <- list()

     # 1. Referential integrity
     if (wave_number >= 2) {
       # All ADSL subjects must exist in DM
       dm <- haven::read_xpt(file.path(data_path, "dm.xpt"))
       adsl <- haven::read_xpt(file.path(data_path, "adsl.xpt"))

       missing_in_dm <- setdiff(adsl$USUBJID, dm$USUBJID)
       if (length(missing_in_dm) > 0) {
         violations$referential_integrity <- paste(
           "ADSL contains", length(missing_in_dm), "subjects not in DM:",
           paste(missing_in_dm, collapse=", ")
         )
       }
     }

     # 2. Date consistency checks
     if (wave_number >= 3 && "adae" %in% completed_datasets) {
       adae <- haven::read_xpt(file.path(data_path, "adae.xpt"))
       adsl <- haven::read_xpt(file.path(data_path, "adsl.xpt"))

       adae_with_dates <- adae %>%
         left_join(adsl %>% select(USUBJID, TRTSDT), by = "USUBJID")

       trtemfl_violations <- adae_with_dates %>%
         filter(TRTEMFL == 'Y', AESTDT < TRTSDT)

       if (nrow(trtemfl_violations) > 0) {
         violations$date_consistency <- paste(
           "Found", nrow(trtemfl_violations),
           "AEs marked TRTEMFL='Y' but AESTDT < TRTSDT"
         )
       }
     }

     # 3. Derived variable spot-checks
     if (wave_number >= 3 && "adrs" %in% completed_datasets) {
       adrs <- haven::read_xpt(file.path(data_path, "adrs.xpt"))

       # Check: BOR parameter must have exactly 1 record per subject
       bor_counts <- adrs %>%
         filter(PARAMCD == 'BOR') %>%
         count(USUBJID)

       bor_violations <- bor_counts %>% filter(n != 1)

       if (nrow(bor_violations) > 0) {
         violations$derived_variable <- paste(
           "BOR parameter must have 1 record per subject, found",
           nrow(bor_violations), "subjects with n != 1"
         )
       }
     }

     # 4. Cross-domain consistency
     if (wave_number >= 4 && "adtte" %in% completed_datasets) {
       adtte <- haven::read_xpt(file.path(data_path, "adtte.xpt"))
       adrs <- haven::read_xpt(file.path(data_path, "adrs.xpt"))

       # Check: DOR records only for responders
       dor_count <- adtte %>% filter(PARAMCD == 'DOR') %>% nrow()
       responder_count <- adrs %>%
         filter(PARAMCD == 'BOR', AVALC %in% c('CR', 'PR')) %>% nrow()

       if (dor_count != responder_count) {
         violations$cross_domain <- paste(
           "DOR records (", dor_count, ") does not match CR/PR count (",
           responder_count, ")"
         )
       }
     }

     # Return verdict
     if (length(violations) == 0) {
       message("✓ All Wave ", wave_number, " validation checks PASSED")
       return(list(verdict = "PASS", violations = NULL))
     } else {
       message("✗ Wave ", wave_number, " validation checks FAILED")
       return(list(verdict = "FAIL", violations = violations))
     }
   }
   ```

2. **Orchestrator integration**:
   ```
   After Wave N completes (all datasets QC passed):
     - Run between_wave_checks.R
     - If verdict = FAIL:
       - Report violations to user
       - Offer to re-run Wave N with corrections
       - HALT until resolved
     - If verdict = PASS:
       - Log validation results
       - Proceed to Wave N+1
   ```

3. **Validation coverage matrix**:

   | Check Type | Wave 1 | Wave 2 | Wave 3 | Wave 4 |
   |------------|--------|--------|--------|--------|
   | Row counts | ✓ | ✓ | ✓ | ✓ |
   | Subject counts | ✓ | ✓ | ✓ | ✓ |
   | Referential integrity | — | ✓ (ADSL vs DM) | ✓ (ADRS/ADAE vs ADSL) | ✓ (ADTTE vs ADSL/ADRS) |
   | Date consistency | — | — | ✓ (TRTEMFL vs TRTSDT) | ✓ (CNSR vs end dates) |
   | Derived variable spot-checks | — | — | ✓ (BOR uniqueness) | ✓ (DOR count) |
   | Cross-domain consistency | — | — | — | ✓ (DOR vs responders) |

**Dependencies:** None — standalone script

**Success criteria:**
- Script detects all validation scenarios from matrix
- Returns actionable error messages (not just "check failed")
- Orchestrator halts when violations detected
- First-pass validation catches at least 1 issue that shallow checks missed

**Priority:** MEDIUM — catches errors before downstream impact

---

### Enhancement 6: Complexity Threshold Detection

**What it does:**
Auto-detects when a dataset specification includes >15 similar derivations and recommends helper function abstraction.

**Technical approach:**
Modify `feature-planner` agent to include complexity analysis in plans.

**Implementation steps:**

1. **Update `.claude/agents/feature-planner.md`**:
   Add complexity detection guidance:
   ```markdown
   ## Complexity Analysis (ADaM Plans)

   When reviewing dataset specifications, count derivations by pattern:

   ### Pattern: Biomarker flags from LB
   - EGFRMUT: Pattern match on LB.LBSTRESC for EGFR
   - KRASMUT: Pattern match on LB.LBSTRESC for KRAS
   - ALK: Pattern match on LB.LBSTRESC for ALK
   - ... (count similar derivations)

   **If count > 15:** Flag for helper function abstraction

   **Recommendation format:**
   ```
   ⚠ COMPLEXITY ALERT: 20 biomarker flags use identical pattern

   Recommend helper function:

   ```r
   create_biomarker_flag <- function(lb_data, test_code, var_name,
                                     positive_pattern = "ALTERED",
                                     negative_pattern = "NOT ALTERED") {
     # Pattern matching logic
     # Return flag variable
   }
   ```

   Apply 20 times:
   ```r
   egfr <- create_biomarker_flag(lb_bl, "EGFR", "EGFRMUT")
   kras <- create_biomarker_flag(lb_bl, "KRAS", "KRASMUT")
   # ... (18 more)
   ```

   **Benefits:**
   - Single point of maintenance for pattern matching logic
   - Easier to update if terminology changes
   - Reduces cognitive load (20 derivations → 1 function + 20 calls)
   ```

2. **Detection algorithm**:
   ```
   For each dataset in plan:
     1. Parse derivation descriptions
     2. Group by pattern signature:
        - Same source domain
        - Same variable type (e.g., "pattern match on LB.LBSTRESC")
        - Different input parameters (EGFR, KRAS, ALK)
     3. Count groups
     4. If any group > 15: Add complexity alert to plan
   ```

3. **Orchestrator usage**:
   - If plan contains complexity alert: Pass to programmer agent
   - Programmer agent implements helper function *first*
   - Programmer applies helper function for all flagged derivations
   - Reviewer checks that helper function was used (not copied 20 times)

**Dependencies:** None — planner enhancement

**Success criteria:**
- Planner detects 20 biomarker flags in ADSL specification
- Planner provides concrete helper function signature
- Programmer implements helper function on first attempt
- Final code has 1 function + 20 calls (not 20 copies of logic)

**Priority:** MEDIUM — reduces internal iterations for high-complexity datasets

---

### Enhancement 7: Plan Validation Command

**What it does:**
Pre-flight check that scans the implementation plan for anti-patterns and missing elements before execution begins.

**Technical approach:**
New command: `/validate-plan`

**Implementation steps:**

1. **Create command file** `.claude/commands/validate-plan.md`:
   ```markdown
   # Validate Plan Command

   Pre-flight check for ADaM automation plans.

   ## Usage

   ```bash
   /validate-plan projects/exelixis-sap/plans/plan_adam_automation_2026-03-27.md
   ```

   ## Checks

   1. **Complexity flags**
      - [ ] Any dataset with >100 variables? → Recommend splitting or checkpoints
      - [ ] Any dataset with >20 similar derivations without abstraction note? → Recommend helper function

   2. **Execution strategy**
      - [ ] Are dependencies correctly ordered in waves?
      - [ ] Any dataset marked HIGH complexity but no checkpoint strategy? → Require checkpoints

   3. **Open questions**
      - [ ] Any open questions without resolution? → Flag for user review
      - [ ] Any REVISIT comments planned without question IDs? → Require linkage

   4. **Source data**
      - [ ] Are all source domains listed in plan available in data path?
      - [ ] Any source variables listed in plan but not in SDTM? → Flag mismatch

   5. **Documentation**
      - [ ] Does plan include expected output (row counts, subject counts)?
      - [ ] Are all derived variables documented with derivation logic?

   ## Output

   ```
   Plan Validation Report
   ======================

   ✓ PASS: Dependency order correct (ADLOT before ADSL before ADRS)
   ✓ PASS: All open questions resolved
   ⚠ WARNING: ADSL has 101 variables but no checkpoint strategy
     Recommendation: Add checkpoints after demographics, biomarkers, comorbidities
   ⚠ WARNING: ADSL has 20 biomarker flags using identical pattern
     Recommendation: Create helper function create_biomarker_flag()
   ✗ BLOCKING: Source domain MH lists variable MHDTC not found in data
     Found alternative: MHSTDTC
     Action required: Update plan or confirm alternative acceptable

   VERDICT: 1 BLOCKING issue, 2 WARNINGS
   Recommendation: Resolve blocking issues before proceeding
   ```
   ```

2. **R implementation** (`projects/exelixis-sap/R/validate_plan.R`):
   ```r
   validate_plan <- function(plan_path, data_path) {
     # Parse plan markdown
     # Extract dataset specs, source variables, dependencies
     # Run checks
     # Return structured report
   }
   ```

3. **Orchestrator integration**:
   - Orchestrator runs `/validate-plan` after loading plan
   - If BLOCKING issues: HALT and report to user
   - If WARNINGS only: Proceed but log warnings
   - If PASS: Proceed normally

**Dependencies:** Enhancement 1 (data contract validation provides similar structure)

**Success criteria:**
- Command detects all anti-patterns from first iteration
- Returns actionable recommendations (not just "error found")
- Catches ADSL complexity, biomarker patterns, MHDTC mismatch
- Plan validation takes <10 seconds

**Priority:** LOW — nice-to-have but not critical for core workflow

---

### Enhancement 8: Multi-Agent Dataset Splitting (High Complexity)

**What it does:**
For datasets with >40 variables, automatically split derivations across multiple programmer agents working in parallel, then merge results.

**Rationale for 40-variable threshold (per Q3 resolution):**
- ADSL at 101 variables required 7 internal iterations in first run
- Splitting at 40 (not 80) provides earlier intervention
- Each agent handles ~25-30 variables — manageable cognitive load
- Override available if planner judges split unnecessary

**Technical approach:**
New orchestration pattern for high-complexity datasets.

**Implementation steps:**

1. **Planner guidance** (update `.claude/agents/feature-planner.md`):
   ```markdown
   ## High-Complexity Dataset Splitting

   For datasets with >40 variables, consider splitting across multiple agents:

   **Example: ADSL (101 variables)**

   Split by derivation category:
   - Agent 1: Demographics + baseline assessments (30 variables)
   - Agent 2: Biomarker flags (20 variables)
   - Agent 3: Comorbidity flags + Charlson CCI (25 variables)
   - Agent 4: Staging + treatment history (26 variables)
   - Orchestrator: Merge results, apply labels, write XPT

   **Constraints:**
   - Each agent writes to a checkpoint file: `adsl_part1.rds`, `adsl_part2.rds`, etc.
   - Orchestrator merges by USUBJID
   - Single reviewer agent reviews the merged output
   - Each part must include USUBJID + STUDYID (merge keys)

   **Benefits:**
   - Parallelizes the most complex dataset
   - Reduces cognitive load per agent
   - Allows independent testing of each part
   ```

2. **Orchestrator workflow**:
   ```
   If dataset complexity > 40 variables AND plan includes split strategy:
     1. Spawn N programmer agents in parallel (one per part)
     2. Each agent:
        - Reads source data
        - Implements assigned derivations
        - Writes checkpoint RDS: projects/exelixis-sap/output-data/adsl_part{N}.rds
     3. Wait for all agents to complete
     4. Orchestrator merges:
        adsl_part1 %>%
          left_join(adsl_part2, by = c("USUBJID", "STUDYID")) %>%
          left_join(adsl_part3, by = c("USUBJID", "STUDYID")) %>%
          left_join(adsl_part4, by = c("USUBJID", "STUDYID"))
     5. Orchestrator applies labels and writes XPT
     6. Single reviewer reviews merged ADSL
   ```

3. **Example split specification** (in plan):
   ```markdown
   ### 4.3 ADSL — Subject-Level Analysis Dataset (SPLIT STRATEGY)

   **Complexity:** HIGH — 101 variables
   **Split into 4 parts:**

   #### Part 1: Demographics + Baseline (Agent A)
   - Variables: USUBJID, STUDYID, AGE, SEX, RACE, ETHNIC, COUNTRY, REGION, ECOG0, ECOG_BL, SMOKGRP, ... (30 total)
   - Source: DM, QS, SU, SC
   - Output: `adsl_part1.rds`

   #### Part 2: Biomarker Flags (Agent B)
   - Variables: USUBJID, STUDYID, EGFRMUT, KRASMUT, ALK, ROS1MUT, ... (20 biomarker flags + 2 keys)
   - Source: LB
   - Helper function: create_biomarker_flag()
   - Output: `adsl_part2.rds`

   #### Part 3: Comorbidity Flags + Charlson (Agent C)
   - Variables: USUBJID, STUDYID, MYHIS, CVAIS, CONGHF, ... (25 comorbidity flags + CCIGRP + 2 keys)
   - Source: MH
   - Helper function: create_comorbidity_flag()
   - Output: `adsl_part3.rds`

   #### Part 4: Staging + Treatment History (Agent D)
   - Variables: USUBJID, STUDYID, TSTAGE, NSTAGE, MSTAGE, AJCCSTG, HISTGRP, LOTSNUM, PFSIND, OSIND, ... (26 total)
   - Source: TU, PR, ADLOT
   - Output: `adsl_part4.rds`

   #### Merge Strategy (Orchestrator)
   - Merge by USUBJID + STUDYID
   - Validate: All parts have same subject count (40)
   - Validate: No duplicate column names (except merge keys)
   - Apply labels from plan
   - Write XPT: `adsl.xpt`
   ```

4. **Validation checks**:
   - Before merge: All parts have same USUBJID set
   - After merge: No missing data introduced by join
   - After merge: Column count = sum of part columns - (N-1)*2 (merge key deduplication)

**Dependencies:** None — orchestration pattern

**Success criteria:**
- ADSL split into 4 parts completes faster than single-agent approach
- Each part has <30 variables (manageable cognitive load)
- Merge produces correct 40 rows × 101 columns
- Reviewer QC passes on merged output

**Priority:** LOW — optimization, not critical for correctness

---

### Enhancement 9: Formalized Open Questions System

**What it does:**
Machine-readable YAML format for tracking open questions, resolutions, and bi-directional linking to code locations.

**Technical approach:**
New file format + associated commands for question management.

**Implementation steps:**

1. **Create `.claude/open-questions.yaml` format**:
   ```yaml
   questions:
     - id: R1
       text: "Which Charlson Comorbidity Index weights should be used?"
       status: resolved
       resolution: "Use Quan 2011 updated weights (not original 1987 Charlson)"
       rationale: "Modern EHR-based studies use ICD-10 codes; Quan 2011 provides validated ICD-10 mappings"
       affected_code:
         - file: projects/exelixis-sap/adam_adsl.R
           lines: [345-360]
           marker: "REVISIT: Quan 2011 weights used — R1"
       resolved_by: feature-planner
       resolved_date: 2026-03-27

     - id: R3
       text: "Does RECIST BOR require confirmed response?"
       status: resolved
       resolution: "Yes, both CR and PR require confirmation with ≥28-day interval per RECIST 1.1"
       rationale: "SAP explicitly states: 'minimum interval between 2 assessments should be no less than 4 weeks'"
       affected_code:
         - file: projects/exelixis-sap/adam_adrs.R
           lines: [156-178]
           marker: "REVISIT: Confirmed response per SAP (≥28-day interval). See R3"
       resolved_by: feature-planner
       resolved_date: 2026-03-27

     - id: W4
       text: "What are the controlled terminology values for LOTENDRSN?"
       status: open
       severity: warning
       rationale: "No standardized CDISC CT exists; raw CMRSDISC values may be acceptable"
       affected_code:
         - file: projects/exelixis-sap/adam_adlot.R
           lines: [144]
           marker: "REVISIT: Using raw CMRSDISC — see W4"
       flagged_by: clinical-code-reviewer
       flagged_date: 2026-03-27
   ```

2. **Create question management commands**:

   **`/resolve-question`**:
   ```bash
   /resolve-question R1 --resolution="Use Quan 2011" --rationale="Modern EHR standard"
   ```

   **`/list-open-questions`**:
   ```bash
   /list-open-questions                    # All open
   /list-open-questions dataset=ADLOT      # Open for specific dataset
   /list-open-questions status=resolved    # All resolved
   ```

   **`/check-revisit-comments`**:
   ```bash
   /check-revisit-comments projects/exelixis-sap/adam_adsl.R
   ```
   - Scans code for `REVISIT:` comments
   - Ensures each links to a question ID in open-questions.yaml
   - Ensures each linked question exists and is resolved
   - Flags orphaned REVISIT comments (no question ID)

3. **Reviewer integration**:
   When reviewer encounters REVISIT comment:
   ```
   Line 345: # REVISIT: Quan 2011 weights used — R1

   Validation:
   ✓ Question R1 exists in open-questions.yaml
   ✓ Question R1 is marked "resolved"
   ✓ Resolution matches code implementation (Quan 2011 weights applied)
   ✓ This file is listed in R1.affected_code

   If any validation fails → Flag as W1 (warning)
   ```

4. **Planner integration**:
   - When creating plan, planner creates open-questions.yaml with all unresolved items
   - Planner assigns IDs: R1, R2, ... (resolved), W1, W2, ... (warnings), B1, B2, ... (blocking)
   - Programmer includes question IDs in REVISIT comments
   - Reviewer validates linkage

**Dependencies:** None — new file format

**Success criteria:**
- YAML format is human-readable and machine-parseable
- Bi-directional linking works (code → question, question → code)
- Commands successfully manage question lifecycle
- Reviewer catches orphaned REVISIT comments

**Priority:** LOW — nice-to-have for traceability

---

## 4. Recommended Phasing

### Phase 1: Foundation (Prevent Errors)

**Goal:** Increase first-pass QC rate from 67% to >75%

| Enhancement | Priority | Effort | Dependencies | Expected Impact |
|-------------|----------|--------|--------------|-----------------|
| 1. Data Contract Validation | HIGH | Medium (2-4h) | None | Prevents structure mismatches |
| 2. Exploration Checkpoint | HIGH | Low (1-2h) | E1 | Forces plan-reality reconciliation |
| 3. Data Profiling Skill | HIGH | High (4-6h) | None | Prevents terminology errors |
| 4. Memory Persistence | MEDIUM | Medium (2-3h) | None | Builds institutional knowledge |
| 5. Enhanced Between-Wave Checks | MEDIUM | Medium (3-4h) | None | Catches logic errors early |

**Total effort:** 12-19 hours
**Parallel workstreams:** E1+E3 (independent), E2+E4+E5 (independent)
**Expected outcome:** >75% first-pass QC rate, fewer internal iterations

### Phase 2: Optimization (Improve Efficiency)

**Goal:** Reduce internal iterations for high-complexity datasets, improve traceability

| Enhancement | Priority | Effort | Dependencies | Expected Impact |
|-------------|----------|--------|--------------|-----------------|
| 6. Complexity Threshold Detection | MEDIUM | Medium (3-4h) | None | Auto-suggests helper functions |
| 7. Plan Validation Command | LOW | Medium (3-4h) | E1 | Catches anti-patterns before execution |
| 8. Multi-Agent Dataset Splitting | LOW | High (6-8h) | E6 | Parallelizes high-complexity datasets |
| 9. Formalized Open Questions | LOW | High (6-8h) | None | Improves traceability |

**Total effort:** 18-24 hours
**Parallel workstreams:** E6+E7 (independent), E8+E9 (independent)
**Expected outcome:** <5 internal iterations for high-complexity datasets, complete audit trail

---

## 5. Implementation Orchestration

### Phase 1 Task Breakdown

| Task | Agent | Priority | Dependencies | Description |
|------|-------|----------|--------------|-------------|
| E1.1: Create data contract command | r-clinical-programmer | P1 | None | Implement `/validate-data-contract` command |
| E1.2: Test data contract on first-iteration data | r-clinical-programmer | P1 | E1.1 | Run command against NPM-008 SDTM, verify detects MHDTC/QSSTRESN |
| E1.3: QC data contract implementation | clinical-code-reviewer | P1 | E1.2 | Verify command accuracy, report correctness |
| E3.1: Create data profiling skill | r-clinical-programmer | P1 | None | Implement `/profile-data` skill + R function |
| E3.2: Generate profiles for NPM-008 | r-clinical-programmer | P1 | E3.1 | Run `/profile-data` for LB, MH, QS domains |
| E3.3: QC profiling outputs | clinical-code-reviewer | P1 | E3.2 | Verify frequency tables accurate, markdown readable |
| E2.1: Update r-code skill with checkpoint | r-clinical-programmer | P2 | E1.3 | Add exploration checkpoint to skill definition |
| E2.2: Test checkpoint enforcement | r-clinical-programmer | P2 | E2.1 | Simulate agent run with checkpoint, verify halts on mismatch |
| E4.1: Define memory templates | feature-planner | P2 | None | Create example feedback/project/reference memories |
| E4.2: Update reviewer agent definition | r-clinical-programmer | P2 | E4.1 | Add memory persistence instructions to agent |
| E4.3: Test memory write-read cycle | r-clinical-programmer | P2 | E4.2 | Simulate QC → save memory → load in next wave |
| E5.1: Create between-wave validation script | r-clinical-programmer | P3 | None | Implement `between_wave_checks.R` |
| E5.2: Test validation on first-iteration data | r-clinical-programmer | P3 | E5.1 | Run checks against completed waves, verify catches issues |
| E5.3: QC validation script | clinical-code-reviewer | P3 | E5.2 | Verify all check types implemented correctly |

**Critical path:** E1.1 → E1.2 → E1.3 (data contract) and E3.1 → E3.2 → E3.3 (profiling)

### Phase 2 Task Breakdown

| Task | Agent | Priority | Dependencies | Description |
|------|-------|----------|--------------|-------------|
| E6.1: Update planner with complexity detection | feature-planner | P1 | Phase 1 complete | Add pattern counting algorithm to planner |
| E6.2: Test detection on ADSL spec | feature-planner | P1 | E6.1 | Run planner on ADSL, verify flags 20 biomarkers |
| E7.1: Create plan validation command | r-clinical-programmer | P2 | E6.2, E1.3 | Implement `/validate-plan` command |
| E7.2: Test validation on first-iteration plan | r-clinical-programmer | P2 | E7.1 | Run against plan_adam_automation, verify catches issues |
| E8.1: Document split orchestration pattern | feature-planner | P2 | E6.2 | Write guidance for multi-agent splitting |
| E8.2: Create example split plan for ADSL | feature-planner | P2 | E8.1 | Write 4-part split specification |
| E8.3: Implement orchestrator merge logic | r-clinical-programmer | P3 | E8.2 | Add merge workflow to orchestrator |
| E9.1: Define open-questions.yaml schema | feature-planner | P3 | None | Document YAML format with examples |
| E9.2: Create question management commands | r-clinical-programmer | P3 | E9.1 | Implement /resolve-question, /list-open-questions, /check-revisit-comments |
| E9.3: Test question lifecycle | r-clinical-programmer | P3 | E9.2 | Create → resolve → link to code → validate |

**Critical path:** E6.1 → E6.2 → E7.1 (complexity detection feeds plan validation)

---

## 6. Open Questions / Decisions — RESOLVED

All questions have been resolved as of 2026-03-27. Decisions are now incorporated throughout the plan.

### Q1: RAG Integration for Data Profiles ✓ RESOLVED

**DECISION:** Markdown only (Option B). Do not add data profiles to RAG.

**Rationale:** RAG should contain only the cleanest reference materials (CDISC standards, controlled terminology). Study-specific data profiles are transient and would add noise.

**Implementation:**
- Data profiles saved to `projects/<study-name>/data-profiles/<domain>.md`
- Lifecycle:
  1. Generated during Step 4.5 (after exploration)
  2. Used during Step 5 (derivation) for actual value reference
  3. Documented in dev logs
  4. Persisted for audit trail
  5. Regenerated only if source data changes
- Agents reference profiles as markdown files when needed

### Q2: Between-Wave Check Failure Handling ✓ RESOLVED

**DECISION:** Auto-retry (Option A).

**Rationale:** Maintains autonomous workflow. Most validation failures are fixable by the agent without user intervention.

**Implementation:**
- When between-wave validation fails, orchestrator automatically spawns a fix cycle
- Fix cycle limited to 1 retry per dataset to prevent runaway compute
- If retry fails, escalate to user with detailed report
- User can override auto-retry behavior via orchestrator flag if needed

### Q3: Multi-Agent Splitting Criteria ✓ RESOLVED

**DECISION:** Automatic splitting at >40 variables (NOT >80 as originally proposed).

**Rationale:** 40 variables is a more practical threshold based on first-iteration experience. ADSL at 101 variables required 7 iterations; splitting would have reduced this significantly.

**Implementation:**
- Any dataset with >40 variables automatically triggers split orchestration
- Planner must provide split strategy in plan (how to divide variables)
- Orchestrator executes split pattern from Enhancement 8
- Override available: Planner can mark dataset as `NO_SPLIT_REQUIRED` if variables are simple

### Q4: Memory Scope ✓ RESOLVED

**DECISION:** Study-specific memory (Option A).

**Rationale:** Prevents cross-contamination between studies. Each study has unique terminology, data structures, and patterns.

**Implementation:**
- Memory saved to `projects/<study-name>/.claude/agent-memory/`
- Each study maintains independent memory files
- General patterns (not study-specific) documented in project rules, not memory
- Agents inherit both study-specific memory and project-wide rules

---

## 7. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Data contract validation false positives | Medium | Medium | Include "alternative variable" detection; don't fail on type mismatches if conversion is obvious |
| Data profiling performance on large domains | Low | Medium | Add row sampling option for domains >10,000 rows; profile top-N values only |
| Memory persistence overhead | Low | Low | Keep memories under 200 lines total; use index file (MEMORY.md) for fast scanning |
| Between-wave checks too strict | Medium | Medium | Use WARNING vs BLOCKING severity; allow user override for non-critical violations |
| Complexity detection false positives | Medium | Low | Use threshold >15 (not >10); include "override" flag in plan if planner judges split unnecessary |
| Multi-agent merge failures | Low | High | Add pre-merge validation (same subject set, no duplicate columns); checkpoint after each part completes |
| RAG query performance degradation | Low | Medium | Keep study-data-profile separate from main RAG if implemented; use dedicated index |
| Open questions YAML drift from code | Medium | Medium | `/check-revisit-comments` command enforces linkage; reviewer validates during QC |

---

## 8. Success Metrics

### Quantitative (Measured per Study)

| Metric | Baseline (First Iteration) | Phase 1 Target | Phase 2 Target |
|--------|---------------------------|----------------|----------------|
| First-pass QC rate | 67% (4/6) | 75% (5-6/6) | 80%+ (5-6/6) |
| Average fix cycles per dataset | 0.33 | 0.25 | 0.15 |
| Internal iterations for high-complexity datasets | 7 (ADSL) | 4-5 | 2-3 |
| Escalations to user | 0 | 0 | 0 |
| Between-wave validation failure rate | Unknown (too shallow) | 10-20% (catching real issues) | 5-10% (cleaner inputs) |
| Data structure mismatches detected pre-execution | 0% (caught in iteration) | 80%+ | 95%+ |

### Qualitative (Assessed per Enhancement)

| Enhancement | Success Criteria |
|-------------|------------------|
| E1: Data Contract | Catches MHDTC/QSSTRESN mismatches before code execution |
| E2: Exploration Checkpoint | Agents halt with actionable message when variables missing |
| E3: Data Profiling | Prevents biomarker terminology mismatch (POSITIVE vs ALTERED) |
| E4: Memory Persistence | At least 2 patterns from Wave 1 applied in Wave 3 |
| E5: Between-Wave Checks | Catches at least 1 logic error before downstream consumption |
| E6: Complexity Detection | ADSL helper function recommended and implemented |
| E7: Plan Validation | Flags all anti-patterns from first iteration |
| E8: Multi-Agent Splitting | ADSL completes in <5 internal iterations using split approach |
| E9: Open Questions | 100% of REVISIT comments linked to resolved questions |

---

## 9. Documentation & Deliverables

### Phase 1 Deliverables

1. **Commands:**
   - `.claude/commands/validate-data-contract.md` (E1)
   - Implementation: `projects/exelixis-sap/R/validate_data_contract.R`

2. **Skills:**
   - `.claude/skills/profile-data.md` (E3)
   - Implementation: `projects/exelixis-sap/R/profile_data.R`
   - Updated: `.claude/skills/r-code.md` (E2 — exploration checkpoint)

3. **Scripts:**
   - `projects/exelixis-sap/programs/between_wave_checks.R` (E5)

4. **Agent updates:**
   - `.claude/agents/clinical-code-reviewer.md` (E4 — memory persistence)

5. **Example outputs:**
   - `projects/exelixis-sap/data-profiles/lb.md` (E3)
   - `projects/exelixis-sap/data-profiles/mh.md` (E3)
   - Memory files: `xpt_flag_encoding.md`, `lot_algorithm_complexity.md`, `npm008_biomarker_terminology.md` (E4)

### Phase 2 Deliverables

1. **Commands:**
   - `.claude/commands/validate-plan.md` (E7)
   - `.claude/commands/resolve-question.md` (E9)
   - `.claude/commands/list-open-questions.md` (E9)
   - `.claude/commands/check-revisit-comments.md` (E9)
   - Implementation: `projects/exelixis-sap/R/validate_plan.R`, `R/manage_questions.R`

2. **Agent updates:**
   - `.claude/agents/feature-planner.md` (E6 — complexity detection, E8 — split guidance)

3. **Configuration:**
   - `.claude/open-questions.yaml` schema and examples (E9)

4. **Documentation:**
   - Multi-agent split orchestration pattern guide (E8)
   - Open questions system user guide (E9)

---

## 10. Next Steps

### Immediate (Pre-Implementation)

1. **User review & approval:**
   - Review this plan with user
   - Resolve open questions Q1-Q4
   - Confirm Phase 1 scope and effort allocation

2. **Agent assignment:**
   - Assign Phase 1 tasks to r-clinical-programmer
   - Schedule clinical-code-reviewer for QC after each task group

### Phase 1 Execution

**Week 1: Foundation (E1, E3)**
- Days 1-2: Data contract validation (E1.1, E1.2, E1.3)
- Days 3-5: Data profiling skill (E3.1, E3.2, E3.3)
- Checkpoint: Both enhancements tested on first-iteration data

**Week 2: Process Improvements (E2, E4, E5)**
- Days 1-2: Exploration checkpoint (E2.1, E2.2)
- Days 3-4: Memory persistence (E4.1, E4.2, E4.3)
- Days 5: Between-wave validation (E5.1, E5.2, E5.3)
- Checkpoint: All Phase 1 enhancements integrated and tested

**Week 3: Phase 1 Validation**
- Re-run first iteration ADaM workflow with Phase 1 enhancements
- Measure metrics vs baselines
- Document Phase 1 results
- Decision point: Proceed to Phase 2 or iterate on Phase 1

### Phase 2 Execution (Contingent on Phase 1 Success)

**Week 4-5: Optimization**
- Implement E6, E7, E8, E9 per task breakdown
- Test on ADSL (highest complexity dataset)
- Measure iteration reduction

**Week 6: Phase 2 Validation**
- Full study re-run with all enhancements
- Compare metrics: Baseline → Phase 1 → Phase 2
- Document final results and lessons learned

---

## 11. Bottom Line

This plan systematically addresses the **four major issue categories** from the first iteration:

1. **Data mismatches** → E1 (contract validation) + E2 (exploration checkpoint)
2. **Terminology errors** → E3 (data profiling)
3. **Complexity struggles** → E6 (auto-detection) + E8 (multi-agent splitting)
4. **Weak validation** → E5 (enhanced between-wave checks)

Additionally, **E4 (memory)** builds institutional knowledge and **E7/E9 (plan validation, open questions)** improve traceability.

**Recommended approach:**
- **Phase 1 first:** Implement E1-E5 (foundation enhancements) to increase first-pass QC rate and prevent errors
- **Measure impact:** Re-run first iteration with Phase 1 enhancements, compare metrics
- **Phase 2 second:** If Phase 1 achieves >75% first-pass QC rate, implement E6-E9 (optimizations)

**Expected outcome:** >80% first-pass QC rate, <3 internal iterations for high-complexity datasets, complete audit trail, production-ready for 200+ subject studies.

---

**Plan Status:** ✅ Ready for Implementation — All questions resolved (2026-03-27)
**Next Action:** User review → resolve open questions → assign Phase 1 tasks → begin implementation
