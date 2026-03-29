# sim_bs.R
# Simulate SDTM BS (Biospecimen) domain for NPM-008 / XB010-101
# Wave 2, Domain order 8 — set.seed(50)
#
# Inputs:
#   output-data/sdtm/dm.rds  — DM spine with latent variables
#   output-data/sdtm/lb.rds  — LB data for genomic collection dates
#   output-data/sdtm/ct_reference.rds — CT reference values
#
# Output:
#   output-data/sdtm/bs.xpt
#   output-data/sdtm/bs.rds

# Load packages explicitly to avoid conflicts_prefer issue
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(haven)
})

# Source validation functions
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

set.seed(50)

# --- Load inputs -------------------------------------------------------------

dm <- readRDS("output-data/sdtm/dm.rds")
lb <- readRDS("output-data/sdtm/lb.rds")
ct_reference <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Derive biospecimen collection date per subject --------------------------
# Use the first LB date from biomarker tests per subject (any biomarker test).
# All biomarker tests come from the same biopsy, so they share the same date.
# This date becomes BSDTC for all biospecimen records for that subject.

# Biomarker test codes from plan section 4.7
biomarker_tests <- c("PDL1SUM", "PDL1SC", "PDL1TYPE", "EGFR", "ALK", "KRAS",
                     "MET", "ROS1", "TP53", "NTRK1", "NTRK2", "NTRK3",
                     "RB1", "RET", "ERBB2", "HER2IHC", "MSISTAT", "TMB",
                     "LOHSUM", "LOHSC", "MMRMLH1", "MMRMSH2", "MMRMSH6",
                     "MMRPMS2", "MMROVER", "CORES")

biospecimen_dates <- lb %>%
  dplyr::filter(LBTESTCD %in% biomarker_tests) %>%
  dplyr::arrange(USUBJID, LBDTC) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::slice(1) %>%
  dplyr::ungroup() %>%
  dplyr::select(USUBJID, BSDTC = LBDTC)

# --- Build subject-level random draws ----------------------------------------
# Sample per-subject values that are shared across all specimens for that
# subject: anatomical region, histology, HE inclusion flag.

n_subj <- nrow(dm)

subject_level <- dm %>%
  dplyr::select(USUBJID, SITEID, SUBJID) %>%
  dplyr::mutate(
    # Anatomical region: same ICD-O3 lobe code for all specimens per subject
    BSANTREG = sample(
      c("C34.1", "C34.2", "C34.3"),
      size = n_subj,
      replace = TRUE,
      prob = c(0.40, 0.10, 0.50)
    ),
    # Histology: same ICD-O3 morphology code for all specimens per subject
    BSHIST = sample(
      c("8140/3", "8070/3", "8012/3", "8046/3"),
      size = n_subj,
      replace = TRUE,
      prob = c(0.60, 0.25, 0.05, 0.10)
    ),
    # HE slide inclusion: 80% probability
    has_he = sample(
      c(TRUE, FALSE),
      size = n_subj,
      replace = TRUE,
      prob = c(0.80, 0.20)
    )
  )

# --- Expand to specimen records ----------------------------------------------
# Every subject always gets FFPEBL (seq 1) and FFPESL (seq 2).
# Subjects with has_he == TRUE also get HE (seq 3).

# Fixed specimens (all subjects)
fixed_specs <- subject_level %>%
  tidyr::crossing(
    tibble(
      BSTESTCD = c("FFPEBL", "FFPESL"),
      BSTEST   = c("FFPE block", "FFPE slides"),
      seq_num  = c(1L, 2L)
    )
  )

# Optional HE specimen (80% of subjects)
he_specs <- subject_level %>%
  dplyr::filter(has_he) %>%
  dplyr::mutate(
    BSTESTCD = "HE",
    BSTEST   = "H&E slides",
    seq_num  = 3L
  )

# Combine and assign per-specimen random draws
bs_raw <- dplyr::bind_rows(fixed_specs, he_specs) %>%
  dplyr::arrange(USUBJID, seq_num) %>%
  # Specimen type: sampled independently per specimen record
  dplyr::mutate(
    BSSPEC = sample(
      c("Primary Tumor", "Metastatic Tissue"),
      size = dplyr::n(),
      replace = TRUE,
      prob = c(0.60, 0.40)
    )
  )

