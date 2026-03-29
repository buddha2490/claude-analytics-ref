# =============================================================================
# Program:    sim_vs.R
# Purpose:    Simulate SDTM VS (Vital Signs) domain for NPM-008 / XB010-101
# Domain:     VS
# Author:     r-clinical-programmer agent
# Date:       2026-03-28
# seed:       set.seed(48)  (VS is domain order 6; 42 + 6 = 48)
# Wave:       1
# Plan:       Section 4.6 (VS — Vital Signs)
# =============================================================================

library(tidyverse)
library(haven)

# --- Constants ----------------------------------------------------------------

STUDYID <- "NPM008"
SEED    <- 48L

# --- Load DM spine ------------------------------------------------------------

dm <- readRDS("output-data/sdtm/dm.rds") %>%
  dplyr::select(USUBJID, RFSTDTC)

n <- nrow(dm)  # 40 subjects

message("=== Simulating VS (Vital Signs) Domain ===")
message("Loaded DM: ", n, " subjects")

# --- Truncation helper --------------------------------------------------------

#' Truncate a numeric vector to the interval [lo, hi].
#' Values outside the range are replaced with the boundary value.
truncate_vals <- function(x, lo, hi) {
  pmin(pmax(x, lo), hi)
}

# --- Simulate baseline values for all 9 vital sign tests ---------------------

set.seed(SEED)

bl <- dm %>%
  dplyr::mutate(
    # Heart Rate
    HR_bl    = truncate_vals(rnorm(n, 78,    12),   50,   120),

    # Blood Pressure
    SYSBP_bl = truncate_vals(rnorm(n, 128,   15),   90,   180),
    DIABP_bl = truncate_vals(rnorm(n, 78,    10),   55,   110),

    # Oxygen Saturation
    SPO2_bl  = truncate_vals(rnorm(n, 96,     2),   88,   100),

    # Respiratory Rate
    RESP_bl  = truncate_vals(rnorm(n, 17,     2),   12,    25),

    # Body Temperature (degrees F)
    TEMP_bl  = truncate_vals(rnorm(n, 98.4,   0.5), 97,   100.5),

    # Height (constant across visits)
    HT_bl    = truncate_vals(rnorm(n, 170,   10),  150,   200),

    # Weight
    WT_bl    = truncate_vals(rnorm(n, 75,    15),   45,   130),

    # BMI derived from baseline WT and HT
    BMI_bl   = WT_bl / (HT_bl / 100)^2
  )

# --- Simulate follow-up values ------------------------------------------------

# Follow-up values are generated in a separate mutate so that the random draws
# are independent and ordered consistently after all baseline draws.
bl <- bl %>%
  dplyr::mutate(
    HR_fu    = truncate_vals(HR_bl    + rnorm(n, 0,   5),   50,  120),
    SYSBP_fu = truncate_vals(SYSBP_bl + rnorm(n, 0,   8),   90,  180),
    DIABP_fu = truncate_vals(DIABP_bl + rnorm(n, 0,   6),   55,  110),
    SPO2_fu  = truncate_vals(SPO2_bl  + rnorm(n, 0,   1),   88,  100),
    RESP_fu  = truncate_vals(RESP_bl  + rnorm(n, 0,   1),   12,   25),
    TEMP_fu  = truncate_vals(TEMP_bl  + rnorm(n, 0,   0.3), 97,  100.5),
    HT_fu    = HT_bl,   # height is constant
    WT_fu    = truncate_vals(WT_bl * rnorm(n, 0.97, 0.03),  45,  130),
    BMI_fu   = WT_fu / (HT_fu / 100)^2
  )

# --- Reshape to long format: one row per subject × test × visit ---------------

# Test metadata lookup table
vs_meta <- tibble::tribble(
  ~VSTESTCD, ~VSTEST,                      ~VSORRESU,
  "HR",      "Heart Rate",                 "beats/min",
  "SYSBP",   "Systolic Blood Pressure",    "mmHg",
  "DIABP",   "Diastolic Blood Pressure",   "mmHg",
  "SPO2",    "Oxygen Saturation",          "%",
  "RESP",    "Respiratory Rate",           "breaths/min",
  "TEMP",    "Body Temperature",           "degrees F",
  "HT",      "Height",                     "cm",
  "WT",      "Weight",                     "kg",
  "BMI",     "Body Mass Index",            "kg/m2"
)

# Pivot baseline values to long
bl_long <- bl %>%
  dplyr::select(USUBJID, RFSTDTC,
    HR = HR_bl, SYSBP = SYSBP_bl, DIABP = DIABP_bl, SPO2 = SPO2_bl,
    RESP = RESP_bl, TEMP = TEMP_bl, HT = HT_bl, WT = WT_bl, BMI = BMI_bl) %>%
  tidyr::pivot_longer(
    cols      = -c(USUBJID, RFSTDTC),
    names_to  = "VSTESTCD",
    values_to = "VSSTRESN_raw"
  ) %>%
  dplyr::mutate(VISIT = "BASELINE")

# Pivot follow-up values to long
fu_long <- bl %>%
  dplyr::select(USUBJID, RFSTDTC,
    HR = HR_fu, SYSBP = SYSBP_fu, DIABP = DIABP_fu, SPO2 = SPO2_fu,
    RESP = RESP_fu, TEMP = TEMP_fu, HT = HT_fu, WT = WT_fu, BMI = BMI_fu) %>%
  tidyr::pivot_longer(
    cols      = -c(USUBJID, RFSTDTC),
    names_to  = "VSTESTCD",
    values_to = "VSSTRESN_raw"
  ) %>%
  dplyr::mutate(VISIT = "FOLLOWUP")

