---
description: Look up CDISC controlled terminology values for a variable or codelist
---

# CDISC Controlled Terminology Lookup

The user wants to look up CDISC controlled terminology. They may provide:
- A variable name (e.g., `VSTESTCD`, `LBTESTCD`, `AESEV`, `SEX`)
- A codelist ID (e.g., `C66741`, `C66742`)
- A domain + variable combination (e.g., "AE severity", "vital signs test codes")
- A general question about valid values (e.g., "what are the valid values for race?")

## What to do

1. **Query the CDISC RAG MCP server** using the `mcp__cdisc-rag__query_documents` tool. Construct a clear query from the user's input:
   - For variable names: query "CDISC controlled terminology for [VARIABLE]"
   - For codelist IDs: query "CDISC codelist [ID]"
   - For descriptive requests: query as stated

2. **Format the results** clearly:

```
## [Variable/Codelist Name]

**Codelist:** [codelist ID if known]
**Extensible:** Yes / No
**Domain(s):** [where this variable appears]

### Valid Values

| Code | Decode |
|------|--------|
| value | meaning |
| value | meaning |
```

3. **If the RAG returns no results**, tell the user and suggest:
   - Check the variable name spelling (CDISC uses uppercase, 8-char max)
   - Try the parent codelist ID instead of the variable name
   - Ask with more context (e.g., "VSTESTCD in the VS domain")

4. **If the RAG returns partial results**, present what's available and note what may be missing.

## Keep it concise

This is a quick reference lookup, not a deep analysis. Return the values in a clean table and stop. Don't explain CDISC fundamentals unless the user asks.
