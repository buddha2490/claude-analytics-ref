# =============================================================================
# sim_lb.R
# NPM-008 / XB010-101 SDTM LB Domain Simulation
#
# Generates:
#   1. Clinical labs at BASELINE: 9 tests x 40 subjects = 360 records
#   2. Genomic/biomarker tests at BASELINE: 26 tests x 40 subjects = 1040 records
#   Total = 1400 records
#
# Inputs:  cohort/output-data/dm.rds
# Outputs: cohort/output-data/sdtm/lb.xpt
#          cohort/output-data/sdtm/lb.rds
#
# Seed: set.seed(49) [LB is domain order 7; 42 + 7 = 49]
# =============================================================================

library(tidyverse)
library(haven)
library(xportr)

set.seed(49)

# --- Load DM spine -----------------------------------------------------------
dm <- readRDS("/Users/briancarter/Rdata/claude-analytics-ref/cohort/output-data/dm.rds")

# Keep only the columns needed from DM
dm_spine <- dm %>%
  dplyr::select(
    STUDYID, USUBJID, RFSTDTC,
    pdl1_status, egfr_status, alk_status, kras_status, liver_mets
  )

n_subjects <- nrow(dm_spine)

# =============================================================================
# Helper: truncate a numeric vector to [lo, hi]
# =============================================================================
truncate_vals <- function(x, lo, hi) {
  pmax(lo, pmin(hi, x))
}

# =============================================================================
# CATEGORY 1 — Clinical Labs (9 tests x 40 subjects = 360 records)
# =============================================================================

# --- Define per-subject collection date offset (5-21 days before RFSTDTC) ---
# One offset per subject; used for all clinical lab tests
clinical_offsets <- sample(5:21, n_subjects, replace = TRUE)

# --- Build the wide-format subject-level clinical data ----------------------
dm_clin <- dm_spine %>%
  mutate(
    lb_clin_dtc = as.character(as.Date(RFSTDTC) - clinical_offsets),

    # ANC: rnorm(n, 3.5, 0.8), truncate [1.5, 8.0]
    ANC_val     = truncate_vals(rnorm(n_subjects, 3.5, 0.8),    1.5,   8.0),

    # HEMOGL: rnorm(n, 11.5, 1.5), truncate [9.0, 16.0]
    HEMOGL_val  = truncate_vals(rnorm(n_subjects, 11.5, 1.5),   9.0,  16.0),

    # PLATELT: rnorm(n, 220, 60), truncate [100, 500]
    PLATELT_val = truncate_vals(rnorm(n_subjects, 220, 60),    100.0, 500.0),

    # ALT: liver_mets changes the upper truncation bound
    ALT_raw     = rnorm(n_subjects, 28, 12),
    ALT_val     = if_else(
      liver_mets,
      truncate_vals(ALT_raw, 8, 150),
      truncate_vals(ALT_raw, 8,  90)
    ),

    # AST: same liver_mets logic
    AST_raw     = rnorm(n_subjects, 30, 12),
    AST_val     = if_else(
      liver_mets,
      truncate_vals(AST_raw, 8, 150),
      truncate_vals(AST_raw, 8,  90)
    ),

    # BILIRUB: rnorm(n, 0.7, 0.25), truncate [0.2, 1.5]
    BILIRUB_val = truncate_vals(rnorm(n_subjects, 0.7, 0.25),  0.2,   1.5),

    # SCREAT: rnorm(n, 0.9, 0.2), truncate [0.5, 2.0]
    SCREAT_val  = truncate_vals(rnorm(n_subjects, 0.9, 0.2),   0.5,   2.0),

    # ALBUM: rnorm(n, 3.8, 0.5), truncate [2.5, 5.0]
    ALBUM_val   = truncate_vals(rnorm(n_subjects, 3.8, 0.5),   2.5,   5.0),

    # WBC: rnorm(n, 7.5, 2.0), truncate [2.5, 15.0]
    WBC_val     = truncate_vals(rnorm(n_subjects, 7.5, 2.0),   2.5,  15.0)
  )

