# =============================================================================
# Program:  tfl_histology_by_month_2025.R
# Date:     2026-03-26
# Purpose:  Cross-tabulate lung cancer histology subgroup by month of diagnosis
#           for calendar year 2025 and write a formatted RTF table.
#           One row per patient (earliest diagnosis); all 12 months guaranteed.
# Output:   output/histology_by_month_2025.rtf
# =============================================================================

library(dplyr)
library(tidyr)
library(lubridate)
library(forcats)
library(huxtable)
library(pharmaRTF)
library(syhelpr)

# --- Section 1: Data pull (server-side filtered) ----------------------------

# Filter and select on the remote before collect() to minimise data transfer.
# Three columns only: patientid, diagnosis_date, histology_subgroup.
raw_df <- get_ads("lung", type = "enriched") %>%
  dplyr::filter(
    diagnosis_date >= as.Date("2025-01-01"),
    diagnosis_date <  as.Date("2026-01-01")
  ) %>%
  dplyr::select(patientid, diagnosis_date, histology_subgroup) %>%
  collect()

message(
  "Pulled ", nrow(raw_df), " rows, ",
  dplyr::n_distinct(raw_df$patientid), " unique patients before dedup"
)

# --- Section 2: Input validation --------------------------------------------

required_cols <- c("patientid", "diagnosis_date", "histology_subgroup")
missing_cols  <- setdiff(required_cols, names(raw_df))
if (length(missing_cols) > 0) {
  stop(
    "Required columns not found in ADS: ",
    paste(missing_cols, collapse = ", "),
    call. = FALSE
  )
}

if (nrow(raw_df) == 0) {
  stop(
    "Zero rows returned after server-side filter. ",
    "No lung ADS patients with diagnosis_date in 2025.",
    call. = FALSE
  )
}

# --- Section 3: Handle missing diagnosis dates ------------------------------

n_na_date <- sum(is.na(raw_df$diagnosis_date))
if (n_na_date > 0) {
  warning(
    n_na_date, " row(s) have NA diagnosis_date and will be excluded.",
    call. = FALSE
  )
}

analysis_df <- raw_df %>%
  dplyr::filter(!is.na(diagnosis_date))

# --- Section 4: Deduplicate to one row per patient --------------------------
# Keep earliest diagnosis per patient. slice_min() with with_ties = FALSE
# guarantees exactly one row even when two records share the same earliest date.

dedup_df <- analysis_df %>%
  dplyr::group_by(patientid) %>%
  dplyr::slice_min(diagnosis_date, n = 1, with_ties = FALSE) %>%
  dplyr::ungroup()

message(
  "After dedup: ", nrow(dedup_df), " unique patients retained"
)

# --- Section 5: Derive month variable ----------------------------------------
# month(label = TRUE, abbr = TRUE) returns an ordered factor with levels Jan-Dec.
# Re-specify levels explicitly against month.abb so calendar order holds
# regardless of locale or which months are actually present in the data.

dedup_df <- dedup_df %>%
  dplyr::mutate(
    dx_month = lubridate::month(diagnosis_date, label = TRUE, abbr = TRUE),
    dx_month = forcats::fct_relevel(dx_month, month.abb)
  )

# --- Section 6: Cross-tabulate and zero-fill all 12 months ------------------
# complete() guarantees every combination of histology x month exists before
# pivot_wider, so months with zero counts appear as 0, not NA.

count_df <- dedup_df %>%
  dplyr::count(histology_subgroup, dx_month) %>%
  tidyr::complete(
    histology_subgroup,
    dx_month = factor(month.abb, levels = month.abb),
    fill = list(n = 0L)
  ) %>%
  tidyr::pivot_wider(
    names_from  = dx_month,
    values_from = n,
    values_fill = 0L
  )

# --- Section 7: Add Total column and Total row ------------------------------

# Ensure all 12 month columns are present (complete() guarantees this, but be
# explicit so column selection below is safe regardless of data sparsity).
month_cols <- month.abb[month.abb %in% names(count_df)]

# Total column: row-wise sum across month columns
count_df <- count_df %>%
  dplyr::mutate(
    Total = rowSums(dplyr::across(dplyr::all_of(month_cols)), na.rm = TRUE)
  )

# Sort rows by descending total count; most common histologies appear first
count_df <- count_df %>%
  dplyr::arrange(dplyr::desc(Total))

# Total row: column-wise sum across all numeric columns
total_row <- count_df %>%
  dplyr::summarise(
    histology_subgroup = "Total",
    dplyr::across(dplyr::all_of(c(month_cols, "Total")), sum)
  )

final_df <- dplyr::bind_rows(count_df, total_row)

n_histology_nonzero <- count_df %>%
  dplyr::filter(Total > 0) %>%
  nrow()

message(
  "Table contains ", nrow(count_df), " histology subgroup(s); ",
  n_histology_nonzero, " with at least one 2025 diagnosis. ",
  "Total unique patients: ", sum(count_df$Total)
)

# --- Section 8: Build huxtable ----------------------------------------------

hux_tbl <- huxtable::as_hux(final_df, add_colnames = TRUE)

# Column alignment: left for histology label, right for all numeric counts
huxtable::align(hux_tbl)[, 1]                             <- "left"
huxtable::align(hux_tbl)[, seq(2, ncol(hux_tbl))]        <- "right"

# Bold header row
huxtable::bold(hux_tbl)[1, ]                              <- TRUE

# Bold histology label column (first column, all rows including header)
huxtable::bold(hux_tbl)[, 1]                              <- TRUE

# Bold Total row (last row)
huxtable::bold(hux_tbl)[nrow(hux_tbl), ]                  <- TRUE

# Top border on header row; bottom border on last data row before Total row
huxtable::top_border(hux_tbl)[1, ]                        <- 0.8
huxtable::bottom_border(hux_tbl)[1, ]                     <- 0.4
huxtable::bottom_border(hux_tbl)[nrow(hux_tbl) - 1, ]    <- 0.4
huxtable::bottom_border(hux_tbl)[nrow(hux_tbl), ]         <- 0.8

# Font size
huxtable::font_size(hux_tbl)                              <- 9

# Column widths: proportionally wider for label column, narrow for months
n_cols  <- ncol(hux_tbl)
col_wts <- c(3, rep(1, n_cols - 2), 1.5)   # label | 12 months | Total
col_wts <- col_wts / sum(col_wts)
huxtable::col_width(hux_tbl)                               <- col_wts

# Table caption — namespace-qualified to resolve huxtable/pharmaRTF conflict
hux_tbl <- huxtable::set_caption(
  hux_tbl,
  "Table X: New Diagnoses by Histology Subgroup and Month of Diagnosis (2025)"
)

# --- Section 9: Write RTF via pharmaRTF ------------------------------------

output_dir  <- "output"
output_file <- file.path(output_dir, "histology_by_month_2025.rtf")

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

rtf_doc <- pharmaRTF::rtf_doc(hux_tbl) %>%
  pharmaRTF::set_font_size(9) %>%
  pharmaRTF::set_orientation("landscape") %>%
  pharmaRTF::set_margins(top = 1, bottom = 1, left = 1, right = 1)

# Namespace-qualified: pharmaRTF::set_header_rows if header rows need marking
# (none needed here — huxtable header row is handled above)

pharmaRTF::write_rtf(rtf_doc, file = output_file)

message("RTF written to: ", output_file)
message(
  "Done. ",
  sum(count_df$Total), " unique patients | ",
  n_histology_nonzero, " histology subgroup(s) with data | ",
  "output: ", output_file
)
