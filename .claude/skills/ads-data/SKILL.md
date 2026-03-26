---
name: ads-data
description: Use when pulling, loading, exploring, or subsetting ADS (Analytical Dataset) data from Databricks. Covers get_ads() usage, enriched vs essentials types, available tumor cohorts, nested JSON columns, and common subsetting patterns.
---

# ADS Data Skill

This skill governs how ADS data is pulled from Databricks and prepared for analysis. It is invoked whenever a program needs to load, explore, or subset ADS data.

## Pulling Data with `get_ads()`

The `syhelpr` package provides `get_ads()` to retrieve ADS data from S3/Databricks:

```r
library(syhelpr)

df <- get_ads(cohort, type, env = "prod", internal = TRUE) %>%
  collect()
```

### Parameters

| Parameter | Values | Description |
|-----------|--------|-------------|
| `cohort` | `"lung"`, `"bladder"`, `"breast"`, `"ovarian"` | Tumor site. Essentials cohorts may include additional tumor types as they are developed. |
| `type` | `"enriched"`, `"essentials"` | Data tier (see below) |
| `env` | `"prod"` (default), `"sqa"`, `"qc"` | Environment |
| `internal` | `TRUE` (default), `FALSE` | `TRUE` = identified (internal only); `FALSE` = de-identified (external/Sandbox) |

### Enriched vs Essentials

| | Enriched | Essentials |
|---|----------|------------|
| **Cohort definition** | Cancer type + diagnosis source (MA only) | Cancer type only (any structured source) |
| **Data sources** | Manually abstracted (MA) by NPM ODS-certified professionals | Registry, EHR, 3rd-party labs, MA |
| **Patient population** | Subset of Curated — highest data quality | Broader — includes all structured sources |
| **Nested JSON columns** | Yes — therapy, radiation, biomarker detail | Limited — fewer manually abstracted fields |
| **Variable coverage** | Full — all enriched-only variables populated | Core variables only; enriched-only vars are missing or NA |
| **Use `enriched_cohort_flag`** | All rows are `TRUE` | `TRUE` for enriched patients, `FALSE` for registry/EHR-only |

**Rule:** Default to `type = "enriched"` for feasibility studies and clinical analyses requiring manually abstracted therapy/radiation detail. Use `type = "essentials"` when broader patient counts or structured-source-only variables are sufficient.

## Lazy Evaluation

`get_ads()` returns a **lazy remote tibble** (Spark/dbplyr). Data stays on the server until `collect()` pulls it into local R memory.

```r
# Lazy — no data transferred yet
remote_df <- get_ads("lung", type = "enriched")

# Materialized — pulls all rows into local memory
df <- remote_df %>% collect()

# Filter server-side before collecting to reduce memory
df <- get_ads("lung", type = "enriched") %>%
  filter(diagnosis_date >= as.Date("2023-01-01")) %>%
  collect()
```

**Rule:** When the full ADS is needed (e.g., cohort cascades that inspect all patients), collect first, then filter locally. When only a subset is needed, push filters before `collect()` to reduce transfer size.

## Patient Identifier

The primary key is **`patientid`** (UUID string). The ADS is **long-form** — multiple rows per patient (one per line of therapy, diagnosis, etc.).

```r
# Count unique patients
n_distinct(df$patientid)

# or
df %>% distinct(patientid) %>% nrow()
```

**Rule:** Always use `patientid` (not `USUBJID`, not `participantid`). Always count patients with `n_distinct(patientid)` or `distinct(patientid)` — never `nrow()` alone.

## Key Identifier Flag

`enriched_cohort_flag` (logical: `TRUE`/`FALSE`) indicates whether a patient has manually curated data. Present in both enriched and essentials pulls.

```r
# Subset to enriched patients only (when using essentials pull)
df_enriched <- df %>% filter(enriched_cohort_flag == TRUE)
```

## ADS Column Structure

### Flat Columns (All Tumor ADS)

These are available across all four tumor cohorts (LNG, OVC, BLAD, BRC):

| Section | Key Variables |
|---------|--------------|
| **Key Variables** | `patientid`, `enriched_cohort_flag` |
| **Demographics** | `age_diagnosis`, `sex`, `race`, `ethnicity`, `birth_date_year` |
| **Key Dates** | `diagnosis_date`, `diagnosis_date_year`, `diagnosis_date_granularity`, `last_abstraction_date` |
| **Clinical Dx** | `icdo3_histology_code`, `icdo3_topography_code`, `prioritized_stage_group_dx`, `prioritized_stage_group_detailed_dx`, pathologic/clinical TNM staging |
| **Recurrent/Met** | `metastasis_flag`, `metastasis_presentation`, `metastasis_date` |
| **Outcomes** | `vital_status`, `date_of_death`, `last_known_alive_date` |

### Nested JSON Columns

Several columns store **JSON strings** (not native R list-columns). Standard `tidyr::unnest()` does not work directly. These require parsing before use.

