# =============================================================================
# sim_pr.R
# Simulate PR (Procedures) domain for NPM-008 / XB010-101
#
# Inputs:  cohort/output-data/dm.rds
# Outputs: cohort/output-data/sdtm/pr.xpt
#
# Section 4.12 of plan:
#   ~50% subjects have radiation, ~30% have surgery.
#   Radiation: 1 record per subject.
#   Surgery:   1-2 records (surgery + optional biopsy at 50%).
#   All procedures are pre-index (PRSTDTC < RFSTDTC).
# =============================================================================

library(tidyverse)
library(haven)

set.seed(54)  # PR is domain order 12; seed = 42 + 12

# --- Load DM spine ------------------------------------------------------------
dm <- readRDS("output-data/sdtm/dm.rds")

spine <- dm %>%
  dplyr::select(USUBJID, RFSTDTC)

# --- Per-subject flags and lobe assignment ------------------------------------
# Sample flags independently; subjects can have both, one, or neither.
# Lobe is assigned once per subject and applied to all their procedure records.

subject_flags <- spine %>%
  mutate(
    has_radiation = rbinom(n(), 1, 0.50),
    has_surgery   = rbinom(n(), 1, 0.30),
    # Same ICD-O3 lobe for all procedures for this subject
    prloc = sample(c("C34.1", "C34.2", "C34.3"),
                   size = n(),
                   replace = TRUE,
                   prob   = c(0.40, 0.10, 0.50))
  )

# --- Build procedure records per subject using purrr::pmap_dfr ---------------

build_subject_records <- function(usubjid, rfstdtc, has_radiation, has_surgery, prloc) {

  records <- list()

  if (has_radiation == 1) {
    # One radiation record
    start_offset <- sample(30:730, 1)
    prstdtc <- as.character(as.Date(rfstdtc) - start_offset)
    prendtc <- as.character(as.Date(prstdtc) + sample(0:14, 1))

    records[[length(records) + 1]] <- tibble(
      USUBJID = usubjid,
      PRTRT   = "Radiation",
      PRCAT   = "Radiation",
      PRLOC   = prloc,
      PRSTDTC = prstdtc,
      PRENDTC = prendtc
    )
  }

  if (has_surgery == 1) {
    # Determine if a biopsy (pathology specimen) accompanies the surgery
    has_specimen <- rbinom(1, 1, 0.50)

    start_offset <- sample(30:730, 1)
    surg_prstdtc <- as.character(as.Date(rfstdtc) - start_offset)
    surg_prendtc <- as.character(as.Date(surg_prstdtc) + sample(0:14, 1))

    if (has_specimen == 1) {
      prcat_surgery <- "Surgery/pathology (specimen)"
    } else {
      prcat_surgery <- "Surgery (no specimen)"
    }

    records[[length(records) + 1]] <- tibble(
      USUBJID = usubjid,
      PRTRT   = "Surgery",
      PRCAT   = prcat_surgery,
      PRLOC   = prloc,
      PRSTDTC = surg_prstdtc,
      PRENDTC = surg_prendtc
    )

    # Optional standalone biopsy record (50% chance, only when has_specimen=0)
    # Per spec: biopsy as a separate record when surgery has no specimen
    if (has_specimen == 0 && rbinom(1, 1, 0.50) == 1) {
      bx_prstdtc <- as.character(as.Date(rfstdtc) - sample(30:730, 1))
      bx_prendtc <- as.character(as.Date(bx_prstdtc) + sample(0:14, 1))

      records[[length(records) + 1]] <- tibble(
        USUBJID = usubjid,
        PRTRT   = "Biopsy",
        PRCAT   = "Pathology only (specimen)",
        PRLOC   = prloc,
        PRSTDTC = bx_prstdtc,
        PRENDTC = bx_prendtc
      )
    }
  }

  # Return NULL-safe: subjects with no procedures contribute 0 rows
  if (length(records) == 0) return(tibble())

  dplyr::bind_rows(records)
}

# Apply across all subjects
pr_raw <- purrr::pmap_dfr(
  .l = list(
    usubjid      = subject_flags$USUBJID,
    rfstdtc      = subject_flags$RFSTDTC,
    has_radiation = subject_flags$has_radiation,
    has_surgery  = subject_flags$has_surgery,
    prloc        = subject_flags$prloc
  ),
  .f = build_subject_records
)

