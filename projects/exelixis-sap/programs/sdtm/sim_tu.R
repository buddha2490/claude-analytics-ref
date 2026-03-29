# =============================================================================
# sim_tu.R
# TU (Tumor Identification) SDTM Domain Simulation
# Study: NPM008 / XB010-101
# Wave: 1, Seed offset: 14 (set.seed = 42 + 14 = 56)
# =============================================================================

library(dplyr)
library(tidyr)
library(stringr)
library(purrr)
library(lubridate)
library(haven)
library(xportr)
library(tibble)

set.seed(56)

# --- Load inputs -------------------------------------------------------------

dm <- readRDS("output-data/sdtm/dm.rds")
ct <- readRDS("output-data/sdtm/ct_reference.rds")

message("✓ Loaded DM: ", nrow(dm), " subjects")

# --- Step 4: Data Contract Validation ---------------------------------------
message("\n--- Data Structure Exploration ---")
message("DM columns: ", paste(names(dm), collapse = ", "))

# Expected variables from plan Section 4.14
plan_vars_dm <- c("USUBJID", "STUDYID", "RFSTDTC", "date_shift", "n_target_lesions",
                  "brain_mets", "liver_mets", "bone_mets", "metastatic_sites")
actual_vars_dm <- names(dm)

missing_vars <- setdiff(plan_vars_dm, actual_vars_dm)

if (length(missing_vars) > 0) {
  stop(
    "Plan lists variables not found in DM: ", paste(missing_vars, collapse = ", "),
    "\nActual DM variables: ", paste(actual_vars_dm, collapse = ", "),
    "\nREVISIT: Update plan or identify alternative variables",
    call. = FALSE
  )
}

message("✓ Data contract OK (DM): All ", length(plan_vars_dm), " expected variables found")

# --- Prepare subject-level data ----------------------------------------------

subjects <- dm %>%
  select(USUBJID, STUDYID, RFSTDTC, date_shift, n_target_lesions,
         brain_mets, liver_mets, bone_mets, metastatic_sites)

# --- Generate BASELINE TARGET lesions ----------------------------------------
message("\n--- Generating TARGET lesions ---")

# Helper vectors for location assignment
lung_dirs <- c(
  "Right Upper Lobe (RUL)", "Right Middle Lobe (RML)", "Right Lower Lobe (RLL)",
  "Left Upper Lobe (LUL)", "Left Lower Lobe (LLL)"
)

target_lesions <- subjects %>%
  rowwise() %>%
  mutate(
    # Generate lesion IDs for each target lesion
    lesion_data = list(
      tibble(
        lesion_num = 1:n_target_lesions,
        TULNKID = sprintf("T%02d", lesion_num)
      )
    )
  ) %>%
  unnest(lesion_data) %>%
  ungroup()

# Assign location and laterality per plan
target_lesions <- target_lesions %>%
  mutate(
    # Lung is always present (primary NSCLC)
    # Other locations based on metastatic pattern
    TULOC = case_when(
      lesion_num == 1 ~ "Lung",  # First lesion always lung per plan
      liver_mets & runif(n()) < 0.4 ~ "Liver",
      bone_mets & runif(n()) < 0.3 ~ "Bone",
      brain_mets & runif(n()) < 0.3 ~ "Brain",
      metastatic_sites >= 3 & runif(n()) < 0.2 ~ "Adrenal Gland",
      metastatic_sites >= 2 & runif(n()) < 0.3 ~ "Lymph Node",
      TRUE ~ sample(c("Lung", "Chest Wall"), 1, prob = c(0.8, 0.2))
    ),
    # Lung location gets specific lobe/laterality per plan
    TUDIR = if_else(
      TULOC == "Lung",
      sample(lung_dirs, 1),
      NA_character_
    ),
    # Imaging method per plan distribution
    TUMETHOD = sample(
      c("CT", "PET/CT", "MRI"),
      n(),
      replace = TRUE,
      prob = c(0.70, 0.20, 0.10)
    ),
    # Baseline visit
    VISITNUM = 1,
    VISIT = "Baseline RECIST assessment",
    # Date: RFSTDTC - random days (per plan: runif(1, 28) days before)
    days_before = runif(n(), 1, 28),
    TUDTC_raw = as.Date(RFSTDTC) - days_before,
    TUDTC = format(TUDTC_raw + date_shift, "%Y-%m-%d"),
    # Standard variables
    TUTESTCD = "TUASSESS",
    TUTEST = "Tumor Identification",
    TUORRES = "TARGET"
  )

message("✓ Generated ", nrow(target_lesions), " TARGET lesion records")

# --- Generate NON-TARGET lesions ---------------------------------------------
message("\n--- Generating NON-TARGET lesions ---")

# 70% of subjects get 1-2 non-target lesions
non_target_lesions <- subjects %>%
  dplyr::filter(runif(n()) < 0.70) %>%  # 70% of subjects per plan
  rowwise() %>%
  mutate(
    n_non_target = sample(1:2, 1),
    lesion_data = list(
      tibble(
        lesion_num = 1:n_non_target,
        TULNKID = sprintf("NT%02d", lesion_num)
      )
    )
  ) %>%
  unnest(lesion_data) %>%
  ungroup()