| Column | Contents | Enriched Only? |
|--------|----------|----------------|
| `systemic_therapy` | Drug name, class, start/end dates, clinical trial flag | Yes (most fields) |
| `radiation_therapy` | Site, intent, modality, start/end dates, dose | Yes (most fields) |
| `line_of_therapy` | Regimen, line number, start/end dates | Yes |
| `tumor_marker` | Gene, alteration type, MSI state, specimen date | No (some from labs) |
| `other_cancer` | Site, diagnosis date of other malignancies | Yes |
| `recurrence` | Site, date of recurrence | Yes |

### Tumor-Specific Columns

Individual cohorts have additional variables not shared across all ADS:

- **Lung:** Smoking history, EGFR/ALK/ROS1/PD-L1 biomarkers, brain metastasis detail
- **Breast:** ER/PR/HER2 status, receptor subtype, Ki-67, BRCA status
- **Bladder:** NMIBC/MIBC classification, primary site surgery, trimodal therapy
- **Ovarian:** BRCA/HRD status, debulking surgery, family history of cancer

**Rule:** When unsure which columns exist for a given cohort, query the RAG tool with `source: "ADS"` for the data dictionary.

## Parsing Nested JSON Columns

Use `parse_json_col()` to expand JSON string columns into rows:

```r
parse_json_col <- function(data, col) {
  col_sym <- rlang::sym(col)
  data %>%
    mutate(
      !!col_sym := purrr::map(!!col_sym, function(x) {
        if (is.na(x) || x == "" || x == "{}" || x == "[]") {
          tibble()
        } else {
          tryCatch(
            as_tibble(jsonlite::fromJSON(x, simplifyDataFrame = TRUE,
                                        flatten = FALSE)),
            error = function(e) tibble()
          )
        }
      })
    ) %>%
    tidyr::unnest(!!col_sym, keep_empty = FALSE)
}
```

This mirrors `syhelpr::unnest_json_df()`. Define it locally in each program for transparency.

### Critical Rule: Deduplicate Before Parsing

The ADS is long-form. Parsing JSON on the full dataset duplicates rows explosively. Always deduplicate to one row per patient before parsing:

```r
# CORRECT — deduplicate first
therapy_df <- df %>%
  select(patientid, systemic_therapy) %>%
  distinct(patientid, .keep_all = TRUE) %>%
  parse_json_col("systemic_therapy")

# WRONG — parsing on full long-form data inflates row counts
therapy_df <- df %>%
  parse_json_col("systemic_therapy")
```

### Systemic Therapy Variables (after parsing)

| Variable | Type | Description |
|----------|------|-------------|
| `therapy_name` | string | Generic drug name |
| `therapy_class` | string | Drug class (e.g., Chemotherapy, Immunotherapy) |
| `therapy_start_date` | date | Start of therapy (YYYY-MM-DD) |
| `therapy_end_date` | date | End of therapy |
| `therapy_clinical_trial` | string | Yes/No/Unknown — whether therapy was part of a clinical trial |
| `therapy_start_date_granularity` | string | NONE/YEAR/MONTH/DAY |

### Radiation Therapy Variables (after parsing)

| Variable | Type | Description |
|----------|------|-------------|
| `radiation_site` | string | Anatomic target |
| `radiation_intent` | string | Curative, Palliative, etc. |
| `radiation_modality` | string | Type of radiation |
| `radiation_start_date` | date | Start of radiation |
| `radiation_end_date` | date | End of radiation |
| `radiation_ongoing` | string | Yes/No/Unknown |

## Alternate Connection: DBI/ODBC Direct

For tables outside the ADS (e.g., raw GPT-normalized data), use a direct DBI connection:

```r
library(DBI)
library(odbc)

con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP")
)

# Three-part table references: catalog.schema.table
result <- DBI::dbGetQuery(con, "
  SELECT count(distinct patientid)
  FROM ai_development.feasibility.diagnosis_gpt_normalized
  WHERE histology_kms_code RLIKE '8041|8042'
")
```

**Rule:** Credentials must come from environment variables (`.Renviron`). Never hardcode connection strings.

## Required Packages

```r
library(dplyr)       # data manipulation
library(tidyr)       # unnesting
library(purrr)       # map for JSON parsing
library(jsonlite)    # fromJSON
library(syhelpr)     # get_ads()
```

## Program Header Template

```r
# =============================================================================
# Study:    <Study Name> (<Protocol Number>)
# Program:  <program_name>.R
# Date:     <YYYY-MM-DD>
# Author:   <Name>
# Purpose:  <Description of what this program does>
# =============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(jsonlite)
library(syhelpr)

# =============================================================================
# DATA PULL
# =============================================================================

df <- get_ads("<cohort>", type = "<enriched|essentials>") %>%
  collect()

message("Loaded ", nrow(df), " rows, ", n_distinct(df$patientid), " patients")
```

## Data Dictionary Lookup

When you need to verify which variables exist for a cohort or what values a column takes, query the RAG tool:

```
source: "ADS"
query: "<variable name or section name> <cohort>"
```

The RAG contains the full data dictionaries for all tumor ADS, including variable descriptions, value sets, enriched-only flags, and data sources.
