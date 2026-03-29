# programs/sim_lb.R
# LB (Laboratory Test Results) domain simulation for NPM-008
# Wave 1, Domain 7 of 18, Seed offset: 7

# --- Setup -------------------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(stringr)
  library(haven)
  library(xportr)
  library(tibble)
})

set.seed(49)  # 42 + 7

# --- Constants ---------------------------------------------------------------
STUDYID <- "NPM008"

# --- Load upstream data ------------------------------------------------------
dm <- readRDS("output-data/sdtm/dm.rds")

message("✓ Loaded DM: ", nrow(dm), " subjects")

# --- Generate clinical labs (Category 1) ------------------------------------
# 9 tests × 40 subjects = 360 records at BASELINE

clinical_tests <- tribble(
  ~LBTESTCD, ~LBTEST, ~LBORRESU,
  "ANC", "Absolute Neutrophil Count (ANC)", "x10^3/uL",
  "HEMOGL", "Hemoglobin", "g/dL",
  "PLATELT", "Platelets", "x10^3/uL",
  "ALT", "Alanine Aminotransferase (ALT)", "U/L",
  "AST", "Aspartate Aminotransferase (AST)", "U/L",
  "BILIRUB", "Total Bilirubin", "mg/dL",
  "SCREAT", "Serum Creatinine", "mg/dL",
  "ALBUM", "Albumin", "g/dL",
  "WBC", "White Blood Cell count (WBC)", "x10^3/uL"
)

lb_clinical <- dm %>%
  select(USUBJID, RFSTDTC, liver_mets, date_shift) %>%
  crossing(clinical_tests) %>%
  mutate(
    # Generate values meeting eligibility thresholds
    LBSTRESN = case_when(
      LBTESTCD == "ANC" ~ pmax(1.5, pmin(8.0, rnorm(n(), 3.5, 0.8))),
      LBTESTCD == "HEMOGL" ~ pmax(9.0, pmin(16.0, rnorm(n(), 11.5, 1.5))),
      LBTESTCD == "PLATELT" ~ pmax(100, pmin(500, rnorm(n(), 220, 60))),
      LBTESTCD == "ALT" ~ if_else(
        liver_mets,
        pmax(8, pmin(150, rnorm(n(), 28, 12))),
        pmax(8, pmin(90, rnorm(n(), 28, 12)))
      ),
      LBTESTCD == "AST" ~ if_else(
        liver_mets,
        pmax(8, pmin(150, rnorm(n(), 30, 12))),
        pmax(8, pmin(90, rnorm(n(), 30, 12)))
      ),
      LBTESTCD == "BILIRUB" ~ pmax(0.2, pmin(1.5, rnorm(n(), 0.7, 0.25))),
      LBTESTCD == "SCREAT" ~ pmax(0.5, pmin(2.0, rnorm(n(), 0.9, 0.2))),
      LBTESTCD == "ALBUM" ~ pmax(2.5, pmin(5.0, rnorm(n(), 3.8, 0.5))),
      LBTESTCD == "WBC" ~ pmax(2.5, pmin(15.0, rnorm(n(), 7.5, 2.0))),
      TRUE ~ NA_real_
    ),
    LBSTRESN = round(LBSTRESN, 1),
    LBORRES = as.character(LBSTRESN),
    LBSTRESC = as.character(LBSTRESN),
    LBSTRESU = LBORRESU,
    LBCAT = "BASELINE",
    VISIT = "BASELINE",
    # Lab drawn 5-21 days before RFSTDTC
    LBDTC = as.character(as.Date(RFSTDTC) - round(runif(n(), 5, 21)) - date_shift),
    LBSPEC = "Blood",
    LBMETHOD = "STANDARD CLINICAL",
    LBNAM = NA_character_
  ) %>%
  select(-liver_mets, -date_shift, -RFSTDTC)

message("✓ Generated clinical labs: ", nrow(lb_clinical), " records")

# --- Generate genomic biomarker tests (Category 2) --------------------------
# One record per test per subject; values driven by DM latent variables

