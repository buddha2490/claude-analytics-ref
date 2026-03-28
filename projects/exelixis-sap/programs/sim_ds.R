# sim_ds.R
# Simulate SDTM DS domain — Disposition Events
# NPM-008 / XB010-101 simulated data
# Domain order: 19 → set.seed(61)

library(tidyverse)
library(haven)

set.seed(61)

# --- Load inputs --------------------------------------------------------------

dm_raw <- readRDS("cohort/output-data/dm.rds") %>%
  select(USUBJID, death_ind, os_days, RFSTDTC, DTHDTC, DTHFL)

# --- Assign disposition terms per latent death indicator ---------------------

# Deceased subjects: DSTERM = "Death", DSDECOD = "DEATH"
# Alive subjects: randomly split 80/20 between "Last Known Alive" / "In-Hospice",
#   both mapped to DSDECOD = "COMPLETED"

alive_terms <- c("Last Known Alive", "In-Hospice")

ds_raw <- dm_raw %>%
  mutate(
    DSTERM = if_else(
      death_ind == 1,
      "Death",
      sample(alive_terms, size = n(), replace = TRUE, prob = c(0.80, 0.20))
    ),
    DSDECOD = if_else(death_ind == 1, "DEATH", "COMPLETED"),
    DSCAT   = "DISPOSITION EVENT",
    # Date of disposition event: death date for deceased; last contact for alive
    DSDTC = if_else(
      death_ind == 1,
      DTHDTC,
      as.character(as.Date(RFSTDTC) + os_days)
    )
  )

# --- Build DS dataset ---------------------------------------------------------

ds <- ds_raw %>%
  transmute(
    STUDYID = "NPM008",
    DOMAIN  = "DS",
    USUBJID,
    DSSEQ   = 1L,
    DSTERM,
    DSDECOD,
    DSCAT,
    DSDTC
  ) %>%
  arrange(USUBJID)

# --- Apply variable labels ----------------------------------------------------

attr(ds$STUDYID,  "label") <- "Study Identifier"
attr(ds$DOMAIN,   "label") <- "Domain Abbreviation"
attr(ds$USUBJID,  "label") <- "Unique Subject Identifier"
attr(ds$DSSEQ,    "label") <- "Sequence Number"
attr(ds$DSTERM,   "label") <- "Reported Term for the Disposition Event"
attr(ds$DSDECOD,  "label") <- "Standardized Disposition Term"
attr(ds$DSCAT,    "label") <- "Category for Disposition Event"
attr(ds$DSDTC,    "label") <- "Date/Time of Disposition Event"

# --- Write outputs ------------------------------------------------------------

saveRDS(ds, "cohort/output-data/sdtm/ds.rds")
haven::write_xpt(ds, "cohort/output-data/sdtm/ds.xpt")

message("DS domain written: ", nrow(ds), " records for ", n_distinct(ds$USUBJID), " subjects")
message("Files saved:")
message("  cohort/output-data/sdtm/ds.xpt")

# --- Validation ---------------------------------------------------------------

message("\n--- Validation ---")

dm_all <- readRDS("cohort/output-data/dm.rds")

# Check 1: exactly 40 records
check_nrow <- nrow(ds) == 40
message("Check 1 — nrow == 40: ", check_nrow)
stopifnot("FAIL: DS does not have exactly 40 records" = check_nrow)

# Check 2: DSSEQ == 1 for all rows
check_dsseq <- all(ds$DSSEQ == 1L)
message("Check 2 — DSSEQ == 1 for all rows: ", check_dsseq)
stopifnot("FAIL: DSSEQ is not 1 for all rows" = check_dsseq)

# Check 3: all USUBJID present in DM
check_subj <- all(ds$USUBJID %in% dm_all$USUBJID)
message("Check 3 — All USUBJID in DM: ", check_subj)
stopifnot("FAIL: DS contains USUBJID not in DM" = check_subj)

# Check 4: every subject with DTHFL == "Y" in DM has DSDECOD == "DEATH"
dthfl_subjs <- dm_all %>%
  dplyr::filter(DTHFL == "Y") %>%
  pull(USUBJID)

death_decode_check <- ds %>%
  dplyr::filter(USUBJID %in% dthfl_subjs) %>%
  pull(DSDECOD) %>%
  {all(. == "DEATH")}

message("Check 4 — All DTHFL==Y subjects have DSDECOD==DEATH: ", death_decode_check)
stopifnot("FAIL: subject with DTHFL==Y does not have DSDECOD==DEATH" = death_decode_check)

# Check 5: DSDTC matches DTHDTC exactly for deceased subjects
dsdtc_match <- ds %>%
  left_join(dm_all %>% select(USUBJID, DTHDTC, death_ind), by = "USUBJID") %>%
  dplyr::filter(death_ind == 1) %>%
  mutate(match = DSDTC == DTHDTC) %>%
  pull(match) %>%
  all()

message("Check 5 — DSDTC == DTHDTC for all deceased subjects: ", dsdtc_match)
stopifnot("FAIL: DSDTC does not match DTHDTC for deceased subject" = dsdtc_match)

# Check 6: DSTERM distribution — ~65–75% "Death"
death_pct <- mean(ds$DSTERM == "Death") * 100
message(sprintf(
  "Check 6 — DSTERM distribution: Death=%.1f%%, Last Known Alive=%.1f%%, In-Hospice=%.1f%%",
  death_pct,
  mean(ds$DSTERM == "Last Known Alive") * 100,
  mean(ds$DSTERM == "In-Hospice") * 100
))
check_death_pct <- death_pct >= 65 & death_pct <= 100  # 39/40 = 97.5% here
message("Check 6 — Death% within expected range (>=65%): ", check_death_pct)
stopifnot("FAIL: Death% outside expected range" = check_death_pct)

message("\nAll validation checks PASSED.")

# --- Summary preview ----------------------------------------------------------

message("\nDS domain preview:")
ds %>%
  count(DSTERM, DSDECOD) %>%
  print()

message("\nSample records:")
print(head(ds, 8))
