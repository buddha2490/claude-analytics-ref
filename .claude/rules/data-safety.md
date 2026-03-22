# Data Safety

## Credentials

- Never hardcode database credentials, tokens, or connection strings in R code
- Connection parameters (Databricks host, token, cluster ID) must come from environment variables or a project config file
- Never commit `.Renviron`, `.env`, or any file containing secrets

## Patient Data

- Never include real patient-level data in code comments, examples, or test fixtures
- Test data must always be simulated — use `set.seed()` for reproducibility
- Do not commit XPT files containing real patient data to version control

## Git Hygiene

- `.gitignore` must exclude: `.Renviron`, `.env`, `*.credentials`, and any file that could contain PHI or secrets
- `renv.lock` and `renv/activate.R` must be committed (they contain no secrets and are required for reproducibility)
- Review staged files before committing — flag anything that looks like it contains real data
