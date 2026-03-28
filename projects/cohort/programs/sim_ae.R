# =============================================================================
# sim_ae.R
# NPM-008 / XB010-101 — SDTM AE Domain Simulation
#
# Inputs:  cohort/output-data/dm.rds   (DM spine with latent variables)
#          cohort/output-data/ex.rds   (EX data: EXSTDTC, EXENDTC, EXTRT)
# Outputs: cohort/output-data/sdtm/ae.xpt
#          cohort/output-data/sdtm/ae.rds
#
# Domain order: 17  →  set.seed(42 + 17) = set.seed(59)
# Avg AEs per subject: 2–4 (minimum 1 per subject enforced)
# =============================================================================

library(tidyverse)
library(haven)
library(lubridate)

set.seed(59)

# --- Paths -------------------------------------------------------------------
data_dir <- "/Users/briancarter/Rdata/claude-analytics-ref/cohort/output-data"

# --- Read inputs -------------------------------------------------------------
dm <- readRDS(file.path(data_dir, "dm.rds"))
ex <- readRDS(file.path(data_dir, "ex.rds"))

# Retain only columns needed from EX
ex_slim <- ex %>%
  dplyr::select(USUBJID, EXTRT, EXSTDTC, EXENDTC) %>%
  mutate(
    ex_start = as.Date(EXSTDTC),
    ex_end   = as.Date(EXENDTC)
  )

# All subjects from DM
subjects <- dm %>% dplyr::select(USUBJID)

# Join EX onto subjects (1:1 since one treatment per subject in this study)
subj_ex <- subjects %>%
  left_join(ex_slim, by = "USUBJID")

# --- AE pool definitions -----------------------------------------------------

# IO drugs (receive ILD probability boost + QTc addition)
io_drugs <- c("Pembrolizumab", "Nivolumab")

# EGFR-targeted drugs (receive Paronychia + Stomatitis additions)
egfr_drugs <- c("Osimertinib")

# Base AE pool: list of (aedecod, prob, grade_probs [G1,G2,G3,G4])
base_ae_pool <- list(
  list(aedecod = "Diarrhea",               prob = 0.35, grade_p = c(0.50, 0.30, 0.15, 0.05)),
  list(aedecod = "Fatigue",                prob = 0.40, grade_p = c(0.55, 0.35, 0.10, 0.00)),
  list(aedecod = "Nausea",                 prob = 0.30, grade_p = c(0.60, 0.30, 0.10, 0.00)),
  list(aedecod = "Rash",                   prob = 0.25, grade_p = c(0.50, 0.35, 0.14, 0.01)),
  list(aedecod = "Hematologic Toxicities", prob = 0.25, grade_p = c(0.20, 0.30, 0.35, 0.15)),
  list(aedecod = "ILD/Pneumonitis",        prob = 0.08, grade_p = c(0.20, 0.40, 0.30, 0.10)),
  list(aedecod = "Peripheral Neuropathy",  prob = 0.20, grade_p = c(0.55, 0.35, 0.10, 0.00)),
  list(aedecod = "Hypoalbuminemia",        prob = 0.15, grade_p = c(0.60, 0.30, 0.10, 0.00)),
  list(aedecod = "Constipation",           prob = 0.20, grade_p = c(0.60, 0.30, 0.10, 0.00)),
  list(aedecod = "Edema",                  prob = 0.15, grade_p = c(0.50, 0.35, 0.15, 0.00)),
  list(aedecod = "Dyspnea",               prob = 0.20, grade_p = c(0.40, 0.40, 0.18, 0.02)),
  list(aedecod = "Vomiting",              prob = 0.20, grade_p = c(0.55, 0.35, 0.10, 0.00))
)

# IO additions
io_ae_pool <- list(
  # ILD boost handled inside loop by doubling base prob
  list(aedecod = "QTc Prolongation", prob = 0.05, grade_p = c(0.50, 0.30, 0.15, 0.05))
)

# EGFR additions
egfr_ae_pool <- list(
  list(aedecod = "Paronychia",          prob = 0.25, grade_p = c(0.60, 0.30, 0.10, 0.00)),
  list(aedecod = "Stomatitis/Mucositis", prob = 0.20, grade_p = c(0.60, 0.30, 0.10, 0.00))
)

