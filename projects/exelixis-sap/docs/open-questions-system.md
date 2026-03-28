# Open Questions Tracking System

**Enhancement 9** from the ADaM Workflow Enhancements Plan

**Implementation Date:** 2026-03-27
**Status:** ✓ Complete and Tested

---

## Overview

A machine-readable YAML-based system for tracking open questions, decisions, and their linkage to code implementations. Provides bidirectional traceability between methodology decisions and code artifacts.

## Components

### 1. YAML Schema (`.claude/open-questions.yaml`)

**Location:** `projects/exelixis-sap/.claude/open-questions.yaml`

**Structure:**

```yaml
questions:
  - id: R1                    # Unique ID (R=resolved, W=warning, B=blocking)
    text: "Question text"
    status: resolved          # open | resolved | deferred
    severity: info            # info | warning | blocking
    rationale: "Why this matters"
    resolution: "Decision made"  # Required when status=resolved
    affected_code:            # Bi-directional linking
      - file: relative/path/to/file.R
        lines: [start, end]
        marker: "REVISIT: Comment text linking to this ID"
    resolved_by: "agent-name"
    resolved_date: "YYYY-MM-DD"
    revisit_trigger: "When to review this decision"
```

**Question ID Conventions:**

| Prefix | Meaning | Example |
|--------|---------|---------|
| R1-R99 | Resolved decisions | R1, R5, R8 |
| W1-W99 | Warning-level open questions | W4, W5, W6 |
| B1-B99 | Blocking open questions | B1, B2 |

### 2. R Management Functions (`R/manage_questions.R`)

**Core Functions:**

```r
# Add a new question
add_question(yaml_path, id, text, rationale, affected_code,
             severity = "info", flagged_by, flagged_date)

# Resolve an open question
resolve_question(yaml_path, id, resolution, resolved_by, resolved_date)

# List questions with optional filters
list_questions(yaml_path, status_filter = NULL, dataset_filter = NULL)

# Check REVISIT comments in code files
check_revisit_comments(code_dir, yaml_path, pattern = "*.R")

# Check if a specific question is resolved
is_question_resolved(yaml_path, id)

# Pretty-print questions to console
print_questions(questions_df)
```

### 3. Commands

#### `/resolve-question`

**Purpose:** Mark an open question as resolved.

**Usage:**

```bash
/resolve-question <id> resolution="<decision>" [rationale="<context>"]
```

**Example:**

```bash
/resolve-question W4 resolution="Use raw CMRSDISC values; no CT mapping needed"
```

#### `/list-open-questions`

**Purpose:** Display questions with optional filters.

**Usage:**

```bash
/list-open-questions [status=<status>] [dataset=<name>] [severity=<level>]
```

**Examples:**

```bash
/list-open-questions                    # All questions
/list-open-questions status=open        # Open questions only
/list-open-questions dataset=ADLOT      # Questions affecting ADLOT
/list-open-questions severity=blocking  # Blocking questions only
```

#### `/check-revisit-comments`

**Purpose:** Scan code for REVISIT comments and validate linkage.

**Usage:**

```bash
/check-revisit-comments [directory]
```

**What it checks:**

- ✓ **OK**: REVISIT comment has valid question ID that is resolved
- ⚠ **WARNING**: REVISIT comment has no question ID
- ⚠ **WARNING**: Question ID exists but is still open
- ✗ **ERROR**: Question ID referenced but not found in YAML

**Example:**

```bash
/check-revisit-comments programs/
```

### 4. Test Suite (`tests/test-manage_questions.R`)

**Coverage:**

- ✓ Add questions
- ✓ Resolve questions
- ✓ List with filters (status, dataset, severity)
- ✓ Check REVISIT comments
- ✓ Validate linkage
- ✓ Error handling (duplicate IDs, missing files, invalid severity)

**Run tests:**

```bash
Rscript --vanilla tests/test-manage_questions.R
```

---

## Workflow Integration

### For Planners (feature-planner agent)

1. **During plan creation:** Identify all open questions and create entries in `open-questions.yaml`
2. **Assign IDs:** Use R1-R99 for resolved, W1-W99 for warnings, B1-B99 for blocking
3. **Document decisions:** For resolved questions, record rationale and affected code locations

### For Programmers (r-clinical-programmer agent)

1. **Before implementation:** Run `/list-open-questions dataset=<DATASET>` to check for relevant questions
2. **In code:** Add REVISIT comments linking to question IDs:
   ```r
   # REVISIT: Quan 2011 weights used per R1
   cci_score <- calculate_charlson(conditions, weights = "quan2011")
   ```
3. **After resolution:** Update affected code to reflect the decision

