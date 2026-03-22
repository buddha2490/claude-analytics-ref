# Clinical Programming with Claude Code

A reference implementation showing how to configure Claude Code for automated clinical programming workflows in R. This repo demonstrates the full configuration system — rules, skills, commands, and agents — applied to pharmaceutical/regulatory data work.

## Prerequisites

- **R 4.5+** with renv installed (`install.packages("renv")`)
- **Claude Code** installed and authenticated ([docs](https://docs.anthropic.com/en/docs/claude-code))
- **VS Code** (recommended) — the project auto-launches Claude Code when opened

## Quickstart

1. **Clone and open:**
   ```bash
   git clone <repo-url>
   cd claude-skills
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
   This walks you through everything — what commands are available, how the agents work, and what the rules enforce. Start here if you're new to Claude Code.

## Project Structure

```
.claude/
  rules/         Always-on project standards (8 files)
  skills/        Auto-invoked workflows (r-code)
  commands/      On-demand actions (/onboard, /ct-lookup, /r-project)
  agents/        Specialized AI roles (planner, programmer, reviewer)
R/               Reusable functions (one per file, with roxygen2 docs)
tests/           testthat test files (one per function)
programs/        Analysis scripts, simulations, data pulls, SDTM mappings
data/            SDTM/ADaM XPT datasets
output/          RTF tables, figures, listings
plans/           Implementation plans from the feature-planner
docs/            Strategy docs and specifications
```

## Available Commands

| Command | What it does |
|---------|-------------|
| `/onboard` | Interactive walkthrough for new team members |
| `/ct-lookup` | Look up CDISC controlled terminology (e.g., `/ct-lookup VSTESTCD`) |
| `/r-project` | Scaffold a new R project with renv and standard structure |

## Agents

The project uses three agents in a pipeline that mirrors clinical programming QC:

```
feature-planner  →  r-clinical-programmer  →  code-reviewer
   (plan)              (implement)              (verify)
```

| Agent | Model | Role |
|-------|-------|------|
| **feature-planner** | Opus | Reviews codebase, asks clarifying questions, writes implementation plans |
| **r-clinical-programmer** | Sonnet | Writes R code, always executes before returning, follows plans |
| **code-reviewer** | Sonnet | Independent QC — checks rules, runs tests, produces PASS/FAIL report |

**For complex work, always start with the planner.** Don't jump straight to code.

## Rules

Rules are enforced automatically in every conversation. You don't need to memorize them — Claude knows them — but here's what's covered:

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

## How It Works

Every conversation with Claude loads:

1. **CLAUDE.md** — project orientation
2. **All rules** — what standards apply
3. **Relevant skill** — how to produce the output (e.g., the r-code skill auto-fires for R work)
4. **Agent if spawned** — which role handles the work

When you ask Claude to write a function:
- Rules enforce style, packages, CDISC conventions
- The r-code skill enforces the workflow: write function → write tests → execute both → report
- No code is returned until it runs without errors

## The Pipeline

This project is building toward a 3-stage automated clinical programming pipeline:

```
Stage 1: Simulated Data    Stage 2: Data Pull      Stage 3: Full Automation
─────────────────────      ──────────────────      ────────────────────────
Generate CDISC-compliant   Pull raw variables      Generate R code that
dummy datasets from        from Databricks into    transforms raw data into
specs and data dictionary  intermediate datasets   final CDISC SDTM domains
```

All stages share the same downstream TFL code — switching from simulated to real data changes only the data source, not the analysis programs.

## Contributing

- Follow the git conventions in `.claude/rules/git-conventions.md`
- Use the feature-planner for anything beyond a simple bug fix
- Run the code-reviewer before submitting a PR
- All R code must be executed and tested before delivery
