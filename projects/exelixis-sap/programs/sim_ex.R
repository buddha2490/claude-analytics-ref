# =============================================================================
# sim_ex.R
# NPM-008 / XB010-101 SDTM EX Domain Simulation
#
# One record per subject. Treatment assignment driven by latent biomarker
# and prior-therapy variables from dm.rds.
#
# Outputs:
#   cohort/output-data/sdtm/ex.xpt
#   cohort/output-data/sdtm/ex.rds
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(haven)
  library(xportr)
})

set.seed(42 + 9)  # 51 — EX is domain order 9

# --- Paths -------------------------------------------------------------------

dm_path  <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/sdtm/dm.rds"
xpt_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/sdtm/ex.xpt"
rds_path <- "/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/output-data/sdtm/ex.rds"

# --- Load DM spine -----------------------------------------------------------

dm <- readRDS(dm_path) %>%
  dplyr::select(
    USUBJID, RFSTDTC,
    pfs_days, os_days, death_ind,
    pdl1_status, egfr_status, alk_status, n_prior_lots
  )

stopifnot(nrow(dm) == 40)

# --- Dose / route lookup table -----------------------------------------------
# Maps each treatment name to (EXDOSTXT, EXDOSU, EXROUTE)

dose_lookup <- list(
  "Osimertinib"             = list(dose = "80",       unit = "mg",           route = "ORAL"),
  "Alectinib"               = list(dose = "600",      unit = "mg",           route = "ORAL"),
  "Pembrolizumab"           = list(dose = "200",      unit = "mg",           route = "INTRAVENOUS"),
  "Docetaxel"               = list(dose = "75",       unit = "mg/m2",        route = "INTRAVENOUS"),
  "Docetaxel + Ramucirumab" = list(dose = "75 + 10",  unit = "mg/m2 + mg/kg", route = "INTRAVENOUS"),
  "Pemetrexed"              = list(dose = "500",      unit = "mg/m2",        route = "INTRAVENOUS"),
  "Nivolumab"               = list(dose = "240",      unit = "mg",           route = "INTRAVENOUS")
)

# --- Treatment selection function --------------------------------------------
# Applied per-subject. Returns treatment name as a single character string.

assign_treatment <- function(egfr_status, alk_status, n_prior_lots, pdl1_status) {
  if (egfr_status == "ALTERED") {
    return("Osimertinib")
  }
  if (alk_status == "ALTERED") {
    return("Alectinib")
  }
  if (n_prior_lots == 1 && pdl1_status == "HIGH") {
    return(sample(
      c("Pembrolizumab", "Docetaxel"),
      size = 1,
      prob = c(0.40, 0.60)
    ))
  }
  if (n_prior_lots == 1) {
    return(sample(
      c("Docetaxel", "Pemetrexed", "Docetaxel + Ramucirumab"),
      size = 1,
      prob = c(0.40, 0.30, 0.30)
    ))
  }
  # n_prior_lots >= 2
  return(sample(
    c("Docetaxel", "Pemetrexed", "Nivolumab"),
    size = 1,
    prob = c(0.40, 0.30, 0.30)
  ))
}

# --- EXADJ selection function ------------------------------------------------
# Progressive disease / AE / completed per protocol, or death-driven

assign_exadj <- function(pfs_days, os_days, death_ind) {
  if (pfs_days < os_days) {
    # Subject progressed before death or end of follow-up
    return(sample(
      c(
        "Progressive Disease",
        "Adverse Event (Side Effects of Cancer Treatment)",
        "Planned Therapy Completed"
      ),
      size = 1,
      prob = c(0.70, 0.20, 0.10)
    ))
  }
  if (death_ind == 1 && pfs_days >= os_days) {
    # Death without documented progression (PFS not shorter than OS)
    return("Progressive Disease")
  }
  return(NA_character_)
}

# --- Build EX -----------------------------------------------------------------

