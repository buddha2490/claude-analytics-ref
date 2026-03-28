---
name: lot_algorithm_complexity
description: NPM LoT algorithm requires three distinct rules, iterative approach
type: project
---

ADLOT required algorithm refactoring due to missing 120-day gap rule and death date censoring. Initial implementation used simplified window-only logic.

**Why:** NPM LoT algorithm for NSCLC has three independent termination rules: 45-day window (for grouping), 120-day gap (for line end), and death date (censoring). All three must be evaluated.

**How to apply:** When implementing LoT derivations in future NPM studies:
- Use iterative line assignment (not vectorized grouping)
- Track current_line_start for each line (window is relative to THIS line, not first therapy)
- Evaluate all three termination conditions in each iteration
- Add explicit validation for date consistency (LOTSTDTC <= LOTENDTC)

See: projects/exelixis-sap/adam_adlot.R lines 85-131 for reference implementation
