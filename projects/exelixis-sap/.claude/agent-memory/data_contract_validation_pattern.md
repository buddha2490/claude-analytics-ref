---
name: data_contract_validation_pattern
description: Proactive checkpoint validates source variables exist before derivations
type: feedback
---

All ADaM programs should include a data contract validation checkpoint after loading source data and before implementing derivations.

**Why:** ADBS QC review (2026-03-29) confirmed this pattern prevents downstream errors and provides clear diagnostics when source data structure changes. Lines 26-59 in adam_adbs.R demonstrate the pattern: load data, define expected variables from plan, verify all exist, stop with informative error if any missing.

**How to apply:** After loading all source domains, before any derivations:

```r
# --- Data Contract Validation -----------------------------------------------
# Checkpoint: Verify all required variables exist before derivations
plan_vars_<domain> <- c("USUBJID", "VAR1", "VAR2", ...)
actual_vars_<domain> <- names(<domain>)

missing_vars <- setdiff(plan_vars_<domain>, actual_vars_<domain>)

if (length(missing_vars) > 0) {
  stop(
    "Plan lists variables not found in <DOMAIN>: ",
    paste(missing_vars, collapse=", "),
    "\nActual <DOMAIN> variables: ",
    paste(actual_vars_<domain>, collapse=", "),
    call. = FALSE
  )
}

message("✓ Data contract OK (<DOMAIN>): All ",
        length(plan_vars_<domain>), " expected variables found")
```

**Benefits validated in ADBS QC:**
- Fails fast with clear diagnostics before wasting time on derivations
- Error message shows both expected and actual variables for easy debugging
- Catches plan/SDTM mismatches early (e.g., MHDTC vs MHSTDTC type issues)
- Checkpoint message confirms validation passed

Apply this pattern to all ADaM programs in waves 2-4 (ADSL, ADRS, ADAE, ADTTE).
