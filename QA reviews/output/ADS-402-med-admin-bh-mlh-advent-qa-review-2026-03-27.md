# ADS-402 QA Review: Expand medication_administration to Advent, BH, and MLH

| Field | Value |
|-------|-------|
| **Branch** | ADS-402-med-admin-bh-mlh-advent |
| **Ticket** | ADS-402 |
| **Date reviewed** | 2026-03-27 |
| **Reviewer** | Brian Carter |
| **Model version** | claude-opus-4-6 |
| **AI caveat** | This report is an advisory tool for the human reviewer. The reviewer is accountable for the final approval decision. Claude can miss context, misread intent, or fail to catch subtle logical errors that require domain expertise to recognize. |

---

## Ticket Overview

**ADS-402: Expand medication_administration to Advent, BH, and MLH**

The ticket requests extending the medication administration pipeline to ingest structured data from three additional health systems -- Advent, BayHealth, and Main Line Health -- using Databricks `production.gold.medication_flat` as the data source. The pipeline is also extended to incorporate abstracted (OpenClinica) medication administration data for all health systems. The result is a "three source" pipeline:

1. **SPMD** (`_spmd` functions): Aurora and Ascension structured EHR data (existing)
2. **OpenClinica** (`_oc` functions): Abstracted medication administration for all health systems (new)
3. **Databricks** (`_db` functions): Advent, BayHealth, MLH structured FHIR/HL7 data (new)

Two new ADS variables are introduced:
- `med_admin_flag` (patient-level): Classifies patients by expected availability of administration data
- `admin_source` (nested, within `medication_administration`): Indicates whether a record is from structured data or abstraction

**Key constraints from ticket comments:**
- RxCUI coverage is very poor in `medication_flat` -- BayHealth has ~30% coverage; Advent and MLH have none (always NA). This is a known upstream data issue.
- Therapy name normalization uses `spmd_sqa.maps.rxnorm_kbtherapy`
- Matching algorithm: admin therapy matches antineoplastics, admin on/after diagnosis date, matches patient's specific systemic therapies
- OpenClinica data is pulled for all patients but only abstracted for Merck priority cohorts
- SPMD data for Aurora and Ascension only; Databricks data for Advent, BayHealth, MLH only

---

## Changed Files Summary

| File | Change Description |
|------|--------------------|
| `ads/utilities/functions/med_admin.R` | Core pipeline extension: new `get_med_admin_oc()`, `get_med_admin_db()`, `clean_med_admin_oc()`, `clean_med_admin_db()` functions; updated `wrangle_med_admin()` to accept three sources; updated `derive_med_admin()` to orchestrate the three-source pipeline; minor behavior change in `clean_med_admin_spmd()` (undated records now dropped) |
| `ads/datasets/bladder.R` | Updated `derive_med_admin()` call: added `cancer` parameter, changed patient filter from `sourcename %in% c("aurora", "ascension")` to `filter(enriched_cohort_flag)`, added `db` connection |
| `ads/datasets/breast.R` | Updated `derive_med_admin()` call: added `cancer` parameter, changed patient source to `breast$patients_enriched` with morphology join for `sourcename`, added `db` connection |
| `ads/datasets/lung.R` | Updated `derive_med_admin()` call: added `cancer` parameter, changed patient source to `lung$patients_enriched` with morphology join for `sourcename`, added `db` connection |
| `ads/datasets/ovarian.R` | Updated `derive_med_admin()` call: added `cancer` parameter, changed patient filter from `sourcename %in% c("aurora", "ascension")` to `filter(enriched_cohort_flag)`, added `db` connection |
| `ads/utilities/definitions.R` | Added `db <- connect_databricks_odbc()` connection and commented-out route normalization map script |
| `ads/whitelist/all_tumor.json` | Added `med_admin_flag` (patient-level) and `admin_source` (nested in `medication_administration`) to all four tumors |
| `NEWS.md` | Documented changes for both Users and Developers sections |
| `investigations/pan-tumor/ADS-402-med-admin-bh-mlh-advent.R` | Investigation script (not reviewed in detail) |
| `reports/pan-tumor/ads-402-advent-bh-mlh-med-admins.Rmd` | Report (not reviewed in detail) |
| `reports/pan-tumor/ads-403-abstracted-admin.Rmd` | Report (not reviewed in detail) |
| `reports/pan-tumor/rsconnect/...` | Posit Connect deployment config |

---

## Changed Code

### ads/utilities/functions/med_admin.R

The primary file with ~400 lines of new/modified code. Key changes organized by function:

