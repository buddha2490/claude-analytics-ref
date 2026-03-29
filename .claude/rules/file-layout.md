# Project File Layout

All generated code and data must follow this directory structure.

```
R/                  Reusable function files (one primary function per file)
tests/              testthat test files (test-<name>.R)
programs/           Analysis scripts, simulation programs, data pulls, mappings
  programs/sdtm/    SDTM simulation programs (sim_*.R)
  programs/adam/    ADaM derivation programs (adam_*.R)
  programs/utils/   Utility and validation scripts
data/               SDTM/ADaM XPT datasets and intermediate data
data/raw/           Raw source data from Databricks or other external systems
output/             RTF tables, figures, listings, and other deliverables
docs/               Documentation, plans, specs
```

## Naming Conventions

| File type | Pattern | Example |
|-----------|---------|---------|
| Function | `R/<function_name>.R` | `R/create_tfl.R` |
| Test | `tests/test-<function_name>.R` | `tests/test-create_tfl.R` |
| SDTM simulation | `programs/sdtm/sim_<domain>.R` | `programs/sdtm/sim_dm.R` |
| ADaM derivation | `programs/adam/adam_<domain>.R` | `programs/adam/adam_adsl.R` |
| Data pull | `programs/utils/pull_<domain>.R` | `programs/utils/pull_dm.R` |
| Utility script | `programs/utils/<name>.R` | `programs/utils/run_preflight.R` |
| TFL program | `programs/tfl_<table_number>.R` | `programs/tfl_14_1_1.R` |
| Dataset | `data/<DOMAIN>.xpt` | `data/dm.xpt` |
| Output | `output/<table_number>.rtf` | `output/14_1_1.rtf` |