# Assign locations (similar logic but non-target)
non_target_lesions <- non_target_lesions %>%
  mutate(
    TULOC = case_when(
      liver_mets & runif(n()) < 0.3 ~ "Liver",
      bone_mets & runif(n()) < 0.3 ~ "Bone",
      brain_mets & runif(n()) < 0.2 ~ "Brain",
      metastatic_sites >= 3 & runif(n()) < 0.3 ~ "Adrenal Gland",
      metastatic_sites >= 2 & runif(n()) < 0.4 ~ "Lymph Node",
      TRUE ~ sample(c("Lung", "Pleura", "Chest Wall"), 1, prob = c(0.5, 0.3, 0.2))
    ),
    TUDIR = if_else(
      TULOC == "Lung",
      sample(lung_dirs, 1),
      NA_character_
    ),
    TUMETHOD = sample(
      c("CT", "PET/CT", "MRI"),
      n(),
      replace = TRUE,
      prob = c(0.70, 0.20, 0.10)
    ),
    VISITNUM = 1,
    VISIT = "Baseline RECIST assessment",
    days_before = runif(n(), 1, 28),
    TUDTC_raw = as.Date(RFSTDTC) - days_before,
    TUDTC = format(TUDTC_raw + date_shift, "%Y-%m-%d"),
    TUTESTCD = "TUASSESS",
    TUTEST = "Tumor Identification",
    TUORRES = "NON-TARGET"
  )

message("✓ Generated ", nrow(non_target_lesions), " NON-TARGET lesion records")

# --- Generate METS identification records ------------------------------------
message("\n--- Generating METS identification records ---")

# One record per metastatic site per subject
mets_records <- subjects %>%
  pivot_longer(
    cols = c(brain_mets, liver_mets, bone_mets),
    names_to = "mets_type",
    values_to = "has_mets"
  ) %>%
  dplyr::filter(has_mets) %>%
  mutate(
    TULOC = str_to_title(str_remove(mets_type, "_mets")),
    TULNKID = NA_character_,
    TUDIR = NA_character_,
    TUMETHOD = "Medical History",
    VISITNUM = NA_integer_,
    VISIT = NA_character_,
    # Date of first metastatic disease (before baseline, per plan)
    days_before = runif(n(), 90, 365),  # 3-12 months before RFSTDTC
    TUDTC_raw = as.Date(RFSTDTC) - days_before,
    TUDTC = format(TUDTC_raw + date_shift, "%Y-%m-%d"),
    TUTESTCD = "METS",
    TUTEST = "First date of metastatic disease for cancer primary",
    TUORRES = "METASTASIS"
  )

message("✓ Generated ", nrow(mets_records), " METS identification records")

# --- Combine all TU records --------------------------------------------------
message("\n--- Combining TU records ---")

tu_combined <- bind_rows(
  target_lesions,
  non_target_lesions,
  mets_records
)

# --- Finalize TU domain ------------------------------------------------------
tu <- tu_combined %>%
  arrange(USUBJID, VISITNUM, TULNKID) %>%
  group_by(USUBJID) %>%
  mutate(TUSEQ = row_number()) %>%
  ungroup() %>%
  mutate(DOMAIN = "TU") %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    TUSEQ,
    TULNKID,
    TUTESTCD,
    TUTEST,
    TUORRES,
    TULOC,
    TUDIR,
    TUMETHOD,
    VISITNUM,
    VISIT,
    TUDTC
  )

message("✓ Final TU domain: ", nrow(tu), " records")

# --- Validation --------------------------------------------------------------
message("\n=== TU Validation ===")

# Check 1: TARGET count matches DM.n_target_lesions
target_counts <- tu %>%
  dplyr::filter(TUORRES == "TARGET") %>%
  count(USUBJID, name = "n_target_actual")

dm_target_check <- dm %>%
  select(USUBJID, n_target_lesions) %>%
  left_join(target_counts, by = "USUBJID") %>%
  mutate(
    n_target_actual = coalesce(n_target_actual, 0L),
    match = n_target_lesions == n_target_actual
  )

n_mismatch <- sum(!dm_target_check$match)
if (n_mismatch > 0) {
  stop(
    "TARGET lesion count mismatch for ", n_mismatch, " subjects.\n",
    "First 5 mismatches:\n",
    paste(capture.output(print(head(dm_target_check[!dm_target_check$match, ], 5))), collapse = "\n"),
    call. = FALSE
  )
}
message("✓ TARGET lesion counts match DM.n_target_lesions (",
        nrow(dm_target_check), " subjects)")

# Check 2: METS match DM mets flags
mets_counts <- tu %>%
  dplyr::filter(TUTESTCD == "METS") %>%
  count(USUBJID, TULOC, name = "n_mets")