**New function: `get_med_admin_oc()`** (lines 63--104)
Pulls OC medication administration records via SQL from `openclinica.formdata`, parsing nested JSON for `systemic_therapy_administration_form`. Filters by `ma_site` for cancer type. Returns an empty tribble with expected columns when no results are found.

**New function: `get_med_admin_db()`** (lines 122--153)
Pulls structured medication data from `production.gold.medication_flat` via Databricks. Uses `maps.rxnorm_kbtherapy` to translate therapy regex into RxNorm codes (generic + ingredient), then filters `medication_flat` to matching codes and "Inpatient"/"Outpatient" categories.

**New function: `clean_med_admin_oc()`** (lines 321--354)
Cleans OC data: imputes dates, maps OC coded values, normalizes therapy names, handles "trial drug" standardization.

**New function: `clean_med_admin_db()`** (lines 385--437)
Cleans Databricks data using the same pattern as `clean_med_admin_spmd()`: date conversion, diagnosis date filtering, exact + regex therapy matching, route normalization.

**Modified: `clean_med_admin_spmd()`** (lines 248--306)
Removed the `is.na(coalesce(startdate, enddate))` arm from the date filter, meaning undated SPMD records are now dropped.

**Modified: `wrangle_med_admin()`** (lines 453--534)
Now accepts three inputs (`.data_spmd`, `.data_oc`, `.data_db`). Implements source priority logic: OC "Yes" patients get OC data only; structured data is kept only for patients without OC data. Renames columns from all three sources to ADS standard names. Derives `med_admin_flag` via `case_when` within each patient group. Adds `admin_source`.

**Modified: `derive_med_admin()`** (lines 568--630)
Now accepts `cancer` and `db` parameters. Internally routes patients to the correct data source by `sourcename`. Orchestrates all three pipelines, calls `wrangle_med_admin()`, nests the result, and uses two `right_join` operations to ensure all patients (including those with no admin data and those with no systemic therapy) get a row with an appropriate `med_admin_flag`.

### ads/datasets/ (bladder.R, breast.R, lung.R, ovarian.R)

All four tumor files updated to pass `cancer`, `db`, and a broader patient set to `derive_med_admin()`. The patient population is expanded from aurora/ascension-only to all enriched patients.

### ads/utilities/definitions.R

Added `db <- connect_databricks_odbc()` at line 15 to establish a Databricks connection available to all downstream scripts. Added commented-out route normalization map script at end of file.

### ads/whitelist/all_tumor.json

Two new entries added:
- `med_admin_flag`: patient-level, non-internal, all four tumors
- `admin_source`: nested within `medication_administration`, non-internal, all four tumors

---

## Code Review Findings

### BLOCKING

**B1. `wrangle_med_admin()` -- `missing_admin_oc` patients who have Databricks data are not excluded from OC rows**

File: `ads/utilities/functions/med_admin.R`, lines 471--478

The source priority logic correctly excludes OC "missing admin" patients who have SPMD data (line 474: `anti_join(.data_spmd, by = "patientid")`), but it does NOT exclude OC "missing admin" patients who have Databricks data. This means an Advent/BH/MLH patient whose OC says "Unknown" or "No" for administrations available, but who HAS structured data in Databricks, will retain both their OC "missing" row AND their Databricks structured rows. The OC "missing" row will pull the `med_admin_flag` toward "Admins not available" via the `case_when` in lines 524--531, since "No..." and "Unknown" are checked after "Has admins - structured".

However, reviewing the `case_when` logic more carefully: the `any()` aggregation means that if a patient has ANY row with `med_admin_flag == "Has admins - structured"` (from DB data), the `case_when` will resolve to "Has admins - structured" before it hits the "Admins not available" branch. So the `med_admin_flag` derivation itself is protected by the priority ordering.

The concern is that the OC "missing" row (with NA therapy name, NA dates) will be present in the `medication_administration` nested data frame alongside the legitimate Databricks records. This is a data quality issue -- these OC placeholder rows carry `admin_source = "ma"` and mostly-NA clinical data. They should be excluded when the patient has structured data.

**Suggested fix** -- `ads/utilities/functions/med_admin.R`, lines 471--478:

```r
  .data_oc <- bind_rows(
    has_admin_oc,
    missing_admin_oc %>%
      anti_join(.data_spmd, by = "patientid") %>%
      anti_join(.data_db, by = "patientid")
    ) %>%
    mutate(
      admin_source = "ma"
    )
```

**B2. `get_med_admin_db()` -- `ingredient_codes` not bang-bang quoted in `dbplyr` filter**

