---
name: ex_combination_dose_parsing
description: EX EXDOSE for combination regimens silently drops second agent dose via str_extract
type: feedback
---

When EXDOSTXT contains combination dose text (e.g. "75 + 10"), `str_extract(EXDOSTXT, "^[0-9.]+")` extracts only the first numeric token and silently discards the second agent's dose.

**Why:** In NPM-008, "Docetaxel + Ramucirumab" has EXDOSTXT = "75 + 10" (mg/m2 + mg/kg). The regex `^[0-9.]+` extracts 75, dropping 10. Four subjects are affected. There is no warning or comment explaining this behaviour.

**How to apply:** When reviewing or implementing EXDOSE derivations for combination regimens:
1. Check whether any EXTRT values contain "+" (combination regimens)
2. If present, flag whether single-record or split-record approach is intended
3. If single record: add explicit comment documenting that EXDOSE captures the primary agent only (sponsor convention)
4. If split record approach is preferred per SDTM-IG: one EX record per agent in the combination

**Pattern to grep for:** `str_extract.*EXDOSTXT` — verify what happens to "+" in the EXDOSTXT values before approving.

See: projects/exelixis-sap/programs/sdtm/sim_ex.R line 146 for example.