dm_mets_check <- dm %>%
  select(USUBJID, brain_mets, liver_mets, bone_mets) %>%
  left_join(
    mets_counts %>%
      pivot_wider(names_from = TULOC, values_from = n_mets, values_fill = 0),
    by = "USUBJID"
  ) %>%
  mutate(
    Brain = coalesce(Brain, 0L),
    Liver = coalesce(Liver, 0L),
    Bone = coalesce(Bone, 0L),
    brain_match = (brain_mets & Brain > 0) | (!brain_mets & Brain == 0),
    liver_match = (liver_mets & Liver > 0) | (!liver_mets & Liver == 0),
    bone_match = (bone_mets & Bone > 0) | (!bone_mets & Bone == 0),
    all_match = brain_match & liver_match & bone_match
  )

n_mets_mismatch <- sum(!dm_mets_check$all_match)
if (n_mets_mismatch > 0) {
  stop(
    "METS site mismatch for ", n_mets_mismatch, " subjects.\n",
    "First 5 mismatches:\n",
    paste(capture.output(print(head(dm_mets_check[!dm_mets_check$all_match, ], 5))), collapse = "\n"),
    call. = FALSE
  )
}
message("✓ METS sites match DM mets flags (", nrow(dm_mets_check), " subjects)")

# Check 3: TUSEQ uniqueness per subject
seq_check <- tu %>%
  group_by(USUBJID) %>%
  summarise(
    n_records = n(),
    n_unique_seq = n_distinct(TUSEQ),
    max_seq = max(TUSEQ),
    .groups = "drop"
  ) %>%
  mutate(
    seq_valid = (n_records == n_unique_seq) & (max_seq == n_records)
  )

if (!all(seq_check$seq_valid)) {
  stop(
    "TUSEQ validation failed for ", sum(!seq_check$seq_valid), " subjects",
    call. = FALSE
  )
}
message("✓ TUSEQ is unique and sequential per subject")

# Check 4: Required variables present
required_vars <- c("STUDYID", "DOMAIN", "USUBJID", "TUSEQ", "TUTESTCD",
                   "TUTEST", "TUORRES", "TUDTC")
missing_required <- setdiff(required_vars, names(tu))
if (length(missing_required) > 0) {
  stop("Missing required variables: ", paste(missing_required, collapse = ", "),
       call. = FALSE)
}
message("✓ All required variables present")

# Check 5: No missing core values
core_vars <- c("USUBJID", "TUSEQ", "TUTESTCD", "TUORRES")
for (var in core_vars) {
  n_missing <- sum(is.na(tu[[var]]))
  if (n_missing > 0) {
    stop(var, " has ", n_missing, " missing values", call. = FALSE)
  }
}
message("✓ No missing values in core variables")

# --- Summary statistics ------------------------------------------------------
message("\n=== TU Summary ===")
message("Total records: ", nrow(tu))
message("Total subjects: ", n_distinct(tu$USUBJID))
message("Records per subject: ",
        sprintf("%.1f (range: %d-%d)",
                mean(table(tu$USUBJID)),
                min(table(tu$USUBJID)),
                max(table(tu$USUBJID))))

tu %>%
  count(TUORRES, name = "n_records") %>%
  mutate(pct = sprintf("%.1f%%", 100 * n_records / sum(n_records))) %>%
  print()

message("\nTop tumor locations:")
tu %>%
  dplyr::filter(TUTESTCD == "TUASSESS") %>%
  count(TULOC, sort = TRUE) %>%
  head(10) %>%
  print()

# --- Apply variable labels and types -----------------------------------------
tu_meta <- tibble(
  variable = c(
    "STUDYID", "DOMAIN", "USUBJID", "TUSEQ", "TULNKID",
    "TUTESTCD", "TUTEST", "TUORRES", "TULOC", "TUDIR",
    "TUMETHOD", "VISITNUM", "VISIT", "TUDTC"
  ),
  label = c(
    "Study Identifier",
    "Domain Abbreviation",
    "Unique Subject Identifier",
    "Sequence Number",
    "Link ID",
    "Tumor Identification Short Name",
    "Tumor Identification",
    "Result or Finding in Original Format",
    "Location of the Tumor",
    "Directionality of the Tumor",
    "Method of Tumor Measurement",
    "Visit Number",
    "Visit Name",
    "Date/Time of Tumor Identification"
  ),
  type = c(
    "character", "character", "character", "numeric", "character",
    "character", "character", "character", "character", "character",
    "character", "numeric",   "character", "character"
  )
)

tu_xpt <- tu %>%
  xportr_label(tu_meta, domain = "TU") %>%
  xportr_type(tu_meta, domain = "TU")

# --- Save outputs ------------------------------------------------------------
saveRDS(tu_xpt, "output-data/sdtm/tu.rds")
message("✓ Saved: output-data/sdtm/tu.rds")

haven::write_xpt(tu_xpt, "output-data/sdtm/tu.xpt", version = 5)
message("✓ Saved: output-data/sdtm/tu.xpt")

message("\n=== TU domain generation complete ===")
