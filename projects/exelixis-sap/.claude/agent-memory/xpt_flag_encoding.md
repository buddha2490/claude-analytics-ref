---
name: xpt_flag_encoding
description: Verify XPT flag encoding before assuming Y/N pattern
type: feedback
---

When reviewing ADaM datasets, always check how NA_character_ is encoded in XPT output.

**Why:** ADSL QC initially flagged "empty string" for flags as a potential error, but this is correct ADaM convention — haven::write_xpt() converts NA_character_ to empty string per CDISC XPT format.

**How to apply:** Before flagging "empty string" as an error in XPT output:
1. Check if the R code uses NA_character_ (correct)
2. Verify haven::write_xpt() was used (converts correctly)
3. Only flag if R code uses "" directly (incorrect)