# --- Assemble final dataset ---------------------------------------------------
pr <- pr_raw %>%
  # Add STUDYID and DOMAIN
  mutate(
    STUDYID = "NPM008",
    DOMAIN  = "PR"
  ) %>%
  # PRSEQ: sequential integer within each USUBJID
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(PRSEQ = dplyr::row_number()) %>%
  dplyr::ungroup() %>%
  # Enforce column order per SDTM convention
  dplyr::select(STUDYID, DOMAIN, USUBJID, PRSEQ, PRTRT, PRCAT, PRLOC, PRSTDTC, PRENDTC)

# --- Apply variable labels ----------------------------------------------------
attr(pr$STUDYID, "label") <- "Study Identifier"
attr(pr$DOMAIN,  "label") <- "Domain Abbreviation"
attr(pr$USUBJID, "label") <- "Unique Subject Identifier"
attr(pr$PRSEQ,   "label") <- "Sequence Number"
attr(pr$PRTRT,   "label") <- "Name of Procedure"
attr(pr$PRCAT,   "label") <- "Category for Procedure"
attr(pr$PRLOC,   "label") <- "Location of a Finding or Procedure"
attr(pr$PRSTDTC, "label") <- "Start Date/Time of Procedure"
attr(pr$PRENDTC, "label") <- "End Date/Time of Procedure"

# --- Validation ---------------------------------------------------------------
message("--- PR Validation ---")

# 1. All USUBJIDs exist in DM
orphan <- dplyr::anti_join(pr, dplyr::select(dm, USUBJID), by = "USUBJID")
stopifnot("Orphan USUBJIDs found in PR not in DM" = nrow(orphan) == 0)
message("PASS: All USUBJID in DM")

# 2. PRSEQ unique within USUBJID
dup_seq <- pr %>%
  dplyr::count(USUBJID, PRSEQ) %>%
  dplyr::filter(n > 1)
stopifnot("Duplicate PRSEQ within USUBJID" = nrow(dup_seq) == 0)
message("PASS: PRSEQ unique within USUBJID")

# 3. All PRSTDTC < RFSTDTC (all procedures pre-index)
date_check <- pr %>%
  dplyr::left_join(dplyr::select(dm, USUBJID, RFSTDTC), by = "USUBJID") %>%
  dplyr::filter(as.Date(PRSTDTC) >= as.Date(RFSTDTC))
stopifnot("PRSTDTC >= RFSTDTC found — must be pre-index" = nrow(date_check) == 0)
message("PASS: All PRSTDTC < RFSTDTC")

# 4. PRENDTC >= PRSTDTC
end_check <- pr %>%
  dplyr::filter(as.Date(PRENDTC) < as.Date(PRSTDTC))
stopifnot("PRENDTC < PRSTDTC found" = nrow(end_check) == 0)
message("PASS: PRENDTC >= PRSTDTC")

# 5. Coverage checks
n_total  <- nrow(dm)
n_rad    <- subject_flags %>% dplyr::filter(has_radiation == 1) %>% nrow()
n_surg   <- subject_flags %>% dplyr::filter(has_surgery == 1)   %>% nrow()
pct_rad  <- round(n_rad / n_total * 100, 1)
pct_surg <- round(n_surg / n_total * 100, 1)

message(sprintf("Subjects with radiation: %d / %d (%.1f%%) — expected 40-60%%", n_rad, n_total, pct_rad))
message(sprintf("Subjects with surgery:   %d / %d (%.1f%%) — expected 20-40%%", n_surg, n_total, pct_surg))

if (!dplyr::between(pct_rad, 40, 60))
  warning(sprintf("Radiation prevalence %.1f%% outside expected 40-60%% range.", pct_rad), call. = FALSE)
if (!dplyr::between(pct_surg, 20, 40))
  warning(sprintf("Surgery prevalence %.1f%% outside expected 20-40%% range.", pct_surg), call. = FALSE)

message(sprintf("Total PR records: %d", nrow(pr)))
message(sprintf("Subjects with >=1 PR record: %d / %d", dplyr::n_distinct(pr$USUBJID), n_total))

# --- Write XPT ----------------------------------------------------------------
saveRDS(pr, "output-data/sdtm/pr.rds")
haven::write_xpt(pr, "output-data/sdtm/pr.xpt")
message("Written: output-data/sdtm/pr.xpt")

# --- Preview ------------------------------------------------------------------
print(head(pr, 10))
