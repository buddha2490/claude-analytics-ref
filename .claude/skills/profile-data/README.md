# Data Profiling Skill

## Quick Start

```bash
# Profile specific variables in a domain
/profile-data domain=LB variables=LBTESTCD,LBSTRESC

# Auto-detect and profile all categorical variables
/profile-data domain=MH

# Custom paths
/profile-data domain=AE data_path=projects/exelixis-sap/data output_path=projects/exelixis-sap/data-profiles
```

## What It Does

Generates frequency tables and cross-tabulations for SDTM domain variables to:

1. **Prevent terminology mismatches** - See actual data values (e.g., "ALTERED" vs "POSITIVE")
2. **Identify data structure issues** - Confirm variables exist and have expected types
3. **Provide concrete examples** - Replace assumptions with actual value distributions
4. **Catch silent errors** - Cross-tabs reveal unexpected variable combinations

## Example Output

```markdown
# Data Profile: LB
**Generated:** 2026-03-28
**Records:** 400
**Subjects:** 40

## LBSTRESC (Result String)

| Value       | Count | Percent |
|-------------|-------|---------|
| ALTERED     | 15    | 3.8%    |
| NOT ALTERED | 62    | 15.5%   |
| DETECTED    | 14    | 3.5%    |
| NOT DETECTED| 146   | 36.5%   |
| POSITIVE    | 5     | 1.2%    |
| NEGATIVE    | 42    | 10.5%   |

## Cross-Tabulations: LBTESTCD × LBSTRESC

| LBTESTCD | LBSTRESC    | Count |
|----------|-------------|-------|
| EGFR     | ALTERED     | 12    |
| EGFR     | NOT ALTERED | 25    |
| KRAS     | DETECTED    | 8     |
| KRAS     | NOT DETECTED| 32    |
| ALK      | POSITIVE    | 5     |
| ALK      | NEGATIVE    | 35    |
```

## Key Finding

The profile shows biomarkers use **mixed terminology**:
- EGFR/BRAF: "ALTERED" / "NOT ALTERED"
- KRAS/ROS1: "DETECTED" / "NOT DETECTED"
- ALK: "POSITIVE" / "NEGATIVE"

This prevents blindly assuming all biomarkers use "POSITIVE"/"NEGATIVE"!

## Integration

**Orchestrator:** Run `/profile-data` for all source domains before spawning programmer agents.

**Programmer agents:** Reference profiles in `projects/<study>/data-profiles/<domain>.md` during derivation to see actual data values.

## Files

- **Skill definition:** `.claude/skills/profile-data/SKILL.md`
- **R function:** `R/profile_data.R`
- **Tests:** `tests/test-profile_data.R`
- **Demo script:** `test-profile-skill.R`

## Testing

```bash
# Run unit tests
Rscript -e "source('R/profile_data.R'); testthat::test_file('tests/test-profile_data.R')"

# Run demo with NPM-008 data
Rscript test-profile-skill.R
```

## Success Criteria

✅ Generates accurate frequency tables for categorical variables
✅ Creates cross-tabulations for related variables (TESTCD × STRESC, CAT × TERM)
✅ Flags high-cardinality variables with warnings
✅ Markdown output is human-readable and agent-parseable
✅ Identifies terminology discrepancies
✅ All tests pass (28/28)
