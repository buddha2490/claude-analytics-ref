# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a workspace for developing Claude Code skills and tooling for clinical programming in R. It serves as a **reference implementation** demonstrating how rules, skills, commands, and agents work together in a Claude Code project.

## Architecture: How the Pieces Fit Together

Claude Code has four configuration layers. Each has a distinct role — understanding the separation is key to building maintainable projects.

### Rules (`.claude/rules/`)

**Always-on project constraints.** Every rule file is loaded into context for every conversation, regardless of what task is being performed. Rules define *what standards this project enforces*.

| Rule | Purpose |
|------|---------|
| `r-style.md` | Tidyverse style conventions, naming, pipes, comments |
| `approved-packages.md` | Allowed package list — ask before using anything else |
| `namespace-conflicts.md` | Known conflicts (huxtable/pharmaRTF, dplyr/stats) and resolution |
| `cdisc-conventions.md` | CDISC identifiers, dates, controlled terminology, cross-domain consistency |
| `file-layout.md` | Directory structure and file naming patterns |
| `data-safety.md` | Credentials, patient data, git hygiene |
| `git-conventions.md` | Branch naming, commit messages, PR descriptions, protected files |
| `error-messages.md` | Standard patterns for `stop()`, `warning()`, `message()` in R |

**When to add a rule:** When a constraint applies across all tasks — code generation, review, refactoring, testing, documentation. If you find yourself repeating the same correction to Claude, it belongs in a rule.

### Skills (`.claude/skills/`)

**Procedural workflows that auto-invoke.** Skills define *how* work gets done for a specific type of task. They fire automatically when the task matches their description.

| Skill | Trigger | What it does |
|-------|---------|--------------|
| `r-code` | Any R code request | Write → source → test → validate workflow with templates |
| `databricks` | Any Databricks connection, query, schema, or data-pull request | Connection patterns, navigation, schema inspection, and `collect()`/`compute()`/`cache()` performance best practices |

Skills inherit all rules automatically. The `r-code` skill doesn't restate style rules — it focuses purely on the 3-artifact workflow (function file, test file, validated execution).

**When to add a skill:** When a specific task type needs a repeatable, multi-step workflow. Skills are for *procedures*, not *policies*.

### Commands (`.claude/commands/`)

**User-invoked actions.** Commands run only when explicitly called with `/command-name`. They're one-shot tasks like scaffolding or generation.

| Command | Invocation | What it does |
|---------|------------|--------------|
| `r-project` | `/r-project` | Scaffold a new R project with renv, .Rprofile, main.R |
| `onboard` | `/onboard` | Interactive walkthrough for new team members |
| `ct-lookup` | `/ct-lookup` | Look up CDISC controlled terminology via the RAG server |

**When to add a command:** When a task is run on-demand (not auto-detected), typically project setup, code generation from specs, or batch operations.

### Agents (`.claude/agents/`)

**Specialized subprocesses for complex work.** Agents are spawned by the main conversation (or by each other) to handle focused tasks. Each agent inherits all rules and has its own model, tools, and persistent memory.

| Agent | Model | Role |
|-------|-------|------|
| `feature-planner` | Opus | Architects implementation plans. Reviews codebase, asks clarifying questions, pushes back on problems, produces structured plans with orchestration guides. Always runs **before** coding begins. |
| `r-clinical-programmer` | Sonnet | Implements R code. Follows plans, writes functions/tests/scripts, and **always executes code before returning it**. The workhorse. |
| `code-reviewer` | Sonnet | Independent QC. Reviews implementations against plans and rules, runs tests, produces a structured QC report with BLOCKING/WARNING/NOTE findings. Does **not** write production code. |

**The standard workflow:**

```
feature-planner  →  r-clinical-programmer  →  code-reviewer
   (plan)              (implement)              (verify)
```

1. **Plan:** The planner explores the codebase, asks questions, and writes a plan to `plans/`
2. **Implement:** The programmer follows the plan, writing and validating code
3. **Review:** The reviewer checks the implementation against the plan and rules, runs tests, and produces a QC report with a PASS/FAIL verdict

This mirrors the clinical programming QC workflow: one programmer writes, an independent reviewer verifies.

**When to add an agent:** When a role requires a distinct persona, model choice, or tool scope. Agents are for *roles*, not *tasks*.

### CLAUDE.md (this file)

**Project-level context and orientation.** This is the first thing Claude reads. It should contain:
- What this project is and how it's structured
- How the configuration layers work together (this section)
- Pointers to external systems (MCP servers, data sources)
- Anything a new team member needs to orient themselves

**What does NOT belong here:** Style rules, coding conventions, or workflow procedures — those go in rules and skills respectively.

### How They Compose

```
Every conversation loads:
  CLAUDE.md          (orientation — what is this project?)
  + all rules/       (constraints — what standards apply?)
  + relevant skill   (workflow — how do I produce the output?)
  + command if invoked (action — run this specific task)
  + agent if spawned  (role — who does this work?)
```

Agents inherit everything above them. When the r-clinical-programmer agent spawns, it gets CLAUDE.md + all rules + the r-code skill — without any of those restating their content in the agent definition.

**Example — simple task:** You ask Claude to write a function that derives study days.

1. **CLAUDE.md** tells Claude this is a clinical programming project
2. **Rules** enforce: snake_case, tidyverse pipe, approved packages only, ISO 8601 dates, CDISC study day calculation formula, file goes in `R/`
3. **r-code skill** fires: write the function → write tests → source both → validate → report

**Example — full pipeline:** You ask Claude to build the AE simulation program.

1. **feature-planner** reviews the AE spec sheet, asks clarifying questions, writes `plans/plan_sim_ae_2026-03-22.md`
2. **r-clinical-programmer** reads the plan, implements `programs/sim_ae.R` and `tests/test-sim_ae.R`, executes both
3. **code-reviewer** reads the plan and implementation, runs tests, checks CDISC compliance, produces a QC report

Rules ensure correctness. Skills ensure process. Agents ensure accountability. No layer duplicates another.

## MCP Servers

- **cdisc-rag**: A local RAG server (`mcp-local-rag`) for querying CDISC standards documentation. Chunks are stored at `~/Rdata/cdisc-rag/chunks` with a LanceDB vector store at `~/Rdata/cdisc-rag/.vectorstore/lancedb`.

## VS Code Integration

The `.vscode/tasks.json` auto-launches Claude Code (`--dangerously-skip-permissions`) and a local shell when the folder is opened.