File: `ads/utilities/functions/med_admin.R`, line 144

The filter `ingredient_code %in% ingredient_codes` passes a local R vector (`ingredient_codes`) to a `dbplyr` lazy table without `!!` forcing. Compare with `generic_code %in% !!codes$generic_code` on the same line, which correctly uses `!!`. Depending on the `dbplyr`/`odbc` version, this may silently fail to filter (treating `ingredient_codes` as a column name rather than a value vector), return zero rows, or error.

**Suggested fix** -- `ads/utilities/functions/med_admin.R`, line 144:

```r
    filter(patientid %in% patients &
             (generic_code %in% !!codes$generic_code | ingredient_code %in% !!ingredient_codes) &
             # per Epic FHIR spec, these make the most sense for admins: https://fhir.epic.com/Specifications?api=997
             category_admin %in% c("Inpatient", "Outpatient")) %>%
```

This is particularly critical given the known RxCUI coverage gap. If `generic_code` is NA for Advent/MLH patients, the only path to matching records is through `ingredient_code`, and if that path is broken by the missing `!!`, zero records will be returned for those health systems.

### WARNING

**W1. Inconsistent patient input across tumor files -- bladder/ovarian vs. breast/lung**

Files: `ads/datasets/bladder.R` line 1190, `ads/datasets/ovarian.R` line 843, `ads/datasets/breast.R` line 1696, `ads/datasets/lung.R` line 550

Bladder and ovarian pass `key_data %>% filter(enriched_cohort_flag)`, while breast and lung pass `patients_enriched %>% left_join(morphology %>% select(patientid, sourcename), by = "patientid")`.

The concern is whether `key_data %>% filter(enriched_cohort_flag)` reliably contains `sourcename`. The RAG confirms that `key_data` in bladder contains `sourcename` as a key variable (from the output variables table: `patientid`, `tumorid`, `sourcename`, `suborg`, `enriched_cohort_flag`, `cohort`). Ovarian's `key_data` likely has the same structure.

However, the breast/lung approach explicitly joins `sourcename` from `morphology`, suggesting that `patients_enriched` alone does NOT contain `sourcename` in those tumors. If `key_data` in bladder/ovarian does contain `sourcename`, then the approaches are functionally equivalent but inconsistent in style.

If bladder/ovarian's `key_data` does NOT contain `sourcename` (or if it is ever refactored to drop it), `derive_med_admin()` will fail at line 571 (`filter(sourcename %in% c("aurora", "ascension"))`) with a column-not-found error. The breast/lung approach is more defensive.

**Suggested fix** -- Verify that `bladder_ads$key_data` and `ovarian_ads$key_data` contain `sourcename` after filtering by `enriched_cohort_flag`. If they do, this is a NOTE (inconsistent style). If they do not, this is BLOCKING. The reviewer should confirm by inspecting the objects at runtime or checking how `key_data` is constructed upstream.

**W2. `clean_med_admin_db()` receives unfiltered `sys_tx` -- unnecessary computation**

File: `ads/utilities/functions/med_admin.R`, line 613

In `derive_med_admin()`, the call `clean_med_admin_db(sys_tx = sys_tx, ...)` passes the full `sys_tx` (all patients across all health systems), rather than filtering to `advent_bh_mlh` patients. This means `patient_regexes` in `clean_med_admin_db()` (line 408) computes regex patterns for aurora/ascension patients that will never match any Databricks records.

This is not a correctness issue -- the `inner_join` on `patientid` in line 416 ensures only relevant patients match. However, it wastes memory and CPU constructing regexes for patients that cannot appear in the data.

**Suggested fix** -- `ads/utilities/functions/med_admin.R`, line 613:

```r
    clean_med_admin_db(sys_tx = sys_tx %>% filter(patientid %in% advent_bh_mlh),
                       diagnosis = diagnosis,
                       spmd = spmd)
```

This mirrors the pattern already used for SPMD at line 586: `sys_tx %>% filter(patientid %in% aurora_ascension)`.

**W3. `get_med_admin_db()` -- `maps.rxnorm_kbtherapy` schema reference**

File: `ads/utilities/functions/med_admin.R`, line 126

The function queries `tbl(spmd, in_schema("maps", "rxnorm_kbtherapy"))`. The ticket notes reference `spmd_sqa.maps.rxnorm_kbtherapy`. The `spmd` connection defaults to `spmd_con()` which connects to the production SPMD. Verify that the `maps.rxnorm_kbtherapy` table exists in the production SPMD schema, or whether this should be querying an SQA-specific connection. If the table only exists in SQA, this query will fail in production/Airflow.

