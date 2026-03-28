# =============================================================================
# sim_cm.R
# NPM-008 / XB010-101 SDTM CM Domain Simulation
#
# Two record categories per subject:
#   1. Prior lines of therapy (CMCAT = "PRIOR MEDICATIONS")
#   2. Concomitant supportive medications (CMCAT = "CONCOMITANT MEDICATIONS")
#
# Inputs:
#   cohort/output-data/dm.rds  — DM spine with latent variables
#   cohort/output-data/ex.rds  — EX data (EXSTDTC, EXENDTC as index dates)
#
# Outputs:
#   cohort/output-data/sdtm/cm.xpt
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

set.seed(42 + 11)  # 53 — CM is domain order 11

# --- Paths -------------------------------------------------------------------

dm_path  <- "cohort/output-data/dm.rds"
ex_path  <- "cohort/output-data/ex.rds"
xpt_path <- "cohort/output-data/sdtm/cm.xpt"

# --- Load input data ---------------------------------------------------------

dm <- readRDS(dm_path) %>%
  dplyr::select(
    USUBJID, RFSTDTC,
    n_prior_lots, pdl1_status, egfr_status, alk_status
  )

ex <- readRDS(ex_path) %>%
  dplyr::select(USUBJID, EXSTDTC, EXENDTC)

stopifnot(nrow(dm) == 40)
stopifnot(nrow(ex) == 40)

# --- Merge latent variables with index dates ---------------------------------

subj <- dm %>%
  dplyr::inner_join(ex, by = "USUBJID") %>%
  mutate(
    index_date = as.Date(EXSTDTC),
    end_date   = as.Date(EXENDTC)
  )

stopifnot(nrow(subj) == 40)

# --- Helper: select 1L drug --------------------------------------------------
# Drug selection based on biomarker hierarchy (EGFR > ALK > PDL1 > default)

select_1l_drug <- function(egfr_status, alk_status, pdl1_status) {
  if (egfr_status == "ALTERED") {
    return(sample(c("Osimertinib", "Erlotinib"), size = 1, prob = c(0.50, 0.50)))
  }
  if (alk_status == "ALTERED") {
    return(sample(c("Crizotinib", "Lorlatinib"), size = 1, prob = c(0.50, 0.50)))
  }
  if (pdl1_status == "HIGH") {
    return(sample(
      c("Pembrolizumab", "Carboplatin + Paclitaxel + Pembrolizumab"),
      size = 1,
      prob = c(0.40, 0.60)
    ))
  }
  # Default: PDL1 negative or low
  return(sample(
    c(
      "Carboplatin + Paclitaxel + Pembrolizumab",
      "Carboplatin + Pemetrexed + Pembrolizumab"
    ),
    size = 1,
    prob = c(0.50, 0.50)
  ))
}

# --- Helper: is prior line targeted therapy? ---------------------------------
# Targeted = EGFR or ALK inhibitor regimen

is_targeted <- function(drug) {
  drug %in% c("Osimertinib", "Erlotinib", "Crizotinib", "Lorlatinib")
}

# --- Helper: select 2nd prior line drug --------------------------------------

select_2l_drug <- function(prev_drug) {
  if (is_targeted(prev_drug)) {
    return(sample(c("Docetaxel", "Pemetrexed"), size = 1, prob = c(0.50, 0.50)))
  }
  return(sample(
    c("Docetaxel", "Pemetrexed", "Pembrolizumab"),
    size = 1,
    prob = c(0.40, 0.30, 0.30)
  ))
}

# --- Helper: select 3rd prior line drug --------------------------------------

select_3l_drug <- function() {
  sample(
    c("Docetaxel", "Ramucirumab + Docetaxel", "Nivolumab"),
    size = 1,
    prob = c(0.40, 0.30, 0.30)
  )
}

# --- Helper: dose units lookup for CM drugs ----------------------------------
# Returns CMDOSU for the given CMTRT

get_cmdosu <- function(drug) {
  # Prior LoT drugs — use "mg" or "mg/m2" by class;
  # for combination regimens use "mg/m2" as the primary unit
  targeted_oral  <- c("Osimertinib", "Erlotinib", "Crizotinib", "Lorlatinib")
  iv_flat        <- c("Pembrolizumab", "Nivolumab")
  iv_bsa_combos  <- c(
    "Carboplatin + Paclitaxel + Pembrolizumab",
    "Carboplatin + Pemetrexed + Pembrolizumab",
    "Ramucirumab + Docetaxel"
  )
  iv_bsa_single  <- c("Docetaxel", "Pemetrexed")

  if (drug %in% targeted_oral) return("mg")
  if (drug %in% iv_flat)       return("mg")
  if (drug %in% iv_bsa_combos) return("mg/m2")
  if (drug %in% iv_bsa_single) return("mg/m2")
  return("mg")
}

# --- Build prior LoT records for one subject ---------------------------------
# The date chain is built forward from a fixed 1L anchor, then validated.
# If a later line's start overshoots index_date (possible when durations are
# long), the entire chain is compressed so every start date is strictly before
# index_date by at least (n_prior_lots - lot_num + 1) * 30 days.

