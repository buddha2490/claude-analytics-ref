# =============================================================================
# Program: projects/exelixis-sap/programs/adam_adrs.R
# Study: NPM-008 / Exelixis XB010-100
# Dataset: ADRS — Response (Tumor Response per RECIST 1.1)
# Author: r-clinical-programmer agent
# Date: 2026-03-29
#
# Source Domains:
#   - RS: USUBJID, RSTESTCD, RSSTRESC, RSSTRESN, RSDTC, VISIT, VISITNUM, RSEVAL
#   - DM: USUBJID, STUDYID
#   - ADSL: USUBJID, TRTSDT
#
# CDISC References:
#   - ADaM-IG v1.3 (BDS structure)
#   - RECIST 1.1 response criteria with confirmation requirement
#   - Open-questions-cdisc.md R3: BOR requires confirmed response (≥28 days)
#   - Open-questions-cdisc.md R8: AVAL coding 1=CR, 2=PR, 3=SD, 4=PD, 5=NE
#
# Dependencies:
#   - ADSL (projects/exelixis-sap/output-data/adam/adsl.xpt) — required for TRTSDT
#   - RS (projects/exelixis-sap/output-data/sdtm/rs.xpt) — source of response assessments
#   - DM (projects/exelixis-sap/output-data/sdtm/dm.xpt) — subject identifiers
# =============================================================================

library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(xportr)

# --- Read source data --------------------------------------------------------

dm <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/dm.xpt")
rs <- haven::read_xpt("projects/exelixis-sap/output-data/sdtm/rs.xpt")
adsl <- haven::read_xpt("projects/exelixis-sap/output-data/adam/adsl.xpt")

# --- Data contract validation ------------------------------------------------

message("=== Step 4: Data Contract Validation ===")

# Expected variables from plan Section 4.4
plan_vars_dm <- c("USUBJID", "STUDYID")
plan_vars_rs <- c("USUBJID", "RSTESTCD", "RSSTRESC", "RSDTC",
                  "VISIT", "VISITNUM", "RSEVAL")
plan_vars_adsl <- c("USUBJID", "TRTSDT")

actual_vars_dm <- names(dm)
actual_vars_rs <- names(rs)
actual_vars_adsl <- names(adsl)