# --- Assemble final BS dataset -----------------------------------------------

bs <- bs_raw %>%
  # Join biospecimen collection date
  dplyr::left_join(biospecimen_dates, by = "USUBJID") %>%
  dplyr::transmute(
    STUDYID  = "NPM008",
    DOMAIN   = "BS",
    USUBJID  = USUBJID,
    BSSEQ    = as.integer(seq_num),
    BSREFID  = paste0("BS-", SITEID, "-", SUBJID, "-", sprintf("%02d", seq_num)),
    BSTESTCD = BSTESTCD,
    BSTEST   = BSTEST,
    BSSPEC   = BSSPEC,
    BSANTREG = BSANTREG,
    BSMETHOD = "FFPE",
    BSHIST   = BSHIST,
    BSDTC    = BSDTC
  ) %>%
  dplyr::arrange(USUBJID, BSSEQ)

# --- Apply variable labels ---------------------------------------------------

attr(bs[["STUDYID"]],  "label") <- "Study Identifier"
attr(bs[["DOMAIN"]],   "label") <- "Domain Abbreviation"
attr(bs[["USUBJID"]],  "label") <- "Unique Subject Identifier"
attr(bs[["BSSEQ"]],    "label") <- "Sequence Number"
attr(bs[["BSREFID"]],  "label") <- "Specimen Reference/Identification"
attr(bs[["BSTESTCD"]], "label") <- "Biospecimen Test Short Name"
attr(bs[["BSTEST"]],   "label") <- "Biospecimen Test Name"
attr(bs[["BSSPEC"]],   "label") <- "Specimen Type Used for Measurement"
attr(bs[["BSANTREG"]], "label") <- "Anatomical Region"
attr(bs[["BSMETHOD"]], "label") <- "Method of Test or Examination"
attr(bs[["BSHIST"]],   "label") <- "Histology"
attr(bs[["BSDTC"]],    "label") <- "Date/Time of Specimen Collection"

# --- Domain-specific validation checks ---------------------------------------