# --- Clinical lab metadata lookup -------------------------------------------
clin_meta <- tibble::tribble(
  ~LBTESTCD, ~LBTEST,                              ~LBORRESU,
  "ANC",     "Absolute Neutrophil Count (ANC)",    "x10^3/uL",
  "HEMOGL",  "Hemoglobin",                         "g/dL",
  "PLATELT", "Platelets",                          "x10^3/uL",
  "ALT",     "Alanine Aminotransferase (ALT)",     "U/L",
  "AST",     "Aspartate Aminotransferase (AST)",   "U/L",
  "BILIRUB", "Total Bilirubin",                    "mg/dL",
  "SCREAT",  "Serum Creatinine",                   "mg/dL",
  "ALBUM",   "Albumin",                            "g/dL",
  "WBC",     "White Blood Cell count (WBC)",       "x10^3/uL"
)

# --- Pivot clinical labs to long format --------------------------------------
lb_clin <- dm_clin %>%
  dplyr::select(STUDYID, USUBJID, lb_clin_dtc,
                ANC_val, HEMOGL_val, PLATELT_val, ALT_val, AST_val,
                BILIRUB_val, SCREAT_val, ALBUM_val, WBC_val) %>%
  pivot_longer(
    cols      = ends_with("_val"),
    names_to  = "LBTESTCD",
    values_to = "num_result"
  ) %>%
  mutate(
    LBTESTCD = str_remove(LBTESTCD, "_val")
  ) %>%
  left_join(clin_meta, by = "LBTESTCD") %>%
  mutate(
    DOMAIN    = "LB",
    VISIT     = "BASELINE",
    LBDTC     = lb_clin_dtc,
    LBSPEC    = "Blood",
    LBMETHOD  = "STANDARD CLINICAL",
    LBCAT     = "CHEMISTRY",
    LBNAM     = NA_character_,

    # LBORRES is character representation of the numeric result
    LBORRES   = as.character(round(num_result, 2)),
    LBORRESU  = LBORRESU,

    # Standard result columns
    LBSTRESC  = LBORRES,
    LBSTRESN  = round(num_result, 2),
    LBSTRESU  = LBORRESU
  ) %>%
  dplyr::select(-lb_clin_dtc, -num_result)

# =============================================================================
# CATEGORY 2 — Genomic / Biomarker Tests (26 tests x 40 subjects = 1040 records)
# =============================================================================

# --- Assign one genomic lab per subject consistently -------------------------
genomic_labs <- c(
  "Foundation Medicine, Inc",
  "Tempus Labs, Inc",
  "Guardant Health",
  "Caris Life Sciences",
  "Neogenomics Laboratories, Inc"
)

dm_gen <- dm_spine %>%
  mutate(
    # Genomic collection date: 30-90 days before RFSTDTC
    gen_offset  = sample(30:90, n_subjects, replace = TRUE),
    lb_gen_dtc  = as.character(as.Date(RFSTDTC) - gen_offset),
    # One lab per subject
    LBNAM       = sample(genomic_labs, n_subjects, replace = TRUE)
  )

