# =============================================================================
# Program: projects/exelixis-sap/programs/adam_adlot.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADLOT — Line of Therapy
# Author: r-clinical-programmer agent
# Date: 2026-03-28
#
# Source Domains:
#   - DM: USUBJID, STUDYID, RFSTDTC, DTHDTC
#   - EX: USUBJID, EXTRT, EXSTDTC, EXENDTC (index treatment drugs)
#   - CM: USUBJID, CMTRT, CMSTDTC, CMENDTC, CMRSDISC (concomitant meds)
#   - EC: USUBJID, ECTRT, ECSTDTC, ECENDTC (exposure as collected)
#   - DS: USUBJID, DSTERM, DSDECOD, DSSTDTC (disposition for death/dropout)
#
# CDISC References:
#   - ADaM-IG: Line of therapy analysis dataset structure
#   - NPM LoT Algorithm (NSCLC): 45-day window, 120-day gap (SAP)
#   - See artifacts/Open-questions-cdisc.md R5
#
# Dependencies:
#   - None (Wave 1 dataset)
# =============================================================================

library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------

dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
ex <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ex.xpt")
cm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/cm.xpt")
ec <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ec.xpt")
ds <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/ds.xpt")

# --- Data Structure Exploration (Step 4 checkpoint) -------------------------

message("=== Data Structure Exploration ===")
message("DM columns: ", paste(names(dm), collapse = ", "))
message("EX columns: ", paste(names(ex), collapse = ", "))
message("CM columns: ", paste(names(cm), collapse = ", "))
message("EC columns: ", paste(names(ec), collapse = ", "))
message("DS columns: ", paste(names(ds), collapse = ", "))

message("\nDM: ", nrow(dm), " rows, ", n_distinct(dm$USUBJID), " subjects")
message("EX: ", nrow(ex), " rows, ", n_distinct(ex$USUBJID), " subjects")
message("CM: ", nrow(cm), " rows, ", n_distinct(cm$USUBJID), " subjects")
message("EC: ", nrow(ec), " rows, ", n_distinct(ec$USUBJID), " subjects")
message("DS: ", nrow(ds), " rows, ", n_distinct(ds$USUBJID), " subjects")

# Explore key variables
message("\n=== Key Variable Exploration ===")
message("EX treatments (first 10): ", paste(head(unique(ex$EXTRT), 10), collapse = ", "))
message("CM treatments (first 10): ", paste(head(unique(cm$CMTRT), 10), collapse = ", "))
message("EC treatments (first 10): ", paste(head(unique(ec$ECTRT), 10), collapse = ", "))
if (nrow(ds) > 0) {
  message("DS terms (unique): ", paste(unique(ds$DSTERM), collapse = ", "))
  message("DS decodes (unique): ", paste(unique(ds$DSDECOD), collapse = ", "))
}
message("CM CMRSDISC values: ", paste(unique(cm$CMRSDISC), collapse = ", "))

# Date completeness check
message("\n=== Date Completeness ===")
message("EX EXSTDTC missing: ", sum(is.na(ex$EXSTDTC)), " / ", nrow(ex))
message("EX EXENDTC missing: ", sum(is.na(ex$EXENDTC)), " / ", nrow(ex))
message("CM CMSTDTC missing: ", sum(is.na(cm$CMSTDTC)), " / ", nrow(cm))
message("CM CMENDTC missing: ", sum(is.na(cm$CMENDTC)), " / ", nrow(cm))
message("EC ECSTDTC missing: ", sum(is.na(ec$ECSTDTC)), " / ", nrow(ec))
message("EC ECENDTC missing: ", sum(is.na(ec$ECENDTC)), " / ", nrow(ec))

# --- Data Contract Validation (Step 4 Mandatory Checkpoint) -----------------

message("\n=== Data Contract Validation ===")

# Expected variables from plan Section 4.1
plan_vars_dm <- c("USUBJID", "STUDYID", "RFSTDTC", "DTHDTC")
plan_vars_ex <- c("USUBJID", "EXTRT", "EXSTDTC", "EXENDTC")
plan_vars_cm <- c("USUBJID", "CMTRT", "CMSTDTC", "CMENDTC", "CMRSDISC")
plan_vars_ec <- c("USUBJID", "ECTRT", "ECSTDTC", "ECENDTC")
plan_vars_ds <- c("USUBJID", "DSTERM", "DSDECOD", "DSDTC")

