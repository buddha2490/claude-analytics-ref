# ADS QA Review Standards

These standards apply to all code reviews performed against the `analytical-datasets` repository. They define what constitutes a complete, useful QA review — not how to run one (that is the `ads-qa-reviewer` agent's job).

## What ADS QA Reviews Are For

ADS QA reviews assess whether a branch correctly implements its stated ticket. They are a **structured aid for the human reviewer** — not a substitute for it. The AI review surfaces areas of concern, identifies potential defects, and provides suggested corrections. The human reviewer must validate every finding and make the final approval determination.

> **Important:** An AI-generated QA report is a starting point, not a verdict. The reviewer is accountable for the approval decision. Claude can miss context, misread intent, or fail to catch subtle logical errors that require domain expertise to recognize.

## Scope

Review only code that changed in the branch (`git diff origin/master...HEAD`). Do not audit the entire codebase. However, when understanding the impact of a change, it is necessary to look at how the changed code is used elsewhere — that context work is in-scope.

## Severity Taxonomy

Every finding must be tagged with one of these levels:

| Level | Meaning | Action |
|-------|---------|--------|
| **BLOCKING** | Defect, logical error, or missing requirement that would corrupt data, produce wrong results, or fail a stated acceptance criterion | Must be fixed before merge |
| **WARNING** | Pattern that is problematic but not demonstrably wrong — risky handling of edge cases, poor readability, missing documentation, convention violations | Should be addressed; reviewer uses judgment |
| **NOTE** | Stylistic improvement, minor inconsistency, or enhancement suggestion | Informational; no action required |
| **STRENGTH** | Something the implementation does particularly well | Included to give balanced feedback |

A review with zero BLOCKING items and manageable WARNINGs should pass. A review with any BLOCKING items should not merge until resolved.

## Review Categories

### 1. Ticket Fidelity (highest priority)

- Does the code implement what the ticket description asks for?
- If acceptance criteria are stated, is each one verifiable in the code?
- Is there scope creep — code that does more than the ticket requested?
- Is there scope gap — something the ticket required that the code doesn't address?

### 2. ADS Data Patterns

These are the most common sources of bugs in ADS development:

- **Deduplication before JSON parsing**: The ADS is long-form. Any `parse_json_col()` call or `jsonlite::fromJSON()` invocation must be preceded by `distinct(patientid, .keep_all = TRUE)` or equivalent. Failure to deduplicate causes explosive row duplication.
- **Patient identifier**: Must use `patientid` (UUID). Never `USUBJID`, `participantid`, or other surrogates.
- **Patient counts**: Must use `n_distinct(patientid)` or `distinct(patientid) %>% nrow()`. Never `nrow()` alone on non-deduplicated data.
- **`enriched_cohort_flag` handling**: If the analysis is restricted to enriched patients, the filter must use `enriched_cohort_flag == TRUE`. Understand whether the ticket requires enriched-only or all patients.
- **Date granularity**: Date columns have corresponding `*_granularity` fields (NONE / YEAR / MONTH / DAY). Code that filters or compares dates without checking granularity may silently include or exclude patients with partial dates.
- **`get_ads()` parameters**: Verify `cohort` and `type` match the ticket's stated population. Using `"essentials"` when the ticket requires manually abstracted fields is a data integrity error.
- **Lazy evaluation**: `collect()` must be called before any local R operations. Filtering should happen server-side before `collect()` when only a subset is needed.
- **`dbplyr` local vector quoting**: When passing a local R vector into a `dbplyr`/`tbl()` filter, force it with `!!` (bang-bang). Without `!!`, `dbplyr` may silently interpret the name as a column reference rather than a local value vector, causing the filter to match nothing or error. Example: `filter(x %in% !!local_vec)` is correct; `filter(x %in% local_vec)` is not. This is easy to miss because one side of an `|` condition may already use `!!` correctly while the other does not.

### 3. Code Correctness

- Logical errors in derivation formulas
- NA and NULL handling — what happens when expected fields are missing?
- Off-by-one errors in date calculations or sequence numbers
- Incorrect join keys — verify joins are on the intended keys and that the join type (left, inner, anti) matches the intended behavior
- Filter conditions that are too broad or too narrow relative to the ticket intent

### 4. Cross-Codebase Impact

- Does the changed function have callers elsewhere in the codebase? Query the RAG to check.
- If a variable is added, is it added consistently across all tumor-specific files that should have it?
- If a variable is renamed or removed, are all references updated?
- Are `NEWS.md` entries present for substantive changes?
- Are new variables added to the appropriate whitelists?
- If a utility function is changed, do downstream uses still work correctly?

### 5. R Style and Conventions

Per `r-style.md`:
- `snake_case` for all variable and function names
- `%>%` pipe preferred; one operation per line
- Section headers use `# --- Section Name ---` format
- Comments explain *why*, not just *what*
- No use of `require()` — must use `library()`
- No hardcoded credentials or file paths (per `data-safety.md`)

### 6. Documentation and Maintenance

- Does `NEWS.md` have an entry describing the change?
- Are whitelist files updated for new variables?
- Are comments adequate for non-obvious logic?

## Code Suggestion Format

When a finding requires a code change, provide a **replacement code block** alongside the finding. Format as:

```
**Suggested fix** — `path/to/file.R`, lines [start]–[end]:

```r
# [replacement code here]
```
```

Always include:
- The exact file path
- The line range being replaced (from the diff)
- Complete, runnable replacement code — not pseudocode
- A brief comment explaining what changed and why

The reviewer should be able to copy the replacement block directly into the file.

## Output Document Requirements

Every QA review document must include:

1. **Header block**: Branch name, ticket number, date reviewed, reviewer name, model version used
2. **Ticket Overview**: Synthesized from the Jira ticket — what problem is being solved, stated acceptance criteria
3. **Process Quality Assessment**: A brief meta-section immediately after the ticket overview — RAG coverage, files read in full, overall confidence level, what the AI could not assess, and specific items the human reviewer should manually verify
4. **Changed Files Summary**: Table of all files changed with a one-line description of each change
5. **Changed Code**: The formatted diff organized by file, with inline annotations where relevant
6. **Code Review Findings**: Organized by severity (BLOCKING → WARNING → NOTE), each with file path, line numbers, description, and suggested fix where applicable. RAG-grounded claims must cite their source inline.
7. **Strengths**: What the implementation does well
8. **Weaknesses and Concerns**: Patterns that are problematic without necessarily being blocking
9. **Required Changes Summary**: A clean numbered list of everything tagged BLOCKING — the minimum that must be fixed before merge
10. **Reviewer Notes**: Placeholder for human sign-off (left blank by the AI reviewer)
11. **RAG Reference Log**: Compact table of every RAG/MCP query run during the review — query text, tool used, source filter, and one-line result summary. Empty results must be noted; they indicate RAG index gaps.

## What This Review Does Not Cover

- Full regression testing of the entire ADS pipeline — that requires a live Databricks environment
- Statistical validation of derived variables — clinical domain expertise required
- Performance benchmarking — out of scope for a code review
- Approval authority — the human reviewer holds approval; the AI report is advisory only
