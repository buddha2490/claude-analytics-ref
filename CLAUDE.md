# CLAUDE.md

Clinical programming workspace for R — demonstrates Claude Code configuration patterns (rules, skills, commands, agents).

## Configuration Layers

**Rules** (`.claude/rules/`) — Always-on constraints: r-style, approved-packages, namespace-conflicts, cdisc-conventions, file-layout, data-safety, git-conventions, error-messages

**Skills** (`.claude/skills/`) — Auto-invoked workflows: r-code (write→test→validate), ads-data (ADS data patterns), cohort-cascade (exclusion logic), databricks (connection/query patterns), cdisc-data-validation (SDTM/ADaM compliance checks)

**Commands** (`.claude/commands/`) — Explicit invocations: /r-project (scaffold), /onboard (walkthrough), /ct-lookup (CDISC CT queries)

**Agents** (`.claude/agents/`) — Specialized roles:
- `feature-planner` (Opus) — Plan before coding
- `r-clinical-programmer` (Sonnet) — Implement and execute
- `code-reviewer` (Sonnet) — Independent QC

Standard workflow: planner → programmer → reviewer (mirrors clinical QC)

## Context Composition

Every conversation loads: CLAUDE.md + all rules + relevant skill + command (if invoked) + agent (if spawned)

Agents inherit everything. No layer duplicates another.

## External Systems

- **cdisc-rag** MCP server: Query CDISC standards via `mcp__npm-rag-v1__query_documents` (RAG index at `~/Rdata/cdisc-rag/`)
- **VS Code**: `.vscode/tasks.json` auto-launches Claude Code on folder open
