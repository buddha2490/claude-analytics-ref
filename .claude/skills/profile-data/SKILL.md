# Data Profiling Skill

Auto-generates frequency tables and cross-tabulations for SDTM domain variables to prevent terminology mismatches and provide concrete data value examples during ADaM derivation.

## Command

```bash
/profile-data domain=<DOMAIN> [variables=<var1,var2,...>] [data_path=<path>] [output_path=<path>] [top_n=<N>]
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `domain` | Yes | - | SDTM domain code (e.g., `LB`, `MH`, `AE`) |
| `variables` | No | Auto-detect | Comma-separated list of variables to profile. If omitted, profiles all categorical variables. |
| `data_path` | No | Auto-detect from context | Path to directory containing SDTM XPT files |
| `output_path` | No | `projects/<study>/data-profiles/` | Path to directory for markdown output |
| `top_n` | No | 50 | Maximum unique values to display per variable |

## Usage Examples

```bash
# Profile specific biomarker variables
/profile-data domain=LB variables=LBTESTCD,LBSTRESC

# Profile all categorical variables in medical history
/profile-data domain=MH

# Profile with custom output location
/profile-data domain=AE output_path=projects/exelixis-sap/data-profiles

# Limit high-cardinality output
/profile-data domain=CM variables=CMTRT top_n=20
```

## Process

1. **Parameter resolution:**
   - If `data_path` not specified, infer from current working directory context (e.g., if in `projects/exelixis-sap/`, use `projects/exelixis-sap/data/`)
   - If `output_path` not specified, use `projects/<study-name>/data-profiles/` based on current context
   - If `variables` not specified, auto-detect categorical variables (character/factor + numeric with ≤20 unique values)

2. **Call R function:**
   ```r
   source("R/profile_data.R")

   result <- profile_data(
     domain = "<DOMAIN>",
     variables = c("<var1>", "<var2>", ...),  # or NULL for auto-detect
     data_path = "<resolved_path>",
     output_path = "<resolved_path>",
     top_n = <N>
   )
   ```

3. **Generate markdown output:**
   - Frequency tables for each variable (count, percent)
   - Cross-tabulations for related variables (e.g., `LBTESTCD × LBSTRESC`)
   - High-cardinality warnings
   - Top N values per variable

4. **Display summary:**
   - Domain and record/subject counts
   - Variables profiled
   - Output file location
   - Key warnings (unexpected patterns, high cardinality)

## Output Format

The generated markdown file (`<domain>.md`) contains:

```markdown
# Data Profile: LB (Laboratory)
**Generated:** 2026-03-27
**Records:** 450
**Subjects:** 40

---

## LBTESTCD (Test Code)
**Unique values:** 10

| Value | Count | Percent |
|-------|-------|---------|
| EGFR  | 40    | 8.9%    |
| KRAS  | 40    | 8.9%    |
| ALK   | 40    | 8.9%    |
| ...   | ...   | ...     |

---

## LBSTRESC (Result String)
**Unique values:** 8

| Value       | Count | Percent |
|-------------|-------|---------|
| ALTERED     | 45    | 10.0%   |
| NOT ALTERED | 320   | 71.1%   |
| DETECTED    | 30    | 6.7%    |
| NOT DETECTED| 50    | 11.1%   |
| ...         | ...   | ...     |

---

# Cross-Tabulations

## LBTESTCD × LBSTRESC

| LBTESTCD | LBSTRESC    | Count |
|----------|-------------|-------|
| EGFR     | ALTERED     | 12    |
| EGFR     | NOT ALTERED | 25    |
| EGFR     | NOT TESTED  | 3     |
| KRAS     | DETECTED    | 5     |
| KRAS     | NOT DETECTED| 35    |
| ...      | ...         | ...   |

---
```

## Integration with Workflow

### When to Use

1. **After data contract validation** (Enhancement 1) confirms XPT files exist
2. **Before programmer agents start implementation** — profiling provides concrete examples
3. **During Step 4.5 (Explore Source Data)** of the r-code skill
4. **When terminology questions arise** — check actual values vs. plan expectations

### Orchestrator Integration

The orchestrator should run `/profile-data` for all source domains listed in the plan **before** spawning programmer agents:

```markdown
## Step 3.5: Profile Source Data

For each domain in plan's source data section:
  1. Run `/profile-data domain=<DOMAIN>`
  2. Store output in `projects/<study>/data-profiles/<domain>.md`
  3. Check for warnings (high cardinality, unexpected patterns)
  4. If critical issues found, report to user before proceeding

Profiling outputs are available to programmer agents as reference during derivation.
```

### Programmer Agent Usage

When implementing derivations, agents should:

1. Reference profiles to see **actual data values** (not just plan specifications)
2. Check cross-tabulations to understand **variable relationships**
3. Identify **terminology patterns** (e.g., "ALTERED" vs "POSITIVE" for biomarker results)
4. Detect **high-cardinality variables** that need careful handling

## Key Benefits

1. **Prevents terminology mismatches:**
   - Plan says biomarker results are "POSITIVE"/"NEGATIVE"
   - Profile shows actual data uses "ALTERED"/"NOT ALTERED"
   - → Agent uses correct pattern matching logic

2. **Identifies data structure issues:**
   - Plan lists MHDTC
   - Profile generated from MH.xpt shows MHSTDTC instead
   - → Caught before code execution begins

3. **Provides concrete examples:**
   - Instead of guessing valid QSCAT values, agent sees actual frequency table
   - Reduces assumptions and trial-and-error

4. **Catches silent errors:**
   - Cross-tabs reveal unexpected combinations (e.g., QSCAT="SCREENING" with post-baseline dates)
   - Flags for investigation before derivation

## Storage and Lifecycle

- **Location:** `projects/<study-name>/data-profiles/<domain>.md`
- **Format:** Markdown only (NOT added to RAG server)
- **Generation:** Once per domain, before Wave 1 implementation
- **Regeneration:** Only if source data changes
- **Persistence:** Committed to version control for audit trail

## Success Criteria

- Generates accurate frequency tables for all categorical variables
- Creates cross-tabulations for related variables (TESTCD × STRESC, CAT × TERM)
- Flags high-cardinality variables with warnings
- Markdown output is human-readable and agent-parseable
- Identifies terminology discrepancies (e.g., ALTERED vs POSITIVE)
- Output location follows project conventions
- Function executes cleanly with test data

## Dependencies

- R function: `R/profile_data.R`
- Test suite: `tests/test-profile_data.R`
- Required packages: tidyverse, haven

## Implementation Notes

- Auto-detection considers character, factor, and low-cardinality numeric variables (≤20 unique values)
- Cross-tabulation pairs identified by common SDTM patterns:
  - `*TESTCD` × `*STRESC` (test code × result)
  - `*TESTCD` × `*ORRES` (test code × original result)
  - `*CAT` × `*TERM` (category × term)
  - `*TRT` × `*DOSE` (treatment × dose)
- Top N limiting prevents overwhelming output for high-cardinality variables
- All categorical variables profiled unless user specifies subset
