# =============================================================================
# Program: cohort/adam_adrs.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADRS — Response (Tumor Response Assessment per RECIST 1.1)
# Author: r-clinical-programmer agent
# Date: 2026-03-27
#
# Source Domains:
#   - RS: USUBJID, RSTESTCD, RSSTRESC, RSSTRESN, RSDTC, VISIT, VISITNUM, RSEVAL
#   - DM: USUBJID, STUDYID
#   - ADSL: USUBJID, TRTSDT (from cohort/output-data/adam/adsl.xpt)
#
# CDISC References:
#   - ADaM-IG v1.3 BDS structure for oncology endpoints
#   - RECIST 1.1 confirmation criteria (SAP Section)
#
# Dependencies:
#   - ADSL (cohort/output-data/adam/adsl.xpt) — required for TRTSDT
#
# Key Logic:
#   - Filter RS to RSTESTCD = 'RECIST' for visit-level per-assessment records
#   - RSTESTCD = 'CLINRES' records are NOT used (clinician-stated BOR)
#   - BOR derivation requires CONFIRMED response: two consecutive CR or PR
#     assessments with >=28 day interval per SAP
#   - AVAL numeric coding (study-specific): 1=CR, 2=PR, 3=SD, 4=PD, 5=NE
#   - ADY = ADT - TRTSDT + 1 (if on/after TRTSDT), else ADT - TRTSDT
#
# REVISIT:
#   - Confirmed response per SAP (≥28-day interval).
#     See artifacts/NPM-008/Open-questions-cdisc.md R3
#   - AVAL numeric coding is study-specific (not CDISC standard).
#     See artifacts/NPM-008/Open-questions-cdisc.md R8
# =============================================================================

# --- Load packages -----------------------------------------------------------
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------
message("Reading source data...")
dm <- haven::read_xpt("cohort/output-data/sdtm/dm.xpt")
rs <- haven::read_xpt("cohort/output-data/sdtm/rs.xpt")
adsl <- haven::read_xpt("cohort/output-data/adam/adsl.xpt")

message("  DM rows: ", nrow(dm))
message("  RS rows: ", nrow(rs))
message("  ADSL rows: ", nrow(adsl))

# --- Filter RS to RECIST assessments -----------------------------------------
# NOTE: RSTESTCD = 'RECIST' contains visit-level per-assessment records
# NOTE: RSTESTCD = 'CLINRES' are clinician-stated BOR and are NOT used
message("Filtering RS to RSTESTCD = 'RECIST'...")
rs_recist <- rs %>%
  filter(RSTESTCD == "RECIST")

message("  RS RECIST rows: ", nrow(rs_recist))

# --- Create OVRLRESP (per-visit response) records ----------------------------
message("Creating OVRLRESP records...")

# Merge with ADSL to get TRTSDT
# Note: STUDYID already in RS domain
adrs_ovrl <- rs_recist %>%
  left_join(adsl %>% select(USUBJID, TRTSDT), by = "USUBJID") %>%
  mutate(
    PARAMCD = "OVRLRESP",
    PARAM = "Overall Response by Investigator",
    AVALC = RSSTRESC,
    # NOTE: Study-specific AVAL coding — not CDISC standard
    # Lower number = better response
    AVAL = case_when(
      RSSTRESC == "CR" ~ 1,
      RSSTRESC == "PR" ~ 2,
      RSSTRESC == "SD" ~ 3,
      RSSTRESC == "PD" ~ 4,
      RSSTRESC == "NE" ~ 5,
      TRUE ~ NA_real_
    ),
    ADT = as.numeric(as.Date(RSDTC)),
    # ADY calculation per CDISC: no day zero
    ADY = if_else(as.Date(RSDTC) >= as.Date(TRTSDT, origin = "1970-01-01"),
                  as.numeric(as.Date(RSDTC) - as.Date(TRTSDT, origin = "1970-01-01")) + 1,
                  as.numeric(as.Date(RSDTC) - as.Date(TRTSDT, origin = "1970-01-01"))),
    AVISIT = VISIT,
    AVISITN = VISITNUM,
    ANL01FL = "Y"  # All RECIST assessments included in primary analysis
  )

# --- Derive baseline flag (ABLFL) --------------------------------------------
message("Deriving baseline flag (ABLFL)...")

