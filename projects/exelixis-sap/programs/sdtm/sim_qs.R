# =============================================================================
# Program     : sim_qs.R
# Description : Simulate QS (Questionnaires and Ratings) SDTM domain for
#               NPM-008 / XB010-101 study.
#
#               17 records per subject (40 subjects = 680 rows total):
#                 - 12 CCI comorbidity survey items (CCI01–CCI12)
#                 -  1 ECOG performance score
#                 -  1 Smoking status
#                 -  3 SC-consistent records (INCOME, EDUC, MARISTAT)
#
# Seed        : 55 (42 + 13; QS is domain order 13)
# Input       : output-data/sdtm/dm.rds
# Output      : output-data/sdtm/qs.rds, output-data/sdtm/qs.xpt
# =============================================================================

library(tidyverse)
library(xportr)
library(haven)

set.seed(55)

# --- Load DM spine ------------------------------------------------------------
dm <- readRDS("output-data/sdtm/dm.rds")

# Retain only the columns needed for QS derivation
dm_spine <- dm %>%
  dplyr::select(STUDYID, USUBJID, RFICDTC, ecog_bl)

# --- Define CCI item metadata ------------------------------------------------
cci_meta <- tibble::tibble(
  QSTESTCD = paste0("CCI", sprintf("%02d", 1:12)),
  QSTEST = c(
    "Myocardial Infarction",
    "Congestive Heart Failure",
    "Peripheral Vascular Disease",
    "Cerebrovascular Disease",
    "Dementia",
    "Chronic Pulmonary Disease",
    "Connective Tissue Disease",
    "Peptic Ulcer Disease",
    "Mild Liver Disease",
    "Diabetes Without Complication",
    "Diabetes With End Organ Damage",
    "Renal Disease"
  ),
  cci_prob = c(0.15, 0.08, 0.10, 0.08, 0.03, 0.20, 0.05, 0.05, 0.05, 0.18, 0.05, 0.10)
)

# --- Generate records per subject --------------------------------------------

# Pre-draw all random values so that set.seed(55) governs the full sequence
# in a reproducible order: CCI per subject, then SMOKE, then INCOME/EDUC/MARISTAT.

n_subj <- nrow(dm_spine)

# CCI: 12 yes/no draws per subject (n_subj x 12 matrix)
cci_draws <- matrix(
  rbinom(n_subj * 12, size = 1, prob = rep(cci_meta$cci_prob, each = n_subj)),
  nrow = n_subj,
  ncol = 12
)

# Smoking status: 1 draw per subject
smoke_draws <- sample(
  c("Current", "Former", "Never"),
  size = n_subj,
  replace = TRUE,
  prob = c(0.40, 0.45, 0.15)
)

# Income: 1 draw per subject
income_draws <- sample(
  c(
    "Less than $25,000",
    "$25,000 to less than $50,000",
    "$50,000 to less than $75,000",
    "$75,000 to less than $100,000",
    "$100,000 or more",
    "Prefer not to answer",
    "Unknown"
  ),
  size = n_subj,
  replace = TRUE,
  prob = c(0.15, 0.20, 0.20, 0.15, 0.20, 0.05, 0.05)
)

# Education: 1 draw per subject
educ_draws <- sample(
  c(
    "Did not graduate High School",
    "Graduated High School",
    "Attended College or Technical School",
    "Graduated from College or Technical School",
    "Graduate Degree"
  ),
  size = n_subj,
  replace = TRUE,
  prob = c(0.10, 0.25, 0.25, 0.25, 0.15)
)

# Marital status: 1 draw per subject
maristat_draws <- sample(
  c("Married or Domestic Partner", "Single", "Divorced", "Widowed", "Separated", "Unknown"),
  size = n_subj,
  replace = TRUE,
  prob = c(0.50, 0.15, 0.15, 0.12, 0.03, 0.05)
)

# --- Build QS rows per subject -----------------------------------------------

