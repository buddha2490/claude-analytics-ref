---
name: adrs_confirmed_response_pattern
description: ADRS BOR confirmation requires scanning ALL subsequent assessments not just next one
type: feedback
---

When implementing RECIST 1.1 confirmed response logic, use an iterative approach that scans ALL subsequent assessments, not just the immediate next assessment.

**Why:** The ADRS QC review validated that BOR confirmation requires checking if ANY subsequent assessment ≥28 days later is CR/PR, not just the next one. A subject might have: PR (Week 6) → SD (Week 12) → PR (Week 24). The confirmation interval is from Week 6 to Week 24 (18 weeks = 126 days), NOT Week 6 to Week 12.

**How to apply:** When implementing BOR derivation for RECIST datasets:
- Use `sapply()` to scan from current position to end: `(i+1):length(AVALC)`
- Check if ANY later assessment meets both criteria: (1) is CR/PR AND (2) ≥28 days later
- Do NOT use `lead()` or `lag()` — these only check adjacent records
- For vectorized alternative, use `purrr::map_lgl()` with similar scan-forward logic

**Code pattern (verified in adam_adrs.R lines 184-205):**
```r
has_confirmed_cr = any(
  AVALC == "CR" &
  sapply(seq_along(AVALC), function(i) {
    if (AVALC[i] == "CR") {
      any(AVALC[(i+1):length(AVALC)] %in% c("CR", "PR") &
          (ADT[(i+1):length(ADT)] - ADT[i]) >= 28, na.rm = TRUE)
    } else {
      FALSE
    }
  })
)
```

See: projects/exelixis-sap/programs/adam_adrs.R lines 176-241 for reference implementation