# Baseline = last assessment before or on TRTSDT
adrs_ovrl <- adrs_ovrl %>%
  group_by(USUBJID) %>%
  mutate(
    # Find max baseline date (assessments <= TRTSDT)
    max_bl_dt = max(ADT[ADT <= TRTSDT], na.rm = TRUE),
    # Flag baseline record (handle case where no baseline exists)
    ABLFL = if_else(
      !is.infinite(max_bl_dt) & ADT == max_bl_dt,
      "Y",
      NA_character_
    )
  ) %>%
  ungroup() %>%
  select(-max_bl_dt)

# --- Derive BOR (Best Overall Response) --------------------------------------
message("Deriving BOR (confirmed response per SAP)...")

# REVISIT: Confirmed response per SAP (≥28-day interval).
#          See artifacts/NPM-008/Open-questions-cdisc.md R3
#
# BOR Logic:
# 1. Confirmed CR: Any CR with a second CR/PR ≥28 days later → BOR = CR
# 2. Confirmed PR: Any PR with a second PR/CR ≥28 days later (no confirmed CR) → BOR = PR
# 3. SD (no confirmed CR/PR): → BOR = SD
# 4. Only PD (no SD/CR/PR): → BOR = PD
# 5. No post-baseline assessments: → BOR = NE

# Get post-baseline assessments ordered by date
adrs_post_bl <- adrs_ovrl %>%
  filter(ADT > TRTSDT, !is.na(AVALC)) %>%
  arrange(USUBJID, ADT)

# Derive BOR per subject
bor_derivation <- adrs_post_bl %>%
  group_by(USUBJID) %>%
  summarise(
    # Check for confirmed CR
    confirmed_cr = any(sapply(seq_along(AVALC), function(i) {
      if (i == length(AVALC)) return(FALSE)
      if (AVALC[i] != "CR") return(FALSE)
      # Check if any subsequent assessment is CR or PR and ≥28 days later
      any(AVALC[(i+1):length(AVALC)] %in% c("CR", "PR") &
            ADT[(i+1):length(AVALC)] - ADT[i] >= 28)
    })),

    # Check for confirmed PR (only if no confirmed CR)
    confirmed_pr = any(sapply(seq_along(AVALC), function(i) {
      if (i == length(AVALC)) return(FALSE)
      if (AVALC[i] != "PR") return(FALSE)
      # Check if any subsequent assessment is PR or CR and ≥28 days later
      any(AVALC[(i+1):length(AVALC)] %in% c("CR", "PR") &
            ADT[(i+1):length(AVALC)] - ADT[i] >= 28)
    })),

    # Check for SD
    has_sd = any(AVALC == "SD"),

    # Check for PD
    has_pd = any(AVALC == "PD"),

    # Get earliest post-baseline assessment date for BOR record
    bor_dt = min(ADT),

    .groups = "drop"
  ) %>%
  mutate(
    BOR_AVALC = case_when(
      confirmed_cr ~ "CR",
      confirmed_pr ~ "PR",
      has_sd ~ "SD",
      has_pd ~ "PD",
      TRUE ~ "NE"
    ),
    # NOTE: Study-specific AVAL coding — not CDISC standard
    BOR_AVAL = case_when(
      BOR_AVALC == "CR" ~ 1,
      BOR_AVALC == "PR" ~ 2,
      BOR_AVALC == "SD" ~ 3,
      BOR_AVALC == "PD" ~ 4,
      BOR_AVALC == "NE" ~ 5,
      TRUE ~ NA_real_
    )
  )

# Handle subjects with no post-baseline assessments
subjects_no_post_bl <- adsl %>%
  anti_join(adrs_post_bl %>% distinct(USUBJID), by = "USUBJID") %>%
  select(USUBJID, TRTSDT) %>%
  mutate(
    BOR_AVALC = "NE",
    BOR_AVAL = 5,
    bor_dt = as.numeric(NA)
  )

# Combine BOR derivations
bor_all <- bind_rows(
  bor_derivation %>% select(USUBJID, BOR_AVALC, BOR_AVAL, bor_dt),
  subjects_no_post_bl %>% select(USUBJID, BOR_AVALC, BOR_AVAL, bor_dt)
)

