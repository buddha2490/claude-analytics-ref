# CDISC Conventions

These rules apply to all code that creates, transforms, or validates CDISC datasets (SDTM, ADaM).

## Identifiers

- `STUDYID` must be consistent across all domains within a study
- `USUBJID` format: `{STUDYID}-{SITEID}-{SUBJID}` — must be unique and match across domains
- `--SEQ` variables (e.g., `AESEQ`, `CMSEQ`) must be unique integers within each `USUBJID`

## Dates and Times

- All dates use ISO 8601 format: `YYYY-MM-DD` or `YYYY-MM-DDThh:mm:ss`
- Partial dates are permitted per SDTM-IG rules (e.g., `2024-01` when day is unknown)
- Study day variables (`--DY`) are calculated relative to `RFSTDTC`:
  - On or after RFSTDTC: `date - RFSTDTC + 1` (no day zero)
  - Before RFSTDTC: `date - RFSTDTC`

## Controlled Terminology

- Use CDISC Controlled Terminology values exactly as published — no custom values unless the spec explicitly allows extensible CT
- When available, query the CDISC RAG MCP server for current CT values rather than hardcoding

## Cross-Domain Consistency

- All subjects referenced in any domain must exist in DM
- Event dates must fall within the subject's study period (`RFSTDTC` to `RFENDTC`) unless the event is a screen failure or pre-study
- DM is always generated/processed first; other domains reference it

## Variable Attributes

- All variables must carry labels (required for XPT transport)
- Variable names: uppercase, max 8 characters per SDTM-IG
- Use `xportr` functions to apply labels, types, and lengths before writing XPT
- Write final datasets with `haven::write_xpt()`