### For Reviewers (clinical-code-reviewer agent)

1. **During QC:** Run `/check-revisit-comments programs/` to validate all linkages
2. **Check resolution:** Verify all question IDs in REVISIT comments are resolved
3. **Flag issues:** Report orphaned comments or unresolved questions as QC findings

---

## NPM-008 Example Questions

The system is pre-populated with 11 questions from NPM-008:

**Resolved (R1-R8):**

- **R1:** Charlson Comorbidity Index version → Use Quan 2011
- **R2:** CCI scoring source → Derive from MH.MHTERM
- **R3:** RECIST BOR confirmation → Confirmed response required (≥28 days)
- **R4:** ADTTE month conversion → days / 30.4375
- **R5:** NPM LoT parameters → 45-day window, 120-day gap, no switching
- **R6:** AE-HO linkage → Join on USUBJID + HOHNKID == AESEQ
- **R7:** Flag convention → Use Y/blank (ADaM standard)
- **R8:** ADRS AVAL coding → Study-specific 1=CR, 2=PR convention

**Open (W4-W6):**

- **W4:** LOTENDRSN controlled terminology values
- **W5:** Neoadjuvant vs adjuvant definition
- **W6:** ADBS ADaM compliance structure

---

## Benefits

### 1. Traceability

- Every methodology decision has a documented rationale
- Code links back to decisions via REVISIT comments
- Decisions link forward to code locations
- Audit trail for regulatory submission

### 2. Knowledge Management

- Institutional memory of "why" decisions were made
- Prevents repeating mistakes across studies
- Onboarding resource for new team members
- Review triggers document when to revisit decisions

### 3. Quality Assurance

- Automated validation of code-decision linkage
- Catches orphaned REVISIT comments
- Ensures all questions are resolved before final analysis
- Reviewer can verify all decisions are implemented correctly

### 4. Collaboration

- Clear handoff between planner → programmer → reviewer
- Status tracking (open vs resolved)
- Severity levels prioritize what needs resolution
- Dataset filtering focuses attention on relevant questions

---

## Demo Script

A complete demonstration is available in `demo_open_questions.R`:

```bash
Rscript demo_open_questions.R
```

**Demo shows:**

1. Listing all questions
2. Filtering by status (open/resolved)
3. Filtering by dataset (ADLOT)
4. Checking resolution status
5. Adding a new question
6. Resolving a question
7. Validating REVISIT comments

---

## File Locations

| Component | Path |
|-----------|------|
| YAML schema | `projects/exelixis-sap/.claude/open-questions.yaml` |
| R functions | `projects/exelixis-sap/R/manage_questions.R` |
| Test suite | `projects/exelixis-sap/tests/test-manage_questions.R` |
| Demo script | `projects/exelixis-sap/demo_open_questions.R` |
| `/resolve-question` | `.claude/commands/resolve-question.md` |
| `/list-open-questions` | `.claude/commands/list-open-questions.md` |
| `/check-revisit-comments` | `.claude/commands/check-revisit-comments.md` |
| Documentation | `projects/exelixis-sap/docs/open-questions-system.md` (this file) |

---

## Next Steps

1. **Integrate into orchestrator:** Run `/list-open-questions status=blocking` before each wave
2. **Integrate into reviewer:** Run `/check-revisit-comments` as part of QC checklist
3. **Document in dev logs:** Reference question IDs when discussing decisions
4. **Train agents:** Update planner/programmer/reviewer agent instructions to use this system

---

## Success Metrics

✓ **Implementation Complete:**

- YAML format is human-readable and machine-parseable
- Bi-directional linking works (code ↔ question)
- Commands successfully manage question lifecycle
- Test suite passes (100% coverage)
- Demo validates end-to-end workflow

**Expected Impact:**

- Reduce "why did we do this?" questions during review
- Prevent silent errors from undocumented assumptions
- Improve regulatory audit trail
- Build institutional memory across studies

---

## Appendix: REVISIT Comment Patterns

**Good patterns:**

```r
# REVISIT: Quan 2011 weights used per R1
# REVISIT: Confirmed response (≥28-day interval) per R3
# REVISIT: Study-specific AVAL coding — see R8
# REVISIT: SAFFL definition pending resolution of W7
```

**Bad patterns (will be flagged):**

```r
# REVISIT: Check this later (no question ID)
# REVISIT: See X99 (invalid prefix)
# TODO: Revisit after SAP review (use REVISIT: not TODO:)
```

**Best practice:**

Always include the question ID at the end of the REVISIT comment. The `/check-revisit-comments` command uses regex pattern `[RWB]\d+` to extract IDs.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-27 | Initial implementation with NPM-008 examples |
