# =============================================================================
# Program:   sim_ie.R
# Study:     NPM-008 / XB010-101 External Control Arm
# Domain:    IE — Inclusion/Exclusion Criteria
# Purpose:   Simulate the IE domain. 10 records per subject (5 inclusion +
#            5 exclusion criteria). All subjects meet all criteria (enrolled).
# Seed:      set.seed(44) — domain offset 2 from base seed 42
# Author:    r-clinical-programmer agent
# Date:      2026-03-27
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)


set.seed(44)


# --- Constants ---------------------------------------------------------------

STUDYID    <- "NPM008"
OUTPUT_DIR <- "cohort/output-data"

# Inclusion/exclusion criteria lookup table
ie_criteria <- tribble(
  ~IETESTCD, ~IETEST,                                                                         ~IECAT,
  "IC01",    "Pathologically confirmed locally advanced or metastatic NSCLC",                 "INCLUSION",
  "IC02",    "Radiographically measurable disease",                                           "INCLUSION",
  "IC03",    "ECOG performance score 0 or 1",                                                 "INCLUSION",
  "IC04",    "Received prior systemic anticancer therapy",                                    "INCLUSION",
  "IC05",    "Age 18 or older",                                                               "INCLUSION",
  "EC01",    "Radiation therapy within 14 days prior to index date",                          "EXCLUSION",
  "EC02",    "Untreated brain metastases",                                                    "EXCLUSION",
  "EC03",    "Severe liver disease per Charlson Comorbidity Index",                           "EXCLUSION",
  "EC04",    "Surgery in 4 weeks prior to index date",                                        "EXCLUSION",
  "EC05",    "Diagnosis of another malignancy in 2 years prior to index date",                "EXCLUSION"
)


# --- Read DM spine -----------------------------------------------------------

dm <- readRDS(file.path(OUTPUT_DIR, "dm.rds"))


# --- Build IE dataset --------------------------------------------------------

# Cross-join each subject with the 10 criteria, then derive all variables
ie <- dm %>%
  dplyr::select(USUBJID, RFICDTC) %>%
  # One row per subject per criterion
  cross_join(ie_criteria) %>%
  # Sort for consistent IESEQ assignment: by subject then criterion order
  arrange(USUBJID, match(IETESTCD, ie_criteria$IETESTCD)) %>%
  group_by(USUBJID) %>%
  mutate(
    IESEQ = row_number()
  ) %>%
  ungroup() %>%
  mutate(
    STUDYID = STUDYID,
    DOMAIN  = "IE",
    # All subjects enrolled: inclusion met (YES), exclusion not met (NO)
    IEORRES = if_else(IECAT == "INCLUSION", "YES", "NO"),
    IESTRESC = IEORRES,
    # Date of collection = informed consent date from DM (already shifted)
    IEDTC = RFICDTC
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, IESEQ,
    IETESTCD, IETEST, IECAT,
    IEORRES, IESTRESC, IEDTC
  )


# --- Variable metadata for xportr --------------------------------------------

ie_meta <- tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "IESEQ",
    "IETESTCD", "IETEST", "IECAT",
    "IEORRES", "IESTRESC", "IEDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Incl/Excl Criterion Short Name",
    "Inclusion/Exclusion Criterion",
    "Incl/Excl Category",
    "I/E Criterion Original Result",
    "I/E Criterion Std Result",
    "Date of Collection"
  ),
  type = c(
    "character", "character", "character", "numeric",
    "character", "character", "character",
    "character", "character", "character"
  ),
  length = c(
    200L, 2L, 200L, NA_integer_,
    8L, 300L, 40L,
    8L, 8L, 20L
  )
)


# --- XPT export --------------------------------------------------------------

ie_xpt <- ie %>%
  xportr_label(ie_meta, domain = "IE") %>%
  xportr_type(ie_meta, domain = "IE") %>%
  xportr_length(ie_meta, domain = "IE")

saveRDS(ie_xpt, file.path(OUTPUT_DIR, "ie.rds"))
haven::write_xpt(ie_xpt, path = file.path(OUTPUT_DIR, "ie.xpt"))

message("IE XPT written to: ", file.path(OUTPUT_DIR, "ie.xpt"))


# --- Validation --------------------------------------------------------------

message("\n--- IE Validation ---")

# Check 1: Row count
stopifnot("nrow must be 400" = nrow(ie) == 400)
message("PASS nrow = ", nrow(ie))

# Check 2: All USUBJID in DM
orphan_subjects <- setdiff(unique(ie$USUBJID), dm$USUBJID)
stopifnot("All USUBJID must be in DM" = length(orphan_subjects) == 0)
message("PASS all USUBJID in DM (", dplyr::n_distinct(ie$USUBJID), " subjects)")

# Check 3: IESEQ unique within USUBJID and ranges 1-10
ieseq_check <- ie %>%
  group_by(USUBJID) %>%
  summarise(
    n_seq      = dplyr::n(),
    min_seq    = min(IESEQ),
    max_seq    = max(IESEQ),
    n_distinct = dplyr::n_distinct(IESEQ),
    .groups = "drop"
  )
stopifnot(
  "IESEQ must be unique within USUBJID" = all(ieseq_check$n_seq == ieseq_check$n_distinct),
  "IESEQ min must be 1"                 = all(ieseq_check$min_seq == 1),
  "IESEQ max must be 10"                = all(ieseq_check$max_seq == 10)
)
message("PASS IESEQ is unique within USUBJID and ranges 1-10")

# Check 4: No NA in IETESTCD
stopifnot("No NA in IETESTCD" = !anyNA(ie$IETESTCD))
message("PASS no NA in IETESTCD")

# Check 5: IEORRES values consistent with IECAT
ieorres_check <- ie %>%
  dplyr::filter(
    (IECAT == "INCLUSION" & IEORRES != "YES") |
    (IECAT == "EXCLUSION" & IEORRES != "NO")
  )
stopifnot("IEORRES must be YES for inclusion, NO for exclusion" = nrow(ieorres_check) == 0)
message("PASS IEORRES consistent with IECAT")

message("\nIE simulation complete: ", nrow(ie), " records, ",
        dplyr::n_distinct(ie$USUBJID), " subjects.")
