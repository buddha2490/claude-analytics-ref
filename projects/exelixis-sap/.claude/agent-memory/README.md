# NPM-008 Study Memory System

## Overview

This directory contains study-specific memories that help agents avoid repeating mistakes and apply proven approaches across implementation waves.

## Structure

```
projects/exelixis-sap/.claude/agent-memory/
├── MEMORY.md                           # Index file (always read first)
├── xpt_flag_encoding.md                # Feedback memory
├── lot_algorithm_complexity.md         # Project memory
└── npm008_biomarker_terminology.md     # Reference memory
```

## Memory Types

| Type | When to Save | Example |
|------|-------------|---------|
| **Feedback** | Error patterns, validated approaches | XPT flag encoding handling |
| **Project** | Complexity insights, study constraints | LoT algorithm requires 3 rules |
| **Reference** | Study-specific terminology, quirks | ALTERED vs NOT ALTERED |

## Workflow

### For Programmers (r-clinical-programmer)

**Before starting implementation:**

1. Read `MEMORY.md` to see available memories
2. Load memories relevant to your task:
   - Biomarkers? → Check reference memories
   - Complex algorithms? → Check project memories
   - Data encoding? → Check feedback memories
3. Apply guidance from "How to apply" sections
4. Note memory usage in dev log

**During implementation:**

- If you discover new patterns, note them for reviewer
- Do not create memories yourself (reviewer's job)

### For Reviewers (clinical-code-reviewer)

**After producing QC report:**

1. **Identify patterns worth saving:**
   - Found a recurring error?
   - Validated a complex approach?
   - Discovered study-specific quirks?

2. **Create memory file:**
   ```markdown
   ---
   name: memory_name
   description: One-line description
   type: feedback | project | reference
   ---
   
   [Rule/fact/finding]
   
   **Why:** [Reason this matters]
   
   **How to apply:** [Specific guidance]
   ```

3. **Update MEMORY.md:**
   ```markdown
   - [memory_name.md](memory_name.md) — Brief description
   ```

## Example Usage

**Scenario:** Implementing ADRS with biomarker response criteria

```
1. Programmer reads MEMORY.md
2. Finds: npm008_biomarker_terminology.md
3. Learns: Use ALTERED/NOT ALTERED (not POSITIVE/NEGATIVE)
4. Implements with correct terminology
5. Notes in dev log: "Applied npm008_biomarker_terminology.md"
6. Reviewer validates approach matches memory
```

## Benefits

- **Prevents error recurrence:** Same mistake won't happen in Wave 2, 3, 4
- **Captures complexity insights:** LoT algorithm learnings apply to future LoT work
- **Preserves study-specific knowledge:** ALTERED terminology applies to all biomarker derivations
- **Reduces iteration cycles:** Programmer knows correct approach before coding

## Current Memories (as of 2026-03-28)

### Feedback
- **xpt_flag_encoding**: Haven converts NA_character_ to empty string (correct)

### Project
- **lot_algorithm_complexity**: LoT requires 3 termination rules, iterative approach

### Reference
- **npm008_biomarker_terminology**: ALTERED/NOT ALTERED pattern, check order matters