# --- Per-subject genomic draws using purrr::pmap ----------------------------
# Each row gets independent draws for all 26 tests.
gen_rows <- purrr::pmap(
  list(
    studyid     = dm_gen$STUDYID,
    usubjid     = dm_gen$USUBJID,
    lb_gen_dtc  = dm_gen$lb_gen_dtc,
    lbnam       = dm_gen$LBNAM,
    pdl1_status = dm_gen$pdl1_status,
    egfr_status = dm_gen$egfr_status,
    alk_status  = dm_gen$alk_status,
    kras_status = dm_gen$kras_status
  ),
  function(studyid, usubjid, lb_gen_dtc, lbnam,
           pdl1_status, egfr_status, alk_status, kras_status) {

    # ---- PDL1SUM -----------------------------------------------------------
    # 5% chance of "Not Stated" regardless of pdl1_status
    pdl1sum <- if (runif(1) < 0.05) {
      "Not Stated"
    } else {
      pdl1_status  # "HIGH", "LOW", or "NEGATIVE"
    }

    # ---- PDL1SC ------------------------------------------------------------
    pdl1sc <- switch(pdl1_status,
      "HIGH"     = as.character(round(runif(1, 50, 100))),
      "LOW"      = as.character(round(runif(1,  1,  49))),
      "NEGATIVE" = as.character(round(runif(1,  0,   1))),
      NA_character_
    )

    # ---- PDL1TYPE ----------------------------------------------------------
    pdl1type <- sample(c("TPS", "CPS"), 1, prob = c(0.70, 0.30))

    # ---- EGFR --------------------------------------------------------------
    egfr <- if (egfr_status == "ALTERED") {
      "ALTERED"
    } else {
      p <- c(0.95, 0.02, 0.03)
      sample(c("NOT ALTERED", "VUS", "NOT TESTED"), 1, prob = p / sum(p))
    }

    # ---- ALK ---------------------------------------------------------------
    alk <- if (alk_status == "ALTERED") {
      "ALTERED"
    } else {
      p <- c(0.94, 0.01, 0.05)
      sample(c("NOT ALTERED", "VUS", "NOT TESTED"), 1, prob = p / sum(p))
    }

    # ---- KRAS --------------------------------------------------------------
    kras <- if (kras_status == "ALTERED") {
      "ALTERED"
    } else {
      p <- c(0.95, 0.05)
      sample(c("NOT ALTERED", "NOT TESTED"), 1, prob = p / sum(p))
    }

    # ---- MET ---------------------------------------------------------------
    met <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.03, 0.82, 0.05, 0.10)
    )

    # ---- ROS1 --------------------------------------------------------------
    ros1 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.02, 0.85, 0.03, 0.10)
    )

    # ---- TP53 --------------------------------------------------------------
    tp53 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.45, 0.45, 0.05, 0.05)
    )

    # ---- NTRK1 / NTRK2 / NTRK3 --------------------------------------------
    ntrk1 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.01, 0.85, 0.04, 0.10)
    )
    ntrk2 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.01, 0.85, 0.04, 0.10)
    )
    ntrk3 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.01, 0.85, 0.04, 0.10)
    )

    # ---- RB1 ---------------------------------------------------------------
    rb1 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.08, 0.82, 0.05, 0.05)
    )

    # ---- RET ---------------------------------------------------------------
    ret <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.02, 0.85, 0.03, 0.10)
    )

    # ---- ERBB2 -------------------------------------------------------------
    erbb2 <- sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      1, prob = c(0.03, 0.85, 0.05, 0.07)
    )

    # ---- HER2IHC -----------------------------------------------------------
    her2ihc <- sample(
      c("0", "1+", "2+", "3+", "QNS", "Indeterminate"),
      1, prob = c(0.50, 0.25, 0.15, 0.05, 0.03, 0.02)
    )

    # ---- MSISTAT -----------------------------------------------------------
    msistat <- sample(
      c("MSS", "MSI-HIGH", "NOT TESTED"),
      1, prob = c(0.93, 0.02, 0.05)
    )

    # ---- TMB ---------------------------------------------------------------
    tmb_val <- truncate_vals(rnorm(1, 8, 5), 1, 40)
    tmb     <- as.character(round(tmb_val, 1))

    # ---- LOHSUM / LOHSC ----------------------------------------------------
    lohsum <- sample(
      c("Low", "High", "Indeterminate", "Not Stated"),
      1, prob = c(0.50, 0.35, 0.08, 0.07)
    )
    lohsc <- if (lohsum == "Low") {
      as.character(round(runif(1, 0, 16), 1))
    } else if (lohsum == "High") {
      as.character(round(runif(1, 16, 50), 1))
    } else {
      NA_character_
    }

    # ---- MMR proteins ------------------------------------------------------
    mmrmlh1 <- sample(
      c("Positive/Intact", "Negative/Absent"), 1, prob = c(0.97, 0.03)
    )
    mmrmsh2 <- sample(
      c("Positive/Intact", "Negative/Absent"), 1, prob = c(0.97, 0.03)
    )
    mmrmsh6 <- sample(
      c("Positive/Intact", "Negative/Absent"), 1, prob = c(0.97, 0.03)
    )
    mmrpms2 <- sample(
      c("Positive/Intact", "Negative/Absent"), 1, prob = c(0.97, 0.03)
    )

    # MMROVER: "Proficient" if ALL 4 intact, "Deficient" if any absent
    mmrover <- if (all(c(mmrmlh1, mmrmsh2, mmrmsh6, mmrpms2) == "Positive/Intact")) {
      "Proficient"
    } else {
      "Deficient"
    }

    # ---- CORES -------------------------------------------------------------
    cores <- as.character(sample(2:8, 1, replace = TRUE))

    # ---- Assemble this subject's 26 rows -----------------------------------
    tibble(
      STUDYID  = studyid,
      USUBJID  = usubjid,
      lb_gen_dtc = lb_gen_dtc,
      LBNAM    = lbnam,
      LBTESTCD = c("PDL1SUM", "PDL1SC", "PDL1TYPE", "EGFR", "ALK", "KRAS",
                   "MET", "ROS1", "TP53", "NTRK1", "NTRK2", "NTRK3",
                   "RB1", "RET", "ERBB2", "HER2IHC", "MSISTAT", "TMB",
                   "LOHSUM", "LOHSC", "MMRMLH1", "MMRMSH2", "MMRMSH6",
                   "MMRPMS2", "MMROVER", "CORES"),
      LBORRES  = c(pdl1sum, pdl1sc, pdl1type, egfr, alk, kras,
                   met, ros1, tp53, ntrk1, ntrk2, ntrk3,
                   rb1, ret, erbb2, her2ihc, msistat, tmb,
                   lohsum, lohsc, mmrmlh1, mmrmsh2, mmrmsh6,
                   mmrpms2, mmrover, cores)
    )
  }
)