**W4. Typo in `@param` documentation: "Heatlh" should be "Health"**

File: `ads/utilities/functions/med_admin.R`, line 110

```
#' BayHealth, and Main Line Heatlh patients in the ADS.
```

Minor, but should be corrected for documentation quality.

**Suggested fix** -- `ads/utilities/functions/med_admin.R`, line 110:

```r
#' BayHealth, and Main Line Health patients in the ADS.
```

**W5. Docstring typo: "on our after" should be "on or after"**

File: `ads/utilities/functions/med_admin.R`, lines 228 and 366

This typo appears twice in the file (once in `clean_med_admin_spmd()` and once in `clean_med_admin_db()`):

```
#' An administration is considered a match if it occurs on our after the patient's diagnosis date
```

**Suggested fix** -- Both occurrences:

```r
#' An administration is considered a match if it occurs on or after the patient's diagnosis date
```

**W6. `clean_med_admin_oc()` -- `administrationsavilable` misspelling propagated**

File: `ads/utilities/functions/med_admin.R`, lines 88, 325, 338, 456--462, 496, 527--529

The variable name `administrationsavilable` (missing second "a" -- should be "administrationsAvailable") is propagated from the OC source data. This is likely an upstream data artifact (the OC form field is literally spelled this way), so it cannot be renamed without breaking the pipeline. However, it should be documented clearly in comments so future developers understand this is intentional, not a code typo.

**W7. `derive_med_admin()` docstring typo: "medication_admnistration"**

File: `ads/utilities/functions/med_admin.R`, line 538

```
#' `derive_med_admin()` derives the nested `medication_admnistration` data frame
```

Should be `medication_administration`.

**Suggested fix** -- `ads/utilities/functions/med_admin.R`, line 538:

```r
#' `derive_med_admin()` derives the nested `medication_administration` data frame that matches the input
```

**W8. DB therapy regex excludes "other", "unknown", "trial drug" but SPMD regex does not**

File: `ads/utilities/functions/med_admin.R`, line 605 vs. line 578

The Databricks therapy regex (line 605) includes an additional filter:
```r
filter(!therapy_name_clean %in% c("other", "unknown", "trial drug")) %>%
```

The SPMD therapy regex (line 578) does not have this filter. This means the SPMD pull may attempt to match generic terms like "other" and "unknown" in the `mdr.medication_medications` table, while the Databricks pull intentionally excludes them. If this asymmetry is intentional (e.g., the SPMD drugproduct normalization via `ca.map_drugproduct` handles these), it should be documented. If not, the SPMD regex should also exclude these terms.

### NOTE

**N1. Removal of undated records from `clean_med_admin_spmd()` is a behavior change**

File: `ads/utilities/functions/med_admin.R`, lines 269--270

The original code included undated SPMD records:
```r
filter(startdate >= diagnosis_date |
         enddate >= diagnosis_date |
         is.na(coalesce(startdate, enddate)))
```

The new code drops them:
```r
filter(startdate >= diagnosis_date |
         enddate >= diagnosis_date)
```

The original comment noted "<1% antineoplastic Aurora/Ascension med admins are undated." This is a minor data loss. The docstring was updated to remove the "or is undated" language, confirming this is intentional. Low risk but worth noting for completeness.

**N2. `clean_med_admin_oc()` filters out `agentstartdate_granularity == "NONE"` with comment "assuming the admin data is not available"**

File: `ads/utilities/functions/med_admin.R`, line 332

This assumption should be validated. If a patient has an OC record with `administrationsavilable == "Yes"` but `agentstartdate_granularity == "NONE"`, they will lose that record. The comment acknowledges the assumption but it would be stronger with a data-backed justification.

**N3. NEWS.md references #339 and #340 but the branch is ADS-402**

File: `NEWS.md`, lines 10, 13, 17, 24

The NEWS entries reference ticket numbers #339 and #340 rather than #402. These may be PR numbers or sub-task numbers. Verify these are the correct cross-references per the team's convention.

**N4. `definitions.R` -- commented-out route normalization code**

File: `ads/utilities/definitions.R`, lines 510--516

Commented-out code for writing `map_admin_route` to SPMD. This is fine as a developer reference but should eventually be removed or moved to a migration script to keep `definitions.R` clean.

**N5. `get_med_admin_oc()` -- SQL injection risk with `glue::glue()` and `cancer` parameter**

File: `ads/utilities/functions/med_admin.R`, line 76