bs_domain_checks <- function(bs_df, dm_ref) {
  checks <- list()

  # D1: BSTESTCD contains only permitted values
  invalid_testcd <- setdiff(unique(bs_df$BSTESTCD), c("FFPEBL", "FFPESL", "HE"))
  if (length(invalid_testcd) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D1",
      description = "BSTESTCD contains only permitted values (FFPEBL, FFPESL, HE)",
      result = "FAIL",
      detail = sprintf("Invalid values: %s", paste(invalid_testcd, collapse = ", "))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D1",
      description = "BSTESTCD contains only permitted values (FFPEBL, FFPESL, HE)",
      result = "PASS",
      detail = ""
    )
  }

  # D2: All subjects have FFPEBL and FFPESL
  ffpe_check <- bs_df %>%
    dplyr::filter(BSTESTCD %in% c("FFPEBL", "FFPESL")) %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::summarise(
      has_bl = any(BSTESTCD == "FFPEBL"),
      has_sl = any(BSTESTCD == "FFPESL"),
      .groups = "drop"
    ) %>%
    dplyr::filter(!has_bl | !has_sl)

  if (nrow(ffpe_check) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D2",
      description = "All subjects have FFPEBL and FFPESL specimens",
      result = "FAIL",
      detail = sprintf("%d subject(s) missing required FFPE specimens", nrow(ffpe_check))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D2",
      description = "All subjects have FFPEBL and FFPESL specimens",
      result = "PASS",
      detail = ""
    )
  }

  # D3: BSDTC matches biomarker test collection date from LB
  # Cross-check that all BS dates align with LB biomarker test dates
  lb <- readRDS("output-data/sdtm/lb.rds")

  # Biomarker test codes
  biomarker_tests <- c("PDL1SUM", "PDL1SC", "PDL1TYPE", "EGFR", "ALK", "KRAS",
                       "MET", "ROS1", "TP53", "NTRK1", "NTRK2", "NTRK3",
                       "RB1", "RET", "ERBB2", "HER2IHC", "MSISTAT", "TMB",
                       "LOHSUM", "LOHSC", "MMRMLH1", "MMRMSH2", "MMRMSH6",
                       "MMRPMS2", "MMROVER", "CORES")

  biomarker_lb_dates <- lb %>%
    dplyr::filter(LBTESTCD %in% biomarker_tests) %>%
    dplyr::group_by(USUBJID) %>%
    dplyr::arrange(USUBJID, LBDTC) %>%
    dplyr::slice(1) %>%
    dplyr::ungroup() %>%
    dplyr::select(USUBJID, lb_date = LBDTC)

  bs_dates <- bs_df %>%
    dplyr::select(USUBJID, BSDTC) %>%
    dplyr::distinct()

  date_mismatch <- bs_dates %>%
    dplyr::inner_join(biomarker_lb_dates, by = "USUBJID") %>%
    dplyr::filter(BSDTC != lb_date)

  if (nrow(date_mismatch) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D3",
      description = "BSDTC matches first biomarker LB collection date per subject",
      result = "FAIL",
      detail = sprintf("%d subject(s) with date mismatch between BS and LB", nrow(date_mismatch))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D3",
      description = "BSDTC matches first biomarker LB collection date per subject",
      result = "PASS",
      detail = ""
    )
  }

  # D4: BSREFID format validation
  invalid_bsrefid <- bs_df$BSREFID[!stringr::str_detect(bs_df$BSREFID, "^BS-\\d{2}-[A-Z]\\d{4}-\\d{2}$")]
  if (length(invalid_bsrefid) > 0) {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D4",
      description = "BSREFID matches expected format BS-{SITE}-{SUBJ}-{SEQ}",
      result = "FAIL",
      detail = sprintf("%d invalid BSREFID(s): %s",
                      length(invalid_bsrefid),
                      paste(head(invalid_bsrefid, 3), collapse = ", "))
    )
  } else {
    checks[[length(checks) + 1]] <- list(
      check_id = "BS_D4",
      description = "BSREFID matches expected format BS-{SITE}-{SUBJ}-{SEQ}",
      result = "PASS",
      detail = ""
    )
  }

  checks
}

# --- Run validation ----------------------------------------------------------

message("\n--- BS Validation ---\n")

# Build CT reference for BS
ct_bs <- list(
  DOMAIN = "BS",
  BSTESTCD = c("FFPEBL", "FFPESL", "HE"),
  BSMETHOD = "FFPE"
)

validation_result <- validate_sdtm_domain(
  domain_df = bs,
  domain_code = "BS",
  dm_ref = dm,
  expected_rows = c(90, 120),
  ct_reference = ct_bs,
  domain_checks = bs_domain_checks
)

# Log result
log_sdtm_result(
  domain_code = "BS",
  wave = 2,
  row_count = nrow(bs),
  col_count = ncol(bs),
  validation_result = validation_result,
  notes = c(
    "Specimen collection dates match biomarker LB test dates",
    "All subjects have FFPEBL and FFPESL; HE slides present for ~80%"
  )
)

message(validation_result$summary)

# --- Diagnostic summary ------------------------------------------------------

message("\n--- BS Diagnostic Summary ---")
message("Total records: ", nrow(bs))
message("Unique subjects: ", dplyr::n_distinct(bs$USUBJID))
message("Records per subject: ", round(nrow(bs) / dplyr::n_distinct(bs$USUBJID), 1))

message("\nBSTESTCD frequency:")
print(dplyr::count(bs, BSTESTCD))

message("\nBSSPEC frequency:")
print(dplyr::count(bs, BSSPEC))

message("\nBSANTREG frequency:")
print(dplyr::count(bs, BSANTREG) %>% dplyr::arrange(BSANTREG))

# --- Write XPT ---------------------------------------------------------------

haven::write_xpt(bs, "output-data/sdtm/bs.xpt")
message("\nWrote: output-data/sdtm/bs.xpt (", nrow(bs), " records)")

# Persist RDS for downstream domain use
saveRDS(bs, "output-data/sdtm/bs.rds")
message("Wrote: output-data/sdtm/bs.rds")
