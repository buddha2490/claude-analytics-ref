---
name: r-code
description: Auto-invoked when the user requests R code. Governs the write-source-test-validate workflow, artifact structure, and code templates for R development.
---

# R Code Generation Skill

This skill governs the **workflow** for all R code generation. It is auto-invoked whenever the user requests R code.

Style, packages, naming, CDISC conventions, and file layout are enforced by project rules (`.claude/rules/`) — they apply to every interaction, not just this skill. This skill defines *how code is produced and validated*.

## Core Principle

**All generated code must run without errors.** If you wrote it, you run it. No exceptions.

## Function Workflow (3 artifacts)

Every function produces three artifacts:

1. `R/<function_name>.R` — the function file with roxygen2 documentation
2. `tests/test-<function_name>.R` — a self-contained testthat test file
3. **Validated execution** — both files sourced/run successfully

### Validation Sequence

1. **Write** the function file to `R/`
2. **Source** it in R to confirm it loads without errors
3. **Write** the test file to `tests/`
4. **Run** the tests: `Rscript -e 'testthat::test_file("tests/test-<name>.R")'`
5. **If any step fails:** read the error, fix the code, re-run from the failed step
6. **Report** results — confirm what passed, flag anything that needed revision

## Function File Template (`R/*.R`)

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
- Helper functions may live in the same file below the primary function, without `@export`
- All parameters documented with `@param`
- Return value documented with `@return`
- At least one `@examples` block

## Test File Template (`tests/test-*.R`)

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
- Test at minimum: normal input, empty input, missing values (NA), and domain-specific edge cases
- End every test file with `rm(list = ls())` to clean the environment

## Analysis Script Workflow

When the user asks for analysis code (not a reusable function), write it as a standalone `.R` script in `programs/` or a location the user specifies.

1. **Write** the script
2. **Execute** it via `Rscript`
3. **Fix and re-run** until clean execution
4. **Report** results

Analysis scripts do not require a separate test file, but all code must still be executed to confirm it runs.

## Data Dependencies

Some scripts depend on input files that may not exist yet (e.g., a TFL program that reads `data/dm.xpt` before the simulation program has run). When this happens:

- **If the input data exists:** Run the script normally.
- **If the input data does not exist:** Tell the user which files are missing and which programs generate them (per `file-layout.md` naming conventions). Do not fabricate empty placeholder files. Instead, offer to generate the prerequisite program first.
- **Cross-domain dependency order:** DM must be generated before any other SDTM domain. See `cdisc-conventions.md` for details.
