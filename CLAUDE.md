# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a workspace for developing Claude Code skills and tooling, primarily focused on R/data workflows. The repository is in early stages.

## MCP Servers

- **cdisc-rag**: A local RAG server (`mcp-local-rag`) for querying CDISC standards documentation. Chunks are stored at `~/Rdata/cdisc-rag/chunks` with a LanceDB vector store at `~/Rdata/cdisc-rag/.vectorstore/lancedb`.

## VS Code Integration

The `.vscode/tasks.json` auto-launches Claude Code (`--dangerously-skip-permissions`) and a local shell when the folder is opened.
