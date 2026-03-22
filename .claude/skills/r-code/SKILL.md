---
name: r-code
description: Auto-invoked when the user requests R code. Enforces tidyverse style, roxygen2 documentation, testthat tests, validation by execution, and approved package usage for clinical programming workflows.
---

# R Code Generation Skill

This skill governs all R code generation in this project. It is auto-invoked whenever the user requests R code — no explicit command needed.

## Core Principles

1. **Every function produces three artifacts:**
   - `R/<function_name>.R` — the function file with roxygen2 tags
   - `tests/test-<function_name>.R` — a self-contained testthat test file
   - The function and tests must be **validated by execution** before delivery

2. **All generated code must run without errors.** After writing code, execute it in R to confirm it works. If it fails, revise and re-run until it succeeds. This applies to:
   - Standalone scripts and analysis code
   - Function files (source them)
   - Test files (run them and confirm tests pass)
   - Any code chunk — if you wrote it, you run it

## Style Guide

Follow the [tidyverse style guide](https://style.tidyverse.org/) with these project-specific rules:

### Naming
- Use `snake_case` for functions, variables, and file names
- Function files: `R/<function_name>.R`
- Test files: `tests/test-<function_name>.R`

### Package Loading
- **Default:** Use `library(package)` then call functions directly (e.g., `filter()`, not `dplyr::filter()`)
- **Exception:** Use `package::function()` only when there is a genuine namespace conflict (e.g., `dplyr::filter()` vs `stats::filter()`)
- Never use `require()` — always use `library()`

### Comments
- Every logical section of code must have a comment explaining what it does
- Use section headers for major blocks:
```r
# --- Section Name -----------------------------------------------------------
```
- Comments should explain *why*, not just *what*

### Pipes
- Prefer the tidyverse pipe `%>%` unless the user specifies the base pipe `|>`
- One operation per line in pipe chains

## Function Files (`R/*.R`)

Each function gets its own file. Structure:

```r
#' Title of the Function
#'
#' @description
#' A clear description of what the function does.
#'
#' @param param_name Description of the parameter.
#' @param another_param Description with expected type/format.
#'
#' @return Description of the return value.
#'
#' @examples
#' # Example usage
#' result <- my_function(arg1, arg2)
#'
#' @export
my_function <- function(param_name, another_param) {
  # --- Validate inputs -------------------------------------------------------
  # input validation code

  # --- Main logic -------------------------------------------------------------
  # function body

  # --- Return -----------------------------------------------------------------
  return(result)
}
```

Rules:
- One primary function per file
- Helper functions used only by that function may live in the same file, defined below the primary function, without `@export`
- All parameters documented with `@param`
- Return value documented with `@return`
- At least one `@examples` block

## Test Files (`tests/test-*.R`)

Each test file is self-contained. Structure:

```r
library(testthat)

# Source the function under test
source("R/<function_name>.R")

# --- Test Data ----------------------------------------------------------------
# Simulate test data inline. Use set.seed() for reproducibility.
set.seed(12345)

test_data <- tibble(
  # simulated data here
)

# --- Tests --------------------------------------------------------------------

test_that("<function_name> handles normal input", {
  result <- my_function(test_data)
  expect_equal(nrow(result), expected_n)
  # additional expectations
})

test_that("<function_name> handles edge case: empty input", {
  empty_df <- tibble()
  expect_error(my_function(empty_df), "expected error message")
})

test_that("<function_name> handles edge case: missing values", {
  # test with NA values
})

# --- Cleanup ------------------------------------------------------------------
rm(list = ls())
```

Rules:
- Every test file starts by loading `testthat` and sourcing the function
- Test data is simulated inline — no external fixture files
- Always use `set.seed()` before any randomized data generation
- Test at minimum: normal/expected input, empty input, missing values (NA), and any domain-specific edge cases
- End every test file with `rm(list = ls())` to clean the environment

## Approved Packages

Only use packages from this approved list. If a task requires a package not listed here, ask the user before using it.

**Core:**
- tidyverse (dplyr, tidyr, readr, stringr, purrr, forcats, lubridate, tibble)
- ggplot2
- plotly
- gt
- huxtable
- pharmaRTF

**Data/Infrastructure:**
- DBI
- sparklyr

**Pharmaverse** (any package, as appropriate for clinical programming):
- admiral, admiraldev
- metacore, metatools
- xportr
- and other pharmaverse packages as needed for the task

**Testing:**
- testthat

## Validation Process

After generating code, follow this sequence:

1. **Write** the function file to `R/`
2. **Source** the function file in R to confirm it loads without errors
3. **Write** the test file to `tests/`
4. **Run** the test file with `Rscript -e 'testthat::test_file("tests/test-<name>.R")'`
5. **If any step fails:** read the error, fix the code, and re-run from the failed step
6. **Report** results to the user — confirm what passed, flag anything that needed revision

For standalone scripts (not functions):
1. **Write** the script
2. **Execute** it section by section or in full via `Rscript`
3. **Fix and re-run** until clean execution
4. **Report** results

## Analysis Scripts

When the user asks for analysis code (not a reusable function), write it as a standalone `.R` script in the project root or a location the user specifies. Follow the same style, commenting, and validation rules. Analysis scripts do not require a separate test file, but all code must still be executed to confirm it runs.
