# QA Reports for SDTM and ADaM Datasets

This directory contains Quarto-based QA reports that provide comprehensive variable summaries for all SDTM and ADaM datasets.

## Quick Start

Generate both reports:

```bash
cd projects/exelixis-sap
./render_qa.sh
```

Output files:
- `output-reports/qa_sdtm.html` - SDTM QA Report
- `output-reports/qa_adam.html` - ADaM QA Report

## Reports

- **qa_sdtm.qmd** - SDTM Dataset QA Report (auto-discovers all SDTM domains)
- **qa_adam.qmd** - ADaM Dataset QA Report (auto-discovers all ADaM datasets)

## Report Structure

Each report contains:

### 1. Overview Section
- Data quality notice (AI-generated datasets require validation)
- Total number of datasets/domains
- List of included datasets
- Generation timestamp

### 2. Dataset Sections (one per domain/dataset)
- Total records and variables
- **Variable subsections** with interactive summary tables:
  - **Numeric variables**: N, Mean, SD, Median, Min, Max, Missing count
  - **Character variables**: Frequency tables with N (%)
  - **Date variables** (ending in "DT"): N, Earliest, Latest, Range, Missing count
  - **Character dates** (ending in "DTC"): Treated as character

### 3. Report Information Footer
- Prepared by, date, purpose statement

## Features

- ✅ **Fully self-contained** - No child templates, easy to deploy
- ✅ **Interactive tables** - Searchable, sortable via DT package
- ✅ **Auto-discovery** - Automatically finds all XPT files in data/
- ✅ **Smart variable handling** - Routes to appropriate summary based on type
- ✅ **CDISC compliant** - Proper handling of DT vs DTC date variables
- ✅ **Professional styling** - Cosmo theme with TOC navigation
- ✅ **Connect-ready** - Embedded resources for easy deployment

## Rendering Reports

### Using the Shell Script (Recommended)

```bash
./render_qa.sh
```

### Rendering Individually

```bash
# SDTM Report
R_PROFILE_USER=/dev/null quarto render qa_sdtm.qmd --to html

# ADaM Report
R_PROFILE_USER=/dev/null quarto render qa_adam.qmd --to html

# Move to output directory
mv qa_sdtm.html output-reports/
mv qa_adam.html output-reports/
```

> **Note**: The `R_PROFILE_USER=/dev/null` flag prevents conflicts with the project .Rprofile during rendering.

## Publishing to Connect

These HTML reports are self-contained and ready for Posit Connect:

1. Open the HTML file in your browser to verify
2. Push to Connect using the rsconnect package or Connect UI
3. All JavaScript, CSS, and data are embedded in the single HTML file

## Technical Details

### Data Discovery

Reports automatically load:
- **SDTM**: All files matching `data/[a-z]{2}.xpt` (e.g., dm.xpt, ae.xpt)
- **ADaM**: All files matching `data/ad[a-z]+.xpt` (e.g., adsl.xpt, adae.xpt)

### Core Functions

The reports use these functions from `R/`:

| Function | Purpose |
|----------|---------|
| `summarize_numeric()` | Numeric variable summaries |
| `summarize_character()` | Character/factor frequency tables |
| `summarize_date()` | Date variable summaries |
| `summarize_variable()` | Smart routing wrapper (auto-detects type) |

### Variable Type Detection

The `summarize_variable()` function routes based on:

1. **Variable name suffix**:
   - Ends with "DT" (e.g., STARTDT) → Date summary
   - Ends with "DTC" (e.g., STARTDTC) → Character summary (CDISC partial dates)

2. **Variable type**:
   - `numeric`/`integer` → Numeric summary
   - `character`/`factor` → Frequency table
   - `Date` → Date summary

## Dependencies

Required R packages:
- **haven** - Read XPT files
- **dplyr** - Data manipulation
- **DT** - Interactive tables
- **stringr** - String operations
- **here** - Path management
- **quarto** - Rendering (install via system package manager)

Install R packages:

```r
install.packages(c("haven", "dplyr", "DT", "stringr", "here"))
```

## Testing

All functions have comprehensive test suites:

```bash
# Run all tests
Rscript -e "testthat::test_dir('tests')"
```

**Test Coverage: 143 passing tests**
- `test-summarize_numeric.R`: 37 tests
- `test-summarize_character.R`: 35 tests
- `test-summarize_date.R`: 39 tests
- `test-summarize_variable.R`: 32 tests

## Validation

✅ All 143 unit tests pass
✅ Reports successfully generated with real data (19 SDTM domains, 6 ADaM datasets)
✅ Date handling logic validated (DT vs DTC suffixes)
✅ Missing value handling confirmed
✅ Output format meets CDISC standards
✅ Interactive tables working
✅ Self-contained HTML deployment verified

## Files

### Quarto Documents
- `qa_sdtm.qmd` - SDTM QA report (self-contained)
- `qa_adam.qmd` - ADaM QA report (self-contained)

### Scripts
- `render_qa.sh` - Shell script to render both reports
- `generate_qa_report_simple.R` - Alternative R-based generation (deprecated)

### Core Functions (in repository root `R/`)
- `R/summarize_numeric.R`
- `R/summarize_character.R`
- `R/summarize_date.R`
- `R/summarize_variable.R`

### Test Files (in repository root `tests/`)
- `tests/test-summarize_numeric.R`
- `tests/test-summarize_character.R`
- `tests/test-summarize_date.R`
- `tests/test-summarize_variable.R`

## Troubleshooting

### Report stops after "Purpose" section

This was caused by using child templates. Fixed by making the Quarto documents fully self-contained.

### "could not find function 'conflicts_prefer'" Error

Use `R_PROFILE_USER=/dev/null` when rendering (already in render_qa.sh).

### DT Package Not Found

Install the DT package:

```r
install.packages("DT")
```

## For More Information

See `QUARTO_QA_IMPLEMENTATION.md` for detailed technical specifications.
