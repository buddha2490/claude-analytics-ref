# Clinical Programming with Claude Code

A reference implementation showing how to configure Claude Code for automated clinical programming workflows in R. Demonstrates the full configuration system — rules, skills, commands, and agents — applied to pharmaceutical/regulatory data work.

## Prerequisites

- **R 4.5+** with renv installed (`install.packages("renv")`)
- **Claude Code** installed and authenticated ([docs](https://docs.anthropic.com/en/docs/claude-code))
- **VS Code** (recommended) — the project auto-launches Claude Code when opened

## Quickstart

1. **Clone and open:**
   ```bash
   git clone <repo-url>
   cd claude-analytics-ref
   code .    # VS Code auto-launches Claude Code
   ```

2. **Restore R packages:**
   ```r
   renv::restore()
   ```

3. **Run the onboarding walkthrough:**
   ```
   /onboard
   ```

## Project Structure

```
.claude/
  rules/         Always-on project standards (9 files)
  skills/        Auto-invoked workflows (r-code, databricks, ads-data, cohort-cascade)
  commands/      On-demand actions (/onboard, /ct-lookup, /r-project, /ads-qa-review)
  agents/        Specialized AI roles (planner, programmer, reviewer, ADS QA reviewer)
R/               Reusable functions (one per file, with roxygen2 docs)
tests/           testthat test files (one per function)
programs/        Analysis scripts, simulations, data pulls, SDTM mappings
data/            SDTM/ADaM XPT datasets
output/          RTF tables, figures, listings
plans/           Implementation plans from the feature-planner
docs/            Strategy docs and specifications
```

## Commands

| Command | What it does |
|---------|-------------|
| `/onboard` | Interactive walkthrough for new team members |
| `/ct-lookup` | Look up CDISC controlled terminology (e.g., `/ct-lookup VSTESTCD`) |
| `/r-project` | Scaffold a new R project with renv and standard structure |
| `/ads-qa-review` | Run AI-assisted QA review on a cloned ADS branch |

## Agents

The project has two agent pipelines: one for clinical R programming and one for ADS branch QA.

**Clinical programming pipeline:**
```
feature-planner  →  r-clinical-programmer  →  clinical-code-reviewer
   (plan)              (implement)              (verify)
```

**ADS QA pipeline:**
```
/ads-qa-review  →  ads-qa-reviewer
  (command)         (review report)
```

| Agent | Model | Role |
|-------|-------|------|
| **feature-planner** | Opus | Reviews codebase, asks clarifying questions, writes implementation plans |
| **r-clinical-programmer** | Sonnet | Writes R code, always executes before returning, follows plans |
| **clinical-code-reviewer** | Sonnet | Independent QC for CDISC-regulated R code — checks rules, runs tests, produces PASS/FAIL report |
| **ads-qa-reviewer** | Opus | Reviews ADS branches against Jira tickets — reads diffs, queries RAG, validates variable specs |

## Skills

Skills auto-invoke when the task type matches — no explicit command needed.

| Skill | When it fires |
|-------|--------------|
| `r-code` | Any R code request — enforces the write → test → execute → validate workflow |
| `databricks` | Databricks connections, queries, schema navigation |
| `ads-data` | Pulling or subsetting ADS data via `get_ads()` |
| `cohort-cascade` | Building exclusion criteria or patient attrition tables |

## Rules

Enforced automatically in every conversation.

| Rule | What it enforces |
|------|-----------------|
| `r-style` | Tidyverse style, snake_case, `%>%` pipe, section headers |
| `approved-packages` | Only use listed packages; ask before adding new ones |
| `namespace-conflicts` | huxtable/pharmaRTF and dplyr/stats need explicit `package::` |
| `cdisc-conventions` | ISO 8601 dates, USUBJID format, study days, DM-first ordering |
| `file-layout` | Directory structure and file naming patterns |
| `data-safety` | No real patient data in code, no hardcoded credentials |
| `git-conventions` | Branch naming, commit messages, PR descriptions |
| `error-messages` | Standard patterns for `stop()`, `warning()`, `message()` |
| `ads-qa-review-standards` | Severity taxonomy, ADS-specific defect patterns, report format for ADS QA reviews |

## Contributing

- Follow the git conventions in `.claude/rules/git-conventions.md`
- Use the feature-planner for anything beyond a simple bug fix
- Run the clinical-code-reviewer before submitting a PR
- All R code must be executed and tested before delivery
