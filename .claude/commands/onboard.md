---
description: Interactive onboarding walkthrough for new team members
---

# Team Onboarding

You are onboarding a new team member who has never used Claude Code before. Walk them through this project step by step. Be friendly, concrete, and patient. Use examples they can try immediately.

## Step 1: Orient them

Start by explaining what they're looking at:

> Welcome! This project uses **Claude Code** to automate clinical programming workflows. Claude Code is an AI assistant that lives in your terminal (or VS Code) and can read files, write code, run programs, and follow project-specific rules.
>
> This project is set up so that Claude already knows your team's coding standards, CDISC conventions, and the clinical programming pipeline. You don't need to explain these things — they're built into the configuration.

Then show them the project structure by listing the key directories:

```
.claude/
  rules/       ← Standards that apply to ALL work (style, packages, CDISC, safety)
  skills/      ← Automated workflows (how R code gets generated and tested)
  commands/    ← On-demand actions you invoke with /command-name
  agents/      ← Specialized AI roles (planner, programmer, reviewer)
R/             ← Reusable function files
tests/         ← testthat test files
programs/      ← Analysis scripts, simulations, data pulls, mappings
data/          ← SDTM/ADaM XPT datasets
output/        ← RTF tables, figures, listings
plans/         ← Implementation plans from the feature-planner agent
docs/          ← Documentation and strategy docs
```

## Step 2: Show them what they can do right now

Walk them through these examples one at a time. After each example, pause and ask if they want to try it or move on.

### Try 1: Ask Claude a question
> Type a question about the project and Claude will answer using its knowledge of the codebase. Try:
> - "What packages are approved for this project?"
> - "How should I name my branch for a new SDTM domain?"
> - "What's the rule for handling namespace conflicts?"

Explain that Claude answers these by reading the rules in `.claude/rules/`.

### Try 2: Look up CDISC controlled terminology
> Use the `/ct-lookup` command to query CDISC standards. Try:
> - `/ct-lookup VSTESTCD`
> - `/ct-lookup LBTESTCD`
> - `/ct-lookup C66741`

Explain this queries the CDISC RAG (Retrieval-Augmented Generation) server, which contains the full SDTM Implementation Guide.

### Try 3: Ask Claude to write a function
> Ask Claude to write an R function. For example:
> - "Write a function that calculates study days from a reference date and an event date"
> - "Write a function that formats p-values for a TFL"

Explain what happens behind the scenes:
1. The `r-code` skill auto-activates
2. Claude writes the function file in `R/` with roxygen2 documentation
3. Claude writes a test file in `tests/` with testthat
4. Claude **runs both files** to confirm they work
5. Claude reports the results

This is the 3-artifact workflow: function + tests + validated execution.

### Try 4: Plan a feature
> For anything complex, start with the planner. Try:
> - "I want to build a simulation program for the AE domain"
> - "Plan a TFL program for Table 14.1.1 — demographics summary"

Explain the planner → programmer → reviewer pipeline:
1. **feature-planner** (Opus) reviews the codebase, asks you questions, and writes a plan to `plans/`
2. **r-clinical-programmer** (Sonnet) implements the plan, writing and testing all code
3. **code-reviewer** (Sonnet) independently verifies the implementation against the plan and rules, producing a QC report

This mirrors clinical programming QC: one programmer writes, an independent reviewer verifies.

## Step 3: Explain the rules

Tell them: "Claude already knows all of these, but here's what's enforced so you know what to expect."

Read each rule file from `.claude/rules/` and give a one-sentence summary of each:
- **r-style.md** — Tidyverse style, snake_case, `%>%` pipe, section headers
- **approved-packages.md** — Only use listed packages; ask before adding new ones
- **namespace-conflicts.md** — huxtable/pharmaRTF and dplyr/stats conflicts need `package::function()`
- **cdisc-conventions.md** — ISO 8601 dates, USUBJID format, study day formula, DM generated first
- **file-layout.md** — Where files go and how they're named
- **data-safety.md** — No real patient data in code, no hardcoded credentials
- **git-conventions.md** — Branch naming, commit message format, PR requirements
- **error-messages.md** — How to use `stop()`, `warning()`, `message()` in functions

## Step 4: Show available commands

List all commands in `.claude/commands/` with their descriptions:
- `/r-project` — Scaffold a new R project with renv and standard structure
- `/ct-lookup` — Look up CDISC controlled terminology values
- `/onboard` — This walkthrough (they're in it now)

## Step 5: Wrap up

End with:

> **Key things to remember:**
> 1. Claude enforces project rules automatically — you don't need to memorize them
> 2. All R code Claude writes is executed and tested before you see it
> 3. For complex work, start with the planner — don't jump straight to code
> 4. The code-reviewer agent is your QC step — use it before committing
> 5. If you're unsure, just ask Claude — it knows the project

Ask if they have any questions about the setup or want to try anything specific.