# Bind all subjects' genomic rows
lb_gen_long <- bind_rows(gen_rows)

# --- Genomic test metadata lookup -------------------------------------------
gen_meta <- tibble::tribble(
  ~LBTESTCD, ~LBTEST,
  "PDL1SUM",  "PD-L1 Summary",
  "PDL1SC",   "PD-L1 Score",
  "PDL1TYPE", "PD-L1 Score Type",
  "EGFR",     "EGFR Mutation Status",
  "ALK",      "ALK Rearrangement Status",
  "KRAS",     "KRAS Mutation Status",
  "MET",      "MET Mutation Status",
  "ROS1",     "ROS1 Rearrangement Status",
  "TP53",     "TP53 Mutation Status",
  "NTRK1",    "NTRK 1 Mutation Status",
  "NTRK2",    "NTRK 2 Mutation Status",
  "NTRK3",    "NTRK 3 Mutation Status",
  "RB1",      "RB1 Mutation Status",
  "RET",      "RET Mutation Status",
  "ERBB2",    "ERBB2/HER2 Mutation Status",
  "HER2IHC",  "HER2 IHC",
  "MSISTAT",  "Microsatellite Instability Status (MSI)",
  "TMB",      "Tumor Mutational Burden (TMB)",
  "LOHSUM",   "LOH Summary Statement",
  "LOHSC",    "LOH Score",
  "MMRMLH1",  "MMR MLH1 Expression Status",
  "MMRMSH2",  "MMR MSH2 Expression Status",
  "MMRMSH6",  "MMR MSH6 Expression Status",
  "MMRPMS2",  "MMR PMS2 Expression Status",
  "MMROVER",  "Overall MMR expression",
  "CORES",    "Number of Cores"
)