qs_list <- purrr::map(seq_len(n_subj), function(i) {

  subj   <- dm_spine$USUBJID[i]
  studyid <- dm_spine$STUDYID[i]
  dtc    <- dm_spine$RFICDTC[i]
  ecog   <- as.character(dm_spine$ecog_bl[i])

  # 12 CCI records
  cci_rows <- tibble::tibble(
    STUDYID  = studyid,
    DOMAIN   = "QS",
    USUBJID  = subj,
    QSTESTCD = cci_meta$QSTESTCD,
    QSTEST   = cci_meta$QSTEST,
    QSCAT    = "Comorbidity Survey",
    QSORRES  = ifelse(cci_draws[i, ] == 1, "Yes", "No"),
    VISIT    = "BASELINE",
    QSDTC    = dtc
  )

  # 1 ECOG record
  ecog_row <- tibble::tibble(
    STUDYID  = studyid,
    DOMAIN   = "QS",
    USUBJID  = subj,
    QSTESTCD = "ECOG",
    QSTEST   = "Eastern Cooperative Oncology Group (ECOG) Performance Score",
    QSCAT    = "Medical Oncology",
    QSORRES  = ecog,
    VISIT    = "BASELINE",
    QSDTC    = dtc
  )

  # 1 Smoking status record
  smoke_row <- tibble::tibble(
    STUDYID  = studyid,
    DOMAIN   = "QS",
    USUBJID  = subj,
    QSTESTCD = "SMOKE",
    QSTEST   = "Smoking status",
    QSCAT    = "Patient History Form",
    QSORRES  = smoke_draws[i],
    VISIT    = "BASELINE",
    QSDTC    = dtc
  )

  # 3 SC-consistent records (INCOME, EDUC, MARISTAT)
  sc_rows <- tibble::tibble(
    STUDYID  = studyid,
    DOMAIN   = "QS",
    USUBJID  = subj,
    QSTESTCD = c("INCOME", "EDUC", "MARISTAT"),
    QSTEST   = c(
      "Annual household income",
      "Highest level of education completed",
      "Marital status"
    ),
    QSCAT    = "Clinical Patient Questionnaire",
    QSORRES  = c(income_draws[i], educ_draws[i], maristat_draws[i]),
    VISIT    = "BASELINE",
    QSDTC    = dtc
  )

  # Stack and assign QSSEQ 1–17 (integer per SDTM-IG)
  dplyr::bind_rows(cci_rows, ecog_row, smoke_row, sc_rows) %>%
    dplyr::mutate(QSSEQ = as.integer(dplyr::row_number()))
})

qs_raw <- dplyr::bind_rows(qs_list) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, QSSEQ,
    QSTESTCD, QSTEST, QSCAT, QSORRES,
    VISIT, QSDTC
  )

# --- Apply xportr labels and write XPT ---------------------------------------

qs_labels <- c(
  STUDYID  = "Study Identifier",
  DOMAIN   = "Domain Abbreviation",
  USUBJID  = "Unique Subject Identifier",
  QSSEQ    = "Sequence Number",
  QSTESTCD = "Question Short Name",
  QSTEST   = "Question Name",
  QSCAT    = "Category of Question",
  QSORRES  = "Finding in Original Units",
  VISIT    = "Visit Name",
  QSDTC    = "Date/Time of Finding"
)

qs_xpt <- qs_raw %>%
  xportr_label(metadata = tibble::enframe(qs_labels, name = "variable", value = "label"),
               domain = "QS") %>%
  xportr_type(
    metadata = tibble::tibble(
      variable = names(qs_labels),
      # QSSEQ must be numeric (integer) per SDTM-IG; all others character
      type     = ifelse(names(qs_labels) == "QSSEQ", "numeric", "character")
    ),
    domain = "QS"
  )

output_path <- "output-data/sdtm/qs.xpt"

saveRDS(qs_xpt, "output-data/sdtm/qs.rds")
xportr_write(qs_xpt, path = output_path)

message("Written: ", output_path)

# --- Validation --------------------------------------------------------------

message("\n--- QS Validation ---")

# Total rows
message("nrow: ", nrow(qs_raw), " (expected 680)")
stopifnot(nrow(qs_raw) == 680)

# Distinct subjects
n_subj_out <- dplyr::n_distinct(qs_raw$USUBJID)
message("Distinct subjects: ", n_subj_out, " (expected 40)")
stopifnot(n_subj_out == 40)

# 17 records per subject
records_per_subj <- qs_raw %>%
  dplyr::count(USUBJID) %>%
  dplyr::pull(n)
message("Records per subject range: [", min(records_per_subj), ", ", max(records_per_subj), "] (expected all 17)")
stopifnot(all(records_per_subj == 17))

# QSSEQ unique within USUBJID
dup_seq <- qs_raw %>%
  dplyr::count(USUBJID, QSSEQ) %>%
  dplyr::filter(n > 1)
message("QSSEQ duplicates: ", nrow(dup_seq), " (expected 0)")
stopifnot(nrow(dup_seq) == 0)

# ECOG values are 0 or 1 for all subjects (eligibility criteria)
ecog_vals <- qs_raw %>%
  dplyr::filter(QSTESTCD == "ECOG") %>%
  dplyr::pull(QSORRES)
invalid_ecog <- ecog_vals[!ecog_vals %in% c("0", "1")]
message("ECOG values outside [0,1]: ", length(invalid_ecog), " (expected 0)")
stopifnot(length(invalid_ecog) == 0)

# STUDYID consistent
stopifnot(all(qs_raw$STUDYID == "NPM008"))

# DOMAIN consistent
stopifnot(all(qs_raw$DOMAIN == "QS"))

message("\nAll validations passed.")

# --- Preview -----------------------------------------------------------------
message("\nFirst 5 rows:")
print(head(qs_raw, 5))

message("\nQSTESTCD distribution:")
print(table(qs_raw$QSTESTCD))

message("\nECOG distribution:")
print(table(ecog_vals))

message("\nSmoke distribution:")
print(table(qs_raw$QSORRES[qs_raw$QSTESTCD == "SMOKE"]))