# --- SOC mapping -------------------------------------------------------------
soc_map <- c(
  "Diarrhea"               = "Gastrointestinal disorders",
  "Nausea"                 = "Gastrointestinal disorders",
  "Vomiting"               = "Gastrointestinal disorders",
  "Constipation"           = "Gastrointestinal disorders",
  "Stomatitis/Mucositis"   = "Gastrointestinal disorders",
  "Fatigue"                = "General disorders and administration site conditions",
  "Edema"                  = "General disorders and administration site conditions",
  "Rash"                   = "Skin and subcutaneous tissue disorders",
  "Paronychia"             = "Skin and subcutaneous tissue disorders",
  "Hematologic Toxicities" = "Blood and lymphatic system disorders",
  "ILD/Pneumonitis"        = "Respiratory, thoracic and mediastinal disorders",
  "Dyspnea"                = "Respiratory, thoracic and mediastinal disorders",
  "Peripheral Neuropathy"  = "Nervous system disorders",
  "Hypoalbuminemia"        = "Metabolism and nutrition disorders",
  "QTc Prolongation"       = "Cardiac disorders"
)

# --- AEREL mapping -----------------------------------------------------------
# IO drugs → "IO SACT"; chemo + targeted → "non-IO SACT"
get_aerel <- function(extrt) {
  if (extrt %in% io_drugs) "IO SACT" else "non-IO SACT"
}

# --- Helper: sample AEACN by grade ------------------------------------------
sample_aeacn <- function(grade) {
  if (grade %in% c(1, 2)) {
    sample(c(NA_character_, "DRUG INTERRUPTED"), size = 1, prob = c(0.80, 0.20))
  } else if (grade == 3) {
    sample(
      c("DRUG INTERRUPTED", "DRUG WITHDRAWN", "DOSE NOT CHANGED"),
      size = 1, prob = c(0.50, 0.30, 0.20)
    )
  } else {
    # Grade 4
    sample(c("DRUG WITHDRAWN", "DRUG INTERRUPTED"), size = 1, prob = c(0.70, 0.30))
  }
}

# --- Helper: build AE pool for one subject -----------------------------------
build_subject_ae_pool <- function(extrt) {
  pool <- base_ae_pool

  # IO boost: double ILD/Pneumonitis probability
  if (extrt %in% io_drugs) {
    pool <- purrr::map(pool, function(ae) {
      if (ae$aedecod == "ILD/Pneumonitis") ae$prob <- 0.16
      ae
    })
    pool <- c(pool, io_ae_pool)
  }

  # EGFR additions
  if (extrt %in% egfr_drugs) {
    pool <- c(pool, egfr_ae_pool)
  }

  pool
}

# --- Helper: sample AEs for one subject -------------------------------------
# Returns a data.frame of AE records (0+ rows; caller enforces ≥1)
sample_subject_aes <- function(usubjid, extrt, ex_start, ex_end) {
  pool <- build_subject_ae_pool(extrt)
  aerel <- get_aerel(extrt)

  # Determine window length; handle degenerate windows (0 days)
  window_days <- as.integer(ex_end - ex_start)
  if (is.na(window_days) || window_days < 1) window_days <- 1

  # Sample whether each AE occurs
  occurred <- purrr::map_lgl(pool, function(ae) {
    rbinom(1, 1, prob = ae$prob) == 1
  })
  selected_pool <- pool[occurred]

  if (length(selected_pool) == 0) return(NULL)  # caller will re-sample

  # For each selected AE, sample grade and dates
  purrr::map_dfr(selected_pool, function(ae) {
    grade_int <- sample(1:4, size = 1, prob = ae$grade_p)
    grade_chr <- as.character(grade_int)

    aesev <- switch(grade_chr,
      "1" = "MILD",
      "2" = "MODERATE",
      "3" = "SEVERE",
      "4" = "LIFE THREATENING"
    )

    # AESTDTC: uniform within (ex_start, ex_end); use integer offset
    start_offset <- sample(0:window_days, size = 1)
    ae_start <- ex_start + start_offset
    # Clamp to window
    ae_start <- pmin(ae_start, ex_end)

    # AEENDTC: grade 4 may have longer duration
    if (grade_int == 4) {
      duration <- sample(30:180, size = 1)
    } else {
      duration <- sample(5:60, size = 1)
    }
    ae_end <- ae_start + duration

    aeacn   <- sample_aeacn(grade_int)
    aeshosp <- if (grade_int >= 3) sample(c("Y", "N"), 1, prob = c(0.40, 0.60)) else "N"
    aeser   <- if (aeshosp == "Y") "Y" else "N"

    tibble(
      AEDECOD  = ae$aedecod,
      AETOXGR  = grade_chr,
      AESEV    = aesev,
      AESTDTC  = format(ae_start, "%Y-%m-%d"),
      AEENDTC  = format(ae_end,   "%Y-%m-%d"),
      AEREL    = aerel,
      AEACN    = aeacn,
      AESHOSP  = aeshosp,
      AESER    = aeser
    )
  })
}