lb_gen <- lb_gen_long %>%
  left_join(gen_meta, by = "LBTESTCD") %>%
  mutate(
    DOMAIN   = "LB",
    VISIT    = "BASELINE",
    LBDTC    = lb_gen_dtc,
    LBSPEC   = "Tissue",
    LBCAT    = "GENOMICS",
    LBMETHOD = NA_character_,
    LBORRESU = NA_character_,

    # Numeric standard result: TMB and LOHSC are numeric; PDL1SC is numeric
    LBSTRESN = dplyr::case_when(
      LBTESTCD == "TMB"    ~ as.numeric(LBORRES),
      LBTESTCD == "LOHSC"  ~ suppressWarnings(as.numeric(LBORRES)),
      LBTESTCD == "PDL1SC" ~ suppressWarnings(as.numeric(LBORRES)),
      LBTESTCD == "CORES"  ~ suppressWarnings(as.numeric(LBORRES)),
      TRUE                  ~ NA_real_
    ),
    LBSTRESC = LBORRES,
    LBSTRESU = NA_character_
  ) %>%
  dplyr::select(-lb_gen_dtc)

# =============================================================================
# COMBINE AND FINALIZE
# =============================================================================

# --- Stack clinical + genomic -----------------------------------------------
lb_combined <- bind_rows(lb_clin, lb_gen) %>%
  # Sort by subject, then by category (CHEMISTRY first, GENOMICS second),
  # then by the test order as defined in the spec
  mutate(
    cat_order = if_else(LBCAT == "CHEMISTRY", 1L, 2L),
    test_order = match(
      LBTESTCD,
      c("ANC", "HEMOGL", "PLATELT", "ALT", "AST", "BILIRUB", "SCREAT",
        "ALBUM", "WBC",
        "PDL1SUM", "PDL1SC", "PDL1TYPE", "EGFR", "ALK", "KRAS",
        "MET", "ROS1", "TP53", "NTRK1", "NTRK2", "NTRK3",
        "RB1", "RET", "ERBB2", "HER2IHC", "MSISTAT", "TMB",
        "LOHSUM", "LOHSC", "MMRMLH1", "MMRMSH2", "MMRMSH6",
        "MMRPMS2", "MMROVER", "CORES")
    )
  ) %>%
  arrange(USUBJID, cat_order, test_order) %>%
  dplyr::select(-cat_order, -test_order)

# --- Assign LBSEQ: sequential per subject across ALL records ----------------
lb_combined <- lb_combined %>%
  group_by(USUBJID) %>%
  mutate(LBSEQ = row_number()) %>%
  ungroup()

# --- Final column selection / ordering for SDTM LB -------------------------
lb_final <- lb_combined %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, LBSEQ,
    LBTESTCD, LBTEST, LBCAT,
    LBORRES, LBORRESU, LBSTRESC, LBSTRESN, LBSTRESU,
    LBNAM, LBSPEC, LBMETHOD,
    VISIT, LBDTC
  )

# --- Quick validation before export -----------------------------------------
message("Total records: ", nrow(lb_final))
stopifnot(nrow(lb_final) == 1400)

# Validate clinical lab bounds
clin_check <- lb_combined %>%
  dplyr::filter(LBCAT == "CHEMISTRY")

anc_vals    <- as.numeric(clin_check$LBORRES[clin_check$LBTESTCD == "ANC"])
hemogl_vals <- as.numeric(clin_check$LBORRES[clin_check$LBTESTCD == "HEMOGL"])
platelt_vals <- as.numeric(clin_check$LBORRES[clin_check$LBTESTCD == "PLATELT"])

stopifnot("ANC values below 1.5"    = all(anc_vals    >= 1.5))
stopifnot("HEMOGL values below 9.0" = all(hemogl_vals >= 9.0))
stopifnot("PLATELT values below 100" = all(platelt_vals >= 100))

message("Validation passed: ANC >= 1.5, HEMOGL >= 9.0, PLATELT >= 100")
message("Clinical records: ", sum(lb_final$LBCAT == "CHEMISTRY"))
message("Genomic records:  ", sum(lb_final$LBCAT == "GENOMICS"))

# =============================================================================
# APPLY XPORTR LABELS AND WRITE OUTPUTS
# =============================================================================