# Biomarker test labs
labs_genomic <- c(
  "Foundation Medicine, Inc",
  "Tempus Labs, Inc",
  "Guardant Health",
  "Caris Life Sciences",
  "Neogenomics Laboratories, Inc"
)

genomic_base <- dm %>%
  select(USUBJID, RFSTDTC, date_shift, pdl1_status, egfr_status, alk_status, kras_status)

# PD-L1 Summary
lb_pdl1sum <- genomic_base %>%
  mutate(
    LBTESTCD = "PDL1SUM",
    LBTEST = "PD-L1 Summary",
    LBORRESU = "expression",
    LBORRES = case_when(
      pdl1_status == "HIGH" ~ "HIGH",
      pdl1_status == "LOW" ~ "LOW",
      pdl1_status == "NEGATIVE" ~ "NEGATIVE",
      runif(n()) < 0.05 ~ "Not Stated",
      TRUE ~ pdl1_status
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# PD-L1 Score
lb_pdl1sc <- genomic_base %>%
  mutate(
    LBTESTCD = "PDL1SC",
    LBTEST = "PD-L1 Score",
    LBORRESU = "percentage",
    LBSTRESN = case_when(
      pdl1_status == "HIGH" ~ round(runif(n(), 50, 100)),
      pdl1_status == "LOW" ~ round(runif(n(), 1, 49)),
      pdl1_status == "NEGATIVE" ~ round(runif(n(), 0, 1)),
      TRUE ~ NA_real_
    ),
    LBORRES = as.character(LBSTRESN),
    LBSTRESC = LBORRES
  )

# PD-L1 Score Type
lb_pdl1type <- genomic_base %>%
  mutate(
    LBTESTCD = "PDL1TYPE",
    LBTEST = "PD-L1 Score Type",
    LBORRESU = "score type",
    LBORRES = sample(c("TPS", "CPS"), n(), replace = TRUE, prob = c(0.70, 0.30)),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# EGFR Mutation Status
lb_egfr <- genomic_base %>%
  mutate(
    LBTESTCD = "EGFR",
    LBTEST = "EGFR Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = case_when(
      egfr_status == "ALTERED" ~ "ALTERED",
      runif(n()) < 0.02 ~ "VUS",
      runif(n()) < 0.03 ~ "NOT TESTED",
      TRUE ~ "NOT ALTERED"
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# ALK Rearrangement Status
lb_alk <- genomic_base %>%
  mutate(
    LBTESTCD = "ALK",
    LBTEST = "ALK Rearrangement Status",
    LBORRESU = "mutation status",
    LBORRES = case_when(
      alk_status == "ALTERED" ~ "ALTERED",
      runif(n()) < 0.01 ~ "VUS",
      runif(n()) < 0.05 ~ "NOT TESTED",
      TRUE ~ "NOT ALTERED"
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# KRAS Mutation Status
lb_kras <- genomic_base %>%
  mutate(
    LBTESTCD = "KRAS",
    LBTEST = "KRAS Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = case_when(
      kras_status == "ALTERED" ~ "ALTERED",
      runif(n()) < 0.05 ~ "NOT TESTED",
      TRUE ~ "NOT ALTERED"
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# MET Mutation Status
lb_met <- genomic_base %>%
  mutate(
    LBTESTCD = "MET",
    LBTEST = "MET Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.03, 0.82, 0.05, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# ROS1 Rearrangement Status
lb_ros1 <- genomic_base %>%
  mutate(
    LBTESTCD = "ROS1",
    LBTEST = "ROS1 Rearrangement Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.02, 0.85, 0.03, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# TP53 Mutation Status
lb_tp53 <- genomic_base %>%
  mutate(
    LBTESTCD = "TP53",
    LBTEST = "TP53 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.45, 0.45, 0.05, 0.05)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# NTRK1, NTRK2, NTRK3 Mutation Status
lb_ntrk1 <- genomic_base %>%
  mutate(
    LBTESTCD = "NTRK1",
    LBTEST = "NTRK 1 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.01, 0.85, 0.04, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

lb_ntrk2 <- genomic_base %>%
  mutate(
    LBTESTCD = "NTRK2",
    LBTEST = "NTRK 2 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.01, 0.85, 0.04, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

lb_ntrk3 <- genomic_base %>%
  mutate(
    LBTESTCD = "NTRK3",
    LBTEST = "NTRK 3 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.01, 0.85, 0.04, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# RB1 Mutation Status
lb_rb1 <- genomic_base %>%
  mutate(
    LBTESTCD = "RB1",
    LBTEST = "RB1 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.08, 0.82, 0.05, 0.05)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# RET Mutation Status
lb_ret <- genomic_base %>%
  mutate(
    LBTESTCD = "RET",
    LBTEST = "RET Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.02, 0.85, 0.03, 0.10)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# ERBB2/HER2 Mutation Status
lb_erbb2 <- genomic_base %>%
  mutate(
    LBTESTCD = "ERBB2",
    LBTEST = "ERBB2/HER2 Mutation Status",
    LBORRESU = "mutation status",
    LBORRES = sample(
      c("ALTERED", "NOT ALTERED", "VUS", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.03, 0.85, 0.05, 0.07)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# HER2 IHC
lb_her2ihc <- genomic_base %>%
  mutate(
    LBTESTCD = "HER2IHC",
    LBTEST = "HER2 IHC",
    LBORRESU = "score",
    LBORRES = sample(
      c("0", "1+", "2+", "3+", "QNS", "Indeterminate"),
      n(), replace = TRUE, prob = c(0.50, 0.25, 0.15, 0.05, 0.03, 0.02)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# MSI Status
lb_msistat <- genomic_base %>%
  mutate(
    LBTESTCD = "MSISTAT",
    LBTEST = "Microsatellite Instability Status (MSI)",
    LBORRESU = "status",
    LBORRES = sample(
      c("MSS", "MSI-HIGH", "NOT TESTED"),
      n(), replace = TRUE, prob = c(0.93, 0.02, 0.05)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# Tumor Mutational Burden (TMB)
lb_tmb <- genomic_base %>%
  mutate(
    LBTESTCD = "TMB",
    LBTEST = "Tumor Mutational Burden (TMB)",
    LBORRESU = "mut/Mb",
    LBSTRESN = pmax(1, pmin(40, rnorm(n(), 8, 5))),
    LBSTRESN = round(LBSTRESN, 1),
    LBORRES = as.character(LBSTRESN),
    LBSTRESC = LBORRES
  )

# LOH Summary
lb_lohsum <- genomic_base %>%
  mutate(
    LBTESTCD = "LOHSUM",
    LBTEST = "LOH Summary Statement",
    LBORRESU = "status",
    LBORRES = sample(
      c("Low", "High", "Indeterminate", "Not Stated"),
      n(), replace = TRUE, prob = c(0.50, 0.35, 0.08, 0.07)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# LOH Score
lb_lohsc <- genomic_base %>%
  left_join(
    lb_lohsum %>% select(USUBJID, loh_sum = LBORRES),
    by = "USUBJID"
  ) %>%
  mutate(
    LBTESTCD = "LOHSC",
    LBTEST = "LOH Score",
    LBORRESU = "percentage",
    LBSTRESN = case_when(
      loh_sum == "Low" ~ runif(n(), 0, 16),
      loh_sum == "High" ~ runif(n(), 16, 50),
      TRUE ~ NA_real_
    ),
    LBSTRESN = round(LBSTRESN, 1),
    LBORRES = as.character(LBSTRESN),
    LBSTRESC = LBORRES
  ) %>%
  select(-loh_sum)

# MMR MLH1 Expression Status
lb_mmrmlh1 <- genomic_base %>%
  mutate(
    LBTESTCD = "MMRMLH1",
    LBTEST = "MMR MLH1 Expression Status",
    LBORRESU = "expression",
    LBORRES = sample(
      c("Positive/Intact", "Negative/Absent"),
      n(), replace = TRUE, prob = c(0.97, 0.03)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# MMR MSH2 Expression Status
lb_mmrmsh2 <- genomic_base %>%
  mutate(
    LBTESTCD = "MMRMSH2",
    LBTEST = "MMR MSH2 Expression Status",
    LBORRESU = "expression",
    LBORRES = sample(
      c("Positive/Intact", "Negative/Absent"),
      n(), replace = TRUE, prob = c(0.97, 0.03)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# MMR MSH6 Expression Status
lb_mmrmsh6 <- genomic_base %>%
  mutate(
    LBTESTCD = "MMRMSH6",
    LBTEST = "MMR MSH6 Expression Status",
    LBORRESU = "expression",
    LBORRES = sample(
      c("Positive/Intact", "Negative/Absent"),
      n(), replace = TRUE, prob = c(0.97, 0.03)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# MMR PMS2 Expression Status
lb_mmrpms2 <- genomic_base %>%
  mutate(
    LBTESTCD = "MMRPMS2",
    LBTEST = "MMR PMS2 Expression Status",
    LBORRESU = "expression",
    LBORRES = sample(
      c("Positive/Intact", "Negative/Absent"),
      n(), replace = TRUE, prob = c(0.97, 0.03)
    ),
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  )

# Overall MMR expression
# Need to check all 4 MMR proteins per subject
lb_mmrover <- genomic_base %>%
  left_join(
    bind_rows(
      lb_mmrmlh1 %>% select(USUBJID, protein = LBTEST, status = LBORRES),
      lb_mmrmsh2 %>% select(USUBJID, protein = LBTEST, status = LBORRES),
      lb_mmrmsh6 %>% select(USUBJID, protein = LBTEST, status = LBORRES),
      lb_mmrpms2 %>% select(USUBJID, protein = LBTEST, status = LBORRES)
    ) %>%
      group_by(USUBJID) %>%
      summarise(
        mmr_overall = if_else(
          all(status == "Positive/Intact"),
          "Proficient",
          "Deficient"
        ),
        .groups = "drop"
      ),
    by = "USUBJID"
  ) %>%
  mutate(
    LBTESTCD = "MMROVER",
    LBTEST = "Overall MMR expression",
    LBORRESU = "status",
    LBORRES = mmr_overall,
    LBSTRESC = LBORRES,
    LBSTRESN = NA_real_
  ) %>%
  select(-mmr_overall)

# Number of Cores
lb_cores <- genomic_base %>%
  mutate(
    LBTESTCD = "CORES",
    LBTEST = "Number of Cores",
    LBORRESU = "number of cores",
    LBSTRESN = sample(2:8, n(), replace = TRUE),
    LBORRES = as.character(LBSTRESN),
    LBSTRESC = LBORRES
  )

# --- Combine all genomic biomarker tests -------------------------------------
lb_genomic <- bind_rows(
  lb_pdl1sum, lb_pdl1sc, lb_pdl1type,
  lb_egfr, lb_alk, lb_kras,
  lb_met, lb_ros1, lb_tp53,
  lb_ntrk1, lb_ntrk2, lb_ntrk3,
  lb_rb1, lb_ret, lb_erbb2, lb_her2ihc,
  lb_msistat, lb_tmb,
  lb_lohsum, lb_lohsc,
  lb_mmrmlh1, lb_mmrmsh2, lb_mmrmsh6, lb_mmrpms2, lb_mmrover,
  lb_cores
) %>%
  mutate(
    LBCAT = "BASELINE",
    VISIT = "BASELINE",
    # Genomic testing drawn 30-90 days before RFSTDTC
    LBDTC = as.character(as.Date(RFSTDTC) - round(runif(n(), 30, 90)) - date_shift),
    LBSPEC = "Tissue/Bone Marrow",
    LBMETHOD = NA_character_,
    LBNAM = sample(labs_genomic, n(), replace = TRUE)
  ) %>%
  select(-RFSTDTC, -date_shift, -pdl1_status, -egfr_status, -alk_status, -kras_status)

message("✓ Generated genomic biomarker tests: ", nrow(lb_genomic), " records")

# --- Combine clinical and genomic labs ---------------------------------------
lb <- bind_rows(lb_clinical, lb_genomic) %>%
  group_by(USUBJID) %>%
  mutate(LBSEQ = row_number()) %>%
  ungroup() %>%
  mutate(
    STUDYID = STUDYID,
    DOMAIN = "LB"
  ) %>%
  # LBBLFL: "Y" for earliest record per USUBJID x LBTESTCD (minimum LBDTC)
  group_by(USUBJID, LBTESTCD) %>%
  mutate(
    min_lbdtc = min(LBDTC, na.rm = TRUE),
    LBBLFL = ifelse(LBDTC == min_lbdtc, "Y", "")
  ) %>%
  ungroup() %>%
  select(
    STUDYID, DOMAIN, USUBJID, LBSEQ, LBTESTCD, LBTEST, LBCAT,
    LBORRES, LBORRESU, LBSTRESC, LBSTRESN, LBSTRESU, LBBLFL,
    LBNAM, LBSPEC, LBMETHOD, LBDTC, VISIT
  )

message("✓ Combined LB records: ", nrow(lb), " total (clinical + genomic)")

# --- Validation --------------------------------------------------------------
message("\n--- LB Validation ---")

# Row count check (1200-1600 expected: ~360 clinical + ~1040 genomic for 40 subjects)
if (nrow(lb) < 1200 || nrow(lb) > 1600) {
  warning(
    "LB row count outside expected range: ", nrow(lb),
    " (expected 1200-1600 for 40 subjects with genomic tests)",
    call. = FALSE
  )
} else {
  message("✓ Row count OK: ", nrow(lb), " records (1200-1600 expected)")
}

# All subjects present
subjects_dm <- unique(dm$USUBJID)
subjects_lb <- unique(lb$USUBJID)
if (!setequal(subjects_dm, subjects_lb)) {
  stop(
    "LB subjects do not match DM subjects.\n",
    "  Missing in LB: ", paste(setdiff(subjects_dm, subjects_lb), collapse = ", "),
    call. = FALSE
  )
}
message("✓ All 40 subjects present in LB")

# LBSEQ uniqueness within USUBJID
lb_seq_check <- lb %>%
  group_by(USUBJID, LBSEQ) %>%
  dplyr::filter(n() > 1) %>%
  ungroup()

if (nrow(lb_seq_check) > 0) {
  stop("LBSEQ not unique within USUBJID for ", n_distinct(lb_seq_check$USUBJID), " subjects", call. = FALSE)
}
message("✓ LBSEQ unique within USUBJID")

# Check biomarker consistency with DM latent variables
dm_check <- dm %>%
  select(USUBJID, pdl1_status, egfr_status, alk_status, kras_status)

lb_check_pdl1 <- lb %>%
  dplyr::filter(LBTESTCD == "PDL1SUM") %>%
  left_join(dm_check, by = "USUBJID") %>%
  dplyr::filter(
    (pdl1_status == "HIGH" & LBORRES != "HIGH" & LBORRES != "Not Stated") |
    (pdl1_status == "LOW" & LBORRES != "LOW" & LBORRES != "Not Stated") |
    (pdl1_status == "NEGATIVE" & LBORRES != "NEGATIVE" & LBORRES != "Not Stated")
  )

if (nrow(lb_check_pdl1) > 0) {
  warning("PDL1SUM values inconsistent with DM pdl1_status for ", nrow(lb_check_pdl1), " subjects", call. = FALSE)
} else {
  message("✓ PDL1SUM consistent with DM latent variable")
}

lb_check_egfr <- lb %>%
  dplyr::filter(LBTESTCD == "EGFR") %>%
  left_join(dm_check, by = "USUBJID") %>%
  dplyr::filter(
    (egfr_status == "ALTERED" & LBORRES != "ALTERED") |
    (egfr_status == "NOT ALTERED" & LBORRES == "ALTERED")
  )

if (nrow(lb_check_egfr) > 0) {
  warning("EGFR values inconsistent with DM egfr_status for ", nrow(lb_check_egfr), " subjects", call. = FALSE)
} else {
  message("✓ EGFR consistent with DM latent variable")
}

lb_check_alk <- lb %>%
  dplyr::filter(LBTESTCD == "ALK") %>%
  left_join(dm_check, by = "USUBJID") %>%
  dplyr::filter(
    (alk_status == "ALTERED" & LBORRES != "ALTERED") |
    (alk_status == "NOT ALTERED" & LBORRES == "ALTERED")
  )

if (nrow(lb_check_alk) > 0) {
  warning("ALK values inconsistent with DM alk_status for ", nrow(lb_check_alk), " subjects", call. = FALSE)
} else {
  message("✓ ALK consistent with DM latent variable")
}

lb_check_kras <- lb %>%
  dplyr::filter(LBTESTCD == "KRAS") %>%
  left_join(dm_check, by = "USUBJID") %>%
  dplyr::filter(
    (kras_status == "ALTERED" & LBORRES != "ALTERED") |
    (kras_status == "NOT ALTERED" & LBORRES == "ALTERED")
  )

if (nrow(lb_check_kras) > 0) {
  warning("KRAS values inconsistent with DM kras_status for ", nrow(lb_check_kras), " subjects", call. = FALSE)
} else {
  message("✓ KRAS consistent with DM latent variable")
}

# All clinical lab values within eligibility ranges
lb_clin_check <- lb %>%
  dplyr::filter(VISIT == "BASELINE", LBCAT == "BASELINE") %>%
  dplyr::filter(LBTESTCD %in% c("ANC", "HEMOGL", "PLATELT", "BILIRUB", "SCREAT")) %>%
  mutate(
    in_range = case_when(
      LBTESTCD == "ANC" & LBSTRESN >= 1.5 ~ TRUE,
      LBTESTCD == "HEMOGL" & LBSTRESN >= 9.0 ~ TRUE,
      LBTESTCD == "PLATELT" & LBSTRESN >= 100 ~ TRUE,
      LBTESTCD == "BILIRUB" & LBSTRESN <= 1.5 ~ TRUE,
      LBTESTCD == "SCREAT" & LBSTRESN <= 2.0 ~ TRUE,
      TRUE ~ FALSE
    )
  ) %>%
  dplyr::filter(!in_range)

if (nrow(lb_clin_check) > 0) {
  warning(
    nrow(lb_clin_check), " clinical lab values outside eligibility ranges",
    call. = FALSE
  )
} else {
  message("✓ All clinical lab values within eligibility ranges")
}

message("\n--- LB Generation Complete ---")
message("Total records: ", nrow(lb))
message("  Clinical labs: ", sum(lb$LBCAT == "BASELINE" & lb$LBMETHOD == "STANDARD CLINICAL", na.rm = TRUE))
message("  Genomic tests: ", sum(lb$LBCAT == "BASELINE" & is.na(lb$LBMETHOD)))

# --- Apply variable labels and types -----------------------------------------
lb_meta <- tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "LBSEQ", "LBTESTCD", "LBTEST", "LBCAT",
    "LBORRES", "LBORRESU", "LBSTRESC", "LBSTRESN", "LBSTRESU", "LBBLFL",
    "LBNAM", "LBSPEC", "LBMETHOD", "LBDTC", "VISIT"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Lab Test or Examination Short Name",
    "Lab Test or Examination Name",
    "Category for Lab Test",
    "Result or Finding in Original Units",
    "Original Units",
    "Character Result/Finding in Std Format",
    "Numeric Result/Finding in Standard Units",
    "Standard Units",
    "Baseline Flag",
    "Laboratory Name",
    "Specimen Type",
    "Method of Lab Test",
    "Date/Time of Specimen Collection",
    "Visit Name"
  ),
  type = c(
    "character", "character", "character", "numeric", "character", "character", "character",
    "character", "character", "character", "numeric",  "character", "character",
    "character", "character", "character", "character", "character"
  )
)

lb_xpt <- lb %>%
  xportr_label(lb_meta, domain = "LB") %>%
  xportr_type(lb_meta, domain = "LB")

# --- Save outputs ------------------------------------------------------------
saveRDS(lb_xpt, "output-data/sdtm/lb.rds")
haven::write_xpt(lb_xpt, "output-data/sdtm/lb.xpt", version = 5)

message("\n✓ LB written to:")
message("  output-data/sdtm/lb.rds")
message("  output-data/sdtm/lb.xpt")
