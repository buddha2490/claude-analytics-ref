# Data Profiling Skill

Auto-generates frequency tables for categorical variables in SDTM domains to prevent terminology mismatches and provide concrete examples of actual data values.

## Trigger

Use this skill when the user asks to:
- Profile a domain
- Generate frequency tables
- Explore actual data values
- Check terminology in SDTM data

## Usage

```bash
/profile-data domain=LB variables=LBTESTCD,LBSTRESC
/profile-data domain=MH variables=MHCAT,MHTERM --top-n=20
/profile-data domain=QS  # profiles all character variables
```

## Parameters

- `domain` (required): SDTM domain to profile (e.g., DM, LB, MH, QS)
- `variables` (optional): Comma-separated list of variables to profile. If omitted, profiles all character variables.
- `--top-n` (optional): Maximum unique values to show per variable (default: 50)
- `--data-path` (optional): Path to SDTM XPT files (default: `output-data/sdtm/`)

## Process

When invoked, this skill:

1. **Validates inputs**
   - Checks domain XPT file exists at data path
   - Verifies requested variables exist in domain
   - If no variables specified, auto-detects character columns

2. **Generates frequency tables**
   - For each variable, counts unique values with frequencies and percentages
   - For high-cardinality variables (>100 unique), shows top N only
   - For variables with <20 unique values, shows full distribution
   - Flags unusual patterns (empty strings, NAs, whitespace)

3. **Writes markdown output**
   - Saves to `projects/<study-name>/data-profiles/<domain>.md`
   - Includes metadata: generation date, record count, subject count
   - Formats tables for readability by both humans and agents
   - Adds alerts for terminology that may cause derivation errors

4. **Returns summary**
   - Reports file location
   - Flags key findings (e.g., "LB uses ALTERED not POSITIVE")
   - Recommends which profiles to review before derivations

## Output Format

```markdown
# Data Profile: LB (Laboratory Test Results)

**Generated:** 2026-03-28
**Source:** output-data/sdtm/lb.xpt
**Records:** 450
**Subjects:** 40

---

## LBTESTCD (Laboratory Test Code)

**Type:** Character
**Unique values:** 15

| Value | Count | Percent |
|-------|-------|---------|
| EGFR  | 40    | 8.9%    |
| KRAS  | 40    | 8.9%    |
| ALK   | 40    | 8.9%    |
| ROS1  | 40    | 8.9%    |
| PDL1  | 40    | 8.9%    |
| ... (showing top 10 of 15) |

---

## LBSTRESC (Result in Standard Format)

**Type:** Character
**Unique values:** 5

### For LBTESTCD = EGFR

| Value       | Count | Percent | Notes |
|-------------|-------|---------|-------|
| ALTERED     | 12    | 30.0%   | ⚠️ Not "POSITIVE" |
| NOT ALTERED | 25    | 62.5%   | ⚠️ Not "NEGATIVE" |
| NOT TESTED  | 3     | 7.5%    |       |

⚠️ **Terminology Alert:** Values use "ALTERED"/"NOT ALTERED", not CDISC standard "POSITIVE"/"NEGATIVE". Verify pattern matching logic in biomarker derivations.

### For LBTESTCD = KRAS

| Value       | Count | Percent |
|-------------|-------|---------|
| ALTERED     | 6     | 15.0%   |
| NOT ALTERED | 34    | 85.0%   |

---

## Key Findings

1. **Biomarker terminology:** All mutation tests use ALTERED/NOT ALTERED pattern
2. **Completeness:** 0 missing LBSTRESC values (all tests have results)
3. **High-cardinality variables:** None (all < 50 unique values)
```

## Implementation

The skill uses `projects/exelixis-sap/R/profile_data.R` for the R implementation. The function signature:

```r
profile_data <- function(domain,
                        variables = NULL,
                        data_path = "output-data/sdtm",
                        top_n = 50,
                        output_path = "data-profiles") {
  # Read XPT
  # Generate frequency tables
  # Write markdown output
  # Return summary with key findings
}
```

## Storage and Lifecycle

- Profiles saved to `projects/<study-name>/data-profiles/<domain>.md`
- Generated during Step 4.5 (after data exploration, before derivations)
- Used during Step 5 (implementation) for actual value reference
- **NOT added to RAG** — kept as markdown reference only
- Regenerated only if source data changes
- Persisted for audit trail

## Integration with ADaM Workflow

**Orchestrator usage:**
1. After loading plan, identify all source domains
2. Run `/profile-data` for each domain with variables listed in plan
3. Save profiles to `projects/exelixis-sap/data-profiles/`
4. Pass profile locations to programmer agents as context
5. Agents reference profiles during implementation to verify actual values

**Benefits:**
- Prevents terminology mismatches (ALTERED vs POSITIVE)
- Provides concrete examples before coding begins
- Catches empty strings, unexpected NAs, whitespace issues
- Documents actual data state for audit trail

## Example Session

```bash
# Profile LB domain before biomarker derivations
/profile-data domain=LB variables=LBTESTCD,LBSTRESC,LBTEST

Output:
✓ Profile generated: projects/exelixis-sap/data-profiles/lb.md
⚠️ Key finding: LBSTRESC uses "ALTERED" not "POSITIVE" for mutations
  Recommendation: Update pattern matching in biomarker flags

# Profile MH domain before comorbidity derivations
/profile-data domain=MH variables=MHCAT,MHTERM,MHBODSYS --top-n=30

Output:
✓ Profile generated: projects/exelixis-sap/data-profiles/mh.md
✓ MHTERM has 47 unique conditions (showing top 30)
✓ All MHBODSYS values map to standard organ systems
```

## Notes

- For numeric variables, the skill generates summary statistics (mean, median, range, NAs) instead of frequency tables
- Cross-tabulations (e.g., LBSTRESC by LBTESTCD) are automatically generated for variables with clear grouping relationships
- Profile generation takes ~1-3 seconds per domain
- Profiles are human-readable markdown, not structured data (no JSON/YAML)