actual_vars_dm <- names(dm)
actual_vars_ex <- names(ex)
actual_vars_cm <- names(cm)
actual_vars_ec <- names(ec)
actual_vars_ds <- names(ds)

# Validate DM
missing_vars_dm <- setdiff(plan_vars_dm, actual_vars_dm)
if (length(missing_vars_dm) > 0) {
  stop(
    "Plan lists variables not found in DM: ", paste(missing_vars_dm, collapse = ", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# Validate EX
missing_vars_ex <- setdiff(plan_vars_ex, actual_vars_ex)
if (length(missing_vars_ex) > 0) {
  stop(
    "Plan lists variables not found in EX: ", paste(missing_vars_ex, collapse = ", "),
    "\nActual EX variables: ", paste(actual_vars_ex, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (EX): All ", length(plan_vars_ex), " expected variables found")

# Validate CM
missing_vars_cm <- setdiff(plan_vars_cm, actual_vars_cm)
if (length(missing_vars_cm) > 0) {
  stop(
    "Plan lists variables not found in CM: ", paste(missing_vars_cm, collapse = ", "),
    "\nActual CM variables: ", paste(actual_vars_cm, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (CM): All ", length(plan_vars_cm), " expected variables found")

# Validate EC
missing_vars_ec <- setdiff(plan_vars_ec, actual_vars_ec)
if (length(missing_vars_ec) > 0) {
  stop(
    "Plan lists variables not found in EC: ", paste(missing_vars_ec, collapse = ", "),
    "\nActual EC variables: ", paste(actual_vars_ec, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (EC): All ", length(plan_vars_ec), " expected variables found")

# Validate DS
missing_vars_ds <- setdiff(plan_vars_ds, actual_vars_ds)
if (length(missing_vars_ds) > 0) {
  stop(
    "Plan lists variables not found in DS: ", paste(missing_vars_ds, collapse = ", "),
    "\nActual DS variables: ", paste(actual_vars_ds, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}
message("✓ Data contract OK (DS): All ", length(plan_vars_ds), " expected variables found")

message("\n=== All data contracts validated — proceeding to derivations ===\n")

# --- Step 5: Implement Derivations -------------------------------------------

# REVISIT: NPM LoT algorithm — NSCLC-specific parameters from SAP.
# See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R5
# Parameters: 45-day window, 120-day gap, switching = 'no' (NSCLC)

# NPM LoT Algorithm Parameters (NSCLC)
WINDOW_DAYS <- 45    # Drugs started within 45 days of line start = same line
GAP_DAYS <- 120      # Gap >120 days from ALL drugs = line ends

# Combine all treatment records from EX, CM, EC domains
# EX = index (study) treatment
# CM, EC = other systemic therapies (prior, concurrent, subsequent lines)

# Prepare EX domain (index treatment)
ex_clean <- ex %>%
  dplyr::filter(!is.na(USUBJID), !is.na(EXTRT), !is.na(EXSTDTC)) %>%
  mutate(
    drug = EXTRT,
    start_dtc = EXSTDTC,
    end_dtc = EXENDTC,
    source = "EX"
  ) %>%
  select(USUBJID, drug, start_dtc, end_dtc, source)

# Prepare CM domain (concomitant meds)
# Filter for PRIOR MEDICATIONS only — these contain antineoplastic therapies
# CONCOMITANT MEDICATIONS are supportive care (Ondansetron, Dexamethasone, etc.)
cm_clean <- cm %>%
  dplyr::filter(!is.na(USUBJID), !is.na(CMTRT), !is.na(CMSTDTC),
         CMCAT == "PRIOR MEDICATIONS") %>%
  mutate(
    drug = CMTRT,
    start_dtc = CMSTDTC,
    end_dtc = CMENDTC,
    source = "CM",
    disc_reason = CMRSDISC
  ) %>%
  select(USUBJID, drug, start_dtc, end_dtc, source, disc_reason)

# Prepare EC domain (exposure as collected)
ec_clean <- ec %>%
  dplyr::filter(!is.na(USUBJID), !is.na(ECTRT), !is.na(ECSTDTC)) %>%
  mutate(
    drug = ECTRT,
    start_dtc = ECSTDTC,
    end_dtc = ECENDTC,
    source = "EC"
  ) %>%
  select(USUBJID, drug, start_dtc, end_dtc, source)

# Stack all treatment records
all_rx_raw <- bind_rows(
  ex_clean %>% mutate(disc_reason = NA_character_),
  cm_clean,
  ec_clean %>% mutate(disc_reason = NA_character_)
) %>%
  mutate(
    start_date = as.Date(start_dtc),
    end_date = as.Date(end_dtc)
  ) %>%
  dplyr::filter(!is.na(start_date)) %>%
  arrange(USUBJID, drug, start_date)

message("Total raw treatment records: ", nrow(all_rx_raw))

# Collapse contiguous records for the same drug within each subject
# (e.g., EC domain may have one record per administration cycle)
# Merge records with <= 30-day gaps for the same drug

all_rx <- all_rx_raw %>%
  group_by(USUBJID, drug) %>%
  arrange(start_date) %>%
  mutate(
    # Identify new episodes: gap > 30 days from previous record's end
    gap_days = as.numeric(start_date - dplyr::lag(end_date)),
    new_episode = is.na(gap_days) | gap_days > 30
  ) %>%
  mutate(episode_id = cumsum(new_episode)) %>%
  group_by(USUBJID, drug, episode_id) %>%
  summarize(
    start_dtc = first(start_dtc),
    end_dtc = last(end_dtc),
    start_date = min(start_date),
    end_date = max(end_date),
    # Prioritize EX > CM > EC for source
    source = if_else("EX" %in% source, "EX",
              if_else("CM" %in% source, "CM", "EC")),
    disc_reason = first(na.omit(disc_reason)),  # Keep first non-NA disc_reason
    .groups = "drop"
  ) %>%
  ungroup() %>%
  arrange(USUBJID, start_date, drug)

message("Collapsed treatment episodes: ", nrow(all_rx))
message("Subjects with treatment: ", n_distinct(all_rx$USUBJID))

# --- NPM LoT Algorithm: Group drugs into lines -------------------------------

# REVISIT: NPM LoT algorithm — NSCLC-specific parameters from SAP.
# See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R5
#
# Window: 45 days — drugs started within 45 days of line start date are grouped
# Treatment gap: 120 days — gap of >120 days from ALL drugs ends the line
# Switching: 'no' — adding a new drug does NOT start a new line in NSCLC
# Line start: First valid antineoplastic administration date
# Line end: Latest of: last administration date
#                    OR new drug added outside the 45-day window
#                    OR >120-day gap from all drugs in line
#                    OR death date

# Group treatments into lines per subject
adlot_list <- list()

for (subj in unique(all_rx$USUBJID)) {
  subj_rx <- all_rx %>% filter(USUBJID == subj)

  # Get death date from DM
  death_date <- dm %>%
    dplyr::filter(USUBJID == subj) %>%
    pull(DTHDTC) %>%
    as.Date()

  if (length(death_date) == 0) death_date <- NA

  # Initialize line tracking
  lines <- list()
  current_line <- list(
    drugs = character(),
    start_date = as.Date(NA),
    end_date = as.Date(NA),
    sources = character(),
    disc_reasons = character()
  )

  for (i in seq_len(nrow(subj_rx))) {
    drug_rec <- subj_rx[i, ]
    drug_start <- drug_rec$start_date
    drug_end <- drug_rec$end_date
    if (is.na(drug_end)) drug_end <- drug_start  # If no end date, assume at least start date

    # First drug starts the first line
    if (is.na(current_line$start_date)) {
      current_line$start_date <- drug_start
      current_line$end_date <- drug_end
      current_line$drugs <- drug_rec$drug
      current_line$sources <- drug_rec$source
      current_line$disc_reasons <- drug_rec$disc_reason
      next
    }

    # Check if drug belongs to current line (within window)
    days_from_line_start <- as.numeric(drug_start - current_line$start_date)

    if (days_from_line_start <= WINDOW_DAYS) {
      # Within window — add to current line
      current_line$drugs <- c(current_line$drugs, drug_rec$drug)
      current_line$sources <- c(current_line$sources, drug_rec$source)
      current_line$disc_reasons <- c(current_line$disc_reasons, drug_rec$disc_reason)
      current_line$end_date <- max(current_line$end_date, drug_end, na.rm = TRUE)
    } else {
      # Outside window — check for treatment gap
      days_since_line_end <- as.numeric(drug_start - current_line$end_date)

      # If gap > 120 days OR drug is outside window, start new line
      # Note: For NSCLC switching='no', we still start a new line when outside
      # the 45-day window, even if gap < 120 days. The switching rule applies
      # to drugs WITHIN the window that can be added without triggering a new line.
      if (days_since_line_end > GAP_DAYS) {
        # Gap exceeded — definitely new line
        lines <- append(lines, list(current_line))

        current_line <- list(
          drugs = drug_rec$drug,
          start_date = drug_start,
          end_date = drug_end,
          sources = drug_rec$source,
          disc_reasons = drug_rec$disc_reason
        )
      } else {
        # Gap < 120 days but outside window
        # Per NPM LoT algorithm, this starts a new line
        lines <- append(lines, list(current_line))

        current_line <- list(
          drugs = drug_rec$drug,
          start_date = drug_start,
          end_date = drug_end,
          sources = drug_rec$source,
          disc_reasons = drug_rec$disc_reason
        )
      }
    }
  }

  # Save the last line
  if (!is.na(current_line$start_date)) {
    lines <- append(lines, list(current_line))
  }

  # If subject died, cap the last line end date at death date
  if (!is.na(death_date) && length(lines) > 0) {
    last_line <- lines[[length(lines)]]
    last_line$end_date <- min(last_line$end_date, death_date, na.rm = TRUE)
    lines[[length(lines)]] <- last_line
  }

  # Convert lines to data frame
  if (length(lines) > 0) {
    for (j in seq_along(lines)) {
      line <- lines[[j]]

      # Create regimen: unique drugs sorted alphabetically, separated by ' + '
      unique_drugs <- unique(line$drugs)
      regimen <- paste(sort(unique_drugs), collapse = " + ")

      # Check if this is the index line (drugs appear in EX domain)
      is_index <- any(line$sources == "EX")

      # Get discontinuation reason (first non-NA)
      disc_reason <- line$disc_reasons[!is.na(line$disc_reasons)][1]
      if (length(disc_reason) == 0) disc_reason <- NA_character_

      adlot_list <- append(adlot_list, list(
        tibble(
          USUBJID = subj,
          LOT = j,
          LOTSTDTC = as.character(line$start_date),
          LOTENDTC = as.character(line$end_date),
          REGIMEN = regimen,
          INDEXFL = ifelse(is_index, "Y", NA_character_),
          disc_reason_raw = disc_reason
        )
      ))
    }
  }
}

# Combine all lines into ADLOT
adlot <- bind_rows(adlot_list)

# Add DM identifiers
adlot <- adlot %>%
  left_join(
    dm %>% select(USUBJID, STUDYID, RFSTDTC),
    by = "USUBJID"
  ) %>%
  select(STUDYID, USUBJID, LOT, LOTSTDTC, LOTENDTC, REGIMEN, INDEXFL, RFSTDTC, disc_reason_raw)

# --- Derive LOTENDRSN (line end reason) --------------------------------------

# REVISIT: LOTENDRSN mapping is complex — see artifacts/Open-questions-cdisc.md W4
# For now, implement a reasonable default:
# - If next line exists: "NEW REGIMEN"
# - If last line and subject died: "DEATH" (from DS domain)
# - Otherwise: use disc_reason_raw if available, else blank

# Get death records from DS
death_ds <- ds %>%
  dplyr::filter(DSDECOD == "DEATH" | str_detect(toupper(DSTERM), "DEATH")) %>%
  select(USUBJID, DSTERM, DSDECOD, DSDTC)

adlot <- adlot %>%
  group_by(USUBJID) %>%
  mutate(
    max_lot = max(LOT),
    is_last_line = (LOT == max_lot)
  ) %>%
  ungroup() %>%
  left_join(
    death_ds %>% select(USUBJID, death_term = DSTERM),
    by = "USUBJID"
  ) %>%
  mutate(
    LOTENDRSN = case_when(
      !is_last_line ~ "NEW REGIMEN",
      is_last_line & !is.na(death_term) ~ "DEATH",
      !is.na(disc_reason_raw) ~ disc_reason_raw,
      TRUE ~ NA_character_
    )
  ) %>%
  select(-max_lot, -is_last_line, -death_term, -disc_reason_raw)

# --- Derive numeric date variables -------------------------------------------

adlot <- adlot %>%
  mutate(
    LOTSTDT = as.numeric(as.Date(LOTSTDTC)),
    LOTENDT = as.numeric(as.Date(LOTENDTC))
  )

# --- Final dataset structure -------------------------------------------------

adlot <- adlot %>%
  select(STUDYID, USUBJID, LOT, LOTSTDTC, LOTENDTC, LOTSTDT, LOTENDT,
         REGIMEN, INDEXFL, LOTENDRSN)

# --- Validation checks -------------------------------------------------------

message("\n=== Validation Checks ===")
message("Row count: ", nrow(adlot))
message("Subject count: ", n_distinct(adlot$USUBJID))
message("Subjects with multiple lines: ", sum(table(adlot$USUBJID) > 1))

# Key variable completeness
var_completeness <- tibble(
  Variable = c("STUDYID", "USUBJID", "LOT", "LOTSTDTC", "LOTENDTC",
               "LOTSTDT", "LOTENDT", "REGIMEN", "INDEXFL", "LOTENDRSN"),
  N_Missing = sapply(adlot[, c("STUDYID", "USUBJID", "LOT", "LOTSTDTC",
                                "LOTENDTC", "LOTSTDT", "LOTENDT", "REGIMEN",
                                "INDEXFL", "LOTENDRSN")],
                     function(x) sum(is.na(x)))
)
print(var_completeness)

# CDISC compliance: unique keys (USUBJID + LOT)
if (any(duplicated(adlot[, c("USUBJID", "LOT")]))) {
  stop("Duplicate USUBJID + LOT combinations found — key uniqueness violated",
       call. = FALSE)
}
message("✓ Key uniqueness: USUBJID + LOT is unique")

# Cross-domain consistency: all subjects in DM
if (!all(adlot$USUBJID %in% dm$USUBJID)) {
  stop("Some USUBJID values in ADLOT not found in DM", call. = FALSE)
}
message("✓ Cross-domain consistency: All subjects in ADLOT exist in DM")

# Check that at least one line per subject has INDEXFL = 'Y'
index_check <- adlot %>%
  group_by(USUBJID) %>%
  summarize(has_index = any(INDEXFL == "Y", na.rm = TRUE), .groups = "drop")

message("Subjects with INDEXFL='Y': ", sum(index_check$has_index), " / ", nrow(index_check))

# Distribution of lines per subject
lot_dist <- table(table(adlot$USUBJID))
message("\nDistribution of lines per subject:")
print(lot_dist)

# Date consistency: LOTSTDTC <= LOTENDTC
date_violations <- adlot %>%
  dplyr::filter(!is.na(LOTSTDT) & !is.na(LOTENDT) & LOTSTDT > LOTENDT)
message("\nDate consistency violations (LOTSTDTC > LOTENDTC): ", nrow(date_violations))
if (nrow(date_violations) > 0) {
  warning("Date violations detected (LOTSTDTC > LOTENDTC)", call. = FALSE)
}

# --- Apply xportr attributes and write XPT -----------------------------------

# Build metadata frame for xportr
adlot_meta <- tibble::tibble(
  variable = c("STUDYID", "USUBJID", "LOT", "LOTSTDTC", "LOTENDTC",
               "LOTSTDT", "LOTENDT", "REGIMEN", "INDEXFL", "LOTENDRSN"),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Line of Therapy Number",
    "Line Start Date",
    "Line End Date",
    "Line Start Date (Numeric)",
    "Line End Date (Numeric)",
    "Regimen Name",
    "Index Line Flag",
    "Line End Reason"
  ),
  type = c("character", "character", "numeric", "character", "character",
           "numeric", "numeric", "character", "character", "character")
)

adlot <- adlot %>%
  xportr_label(metadata = adlot_meta, domain = "ADLOT") %>%
  xportr_type(metadata = adlot_meta, domain = "ADLOT")

# Save dataset
if (!dir.exists("projects/exelixis-sap/output-data/adam")) {
  dir.create("projects/exelixis-sap/output-data/adam", recursive = TRUE)
}
haven::write_xpt(adlot, "projects/exelixis-sap/output-data/adam/adlot.xpt")

message("\n✓ ADLOT dataset written to: projects/exelixis-sap/output-data/adam/adlot.xpt")
message("✓ Program execution complete")