# Validate DM
missing_vars_dm <- setdiff(plan_vars_dm, actual_vars_dm)
if (length(missing_vars_dm) > 0) {
  stop(
    "Plan lists variables not found in DM: ", paste(missing_vars_dm, collapse=", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# Validate RS
missing_vars_rs <- setdiff(plan_vars_rs, actual_vars_rs)
if (length(missing_vars_rs) > 0) {
  stop(
    "Plan lists variables not found in RS: ", paste(missing_vars_rs, collapse=", "),
    "\nActual RS variables: ", paste(actual_vars_rs, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (RS): All ", length(plan_vars_rs), " expected variables found")

# Validate ADSL
missing_vars_adsl <- setdiff(plan_vars_adsl, actual_vars_adsl)
if (length(missing_vars_adsl) > 0) {
  stop(
    "Plan lists variables not found in ADSL: ", paste(missing_vars_adsl, collapse=", "),
    "\nActual ADSL variables: ", paste(actual_vars_adsl, collapse=", "),
    call. = FALSE
  )
}
message("✓ Data contract OK (ADSL): All ", length(plan_vars_adsl), " expected variables found")

# --- Exploration (for dev log only) ------------------------------------------

message("\n=== RS Domain Exploration ===")
message("Total RS records: ", nrow(rs))
message("Subjects with RS data: ", dplyr::n_distinct(rs$USUBJID))
message("\nRSTESTCD frequencies:")
print(table(rs$RSTESTCD, useNA = "ifany"))
message("\nRSSTRESC frequencies (RSTESTCD=RECIST):")
print(table(rs$RSSTRESC[rs$RSTESTCD == "RECIST"], useNA = "ifany"))

# --- Filter to RECIST assessments --------------------------------------------

# Per plan: Use RSTESTCD = 'RECIST' for visit-level assessments
# RSTESTCD = 'CLINRES' (clinician-stated BOR) is excluded per plan guidance
rs_recist <- rs %>%
  dplyr::filter(RSTESTCD == "RECIST")

message("\nFiltered to RSTESTCD=RECIST: ", nrow(rs_recist), " records")

# --- Create OVRLRESP (per-visit overall response) records -------------------

ovrlresp <- rs_recist %>%
  dplyr::left_join(
    adsl %>% dplyr::select(USUBJID, TRTSDT),
    by = "USUBJID"
  ) %>%
  dplyr::mutate(
    PARAMCD = "OVRLRESP",
    PARAM = "Overall Response by Investigator",
    AVALC = RSSTRESC,
    # NOTE: Study-specific AVAL coding — not CDISC standard
    # Per Open-questions-cdisc.md R8: 1=CR, 2=PR, 3=SD, 4=PD, 5=NE
    AVAL = dplyr::case_when(
      AVALC == "CR" ~ 1,
      AVALC == "PR" ~ 2,
      AVALC == "SD" ~ 3,
      AVALC == "PD" ~ 4,
      AVALC == "NE" ~ 5,
      TRUE ~ NA_real_
    ),
    # Convert RSDTC to numeric date
    ADT = as.numeric(lubridate::ymd(RSDTC)),
    # Study day calculation (no day zero per CDISC)
    ADY = dplyr::if_else(
      !is.na(ADT) & !is.na(TRTSDT) & ADT >= TRTSDT,
      as.integer(ADT - TRTSDT + 1),
      dplyr::if_else(
        !is.na(ADT) & !is.na(TRTSDT) & ADT < TRTSDT,
        as.integer(ADT - TRTSDT),
        NA_integer_
      )
    )
  ) %>%
  dplyr::group_by(USUBJID) %>%
  dplyr::mutate(
    # Baseline flag: last assessment before or on TRTSDT
    max_prebaseline = max(ADT[!is.na(ADT) & !is.na(TRTSDT) & ADT <= TRTSDT], na.rm = TRUE),
    ABLFL = dplyr::if_else(
      !is.na(ADT) & !is.na(max_prebaseline) & is.finite(max_prebaseline) & ADT == max_prebaseline,
      "Y",
      NA_character_
    )
  ) %>%
  dplyr::ungroup() %>%
  dplyr::mutate(
    # ANL01FL: primary analysis flag (all post-baseline RECIST assessments)
    ANL01FL = dplyr::if_else(
      !is.na(ADT) & !is.na(TRTSDT) & ADT > TRTSDT,
      "Y",
      NA_character_
    )
  ) %>%
  dplyr::select(
    STUDYID, USUBJID, PARAMCD, PARAM, AVALC, AVAL, ADT, ADY, VISIT, VISITNUM,
    ABLFL, ANL01FL, TRTSDT
  )

message("\nOVRLRESP records created: ", nrow(ovrlresp))

# --- Derive BOR (Best Overall Response) with confirmation --------------------

# REVISIT: Confirmed response per SAP (≥28-day interval)
# See projects/exelixis-sap/artifacts/Open-questions-cdisc.md R3
#
# BOR logic (RECIST 1.1 — confirmed response):
# 1. Confirmed CR: CR with second CR/PR ≥28 days later → BOR = CR
# 2. Confirmed PR: PR with second PR/CR ≥28 days later (no confirmed CR) → BOR = PR
# 3. SD present (no confirmed CR/PR) → BOR = SD
# 4. Only PD (no SD/CR/PR) → BOR = PD
# 5. No evaluable post-baseline assessments → BOR = NE

bor <- ovrlresp %>%
  dplyr::filter(ANL01FL == "Y") %>%  # Post-baseline only
  dplyr::group_by(USUBJID) %>%
  dplyr::arrange(USUBJID, ADT) %>%
  dplyr::summarise(
    STUDYID = dplyr::first(STUDYID),
    TRTSDT = dplyr::first(TRTSDT),
    # Check for confirmed CR: Any CR with CR/PR ≥28 days later
    has_confirmed_cr = any(
      AVALC == "CR" &
      sapply(seq_along(AVALC), function(i) {
        if (AVALC[i] == "CR") {
          any(AVALC[(i+1):length(AVALC)] %in% c("CR", "PR") &
              (ADT[(i+1):length(ADT)] - ADT[i]) >= 28, na.rm = TRUE)
        } else {
          FALSE
        }
      })
    ),
    # Check for confirmed PR: Any PR with PR/CR ≥28 days later
    has_confirmed_pr = any(
      AVALC == "PR" &
      sapply(seq_along(AVALC), function(i) {
        if (AVALC[i] == "PR") {
          any(AVALC[(i+1):length(AVALC)] %in% c("PR", "CR") &
              (ADT[(i+1):length(ADT)] - ADT[i]) >= 28, na.rm = TRUE)
        } else {
          FALSE
        }
      })
    ),
    has_sd = any(AVALC == "SD"),
    has_pd = any(AVALC == "PD"),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    PARAMCD = "BOR",
    PARAM = "Best Overall Response by Investigator (Confirmed)",
    AVALC = dplyr::case_when(
      has_confirmed_cr ~ "CR",
      has_confirmed_pr ~ "PR",
      has_sd ~ "SD",
      has_pd ~ "PD",
      TRUE ~ "NE"
    ),
    # NOTE: Study-specific AVAL coding — not CDISC standard
    AVAL = dplyr::case_when(
      AVALC == "CR" ~ 1,
      AVALC == "PR" ~ 2,
      AVALC == "SD" ~ 3,
      AVALC == "PD" ~ 4,
      AVALC == "NE" ~ 5,
      TRUE ~ NA_real_
    ),
    # BOR record has no specific date — set to missing
    ADT = NA_real_,
    ADY = NA_integer_,
    VISIT = NA_character_,
    VISITNUM = NA_real_,
    ABLFL = NA_character_,
    ANL01FL = "Y"  # BOR is included in primary analysis
  ) %>%
  dplyr::select(
    STUDYID, USUBJID, PARAMCD, PARAM, AVALC, AVAL, ADT, ADY, VISIT, VISITNUM,
    ABLFL, ANL01FL
  )

message("BOR records created: ", nrow(bor))
message("BOR distribution:")
print(table(bor$AVALC, useNA = "ifany"))

# --- Combine OVRLRESP and BOR records ----------------------------------------

# Remove TRTSDT helper column from ovrlresp before combining
ovrlresp <- ovrlresp %>%
  dplyr::select(-TRTSDT)

adrs <- dplyr::bind_rows(ovrlresp, bor) %>%
  dplyr::arrange(USUBJID, PARAMCD, ADT)

# --- Validation checks -------------------------------------------------------

message("\n=== Step 7: Validation ===")
message("Total ADRS records: ", nrow(adrs))
message("Subjects in ADRS: ", dplyr::n_distinct(adrs$USUBJID))
message("OVRLRESP records: ", sum(adrs$PARAMCD == "OVRLRESP", na.rm = TRUE))
message("BOR records: ", sum(adrs$PARAMCD == "BOR", na.rm = TRUE))

# Check all subjects are in DM
if (!all(adrs$USUBJID %in% dm$USUBJID)) {
  stop("ADRS contains subjects not found in DM", call. = FALSE)
}
message("✓ All ADRS subjects exist in DM")

# Check unique keys (USUBJID + PARAMCD + ADT for OVRLRESP)
adrs_ovrlresp <- adrs %>% dplyr::filter(PARAMCD == "OVRLRESP")
if (any(duplicated(adrs_ovrlresp[, c("USUBJID", "PARAMCD", "ADT")]))) {
  stop("Duplicate keys found in OVRLRESP records (USUBJID + PARAMCD + ADT)",
       call. = FALSE)
}
message("✓ No duplicate OVRLRESP keys")

# Check BOR: one record per subject
adrs_bor <- adrs %>% dplyr::filter(PARAMCD == "BOR")
if (any(duplicated(adrs_bor[, c("USUBJID", "PARAMCD")]))) {
  stop("Duplicate BOR records found for some subjects", call. = FALSE)
}
message("✓ One BOR record per subject")

# Check AVAL coding
invalid_aval <- adrs %>%
  dplyr::filter(!is.na(AVAL) & !AVAL %in% 1:5)
if (nrow(invalid_aval) > 0) {
  stop("Invalid AVAL values found (must be 1-5)", call. = FALSE)
}
message("✓ All AVAL values in valid range (1-5)")

# Check ANL01FL is Y or blank
invalid_anl01fl <- adrs %>%
  dplyr::filter(!is.na(ANL01FL) & ANL01FL != "Y")
if (nrow(invalid_anl01fl) > 0) {
  stop("Invalid ANL01FL values found (must be Y or blank)", call. = FALSE)
}
message("✓ ANL01FL uses Y/blank convention")

# --- Apply xportr attributes -------------------------------------------------

adrs_meta <- tibble::tibble(
  variable = c("STUDYID", "USUBJID", "PARAMCD", "PARAM", "AVALC", "AVAL",
               "ADT", "ADY", "VISIT", "VISITNUM", "ABLFL", "ANL01FL"),
  label = c(
    "Study Identifier",
    "Unique Subject Identifier",
    "Parameter Code",
    "Parameter",
    "Analysis Value (Character)",
    "Analysis Value (Numeric)",
    "Analysis Date",
    "Analysis Relative Day",
    "Visit Name",
    "Visit Number",
    "Baseline Record Flag",
    "Analysis Record Flag 01"
  ),
  type = c(
    "character", "character", "character", "character", "character", "numeric",
    "numeric", "integer", "character", "numeric", "character", "character"
  )
)

adrs <- adrs %>%
  xportr::xportr_label(metadata = adrs_meta, domain = "ADRS") %>%
  xportr::xportr_type(metadata = adrs_meta, domain = "ADRS")

# --- Save dataset ------------------------------------------------------------

haven::write_xpt(
  adrs,
  "projects/exelixis-sap/output-data/adam/adrs.xpt",
  version = 5
)

message("\n=== Step 8: Save Complete ===")
message("Dataset saved to: projects/exelixis-sap/output-data/adam/adrs.xpt")
message("Program complete: ", Sys.time())