build_prior_lots <- function(usubjid, n_prior_lots, pdl1_status, egfr_status,
                             alk_status, index_date) {
  records <- list()

  # 1L start: offset from index by (n_prior_lots * random 120-240 days).
  # Using the upper end of the range ensures enough room for downstream lines.
  lot1_start <- index_date - (n_prior_lots * sample(120:240, 1))
  lot1_drug  <- select_1l_drug(egfr_status, alk_status, pdl1_status)
  lot1_dur   <- sample(60:180, 1)
  lot1_end   <- lot1_start + lot1_dur

  records[[1]] <- list(
    drug  = lot1_drug,
    start = lot1_start,
    end   = lot1_end
  )

  if (n_prior_lots >= 2) {
    lot2_start <- lot1_end + sample(21:90, 1)
    lot2_drug  <- select_2l_drug(lot1_drug)
    lot2_dur   <- sample(60:180, 1)
    lot2_end   <- lot2_start + lot2_dur

    records[[2]] <- list(
      drug  = lot2_drug,
      start = lot2_start,
      end   = lot2_end
    )
  }

  if (n_prior_lots >= 3) {
    lot3_start <- records[[2]]$end + sample(21:90, 1)
    lot3_drug  <- select_3l_drug()
    lot3_dur   <- sample(60:180, 1)
    lot3_end   <- lot3_start + lot3_dur

    records[[3]] <- list(
      drug  = lot3_drug,
      start = lot3_start,
      end   = lot3_end
    )
  }

  # --- Guard: compress chain if any line's start >= index_date ---------------
  # Each lot must start at least 30 days before the next milestone.
  # Work backwards from index_date to force compliance.
  last_idx <- length(records)
  if (as.integer(index_date - records[[last_idx]]$start) < 1) {
    # Re-anchor: distribute n_prior_lots lines evenly before index
    min_spacing <- 90L   # minimum days per lot slot
    chain_start <- index_date - (n_prior_lots * min_spacing)

    for (i in seq_len(n_prior_lots)) {
      records[[i]]$start <- chain_start + ((i - 1L) * min_spacing)
      records[[i]]$end   <- records[[i]]$start + 60L
    }
  }

  # Last prior line end = index_date (per spec)
  records[[last_idx]]$end <- index_date

  # Ensure start < end for all lines (final safety check)
  for (i in seq_len(n_prior_lots)) {
    if (records[[i]]$start >= records[[i]]$end) {
      records[[i]]$start <- records[[i]]$end - 30L
    }
  }

  # --- Assemble tibble rows ---------------------------------------------------
  result <- purrr::map2_dfr(
    records,
    seq_len(n_prior_lots),
    function(rec, lot_num) {
      tibble(
        USUBJID  = usubjid,
        CMTRT    = rec$drug,
        CMSTDTC  = as.character(rec$start),
        CMENDTC  = as.character(rec$end),
        CMDOSU   = get_cmdosu(rec$drug),
        CMCAT    = "PRIOR MEDICATIONS",
        CMRSDISC = if_else(lot_num == n_prior_lots,
                           "Planned Therapy Completed",
                           "Progressive Disease"),
        lot_num  = as.integer(lot_num)
      )
    }
  )

  result
}

# --- Concomitant supportive medications pool ---------------------------------

conmed_pool <- tibble(
  CMTRT = c(
    "Ondansetron", "Dexamethasone", "Filgrastim",
    "Metoprolol", "Lisinopril", "Atorvastatin",
    "Omeprazole", "Lorazepam"
  ),
  prob = c(0.50, 0.40, 0.20, 0.25, 0.20, 0.30, 0.35, 0.20),
  CMDOSU = c("mg", "mg", "mcg", "mg", "mg", "mg", "mg", "mg")
)

# --- Build concomitant records for one subject --------------------------------

build_conmed <- function(usubjid, index_date, end_date) {
  # Determine which drugs this subject takes (independent Bernoulli draws)
  selected <- conmed_pool %>%
    dplyr::filter(runif(nrow(conmed_pool)) < prob)

  if (nrow(selected) == 0) return(tibble())

  # Compute window length (days available for conmed starts)
  window_len <- as.integer(end_date - index_date)
  # Guard: if window_len <= 0, use a single-day window at index
  if (window_len <= 0) window_len <- 1L

  selected %>%
    rowwise() %>%
    mutate(
      USUBJID = usubjid,
      CMCAT   = "CONCOMITANT MEDICATIONS",
      # CMSTDTC: random date within [index_date, end_date]
      CMSTDTC = as.character(
        index_date + sample(0:window_len, 1, replace = TRUE)
      ),
      # CMENDTC: CMSTDTC + 14-180 days; 30% probability of NA (ongoing)
      cm_end_raw = as.character(
        as.Date(CMSTDTC) + sample(14:180, 1)
      ),
      ongoing  = runif(1) < 0.30,
      CMENDTC  = if_else(ongoing, NA_character_, cm_end_raw),
      CMRSDISC = if_else(
        ongoing,
        NA_character_,
        "Planned Therapy Completed"
      ),
      lot_num  = NA_integer_
    ) %>%
    ungroup() %>%
    dplyr::select(USUBJID, CMTRT, CMSTDTC, CMENDTC, CMDOSU, CMCAT, CMRSDISC, lot_num)
}

