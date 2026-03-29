# =============================================================================
# sim_ec.R
# Simulate EC (Exposure as Collected) domain for NPM-008 / XB010-101
#
# Inputs:
#   output-data/sdtm/ex.rds  — EX exposure spine
# Output:
#   output-data/sdtm/ec.xpt
#
# Structure:
#   Oral subjects (EXROUTE == "ORAL"):  1 EC record per subject
#   IV subjects:  n_cycles = min(ceiling(treatment_days / 21), 12) records
# =============================================================================

library(tidyverse)
library(haven)

set.seed(52)  # EC is domain order 10: 42 + 10 = 52

# --- Load input data ----------------------------------------------------------

ex <- readRDS("output-data/sdtm/ex.rds")

# --- Helper: parse first numeric value from dose text -------------------------
# Handles "75", "500", "80", "75 + 10" etc. — takes the leading number.
parse_first_dose <- function(x) {
  as.numeric(sub(" .*", "", trimws(x)))
}

# --- Helper: parse first unit from dose unit text ----------------------------
# Handles "mg", "mg/m2", "mg/m2 + mg/kg" — takes the first token.
parse_first_unit <- function(x) {
  sub(" .*", "", trimws(x))
}

# --- Build EC records ---------------------------------------------------------

ec_raw <- ex %>%
  dplyr::mutate(
    # Parse dose and units (first value for combination regimens)
    ECDOSE  = parse_first_dose(EXDOSTXT),
    ECDOSU  = parse_first_unit(EXDOSU),
    is_oral = EXROUTE == "ORAL",
    # Treatment duration in days (used only for IV cycle count)
    treatment_days = as.numeric(as.Date(EXENDTC) - as.Date(EXSTDTC)),
    n_cycles = dplyr::if_else(
      is_oral,
      1L,
      pmin(ceiling(pmax(treatment_days, 1) / 21), 12L)
    )
  )

# Expand rows: one row per cycle per subject
ec_expanded <- ec_raw %>%
  # Create a list-column of cycle indices for each subject
  dplyr::mutate(
    cycle = purrr::map(n_cycles, ~ seq_len(.x))
  ) %>%
  tidyr::unnest(cycle) %>%
  dplyr::mutate(
    # Cycle start date: cycle 1 = EXSTDTC; cycle k = EXSTDTC + (k-1)*21
    ECSTDTC_d = as.Date(EXSTDTC) + (cycle - 1L) * 21L,
    # Cycle end date: ECSTDTC + 20 days (21-day cycle), capped at EXENDTC
    # Last cycle ends at min(ECSTDTC + 20, EXENDTC)
    ECENDTC_d = pmin(ECSTDTC_d + 20L, as.Date(EXENDTC)),
    ECSTDTC   = as.character(ECSTDTC_d),
    ECENDTC   = as.character(ECENDTC_d)
  )

# --- Assemble final EC dataset ------------------------------------------------

ec <- ec_expanded %>%
  dplyr::arrange(USUBJID, cycle) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(ECSEQ = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  dplyr::transmute(
    STUDYID = "NPM008",
    DOMAIN  = "EC",
    USUBJID,
    ECSEQ,
    ECLNKID = "1",
    ECTRT   = EXTRT,
    ECDOSE,
    ECDOSU,
    ECROUTE = EXROUTE,
    ECSTDTC,
    ECENDTC
  )

# --- Apply variable labels ---------------------------------------------------

var_labels <- list(
  STUDYID = "Study Identifier",
  DOMAIN  = "Domain Abbreviation",
  USUBJID = "Unique Subject Identifier",
  ECSEQ   = "Sequence Number",
  ECLNKID = "Link ID",
  ECTRT   = "Name of Treatment",
  ECDOSE  = "Dose per Administration",
  ECDOSU  = "Dose Units",
  ECROUTE = "Route of Administration",
  ECSTDTC = "Start Date/Time of Treatment",
  ECENDTC = "End Date/Time of Treatment"
)

for (col in names(var_labels)) {
  attr(ec[[col]], "label") <- var_labels[[col]]
}

# --- Validate -----------------------------------------------------------------

message("--- EC Validation ---")

# Join back to EX for boundary checks
check <- ec %>%
  dplyr::left_join(
    ex %>% dplyr::select(USUBJID, EXSTDTC, EXENDTC),
    by = "USUBJID"
  )

# 1. ECSTDTC >= EXSTDTC for all rows
ecstdtc_ok <- all(as.Date(check$ECSTDTC) >= as.Date(check$EXSTDTC))
message("ECSTDTC >= EXSTDTC (all rows): ", ecstdtc_ok)
if (!ecstdtc_ok) {
  warning("Some ECSTDTC values precede EXSTDTC.", call. = FALSE)
}

# 2. ECENDTC <= EXENDTC for all rows
ecendtc_ok <- all(as.Date(check$ECENDTC) <= as.Date(check$EXENDTC))
message("ECENDTC <= EXENDTC (all rows): ", ecendtc_ok)
if (!ecendtc_ok) {
  warning("Some ECENDTC values exceed EXENDTC.", call. = FALSE)
}

# 3. Oral subjects: exactly 1 record each
oral_usubjids <- ex %>%
  dplyr::filter(EXROUTE == "ORAL") %>%
  dplyr::pull(USUBJID)

oral_counts <- ec %>%
  dplyr::filter(USUBJID %in% oral_usubjids) %>%
  dplyr::count(USUBJID)

oral_ok <- all(oral_counts$n == 1L)
message("Oral subjects have exactly 1 record: ", oral_ok)
if (!oral_ok) {
  warning(
    sum(oral_counts$n != 1L),
    " oral subject(s) do not have exactly 1 record.",
    call. = FALSE
  )
}

# 4. IV subjects: 1–12 records each
iv_usubjids <- ex %>%
  dplyr::filter(EXROUTE != "ORAL") %>%
  dplyr::pull(USUBJID)

iv_counts <- ec %>%
  dplyr::filter(USUBJID %in% iv_usubjids) %>%
  dplyr::count(USUBJID)

iv_ok <- all(iv_counts$n >= 1L & iv_counts$n <= 12L)
message("IV subjects have 1–12 records: ", iv_ok)
if (!iv_ok) {
  warning(
    sum(iv_counts$n < 1L | iv_counts$n > 12L),
    " IV subject(s) have out-of-range cycle counts.",
    call. = FALSE
  )
}

message("EC total records: ", nrow(ec))
message("EC unique subjects: ", length(unique(ec$USUBJID)))
message("\nCycle count summary (IV subjects):")
print(summary(iv_counts$n))

# --- Write XPT ---------------------------------------------------------------

saveRDS(ec, "output-data/sdtm/ec.rds")
haven::write_xpt(ec, "output-data/sdtm/ec.xpt")
message("\nWritten to: output-data/sdtm/ec.xpt")
