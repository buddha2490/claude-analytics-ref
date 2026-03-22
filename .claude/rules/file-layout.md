# Project File Layout

All generated code and data must follow this directory structure.

```
R/                  Reusable function files (one primary function per file)
tests/              testthat test files (test-<name>.R)
programs/           Analysis scripts, simulation programs, data pulls, mappings
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
| Simulation | `programs/sim_<domain>.R` | `programs/sim_dm.R` |
| Data pull | `programs/pull_<domain>.R` | `programs/pull_dm.R` |
| SDTM mapping | `programs/sdtm_<domain>.R` | `programs/sdtm_dm.R` |
| TFL program | `programs/tfl_<table_number>.R` | `programs/tfl_14_1_1.R` |
| Dataset | `data/<DOMAIN>.xpt` | `data/dm.xpt` |
| Output | `output/<table_number>.rtf` | `output/14_1_1.rtf` |