# --- Main simulation loop ----------------------------------------------------
message("Simulating AE domain for ", nrow(subj_ex), " subjects...")

ae_list <- purrr::pmap(
  list(
    usubjid  = subj_ex$USUBJID,
    extrt    = subj_ex$EXTRT,
    ex_start = subj_ex$ex_start,
    ex_end   = subj_ex$ex_end
  ),
  function(usubjid, extrt, ex_start, ex_end) {
    # Keep sampling until at least 1 AE occurs (enforces minimum)
    aes <- NULL
    attempts <- 0
    while (is.null(aes) || nrow(aes) == 0) {
      attempts <- attempts + 1
      aes <- sample_subject_aes(usubjid, extrt, ex_start, ex_end)
      if (attempts > 50) {
        # Safety valve: force at least Fatigue G1 if nothing sampled
        message("  Warning: forced Fatigue for subject ", usubjid, " after ", attempts, " attempts")
        aes <- tibble(
          AEDECOD = "Fatigue", AETOXGR = "1", AESEV = "MILD",
          AESTDTC = format(ex_start, "%Y-%m-%d"),
          AEENDTC = format(ex_start + 7, "%Y-%m-%d"),
          AEREL   = get_aerel(extrt),
          AEACN   = NA_character_,
          AESHOSP = "N", AESER = "N"
        )
      }
    }
    aes <- aes %>% mutate(USUBJID = usubjid)
    aes
  }
)

# Combine and add fixed/derived variables
ae_raw <- bind_rows(ae_list)

# --- Assemble final AE dataset -----------------------------------------------
ae <- ae_raw %>%
  mutate(
    STUDYID = "NPM008",
    DOMAIN  = "AE",
    AETERM  = AEDECOD,
    AECAT   = "SACT",
    AELNKID = "1",
    AESOC   = soc_map[AEDECOD]
  ) %>%
  # AESEQ: sequential integer per subject, ordered by AESTDTC
  arrange(USUBJID, AESTDTC, AEDECOD) %>%
  group_by(USUBJID) %>%
  mutate(AESEQ = row_number()) %>%
  ungroup() %>%
  # Final column order per SDTM convention
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, AESEQ, AELNKID,
    AETERM, AEDECOD, AECAT, AESOC,
    AETOXGR, AESEV, AEREL, AEACN,
    AESHOSP, AESER,
    AESTDTC, AEENDTC
  )

message("AE records generated: ", nrow(ae))
message("Subjects with AEs:    ", n_distinct(ae$USUBJID))
message("Avg AEs per subject:  ", round(nrow(ae) / n_distinct(ae$USUBJID), 2))

# --- Apply variable labels ---------------------------------------------------
attr(ae$STUDYID, "label") <- "Study Identifier"
attr(ae$DOMAIN,  "label") <- "Domain Abbreviation"
attr(ae$USUBJID, "label") <- "Unique Subject Identifier"
attr(ae$AESEQ,   "label") <- "Sequence Number"
attr(ae$AELNKID, "label") <- "Link ID"
attr(ae$AETERM,  "label") <- "Reported Term for Adverse Event"
attr(ae$AEDECOD, "label") <- "Dictionary-Derived Term"
attr(ae$AECAT,   "label") <- "Category for Adverse Event"
attr(ae$AESOC,   "label") <- "Primary System Organ Class"
attr(ae$AETOXGR, "label") <- "Standard Toxicity Grade"
attr(ae$AESEV,   "label") <- "Severity/Intensity"
attr(ae$AEREL,   "label") <- "Causality"
attr(ae$AEACN,   "label") <- "Action Taken with Study Treatment"
attr(ae$AESHOSP, "label") <- "Resulted in Hospitalization"
attr(ae$AESER,   "label") <- "Serious Event"
attr(ae$AESTDTC, "label") <- "Start Date/Time of Adverse Event"
attr(ae$AEENDTC, "label") <- "End Date/Time of Adverse Event"

