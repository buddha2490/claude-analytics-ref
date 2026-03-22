# Skill Strategy Plan: Automated Clinical Programming Pipeline

## Vision

Move the clinical programming group to fully automated SDTM/TFL production using Claude Code. The pipeline progresses through three stages: simulated data → automated data pulls → full CDISC dataset generation from real data. All stages share the same downstream code so that switching from simulated to real data requires changing only the data source, not the analysis programs.

## Pipeline Stages

```
Stage 1: Simulated Data          Stage 2: Data Pull           Stage 3: Full Automation
─────────────────────           ──────────────────           ────────────────────────
Generate CDISC-compliant        Pull raw variables from      Generate R code that
dummy datasets from specs       Databricks into local/       transforms raw data into
and data dictionary.            intermediate datasets.       final CDISC SDTM domains.

[sim data] ──┐                  [databricks] ──┐             [databricks] ──┐
             │                                 │                             │
             ├──→ SDTM datasets ──→ TFL code ──→ RTF output                 │
             │                                 │                             │
[can do now] │                  [work computer]│             [final goal]    │
```

## Existing Assets

| Asset | Location | Status |
|-------|----------|--------|
| CDISC SDTM domain specs (15 domains) | `exelixus-sap-demo/.claude/skills/cdisc-sdtm/` | Complete |
| CDISC RAG MCP server | `~/Rdata/cdisc-rag/` | Operational |
| Data dictionaries (2 Excel files) | `exelixus-sap-demo/reference data/` | Available |
| Table shells (Excel) | `exelixus-sap-demo/reference data/` | Available |
| Statistical Analysis Plan (PDF) | `exelixus-sap-demo/docs/` | Available |
| R code generation skill (`r-code`) | `claude-skills/.claude/skills/r-code/` | Complete |
| TFL output function (`create_tfl`) | `claude-skills/R/create_tfl.R` | Complete, tested |
| Simulated DM program | `exelixus-sap-demo/programs/sim_dm.R` | Complete (1 of 15) |

## Proposed Skills

### Skill 1: `/sim-sdtm` — Simulated SDTM Dataset Generator

**Purpose:** Generate a complete, CDISC-compliant simulated dataset for any SDTM domain. This is the Stage 1 workhorse — it reads the domain spec sheet and data dictionary, then produces a self-contained R program that creates realistic dummy data.

**Trigger:** Auto-invoked when the user asks to simulate or generate dummy data for an SDTM domain.

**Inputs:**
- Domain name (e.g., "DM", "AE", "LB")
- Number of subjects (default: 50)
- Reference to the domain spec sheet (auto-located from `cdisc-sdtm` skill)
- Reference to the data dictionary (for source variable names and value constraints)

**Outputs (3 artifacts per the `r-code` skill):**
- `programs/sim_<domain>.R` — The simulation program
- `tests/test-sim_<domain>.R` — Validation tests
- `data/<domain>.xpt` — The generated XPT dataset (produced by running the program)

**What the generated program must do:**
1. Create realistic simulated data using `set.seed()` for reproducibility
2. Ensure all variables match the domain spec (names, labels, types, lengths)
3. Use only valid CDISC Controlled Terminology values (pulled from spec sheet or RAG)
4. Maintain cross-domain consistency:
   - All subjects must exist in DM (DM is generated first, others reference it)
   - Dates must fall within the subject's study period (RFSTDTC to RFENDTC)
   - STUDYID, USUBJID format must match across all domains
   - --SEQ variables must be unique within USUBJID
5. Calculate derived variables (study days, durations, flags)
6. Apply variable labels required for XPT transport
7. Run the full validation block (stopifnot assertions from the spec sheet)
8. Write the dataset to `data/<domain>.xpt` using `haven::write_xpt()`

**Cross-domain dependency order:**
```
DM (first — all other domains reference DM)
 ├── AE, MH, DS, HO, SC, SU, QS (reference DM for dates and demographics)
 ├── CM, PR (reference DM + may reference AE)
 ├── EC, EX (reference DM for treatment period)
 ├── VS, LB (reference DM for visit windows and demographics)
 └── RELREC (last — references AE, CM, HO)
```

**Key design decisions:**
- The simulated DM dataset is the anchor. When generating any other domain, the program must first read `data/dm.xpt` to get the subject list, reference dates, and demographics.
- Realistic clinical patterns matter: not every subject should have every event. AE frequency, lab visit patterns, and medication counts should follow plausible distributions.
- The generated programs should be portable — a team member should be able to run `sim_dm.R` followed by `sim_ae.R` and get consistent, valid datasets without Claude Code.

---

### Skill 2: `/sdtm-pull` — Databricks Data Pull Generator

**Purpose:** Generate R code that connects to Databricks via sparklyr, pulls the raw source variables needed for a given SDTM domain, and saves them as intermediate datasets. This is Stage 2 — it bridges the gap between simulated data and full transformation.

