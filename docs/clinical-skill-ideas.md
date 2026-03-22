# Clinical Programming Skill Ideas

Skill ideas beyond the core SDTM/TFL pipeline. These skills augment custom agents by providing domain expertise and output structure — agents handle the process (multi-step reasoning, tool use, iteration), skills handle the standards (what good looks like, what format to use, what rules to follow).

## The Agent + Skill Pattern

```
Without skill:  "Agent, review this SDTM program"
                → Generic code review, misses pharma-specific issues

With skill:     "Agent, review this SDTM program" + /qc-review loaded
                → Checks CT values, variable attributes, sort order,
                  derivation logic against SAP, produces QC log
```

The skill doesn't replace the agent — it gives the agent domain expertise and output structure.

---

## Code Quality & Compliance

### `/qc-review` — Independent QC / Double Programming Review

Pharma requires independent QC for every program. This skill defines *how* to review R code for regulatory compliance.

**What it does:**
- Checks CDISC CT values against the RAG
- Verifies variable attributes match domain specs (names, labels, types, lengths)
- Confirms sort order matches spec sheet requirements
- Validates derivation logic against the SAP
- Checks for common pitfalls listed in the domain spec sheets

**Output:** A structured QC log (pass/fail per check, reviewer notes, discrepancies flagged).

**Why it matters:** QC is a regulatory requirement. This skill automates the checklist so the reviewer focuses on logic, not mechanics.

---

### `/pkg-qualify` — R Package Qualification for Regulated Use

FDA expects documentation justifying trust in every R package used in a submission.

**What it does:**
- Takes a package name as input
- Pulls CRAN metadata: version, maintainer, license, dependencies
- Checks test coverage and CI status (if available)
- Documents intended use within the project
- Produces a qualification document in the expected format

**Why it matters:** Every time your team installs a new package, someone has to produce this paperwork. This skill generates it from metadata that already exists.

---

## Regulatory Documents

### `/define-xml` — Define.xml Generation

Every SDTM submission requires a define.xml file containing dataset metadata for FDA reviewers.

**What it does:**
- Reads the domain spec sheets and generated XPT files
- Extracts variable metadata (names, labels, types, controlled terminology, origins)
- Produces structured define.xml content or the input for a define.xml generator tool
- Cross-references controlled terminology codelists

**Why it matters:** Define.xml creation is tedious manual work, but almost entirely derivable from information already captured in the spec sheets. This is pure automation of existing knowledge.

---

### `/adrg` — Analysis Data Reviewer's Guide

The ADRG is a required submission document that explains how analysis datasets were created.

**What it does:**
- Reads the R programs, data dictionary, and SAP
- Drafts ADRG sections: data sources, derivation methods, software environment, program listing, conformance summary
- Follows FDA format expectations for ADRG structure

**Why it matters:** Your agents do the heavy analysis. This skill ensures the documentation meets regulatory format without manual assembly.

---

## Data Profiling & Exploration

### `/data-profile` — Source Data Profiling

Before mapping data, you need to understand what the source data actually looks like. The data dictionary says what *should* be there; the profile says what *is* there.

**What it does:**
- Takes a dataset (local file or Databricks table name)
- Produces a standardized profile:
  - Row counts and unique subject counts
  - Unique values per variable (with frequencies for categorical)
  - Missing/null rates per variable
  - Date ranges and format consistency
  - Numeric distributions and outlier flags
  - Value length distributions (important for XPT character widths)

**Why it matters:** When an agent is planning an SDTM mapping, this profile tells it what edge cases to handle. Surfaces data quality issues before they become mapping bugs.

---

### `/ct-lookup` — CDISC Controlled Terminology Quick Reference

A thin skill that wraps the CDISC RAG MCP into a convenient, team-friendly pattern.

**What it does:**
- Takes a variable name or codelist ID (e.g., `VSTESTCD`, `C66741`)
- Queries the CDISC RAG
- Returns the full controlled terminology codelist with valid values
- Formats output for easy copy-paste into R code

**Why it matters:** Simple but high-frequency. Saves time and reduces transcription errors when coding CT values. Lowers the barrier for team members who don't know how to query the RAG directly.

---

## Team & Workflow

### `/spec-author` — Domain Spec Sheet Drafting

You built 15 domain spec sheets for XB010-101. For the next study, you don't want to do that manually again.

**What it does:**
- Takes a study's data dictionary and SAP as input
- Drafts a domain spec sheet in the established format:
  - Domain Overview (observation class, structure, purpose, sort order)
  - Variable Specification (grouped by role)
  - Controlled Terminology Detail
  - RWE/ECA Considerations (source tables, joins, data quality)
  - R Mapping Example
  - SUPP-- section
  - Common Pitfalls
- An agent does the research; this skill constrains the output format so every spec is consistent across studies

**Why it matters:** Spec sheets took significant effort to build the first time. This skill makes the second study (and every study after) dramatically faster. The format is already proven — this just replicates the pattern.

---

### `/onboard` — Team Onboarding Guide

Your team is learning Claude Code. This skill provides interactive, project-specific guidance.

**What it does:**
- Walks a new team member through the project setup:
  - How to use the skills you've built
  - The pipeline stages (simulate → pull → map → TFL)
  - Directory conventions (where programs, data, output, specs live)
  - How to invoke skills and agents
  - How to work with the CDISC RAG
- Tailored to your specific setup, not generic Claude Code docs
- Updated as your workflow evolves

**Why it matters:** You're rolling Claude Code out to a team. The faster they're productive, the faster the group moves to automated programming. This skill is the difference between "ask Brian" and "ask Claude."

---

### `/git-workflow` — Standardized Git Conventions

Defines how your team interacts with version control so agents and humans follow the same patterns.

**What it does:**
- Enforces branch naming conventions (e.g., `sdtm/dm`, `tfl/14-1-1`, `sim/ae`)
- Defines commit message format (e.g., `[SDTM] DM: add demographics mapping program`)
- Specifies what goes in PR descriptions (domains affected, validation status, QC log reference)
- Lists files that should never be committed (data files, credentials, large binaries)
- Agents that generate code follow these conventions automatically when committing

**Why it matters:** Consistency across a team using Claude Code means every commit, branch, and PR follows the same pattern — whether generated by a human or an agent.

---

## Prioritization

| Priority | Skill | Rationale |
|----------|-------|-----------|
| 1 | `/spec-author` | Needed the moment a second study starts. Saves weeks of manual spec writing. |
| 2 | `/qc-review` | Regulatory requirement — QC happens regardless. Automate the checklist. |
| 3 | `/data-profile` | Essential before pulling real data. Profile first, map second. |
| 4 | `/onboard` | Team is adopting Claude Code now. Lower the learning curve early. |
| 5 | `/ct-lookup` | Low effort, high frequency. Quick win for the whole team. |
| 6 | `/define-xml` | Needed at submission time. Can wait until datasets are being finalized. |
| 7 | `/adrg` | Same — submission-time deliverable. Build when the pipeline is mature. |
| 8 | `/pkg-qualify` | Needed per-package, not per-study. Build when the team starts adding packages. |
| 9 | `/git-workflow` | Important but can start as CLAUDE.md conventions before becoming a full skill. |