# --- Save outputs ------------------------------------------------------------
saveRDS(ae, file.path(data_dir, "ae.rds"))
message("Saved: ", file.path(data_dir, "ae.rds"))

haven::write_xpt(ae, path = file.path(data_dir, "ae.xpt"))
message("Saved: ", file.path(data_dir, "ae.xpt"))

# --- Validation --------------------------------------------------------------
message("\n--- Validation ---")

# 1. All USUBJIDs present in DM
orphan_subjids <- setdiff(unique(ae$USUBJID), unique(dm$USUBJID))
if (length(orphan_subjids) == 0) {
  message("PASS: All AE USUBJIDs exist in DM")
} else {
  warning("FAIL: ", length(orphan_subjids), " AE USUBJIDs not in DM: ",
          paste(orphan_subjids, collapse = ", "), call. = FALSE)
}

# 2. AESEQ unique per USUBJID
aeseq_dups <- ae %>%
  group_by(USUBJID, AESEQ) %>%
  dplyr::filter(n() > 1) %>%
  nrow()
if (aeseq_dups == 0) {
  message("PASS: AESEQ is unique per USUBJID")
} else {
  warning("FAIL: ", aeseq_dups, " duplicate AESEQ values found", call. = FALSE)
}

# 3. AESTDTC >= EXSTDTC (treatment start)
date_check <- ae %>%
  left_join(ex_slim %>% dplyr::select(USUBJID, EXSTDTC, EXENDTC),
            by = "USUBJID") %>%
  mutate(
    ae_start_dt = as.Date(AESTDTC),
    ex_start_dt = as.Date(EXSTDTC),
    ex_end_dt   = as.Date(EXENDTC),
    before_ex   = ae_start_dt < ex_start_dt,
    after_ex    = ae_start_dt > ex_end_dt
  )

n_before <- sum(date_check$before_ex, na.rm = TRUE)
n_after  <- sum(date_check$after_ex,  na.rm = TRUE)

if (n_before == 0) {
  message("PASS: No AE starts before EXSTDTC")
} else {
  warning("FAIL: ", n_before, " AEs start before EXSTDTC", call. = FALSE)
}

if (n_after == 0) {
  message("PASS: No AE starts after EXENDTC")
} else {
  warning("FAIL: ", n_after, " AEs start after EXENDTC", call. = FALSE)
}

# 4. Average AEs per subject in 2–4 range
avg_aes <- nrow(ae) / n_distinct(ae$USUBJID)
if (avg_aes >= 2 && avg_aes <= 4) {
  message("PASS: Avg AEs per subject = ", round(avg_aes, 2), " (target 2–4)")
} else {
  message("INFO: Avg AEs per subject = ", round(avg_aes, 2),
          " (target 2–4; note: random variation expected)")
}

# 5. AESEV consistent with AETOXGR
sev_check <- ae %>%
  mutate(
    expected_sev = case_when(
      AETOXGR == "1" ~ "MILD",
      AETOXGR == "2" ~ "MODERATE",
      AETOXGR == "3" ~ "SEVERE",
      AETOXGR == "4" ~ "LIFE THREATENING"
    ),
    sev_match = AESEV == expected_sev
  )
n_sev_mismatch <- sum(!sev_check$sev_match, na.rm = TRUE)
if (n_sev_mismatch == 0) {
  message("PASS: AESEV consistent with AETOXGR for all records")
} else {
  warning("FAIL: ", n_sev_mismatch, " records have AESEV/AETOXGR mismatch", call. = FALSE)
}

# 6. Coverage: every subject in DM has at least one AE
subjects_with_ae <- n_distinct(ae$USUBJID)
subjects_in_dm   <- n_distinct(dm$USUBJID)
if (subjects_with_ae == subjects_in_dm) {
  message("PASS: All ", subjects_in_dm, " DM subjects have at least one AE")
} else {
  warning("FAIL: Only ", subjects_with_ae, " of ", subjects_in_dm,
          " subjects have AEs", call. = FALSE)
}

message("\n--- AE domain simulation complete ---")
