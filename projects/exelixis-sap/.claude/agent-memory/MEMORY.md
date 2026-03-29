# NPM-008 Exelixis Study Memory Index

This file indexes study-specific memories that agents should consult before implementation and after QC reviews.

## Feedback Memories

- [xpt_flag_encoding.md](xpt_flag_encoding.md) — Verify XPT flag encoding before assuming Y/N pattern
- [data_contract_validation_pattern.md](data_contract_validation_pattern.md) — Proactive checkpoint validates source variables exist before derivations
- [adrs_confirmed_response_pattern.md](adrs_confirmed_response_pattern.md) — ADRS BOR confirmation requires scanning ALL subsequent assessments not just next one
- [baseline_max_warning_pattern.md](baseline_max_warning_pattern.md) — max() on empty vector produces -Inf warning requires is.finite() check
- [ex_combination_dose_parsing.md](ex_combination_dose_parsing.md) — EX EXDOSE for combination regimens silently drops second agent dose via str_extract

## Project Memories

- [lot_algorithm_complexity.md](lot_algorithm_complexity.md) — NPM LoT algorithm requires three rules, iterative approach

## Reference Memories

- [npm008_biomarker_terminology.md](npm008_biomarker_terminology.md) — NPM-008 LB uses ALTERED/NOT ALTERED for mutation status
- [adrs_aval_study_specific.md](adrs_aval_study_specific.md) — NPM-008 ADRS uses study-specific AVAL coding 1=CR through 5=NE not CDISC standard