The `cancer` parameter is interpolated directly into a SQL string via `glue::glue()`. In practice, this is called with hardcoded cancer names ("bladder", "breast", "lung", "ovarian") from the tumor scripts, so the risk is negligible. However, parameterized queries would be more defensive.

**N6. `get_med_admin_db()` -- no explicit `collect()` timing comment**

File: `ads/utilities/functions/med_admin.R`, lines 142--152

The function correctly calls `collect()` at line 152 after server-side filtering. Worth a brief comment noting that filtering happens server-side before collection, consistent with the codebase's convention of documenting `collect()` boundaries.

---

## Strengths

1. **Clean three-source architecture.** The `_spmd`, `_oc`, and `_db` suffix convention makes the pipeline easy to follow. Each source has a matched `get_` and `clean_` function, and `wrangle_med_admin()` serves as the single integration point. This is well-designed for maintainability.

2. **Robust source priority logic.** The OC-over-structured priority is implemented correctly at the patient level. Patients with abstracted data get abstracted data; structured data is used only when OC data is absent. The `case_when` in `wrangle_med_admin()` correctly orders the priority (abstracted > structured > not available).

3. **Comprehensive `med_admin_flag` derivation.** The two-stage `right_join` pattern in `derive_med_admin()` (lines 622--629) ensures every patient gets a flag, including those with no systemic therapy at all. The four-level classification is well-designed and clearly documented in NEWS.md.

4. **Consistent pattern reuse.** `clean_med_admin_db()` closely mirrors `clean_med_admin_spmd()` in its date conversion, diagnosis date filtering, exact/regex matching, and route normalization. This makes the code predictable and reduces the cognitive load for reviewers.

5. **Good defensive coding in `get_med_admin_oc()`.** The empty tribble fallback (lines 85--103) ensures downstream functions always receive a data frame with the expected columns, even when no OC records exist for a cancer site.

6. **Thorough NEWS.md documentation.** Both user-facing and developer-facing changes are clearly described with the correct level of detail. The user section explains what the variables mean and their limitations; the developer section explains the three-source architecture.

7. **Whitelist entries correctly placed.** `med_admin_flag` is correctly marked as a patient-level (non-nested) variable, and `admin_source` is correctly marked as a nested variable within `medication_administration`.

---

## Weaknesses and Concerns

1. **Known RxCUI coverage gap severely limits Databricks utility.** Per ticket comments, Advent and MLH have zero RxCUI coverage in `medication_flat` (always NA), and BayHealth has only ~30%. Combined with the potential `!!` bug (B2), the Databricks pipeline may return zero or near-zero records for two of the three target health systems. While this is a known upstream data issue, the practical impact is that the ADS-402 deliverable may not materially change the data for Advent and MLH patients until the upstream issue is resolved.

2. **The `missing_admin_oc` / Databricks interaction gap (B1)** means OC placeholder rows could leak into the nested `medication_administration` data frame for Advent/BH/MLH patients with structured data. This could confuse downstream consumers.

3. **No explicit handling of the case where `therapy_regex` is empty.** If `advent_bh_mlh` contains patients but none have abstracted systemic therapies, `therapy_regex` will be `""` (empty string). `build_med_regex("")` behavior depends on its implementation -- if it passes an empty regex to `get_med_admin_db()`, the `grepl` filter in `get_med_admin_db()` could match all records or error. The same concern exists for the SPMD path if `aurora_ascension` patients exist but have no therapies, though this is an existing condition. Worth verifying `build_med_regex()` handles empty input gracefully.

4. **`clean_med_admin_oc()` does not filter to patients' systemic therapies.** Unlike `clean_med_admin_spmd()` and `clean_med_admin_db()`, which match administrations to the patient's abstracted systemic therapies via exact/regex matching, `clean_med_admin_oc()` keeps all OC administration records regardless of whether they match `sys_tx`. This is likely intentional -- OC data is already manually abstracted and curated -- but means the OC path can contain therapies not in `systemic_therapy`, which could surprise downstream consumers expecting alignment between the two data frames.

---

## Required Changes Summary

1. **B1.** Add `anti_join(.data_db, by = "patientid")` to the `missing_admin_oc` filter in `wrangle_med_admin()` to prevent OC placeholder rows from leaking into the nested data frame for patients with Databricks structured data. (`med_admin.R`, line 474)

2. **B2.** Add `!!` before `ingredient_codes` in the `dbplyr` filter in `get_med_admin_db()` to ensure the local R vector is correctly passed to the SQL translation layer. (`med_admin.R`, line 144)
