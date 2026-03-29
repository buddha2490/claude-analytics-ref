---
name: adrs_aval_study_specific
description: NPM-008 ADRS uses study-specific AVAL coding 1=CR through 5=NE not CDISC standard
type: reference
---

ADRS AVAL coding in NPM-008 uses study-specific convention: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE (lower number = better response).

**Why:** This differs from typical CDISC coding where NE is often 0 or missing. Intentional per NPM-008 analysis plan. Must be documented in code to prevent QC flagging as error.

**Required code comment:**
```r
# NOTE: Study-specific AVAL coding — not CDISC standard
# Per Open-questions-cdisc.md R8: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE
AVAL = dplyr::case_when(
  AVALC == "CR" ~ 1,
  AVALC == "PR" ~ 2,
  AVALC == "SD" ~ 3,
  AVALC == "PD" ~ 4,
  AVALC == "NE" ~ 5,
  TRUE ~ NA_real_
)
```

**How to apply:**
- Add NOTE comment before AVAL derivation in both OVRLRESP and BOR sections
- Reference Open-questions R8 for traceability
- Apply same coding consistently across all response-related parameters

Applies to: ADRS (OVRLRESP, BOR parameters) and any future response-derived variables in NPM-008