# Create BOR records
adrs_bor <- bor_all %>%
  left_join(adsl %>% select(USUBJID, TRTSDT), by = "USUBJID") %>%
  left_join(dm %>% select(USUBJID, STUDYID), by = "USUBJID") %>%
  mutate(
    PARAMCD = "BOR",
    PARAM = "Best Overall Response (Confirmed per RECIST 1.1)",
    AVALC = BOR_AVALC,
    AVAL = BOR_AVAL,
    ADT = bor_dt,
    ADY = if_else(!is.na(bor_dt),
                  if_else(as.Date(bor_dt, origin = "1970-01-01") >= as.Date(TRTSDT, origin = "1970-01-01"),
                          as.numeric(as.Date(bor_dt, origin = "1970-01-01") - as.Date(TRTSDT, origin = "1970-01-01")) + 1,
                          as.numeric(as.Date(bor_dt, origin = "1970-01-01") - as.Date(TRTSDT, origin = "1970-01-01"))),
                  NA_real_),
    AVISIT = "Overall",
    AVISITN = 999,
    ANL01FL = "Y",
    ABLFL = NA_character_
  ) %>%
  select(-bor_dt)

message("  BOR records created: ", nrow(adrs_bor))

# --- Combine OVRLRESP and BOR records ----------------------------------------
message("Combining OVRLRESP and BOR records...")

adrs <- bind_rows(
  adrs_ovrl %>% select(STUDYID, USUBJID, PARAMCD, PARAM, AVAL, AVALC,
                       ADT, ADY, AVISIT, AVISITN, ABLFL, ANL01FL),
  adrs_bor %>% select(STUDYID, USUBJID, PARAMCD, PARAM, AVAL, AVALC,
                      ADT, ADY, AVISIT, AVISITN, ABLFL, ANL01FL)
) %>%
  arrange(USUBJID, PARAMCD, AVISITN)

message("  Total ADRS rows: ", nrow(adrs))

# --- Validation checks -------------------------------------------------------
message("\n=== Validation Checks ===")
message("Row count: ", nrow(adrs))
message("Subject count: ", n_distinct(adrs$USUBJID))
message("PARAMCD distribution:")
print(table(adrs$PARAMCD, useNA = "ifany"))
message("\nBOR AVALC distribution:")
print(table(adrs %>% filter(PARAMCD == "BOR") %>% pull(AVALC), useNA = "ifany"))
message("\nABLFL distribution:")
print(table(adrs$ABLFL, useNA = "ifany"))

# Check for missing key variables
key_vars <- c("STUDYID", "USUBJID", "PARAMCD", "AVALC", "AVAL")
message("\nMissing values in key variables:")
missing_counts <- sapply(adrs[, key_vars], function(x) sum(is.na(x)))
print(missing_counts)

# Check that all subjects are in DM
stopifnot("All ADRS subjects must be in DM" = all(adrs$USUBJID %in% dm$USUBJID))
message("✓ All subjects in ADRS are present in DM")

# Check unique keys
key_combo <- adrs %>%
  group_by(USUBJID, PARAMCD, AVISITN) %>%
  filter(n() > 1)
stopifnot("Key combination (USUBJID, PARAMCD, AVISITN) must be unique" = nrow(key_combo) == 0)
message("✓ Key combination (USUBJID, PARAMCD, AVISITN) is unique")

# --- Apply attributes and write XPT ------------------------------------------
message("\n=== Applying attributes and writing XPT ===")

# Build metadata frame for xportr
adrs_meta <- tibble::tibble(
  variable = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "AVAL", "AVALC",
               "ADT", "ADY", "AVISIT", "AVISITN", "ABLFL", "ANL01FL"),
  label = c("Study Identifier", "Unique Subject Identifier",
            "Parameter Code", "Parameter",
            "Analysis Value (Numeric)", "Analysis Value (Character)",
            "Analysis Date", "Analysis Relative Day",
            "Analysis Visit", "Analysis Visit Number",
            "Baseline Record Flag", "Analysis Record Flag 01"),
  type = c("character", "character", "character", "character",
           "numeric", "character", "numeric", "numeric",
           "character", "numeric", "character", "character")
)

adrs <- adrs %>%
  xportr::xportr_label(metadata = adrs_meta, domain = "ADRS") %>%
  xportr::xportr_type(metadata = adrs_meta, domain = "ADRS")

# Save dataset
saveRDS(adrs, "cohort/output-data/adam/adrs.rds")
haven::write_xpt(adrs, "cohort/output-data/adam/adrs.xpt")
message("✓ ADRS dataset saved to: cohort/output-data/adam/adrs.xpt")

message("\n=== ADRS derivation complete ===")