ex_raw <- dm %>%
  rowwise() %>%
  mutate(
    # Treatment assignment
    EXTRT = assign_treatment(egfr_status, alk_status, n_prior_lots, pdl1_status),

    # Dose and route from lookup
    EXDOSTXT = dose_lookup[[EXTRT]][["dose"]],
    EXDOSU   = dose_lookup[[EXTRT]][["unit"]],
    EXROUTE  = dose_lookup[[EXTRT]][["route"]],

    # Reason for dose adjustment / discontinuation
    EXADJ = assign_exadj(pfs_days, os_days, death_ind),

    # Start date: equals RFSTDTC exactly (index date)
    EXSTDTC = RFSTDTC,

    # End date: earliest of PFS and OS endpoints (minimum 1 day after EXSTDTC
    # to handle the edge case where pfs_days = 0 on the index date)
    EXENDTC = as.character(
      as.Date(RFSTDTC) + pmax(1L, pmin(pfs_days, os_days))
    )
  ) %>%
  ungroup()

# --- Assemble final EX dataset -----------------------------------------------

ex <- ex_raw %>%
  mutate(
    STUDYID = "NPM008",
    DOMAIN  = "EX",
    EXSEQ   = 1L,
    EXLNKID = "1"
  ) %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID,
    EXSEQ, EXLNKID,
    EXTRT, EXDOSTXT, EXDOSU, EXROUTE, EXADJ,
    EXSTDTC, EXENDTC
  )

# --- Apply variable labels and types via xportr metadata ---------------------
# xportr expects a data frame with columns: variable, label, type

xportr_meta <- tibble::tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID",
    "EXSEQ", "EXLNKID",
    "EXTRT", "EXDOSTXT", "EXDOSU", "EXROUTE", "EXADJ",
    "EXSTDTC", "EXENDTC"
  ),
  label = c(
    "Study Identifier", "Domain Abbreviation", "Unique Subject Identifier",
    "Sequence Number", "Link ID",
    "Name of Treatment", "Dose Description", "Dose Units",
    "Route of Administration", "Reason for Dose Adjustment",
    "Start Date/Time of Treatment", "End Date/Time of Treatment"
  ),
  type = c(
    "character", "character", "character",
    "numeric",   "character",
    "character", "character", "character", "character", "character",
    "character", "character"
  )
)

ex_final <- ex %>%
  xportr_label(metadata = xportr_meta, domain = "EX") %>%
  xportr_type(metadata  = xportr_meta, domain = "EX")

# --- Write outputs ------------------------------------------------------------

message("Writing ex.xpt ...")
xportr_write(ex_final, path = xpt_path, domain = "EX")

message("Writing ex.rds ...")
saveRDS(ex_final, file = rds_path)

message("Done. Rows written: ", nrow(ex_final))

# --- Validation ---------------------------------------------------------------

cat("\n=== VALIDATION ===\n")
cat("nrow:", nrow(ex_final), "\n")

# EXSTDTC == RFSTDTC for all subjects
rfstdtc_check <- all(ex_final$EXSTDTC == dm$RFSTDTC[match(ex_final$USUBJID, dm$USUBJID)])
cat("EXSTDTC == DM RFSTDTC (all subjects):", rfstdtc_check, "\n")

# EXENDTC > EXSTDTC for all subjects
endtc_check <- all(as.Date(ex_final$EXENDTC) > as.Date(ex_final$EXSTDTC))
cat("EXENDTC > EXSTDTC (all subjects):", endtc_check, "\n")

# Treatment distribution
cat("\nEXTRT distribution:\n")
print(table(ex_final$EXTRT))

cat("\nEXADJ distribution:\n")
print(table(ex_final$EXADJ, useNA = "always"))

cat("\nEXROUTE distribution:\n")
print(table(ex_final$EXROUTE))

cat("\nSample records:\n")
print(dplyr::select(head(ex_final, 5), USUBJID, EXTRT, EXDOSTXT, EXDOSU, EXROUTE, EXSTDTC, EXENDTC))
