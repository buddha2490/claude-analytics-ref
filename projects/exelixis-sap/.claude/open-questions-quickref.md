# Open Questions System - Quick Reference

**One-page guide for the formalized open questions tracking system**

---

## Question ID Conventions

| Prefix | Meaning | Example |
|--------|---------|---------|
| **R1-R99** | Resolved decisions | R1, R5, R8 |
| **W1-W99** | Warning-level open questions | W4, W5 |
| **B1-B99** | Blocking open questions | B1, B2 |

---

## Commands

### List Questions

```bash
/list-open-questions                    # All questions
/list-open-questions status=open        # Open only
/list-open-questions dataset=ADLOT      # For specific dataset
/list-open-questions severity=blocking  # Blocking only
```

### Resolve a Question

```bash
/resolve-question W4 resolution="Use raw CMRSDISC values"
```

### Validate Code Linkage

```bash
/check-revisit-comments programs/
```

---

## R Functions

```r
# Load functions
source("R/manage_questions.R")

# Add new question
add_question(yaml_path, id = "W7", text = "...", rationale = "...",
             severity = "warning", flagged_by = "user")

# Resolve question
resolve_question(yaml_path, id = "W7", resolution = "...")

# List questions
questions <- list_questions(yaml_path, status_filter = "open")

# Check REVISIT comments
results <- check_revisit_comments("programs/", yaml_path)

# Check if resolved
is_question_resolved(yaml_path, "R1")  # Returns TRUE/FALSE
```

---

## REVISIT Comment Pattern

**Correct:**

```r
# REVISIT: Quan 2011 weights used per R1
# REVISIT: Confirmed response (≥28-day interval) per R3
# REVISIT: Study-specific AVAL coding — see R8
```

**Incorrect (will be flagged):**

```r
# REVISIT: Check this later (no ID)
# TODO: Revisit after SAP review (use REVISIT: not TODO:)
# REVISIT: See X99 (invalid prefix - must be R/W/B)
```

---

## Workflow

### For Planners

1. Create `open-questions.yaml` during plan generation
2. Assign IDs: R (resolved), W (warning), B (blocking)
3. Document rationale and affected code locations

### For Programmers

1. Check open questions: `/list-open-questions dataset=<name>`
2. Add REVISIT comments with IDs in code
3. Implement resolved decisions

### For Reviewers

1. Run `/check-revisit-comments programs/`
2. Verify all IDs are resolved
3. Flag orphaned comments as QC findings

---

## Validation Checks

`/check-revisit-comments` produces:

| Symbol | Meaning | Action |
|--------|---------|--------|
| ✓ | REVISIT has valid resolved question ID | None |
| ⚠ | REVISIT has no question ID | Add question to YAML or remove comment |
| ⚠ | Question ID exists but still open | Resolve question before final QC |
| ✗ | Question ID not found in YAML | Fix ID or add question |

---

## NPM-008 Examples

**Resolved (R1-R8):**

- R1: CCI weights → Quan 2011
- R3: RECIST BOR → Confirmed (≥28 days)
- R5: NPM LoT → 45-day window, 120-day gap
- R7: Flags → Y/blank (ADaM standard)

**Open (W4-W6):**

- W4: LOTENDRSN CT values
- W5: Neoadjuvant/adjuvant definition
- W6: ADBS structure

---

## File Locations

- **YAML:** `.claude/open-questions.yaml`
- **Functions:** `R/manage_questions.R`
- **Tests:** `tests/test-manage_questions.R`
- **Demo:** `demo_open_questions.R`
- **Docs:** `docs/open-questions-system.md`

---

## Common Tasks

**Before starting a new dataset:**

```bash
/list-open-questions dataset=ADSL status=open
```

**After resolving a question:**

```bash
/resolve-question W4 resolution="..."
```

**Before final QC sign-off:**

```bash
/check-revisit-comments programs/
```

**Generate stakeholder report:**

```r
resolved <- list_questions(yaml_path, status_filter = "resolved")
print_questions(resolved)
```

---

## Help

Full documentation: `docs/open-questions-system.md`

Run demo: `Rscript demo_open_questions.R`

Run tests: `Rscript tests/test-manage_questions.R`