# --- Bind visits, compute derived variables, and build VSDTC -----------------

vs_raw <- dplyr::bind_rows(bl_long, fu_long) %>%
  # Round all numeric values to 1 decimal place
  dplyr::mutate(
    VSSTRESN = round(VSSTRESN_raw, 1)
  ) %>%
  # Derive VSDTC from RFSTDTC per visit
  dplyr::mutate(
    VSDTC = dplyr::case_when(
      VISIT == "BASELINE" ~ as.character(as.Date(RFSTDTC) - 7L),
      VISIT == "FOLLOWUP" ~ as.character(as.Date(RFSTDTC) + 42L)
    )
  ) %>%
  # Join test metadata
  dplyr::left_join(vs_meta, by = "VSTESTCD") %>%
  # VSSTRESU mirrors VSORRESU for these tests (same units)
  dplyr::mutate(VSSTRESU = VSORRESU) %>%
  # VSORRES and VSSTRESC are character representations of VSSTRESN
  dplyr::mutate(
    VSORRES  = as.character(VSSTRESN),
    VSSTRESC = VSORRES
  )

# --- Assign VSSEQ: sequential integer within each USUBJID --------------------
# Sort order: USUBJID, then VISIT (BASELINE before FOLLOWUP), then test order
# Test order is preserved by factor levels matching vs_meta row order.

test_order <- vs_meta$VSTESTCD

vs_final <- vs_raw %>%
  dplyr::mutate(
    VSTESTCD_fct = factor(VSTESTCD, levels = test_order),
    VISIT_fct    = factor(VISIT, levels = c("BASELINE", "FOLLOWUP"))
  ) %>%
  dplyr::arrange(USUBJID, VISIT_fct, VSTESTCD_fct) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(VSSEQ = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  # --- Select and order final variables per spec ----------------------------
  dplyr::mutate(
    STUDYID = STUDYID,
    DOMAIN  = "VS"
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, VSSEQ, VSTESTCD, VSTEST,
    VSORRES, VSORRESU, VSSTRESC, VSSTRESN, VSSTRESU,
    VISIT, VSDTC
  )

# --- Validate row count -------------------------------------------------------

expected_rows <- 40L * 9L * 2L

if (nrow(vs_final) != expected_rows) {
  stop(
    "Row count mismatch: expected ", expected_rows,
    " but got ", nrow(vs_final), ".",
    call. = FALSE
  )
}

message("VS row count: ", nrow(vs_final), " (expected ", expected_rows, ")")

# --- Physiological bounds check -----------------------------------------------

check_bounds <- function(df, testcd, lo, hi) {
  vals <- df %>%
    dplyr::filter(VSTESTCD == testcd) %>%
    dplyr::pull(VSSTRESN)
  if (any(vals < lo | vals > hi, na.rm = TRUE)) {
    stop("Out-of-bounds values detected for ", testcd,
         ": range [", lo, ", ", hi, "]", call. = FALSE)
  }
  invisible(NULL)
}

check_bounds(vs_final, "HR",    50,   120)
check_bounds(vs_final, "SYSBP", 90,   180)
check_bounds(vs_final, "DIABP", 55,   110)
check_bounds(vs_final, "SPO2",  88,   100)
check_bounds(vs_final, "RESP",  12,    25)
check_bounds(vs_final, "TEMP",  97,   100.5)
check_bounds(vs_final, "HT",   150,   200)
check_bounds(vs_final, "WT",    45,   130)
check_bounds(vs_final, "BMI",   10,    50)

message("All physiological bounds checks passed.")

# --- Variable labels for xportr -----------------------------------------------

vs_labels <- c(
  STUDYID  = "Study Identifier",
  DOMAIN   = "Domain Abbreviation",
  USUBJID  = "Unique Subject Identifier",
  VSSEQ    = "Sequence Number",
  VSTESTCD = "Vital Signs Test Short Name",
  VSTEST   = "Vital Signs Test Name",
  VSORRES  = "Result or Finding in Original Units",
  VSORRESU = "Original Units",
  VSSTRESC = "Character Result/Finding in Std Format",
  VSSTRESN = "Numeric Result/Finding in Standard Units",
  VSSTRESU = "Standard Units",
  VISIT    = "Visit Name",
  VSDTC    = "Date/Time of Measurements"
)

# --- Apply xportr labels and write outputs ------------------------------------

# Apply SAS variable labels via the "label" column attribute that haven respects
vs_labelled <- vs_final
for (v in names(vs_labels)) {
  if (v %in% names(vs_labelled)) {
    attr(vs_labelled[[v]], "label") <- vs_labels[[v]]
  }
}

# Save RDS
saveRDS(vs_labelled, "output-data/sdtm/vs.rds")
message("✓ Saved: output-data/sdtm/vs.rds")

# Save XPT
haven::write_xpt(vs_labelled, path = "output-data/sdtm/vs.xpt", version = 5)
message("✓ Saved: output-data/sdtm/vs.xpt")

# --- Final summary ------------------------------------------------------------

message("\n--- VS Summary Statistics ---")

summary_tbl <- vs_final %>%
  dplyr::group_by(VSTESTCD, VISIT) %>%
  dplyr::summarise(
    n     = dplyr::n(),
    min   = min(VSSTRESN, na.rm = TRUE),
    mean  = round(mean(VSSTRESN, na.rm = TRUE), 1),
    max   = max(VSSTRESN, na.rm = TRUE),
    .groups = "drop"
  )

print(summary_tbl, n = 20)

message("\n=== VS Domain Complete ===")
