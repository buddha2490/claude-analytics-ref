---
name: baseline_max_warning_pattern
description: max() on empty vector produces -Inf warning requires is.finite() check
type: feedback
---

When deriving baseline flags using `max(date[condition])`, always include `is.finite()` check to handle subjects with no qualifying records.

**Why:** ADRS baseline derivation (line 141) uses `max(ADT[ADT <= TRTSDT])` to find last pre-treatment assessment. Subjects with no assessments before TRTSDT produce `max()` warning: "no non-missing arguments to max; returning -Inf". While non-fatal, the warning clutters output and should be handled.

**Correct pattern (from adam_adrs.R lines 141-146):**
```r
max_prebaseline = max(ADT[!is.na(ADT) & !is.na(TRTSDT) & ADT <= TRTSDT], na.rm = TRUE),
ABLFL = dplyr::if_else(
  !is.na(ADT) & !is.na(max_prebaseline) & is.finite(max_prebaseline) & ADT == max_prebaseline,
  "Y",
  NA_character_
)
```

**Key elements:**
1. `na.rm = TRUE` in `max()` — removes NA dates
2. `is.finite(max_prebaseline)` — handles -Inf from empty vector
3. Result: ABLFL correctly set to NA for subjects without baseline (not flagged incorrectly)

**Alternative pattern (warning-free):**
```r
create_baseline_flag <- function(adt, trtsdt, condition_vector) {
  valid_dates <- adt[condition_vector]
  if (length(valid_dates) == 0 || all(is.na(valid_dates))) {
    return(rep(NA_character_, length(adt)))
  }
  max_date <- max(valid_dates, na.rm = TRUE)
  ifelse(adt == max_date & condition_vector, "Y", NA_character_)
}
```

**When to apply:** Any baseline flag derivation where `max()` operates on a filtered date vector (ADRS, ADAE, ADTTE baseline assessments)