# --- Generate all CM records --------------------------------------------------

# Prior LoT records
prior_records <- subj %>%
  rowwise() %>%
  do(build_prior_lots(
    usubjid      = .$USUBJID,
    n_prior_lots = .$n_prior_lots,
    pdl1_status  = .$pdl1_status,
    egfr_status  = .$egfr_status,
    alk_status   = .$alk_status,
    index_date   = .$index_date
  )) %>%
  ungroup()

# Concomitant records
conmed_records <- subj %>%
  rowwise() %>%
  do(build_conmed(
    usubjid    = .$USUBJID,
    index_date = .$index_date,
    end_date   = .$end_date
  )) %>%
  ungroup()

# Combine and assign CMSEQ sequentially per subject
cm_raw <- bind_rows(prior_records, conmed_records) %>%
  arrange(USUBJID, CMCAT, CMSTDTC) %>%
  group_by(USUBJID) %>%
  mutate(CMSEQ = row_number()) %>%
  ungroup()

# --- Assemble final CM dataset -----------------------------------------------

cm <- cm_raw %>%
  mutate(
    STUDYID = "NPM008",
    DOMAIN  = "CM",
    CMDECOD = CMTRT
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, CMSEQ,
    CMTRT, CMDECOD, CMCAT,
    CMSTDTC, CMENDTC,
    CMDOSU, CMRSDISC
  )

# --- Apply variable labels via attr() ----------------------------------------

attr(cm$STUDYID,  "label") <- "Study Identifier"
attr(cm$DOMAIN,   "label") <- "Domain Abbreviation"
attr(cm$USUBJID,  "label") <- "Unique Subject Identifier"
attr(cm$CMSEQ,    "label") <- "Sequence Number"
attr(cm$CMTRT,    "label") <- "Reported Name of Drug, Med, or Therapy"
attr(cm$CMDECOD,  "label") <- "Standardized Medication Name"
attr(cm$CMCAT,    "label") <- "Category for Medication"
attr(cm$CMSTDTC,  "label") <- "Start Date/Time of Medication"
attr(cm$CMENDTC,  "label") <- "End Date/Time of Medication"
attr(cm$CMDOSU,   "label") <- "Dose Units"
attr(cm$CMRSDISC, "label") <- "Reason Medication Discontinued"

# --- Write output -------------------------------------------------------------

message("Writing cm.xpt ...")
saveRDS(cm, "cohort/output-data/sdtm/cm.rds")
haven::write_xpt(cm, path = xpt_path)

message("Done. Rows written: ", nrow(cm))

# --- Validation ---------------------------------------------------------------

cat("\n=== VALIDATION ===\n")
cat("Total CM records:", nrow(cm), "\n")

# CMSEQ unique per USUBJID
cmseq_check <- cm %>%
  group_by(USUBJID) %>%
  summarise(n_seq = n_distinct(CMSEQ), n_rows = n(), .groups = "drop") %>%
  dplyr::filter(n_seq != n_rows)

cat("CMSEQ unique per USUBJID (0 violations expected):", nrow(cmseq_check), "\n")

# All USUBJID in DM
missing_usubjid <- setdiff(unique(cm$USUBJID), dm$USUBJID)
cat("USUBJID not in DM (0 expected):", length(missing_usubjid), "\n")

# Prior LoT CMSTDTC < EXSTDTC
prior_check <- cm %>%
  dplyr::filter(CMCAT == "PRIOR MEDICATIONS") %>%
  dplyr::left_join(dplyr::select(subj, USUBJID, index_date), by = "USUBJID") %>%
  dplyr::filter(as.Date(CMSTDTC) >= index_date)

cat("Prior LoT CMSTDTC >= EXSTDTC (0 expected):", nrow(prior_check), "\n")

# Concomitant CMSTDTC >= EXSTDTC
conmed_check <- cm %>%
  dplyr::filter(CMCAT == "CONCOMITANT MEDICATIONS") %>%
  dplyr::left_join(dplyr::select(subj, USUBJID, index_date), by = "USUBJID") %>%
  dplyr::filter(as.Date(CMSTDTC) < index_date)

cat("Concomitant CMSTDTC < EXSTDTC (0 expected):", nrow(conmed_check), "\n")

# Subject-level summaries
cat("\nRecords per CMCAT:\n")
print(table(cm$CMCAT))

cat("\nPrior LoT drug distribution:\n")
print(table(cm$CMTRT[cm$CMCAT == "PRIOR MEDICATIONS"]))

cat("\nConcomitant drug distribution:\n")
print(table(cm$CMTRT[cm$CMCAT == "CONCOMITANT MEDICATIONS"]))

cat("\nCMRSDISC distribution (NA = ongoing):\n")
print(table(cm$CMRSDISC, useNA = "always"))

cat("\nSample records (first 8):\n")
print(dplyr::select(head(cm, 8), USUBJID, CMSEQ, CMTRT, CMCAT, CMSTDTC, CMENDTC))
