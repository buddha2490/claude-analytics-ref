# Git Conventions

These conventions apply to all commits, branches, and PRs — whether created by a human or an agent.

## Branch Naming

Use the format `<type>/<short-description>`:

| Type | Use for | Example |
|------|---------|---------|
| `sdtm/` | SDTM domain work (simulation, mapping) | `sdtm/dm`, `sdtm/ae-mapping` |
| `tfl/` | Table, figure, or listing programs | `tfl/14-1-1`, `tfl/demographics` |
| `sim/` | Simulation programs | `sim/ae`, `sim/lb` |
| `feat/` | New features or functions | `feat/create-tfl`, `feat/study-day-calc` |
| `fix/` | Bug fixes | `fix/date-format`, `fix/seq-uniqueness` |
| `refactor/` | Refactoring without behavior change | `refactor/tfl-pipeline` |

## Commit Messages

Format: `[DOMAIN] scope: description`

```
[SDTM] DM: add demographics simulation program
[TFL] 14.1.1: implement primary efficacy table
[FUNC] create_tfl: fix column header alignment
[TEST] sim_ae: add edge case for missing dates
[CONFIG] rules: add git conventions rule
[DOCS] README: add quickstart guide
```

- Use present tense ("add", "fix", "update" — not "added", "fixed", "updated")
- Keep the first line under 72 characters
- Add a blank line and detail paragraph for complex changes

## Pull Request Descriptions

Every PR must include:
- **Domains affected** (e.g., DM, AE, or "infrastructure")
- **What changed** (1-3 bullet summary)
- **Validation status** (tests pass, QC report reference if applicable)

## Files That Must Never Be Committed

- `.Renviron`, `.env`, `*.credentials` — secrets and tokens
- `data/*.xpt` containing real patient data — simulated data only in version control
- Large binary files (> 10MB)
- `.Rhistory`, `.RData` — session artifacts (already in .gitignore)

## Files That Must Always Be Committed

- `renv.lock` — package manifest for reproducibility
- `renv/activate.R` — renv bootstrap script
- All rule, skill, command, and agent definition files
