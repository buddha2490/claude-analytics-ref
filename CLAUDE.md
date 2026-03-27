# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a workspace for clinical programming in R using Claude Code. Configuration layers — rules, skills, commands, and agents — encode team standards so Claude enforces them automatically in every conversation.

## Rules (`.claude/rules/`)

Always-on constraints loaded into every conversation.

| Rule | Purpose |
|------|---------|
| `r-style.md` | Tidyverse style, snake_case, `%>%` pipe, section headers |
| `approved-packages.md` | Allowed package list — ask before using anything else |
| `namespace-conflicts.md` | Known conflicts (huxtable/pharmaRTF, dplyr/stats) and resolution |
| `cdisc-conventions.md` | CDISC identifiers, dates, controlled terminology, cross-domain consistency |
| `file-layout.md` | Directory structure and file naming patterns |
| `data-safety.md` | Credentials, patient data, git hygiene |
| `git-conventions.md` | Branch naming, commit messages, PR descriptions |
| `error-messages.md` | Standard patterns for `stop()`, `warning()`, `message()` |
| `ads-qa-review-standards.md` | Severity taxonomy, ADS defect patterns, and report format for ADS branch QA reviews |

## Skills (`.claude/skills/`)

Auto-invoked procedural workflows that fire when the task type matches.

| Skill | Trigger | What it does |
|-------|---------|--------------|
| `r-code` | Any R code request | Write → source → test → validate workflow |
| `databricks` | Databricks connection, query, schema, or data-pull | Connection patterns, schema navigation, `collect()`/`compute()` best practices |
| `ads-data` | Pulling, loading, or subsetting ADS data | `get_ads()` usage, enriched vs essentials, nested JSON columns, subsetting patterns |
| `cohort-cascade` | Building exclusion criteria or attrition tables | `df → df1/df2/... → cohort` cascade pattern with cumulative exclusion flags |

## Commands (`.claude/commands/`)

User-invoked actions called with `/command-name`.

| Command | What it does |
|---------|--------------|
| `/r-project` | Scaffold a new R project with renv, .Rprofile, main.R |
| `/onboard` | Interactive walkthrough for new team members |
| `/ct-lookup` | Look up CDISC controlled terminology via the RAG server |
| `/ads-qa-review <branch-folder> [reviewer]` | Run AI-assisted QA review on a cloned ADS branch |

## Agents (`.claude/agents/`)

Specialized subprocesses for complex work. Each inherits all rules.

| Agent | Model | Role |
|-------|-------|------|
| `feature-planner` | Opus | Plans implementation. Reviews codebase, asks clarifying questions, writes structured plans to `plans/`. Always runs before coding. |
| `r-clinical-programmer` | Sonnet | Implements R code. Follows plans, writes functions/tests/scripts, always executes before returning. |
| `clinical-code-reviewer` | Sonnet | Independent QC. Reviews CDISC-regulated R code against plans and rules, runs tests, produces BLOCKING/WARNING/NOTE report. Does not write code. |
| `ads-qa-reviewer` | Opus | ADS branch QA. Reads git diffs and Jira tickets, queries the RAG, validates variable specs via ADS MCP, produces a structured review report. Invoked via `/ads-qa-review`. |

**Standard clinical programming workflow:**

```
feature-planner  →  r-clinical-programmer  →  clinical-code-reviewer
   (plan)              (implement)              (verify)
```

## MCP Servers

- **cdisc-rag** (`mcp-local-rag`): RAG server for CDISC standards documentation. Chunks at `~/Rdata/cdisc-rag/chunks`, LanceDB index at `~/Rdata/cdisc-rag/.vectorstore/lancedb`.
- **npm-rag-v1**: ADS variable lookup. Use `lookup_variable` and `query_documents` tools to validate variable specs during ADS QA reviews.

## VS Code Integration

`.vscode/tasks.json` auto-launches Claude Code (`--dangerously-skip-permissions`) and a local shell when the folder is opened.
