# sim_bs.R
# Simulate SDTM BS (Biospecimen) domain for NPM-008 / XB010-101
# Domain order 8 — set.seed(50)
#
# Inputs:
#   cohort/output-data/dm.rds  — DM spine with latent variables
#   cohort/output-data/lb.rds  — LB data for genomic collection dates
#
# Output:
#   cohort/output-data/sdtm/bs.xpt

library(tidyverse)
library(haven)

set.seed(50)

# --- Load inputs -------------------------------------------------------------

dm <- readRDS("cohort/output-data/dm.rds")
lb <- readRDS("cohort/output-data/lb.rds")

# --- Derive genomic collection date per subject ------------------------------
# Use the first LBDTC where LBCAT == "GENOMICS" per subject.
# This date becomes BSDTC for all biospecimen records for that subject.

genomic_dates <- lb %>%
  dplyr::filter(LBCAT == "GENOMICS") %>%
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
  # Join genomic collection date
  dplyr::left_join(genomic_dates, by = "USUBJID") %>%
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

# --- Validate ----------------------------------------------------------------

message("--- BS Validation ---")

# Row count within expected range
nrow_bs <- nrow(bs)
message("Row count: ", nrow_bs, " (expected 90-120)")
if (nrow_bs < 90 || nrow_bs > 120) {
  stop("BS row count out of expected range [90, 120]: ", nrow_bs, call. = FALSE)
}

# All USUBJID present in DM
dm_usubjids <- unique(dm$USUBJID)
bs_usubjids <- unique(bs$USUBJID)
missing_from_dm <- setdiff(bs_usubjids, dm_usubjids)
if (length(missing_from_dm) > 0) {
  stop(
    length(missing_from_dm), " USUBJID(s) in BS not found in DM.",
    call. = FALSE
  )
}
message("All USUBJID present in DM: OK")

# BSSEQ unique within each USUBJID
bsseq_dups <- bs %>%
  dplyr::count(USUBJID, BSSEQ) %>%
  dplyr::filter(n > 1)
if (nrow(bsseq_dups) > 0) {
  stop("BSSEQ is not unique within USUBJID for ", nrow(bsseq_dups), " group(s).",
       call. = FALSE)
}
message("BSSEQ unique per USUBJID: OK")

# BSTESTCD contains only permitted values
invalid_testcd <- setdiff(unique(bs$BSTESTCD), c("FFPEBL", "FFPESL", "HE"))
if (length(invalid_testcd) > 0) {
  stop("Unexpected BSTESTCD value(s): ", paste(invalid_testcd, collapse = ", "),
       call. = FALSE)
}
message("BSTESTCD values valid: OK")

# All subjects have FFPEBL and FFPESL
ffpe_check <- bs %>%
  dplyr::filter(BSTESTCD %in% c("FFPEBL", "FFPESL")) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::summarise(has_bl = any(BSTESTCD == "FFPEBL"),
                   has_sl = any(BSTESTCD == "FFPESL"),
                   .groups = "drop") %>%
  dplyr::filter(!has_bl | !has_sl)
if (nrow(ffpe_check) > 0) {
  stop(nrow(ffpe_check), " subject(s) missing FFPEBL or FFPESL.", call. = FALSE)
}
message("All subjects have FFPEBL and FFPESL: OK")

# HE count approximate (expect ~32 subjects = 80% of 40)
he_count <- sum(bs$BSTESTCD == "HE")
message("HE record count: ", he_count, " (expected ~32, ±10)")

# Summary table
message("\n--- BSTESTCD frequency ---")
print(dplyr::count(bs, BSTESTCD))

message("\n--- BSSPEC frequency ---")
print(dplyr::count(bs, BSSPEC))

message("\n--- BSANTREG frequency ---")
print(dplyr::count(bs, BSANTREG) %>% dplyr::arrange(BSANTREG))

# --- Write XPT ---------------------------------------------------------------

haven::write_xpt(bs, "cohort/output-data/sdtm/bs.xpt")
message("\nWrote: cohort/output-data/sdtm/bs.xpt (", nrow_bs, " records)")

# Persist RDS for downstream domain use
saveRDS(bs, "cohort/output-data/sdtm/bs.rds")
message("Wrote: cohort/output-data/sdtm/bs.rds")
