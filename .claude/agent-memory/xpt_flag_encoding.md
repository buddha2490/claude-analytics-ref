---
name: xpt_flag_encoding
description: Verify XPT flag encoding before assuming Y/N pattern
type: feedback
---

When reviewing ADaM datasets, always check how NA_character_ is encoded in XPT output.

**Why:** ADAE QC initially flagged "Y without blank values" in TRTEMFL as a potential flag convention violation. However, this was correct ADaM implementation — the R code uses `if_else(..., "Y", NA_character_)` per convention, but all 131 AEs in the simulated data happened to be treatment-emergent, so NA_character_ was never written. This is a data artifact, not a code defect.

**How to apply:** Before flagging "all Y, no blanks" as an error in XPT flag variables:
1. Check if the R code uses `if_else(..., "Y", NA_character_)` (correct Y/blank convention)
2. Verify the logical condition — does the data naturally produce any FALSE cases?
3. Check dev log for data characteristics (e.g., "all simulated AEs are treatment-emergent")
4. Only flag if R code uses `"Y"/"N"` or `ifelse(..., "Y", "")` (incorrect patterns)

**ADaM flag convention:** Y/blank means Y for true, NA_character_ (which writes as empty string in XPT) for false. The absence of blank values in output does not indicate a code error if the data legitimately has no false cases.