**Trigger:** Auto-invoked when the user asks to pull data from Databricks for an SDTM domain, or to create a data extraction program.

**Inputs:**
- Domain name (e.g., "DM", "AE")
- Reference to the domain spec sheet (for RWE/ECA Considerations section — contains source table names and join strategies)
- Reference to the data dictionary (for exact source column names)

**Outputs:**
- `programs/pull_<domain>.R` — The data pull program
- `tests/test-pull_<domain>.R` — Tests that validate the pull output structure (run against simulated data as a proxy)

**What the generated program must do:**
1. Connect to Databricks via sparklyr (connection parameters externalized, not hardcoded)
2. Pull only the variables needed for the domain (no `SELECT *`)
3. Perform source-level joins as documented in the spec sheet's RWE/ECA Considerations
4. Apply basic source-level filters (e.g., study population, date ranges)
5. Save intermediate datasets to `data/raw/` as RDS or parquet files
6. Log the pull: record counts per source table, timestamp, any warnings
7. Disconnect from Databricks

**Key design decisions:**
- Connection parameters (Databricks host, token, cluster) should come from environment variables or a config file — never hardcoded in the program.
- The pull programs are intentionally simple. No CDISC transformations happen here — just get the raw data local. This separation makes debugging easier and lets the team inspect source data before transformation.
- Tests use simulated data to validate that the output has the expected structure (correct columns, types). Full integration testing happens on the work computer.

---

### Skill 3: `/sdtm-map` — SDTM Mapping Program Generator

**Purpose:** Generate R code that transforms raw source data into a final CDISC SDTM domain. This is Stage 3 — the full transformation layer. It reads intermediate datasets (from Stage 2 pull or Stage 1 simulation) and produces the final XPT.

**Trigger:** Auto-invoked when the user asks to create an SDTM mapping program, transform data to CDISC, or build a domain dataset.

**Inputs:**
- Domain name
- Reference to the domain spec sheet (for variable specifications, CT values, mapping logic)
- Source data location (either `data/raw/` from pull or `data/` from simulation)

**Outputs:**
- `programs/sdtm_<domain>.R` — The mapping/transformation program
- `tests/test-sdtm_<domain>.R` — Validation tests
- `data/<domain>.xpt` — The final SDTM dataset

**What the generated program must do:**
1. Read source data (raw pulled data or simulated intermediates)
2. Apply all transformations documented in the spec sheet's R Mapping Example:
   - Variable renaming and derivation
   - Controlled Terminology mapping
   - ISO 8601 date/time formatting
   - Study day calculation
   - Sequence number (--SEQ) assignment
   - Supplemental qualifier (SUPP--) generation where applicable
3. Apply variable attributes (labels, types, lengths) using xportr
4. Run the full validation block from the spec sheet
5. Write to `data/<domain>.xpt`

**Key design decisions:**
- The mapping programs must work with both simulated and real data. The input format should be consistent regardless of source. This is why Stage 2 saves intermediates in a standard format.
- Complex business rules (MH/AE boundary, cancer/non-cancer meds) are documented in the spec sheets. The skill should translate those rules directly into R code with clear comments explaining the logic.
- The spec sheets already contain R mapping examples. The skill should use those as a starting template, but adapt them to read from the actual intermediate file locations rather than inline Databricks queries.

---

### Skill 4: `/tfl-build` — TFL Program Generator

**Purpose:** Generate R code that reads final SDTM datasets, prepares an analysis-ready dataset (ARDS), and produces a regulatory-ready RTF table using `create_tfl()`. Maps directly from table shell specifications to working output programs.

**Trigger:** Auto-invoked when the user asks to create a table, figure, or listing, or to implement a table shell.

**Inputs:**
- Table shell specification (from the table shells Excel, or described by the user)
- Target SDTM datasets (which domains to read from)
- Output file name

**Outputs:**
- `programs/tfl_<table_number>.R` — The TFL program
- `tests/test-tfl_<table_number>.R` — Tests that validate the ARDS structure
- `output/<table_number>.rtf` — The formatted RTF output

**What the generated program must do:**
1. Read the required SDTM XPT datasets from `data/`
2. Derive the analysis population (e.g., ITT, Safety, Per-Protocol)
3. Compute summary statistics, counts, or listings as specified by the table shell
4. Assemble the display-ready ARDS data frame (one row per table row, one column per table column)
5. Call `create_tfl()` with appropriate titles, footnotes, and column headers
6. The RTF output should match the table shell layout

**Key design decisions:**
- Table shells define the *what* (layout, statistics, population). The skill translates that into the *how* (dplyr summaries, pivots, formatting).
- Titles and footnotes should come from the table shell specification, not be invented.
- The same TFL program works whether the input datasets are simulated or real — only the data values change, not the code.

---

### Skill 5: `/study-plan` — Study Build Orchestrator

**Purpose:** Read the SAP and data dictionary, then produce a phased implementation plan for the entire study. This is the project management layer — it identifies all required domains and outputs, maps dependencies, and generates the sequence of skill invocations needed to build everything.

