# =============================================================================
# sim_ds.R — Disposition
# Study: NPM-008 / XB010-101 ECA
# Seed: 42 + 19 = 61
# Wave: 1
# Dependencies: dm.rds
# Expected rows: 40 (1 per subject)
# Working directory: projects/exelixis-sap/
# =============================================================================

set.seed(61)

# --- Load dependencies -------------------------------------------------------
dm_full <- readRDS("output-data/sdtm/dm.rds")

# --- Load CT reference -------------------------------------------------------
ct_ref <- readRDS("output-data/sdtm/ct_reference.rds")

# --- Source validation functions ---------------------------------------------
source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Generate DS data --------------------------------------------------------

# DS structure: One record per subject. Final disposition at study end.
# DSDECOD="DEATH" iff DTHFL="Y" in DM.
# Of alive subjects: 80% "Last Known Alive", 20% "In-Hospice".
# DSDTC = DTHDTC if deceased; else RFSTDTC + os_days (last contact date).

ds <- dm_full %>%
  mutate(
    # Determine disposition based on death flag
    deceased = (!is.na(DTHFL) & DTHFL == "Y"),

    # For alive subjects, assign 80% "Last Known Alive", 20% "In-Hospice"
    alive_category = if_else(
      deceased,
      NA_character_,
      sample(c("Last Known Alive", "In-Hospice"),
             n(),
             replace = TRUE,
             prob = c(0.8, 0.2))
    ),

    # DSTERM and DSDECOD
    DSTERM = case_when(
      deceased ~ "Death",
      alive_category == "In-Hospice" ~ "In-Hospice",
      TRUE ~ "Last Known Alive"
    ),
    DSDECOD = case_when(
      deceased ~ "DEATH",
      alive_category == "In-Hospice" ~ "COMPLETED",
      TRUE ~ "COMPLETED"
    ),

    # DSDTC: DTHDTC if deceased, else RFSTDTC + os_days (last contact)
    ds_raw_date = if_else(
      deceased,
      as.Date(DTHDTC),
      as.Date(RFSTDTC) + os_days
    ),
    # Apply date shift
    DSDTC = as.character(ds_raw_date + date_shift),

    # Standard variables
    DOMAIN = "DS",
    DSSEQ = 1L,
    DSCAT = "DISPOSITION EVENT"
  ) %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    DSSEQ,
    DSTERM,
    DSDECOD,
    DSCAT,
    DSDTC
  )

# --- Domain-specific validation closure --------------------------------------
validate_ds <- function(domain_df, dm_ref) {
  checks <- list()

  # D1: DSDECOD="DEATH" iff DTHFL="Y" in DM
  ds_dm <- domain_df %>%
    left_join(dm_ref %>% select(USUBJID, DTHFL, DTHDTC, RFSTDTC), by = "USUBJID")

  death_mismatch <- ds_dm %>%
    filter(
      (DSDECOD == "DEATH" & (is.na(DTHFL) | DTHFL != "Y")) |
      (DSDECOD != "DEATH" & !is.na(DTHFL) & DTHFL == "Y")
    )

  checks[[1]] <- list(
    check_id = "D1",
    description = "DSDECOD='DEATH' iff DTHFL='Y' in DM",
    result = if (nrow(death_mismatch) == 0) "PASS" else "FAIL",
    detail = if (nrow(death_mismatch) > 0)
      sprintf("%d records with DSDECOD-DTHFL mismatch", nrow(death_mismatch))
    else ""
  )

  # D2: DSDTC >= RFSTDTC
  invalid_dates <- ds_dm %>%
    filter(!is.na(DSDTC), !is.na(RFSTDTC), DSDTC < RFSTDTC)

  checks[[2]] <- list(
    check_id = "D2",
    description = "DSDTC >= RFSTDTC for all records",
    result = if (nrow(invalid_dates) == 0) "PASS" else "FAIL",
    detail = if (nrow(invalid_dates) > 0)
      sprintf("%d records with DSDTC < RFSTDTC", nrow(invalid_dates))
    else ""
  )

  # D3: DSSEQ = 1 for all records
  checks[[3]] <- list(
    check_id = "D3",
    description = "DSSEQ = 1 for all records",
    result = if (all(domain_df$DSSEQ == 1)) "PASS" else "FAIL",
    detail = if (any(domain_df$DSSEQ != 1))
      sprintf("%d records with DSSEQ != 1", sum(domain_df$DSSEQ != 1))
    else ""
  )

  # D4: DSCAT = "DISPOSITION EVENT" for all records
  checks[[4]] <- list(
    check_id = "D4",
    description = "DSCAT = 'DISPOSITION EVENT' for all records",
    result = if (all(domain_df$DSCAT == "DISPOSITION EVENT")) "PASS" else "FAIL",
    detail = if (any(domain_df$DSCAT != "DISPOSITION EVENT"))
      sprintf("%d records with invalid DSCAT", sum(domain_df$DSCAT != "DISPOSITION EVENT"))
    else ""
  )

  # D5: Valid DSDECOD values
  valid_dsdecod <- c("DEATH", "COMPLETED", "LOST TO FOLLOW-UP")
  invalid_dsdecod <- domain_df %>%
    filter(!DSDECOD %in% valid_dsdecod)

  checks[[5]] <- list(
    check_id = "D5",
    description = "DSDECOD values are valid CT terms",
    result = if (nrow(invalid_dsdecod) == 0) "PASS" else "FAIL",
    detail = if (nrow(invalid_dsdecod) > 0)
      sprintf("%d records with invalid DSDECOD: %s",
              nrow(invalid_dsdecod),
              paste(unique(invalid_dsdecod$DSDECOD), collapse = ", "))
    else ""
  )

  checks
}

# --- Run validation ----------------------------------------------------------
validation_result <- validate_sdtm_domain(
  domain_df = ds,
  domain_code = "DS",
  dm_ref = dm_full,
  expected_rows = c(40, 40),
  ct_reference = NULL,
  domain_checks = validate_ds
)

# --- Save output -------------------------------------------------------------
saveRDS(ds, "output-data/sdtm/ds.rds")
message("✓ DS saved: output-data/sdtm/ds.rds (", nrow(ds), " rows)")

# --- Log result --------------------------------------------------------------
log_sdtm_result(
  domain_code = "DS",
  wave = 1,
  row_count = nrow(ds),
  col_count = ncol(ds),
  validation_result = validation_result
)

message("✓ DS validation: ", validation_result$verdict)
message("✓ DS log: logs/sdtm_domain_log_", format(Sys.Date(), "%Y-%m-%d"), ".md")

# --- Return data frame -------------------------------------------------------
ds