lb_labels <- tibble::tribble(
  ~variable,  ~label,
  "STUDYID",  "Study Identifier",
  "DOMAIN",   "Domain Abbreviation",
  "USUBJID",  "Unique Subject Identifier",
  "LBSEQ",    "Sequence Number",
  "LBTESTCD", "Lab Test or Examination Short Name",
  "LBTEST",   "Lab Test or Examination Name",
  "LBCAT",    "Category for Lab Test",
  "LBORRES",  "Result or Finding in Original Units",
  "LBORRESU", "Original Units",
  "LBSTRESC", "Character Result/Finding in Std Format",
  "LBSTRESN", "Numeric Result/Finding in Standard Units",
  "LBSTRESU", "Standard Units",
  "LBNAM",    "Laboratory Name",
  "LBSPEC",   "Specimen Type Used for Measurement",
  "LBMETHOD", "Method of Test or Examination",
  "VISIT",    "Visit Name",
  "LBDTC",    "Date/Time of Specimen Collection"
)

# Build a unified metadata frame for xportr
# type: "numeric" for numeric fields, "character" for everything else
# length: SAS max lengths — 8 for numeric, computed from max char width for text
lb_meta <- tibble::tribble(
  ~dataset,  ~variable,   ~label,                                        ~type,       ~length,
  "LB", "STUDYID",  "Study Identifier",                            "character",  40L,
  "LB", "DOMAIN",   "Domain Abbreviation",                         "character",   2L,
  "LB", "USUBJID",  "Unique Subject Identifier",                   "character",  50L,
  "LB", "LBSEQ",    "Sequence Number",                             "numeric",     8L,
  "LB", "LBTESTCD", "Lab Test or Examination Short Name",          "character",   8L,
  "LB", "LBTEST",   "Lab Test or Examination Name",                "character",  60L,
  "LB", "LBCAT",    "Category for Lab Test",                       "character",  20L,
  "LB", "LBORRES",  "Result or Finding in Original Units",         "character",  50L,
  "LB", "LBORRESU", "Original Units",                              "character",  20L,
  "LB", "LBSTRESC", "Character Result/Finding in Std Format",      "character",  50L,
  "LB", "LBSTRESN", "Numeric Result/Finding in Standard Units",    "numeric",     8L,
  "LB", "LBSTRESU", "Standard Units",                              "character",  20L,
  "LB", "LBNAM",    "Laboratory Name",                             "character",  60L,
  "LB", "LBSPEC",   "Specimen Type Used for Measurement",          "character",  30L,
  "LB", "LBMETHOD", "Method of Test or Examination",               "character",  30L,
  "LB", "VISIT",    "Visit Name",                                  "character",  20L,
  "LB", "LBDTC",    "Date/Time of Specimen Collection",            "character",  20L
)

lb_xpt <- lb_final %>%
  xportr_metadata(lb_meta, domain = "LB") %>%
  xportr_type() %>%
  xportr_label() %>%
  xportr_length()

# --- Save RDS (includes all helper columns in lb_combined) ------------------
saveRDS(lb_combined, "/Users/briancarter/Rdata/claude-analytics-ref/cohort/output-data/sdtm/lb.rds")
message("Saved lb.rds")

# --- Write XPT --------------------------------------------------------------
xportr_write(
  lb_xpt,
  path   = "/Users/briancarter/Rdata/claude-analytics-ref/cohort/output-data/sdtm/lb.xpt",
  domain = "LB"
)
message("Saved lb.xpt")

# --- Final summary ----------------------------------------------------------
message("\n--- LB Domain Summary ---")
message("Total records:    ", nrow(lb_final))
message("Unique subjects:  ", n_distinct(lb_final$USUBJID))
message("Tests per subject: ", nrow(lb_final) / n_distinct(lb_final$USUBJID))
message("")
message("Category breakdown:")
print(table(lb_final$LBCAT))
message("")
message("Clinical lab value ranges:")
lb_final %>%
  dplyr::filter(LBCAT == "CHEMISTRY") %>%
  dplyr::mutate(numeric_val = as.numeric(LBORRES)) %>%
  dplyr::group_by(LBTESTCD) %>%
  dplyr::summarise(
    min_val = round(min(numeric_val, na.rm = TRUE), 2),
    max_val = round(max(numeric_val, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  print()