**Trigger:** Invoked when the user asks to plan a full study build, assess what needs to be done, or generate a project roadmap.

**Inputs:**
- Statistical Analysis Plan (PDF)
- Data dictionary (Excel)
- Table shells (Excel)
- Current state of `data/` and `programs/` directories (to assess what's already done)

**Outputs:**
- A plan document (markdown) with:
  - List of all SDTM domains required and their dependency order
  - List of all TFLs required from the table shells
  - Phased build sequence (which domains first, which TFLs depend on which domains)
  - Estimated skill invocations (e.g., "run `/sim-sdtm DM` first, then `/sim-sdtm AE`...")
  - Open questions or blockers identified from the specs

**Key design decisions:**
- This skill does not generate code — it generates the plan. The user reviews and approves the plan, then executes it step by step (or asks Claude to execute it).
- The plan should be concrete enough that a team member could follow it without understanding the full SAP.
- The skill should check what already exists (which XPT files are in `data/`, which programs are in `programs/`) and only plan what's remaining.

---

## Skill Dependency Map

```
/study-plan                          (planning — reads SAP, DD, table shells)
     │
     ▼
/sim-sdtm                           (Stage 1 — simulated data)
     │  generates data/*.xpt
     │  from spec sheets + DD
     │
     ├──────────────────────┐
     ▼                      ▼
/sdtm-pull               /tfl-build  (Stage 2/TFL — can run in parallel)
     │  generates            │  generates TFL programs
     │  data/raw/*           │  from table shells + data/*.xpt
     │                       │
     ▼                       ▼
/sdtm-map                output/*.rtf
     │  generates
     │  data/*.xpt (real)
     │
     ▼
/tfl-build (rerun with real data — same code, new input)
     │
     ▼
output/*.rtf (final regulatory tables)
```

## Cross-Cutting Concerns

### Skill Interaction with `r-code`

All skills that generate R programs inherit the `r-code` skill rules:
- Tidyverse style guide
- roxygen2 documentation for functions
- testthat tests for every program
- Validation by execution before delivery
- Approved package list
- `library()` over `package::function()` (except namespace conflicts)

Each skill adds domain-specific rules on top of `r-code`.

### CDISC RAG Integration

Skills that need controlled terminology values should query the CDISC RAG MCP server rather than hardcoding values. This keeps the skills current if CT versions are updated.

### Spec Sheet as Single Source of Truth

The `cdisc-sdtm` spec sheets are the authority for:
- Variable names, labels, types, and core designations
- Controlled terminology values
- Source table names and join strategies
- Validation assertions
- Common pitfalls to avoid

All code-generating skills reference these specs. If a spec changes, the generated code should reflect the change on the next invocation. The specs are never duplicated into the skills — they are read at invocation time.

### Team Workflow

Since the group will all use Claude Code:
1. Spec sheets and skills live in the shared repository
2. A new team member clones the repo, opens in VS Code, and Claude Code auto-launches
3. They run `/study-plan` to see what needs to be done
4. They run `/sim-sdtm DM`, `/sim-sdtm AE`, etc. to generate programs and data
5. On their work computer with Databricks access, they run `/sdtm-pull` and `/sdtm-map`
6. They run `/tfl-build` to produce regulatory tables
7. All generated programs are committed to the repo — they're reviewable R code, not black boxes

### Portability Between Studies

These skills are designed around one study (XB010-101), but the architecture is portable:
- The `r-code`, `create_tfl`, `/tfl-build`, and `/study-plan` skills are study-agnostic
- `/sim-sdtm`, `/sdtm-pull`, and `/sdtm-map` read from spec sheets — a new study just needs new spec sheets
- The CDISC RAG is already study-agnostic (it contains SDTM-IG standards, not study data)
- To onboard a new study: create spec sheets (potentially using Claude to draft from the study's data dictionary), then run the same pipeline

## Implementation Priority

| Priority | Skill | Why First |
|----------|-------|-----------|
| 1 | `/sim-sdtm` | Unblocks everything — you can build and test TFL code without Databricks access. You already have 1 of 15 domains (sim_dm.R). |
| 2 | `/tfl-build` | Highest visible value — produces the deliverables your team and sponsors see. Can run immediately on simulated data. |
| 3 | `/study-plan` | Helps the team self-serve — they can see the full picture and pick up work without your guidance. |
| 4 | `/sdtm-pull` | Only useful on the work computer with Databricks. Build this when you're ready to connect real data. |
| 5 | `/sdtm-map` | The final transformation layer. Most of the logic is already in the spec sheets — this skill just operationalizes it. |

## Next Step

Build `/sim-sdtm` first. Start by generating the remaining 14 simulated domain datasets (AE, VS, LB, etc.) using the existing spec sheets. Each domain validates the spec sheet's completeness — if the spec is missing information needed to simulate data, that surfaces immediately.
