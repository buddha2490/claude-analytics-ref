# =============================================================================
# sim_tu.R
# TU (Tumor Identification) SDTM Domain Simulation
# Study: NPM008 / XB010-101
# Domain order: 14 — seed = 42 + 14 = 56
# =============================================================================

library(tidyverse)
library(haven)

set.seed(56)

# --- Load inputs -------------------------------------------------------------

dm <- readRDS("cohort/output-data/dm.rds")
ex <- readRDS("cohort/output-data/ex.rds")

# One EXSTDTC per subject (first dose date, Cycle 1 Day 1)
ex_dates <- ex %>%
  dplyr::select(USUBJID, EXSTDTC) %>%
  distinct(USUBJID, .keep_all = TRUE)

# Merge DM latent variables with first-dose dates
subjects <- dm %>%
  dplyr::select(USUBJID, STUDYID, n_target_lesions, brain_mets, liver_mets, bone_mets) %>%
  left_join(ex_dates, by = "USUBJID")

# --- Helper: derive TULOC for target lesions ---------------------------------
# First target always "Lung"; subsequent lesions drawn from met sites present,
# then from generic sites if more are needed.

build_target_locations <- function(n, brain, liver, bone) {
  # Pool of available met-site locations (excluding Lung, always first)
  met_pool <- c(
    if (brain) "Brain"  else character(0),
    if (liver) "Liver"  else character(0),
    if (bone)  "Bone"   else character(0)
  )
  generic_pool <- c("Lymph Node", "Adrenal Gland", "Chest Wall")

  locs <- "Lung"  # First target is always Lung

  if (n > 1) {
    need_more <- n - 1
    # Draw from met pool (no replacement if pool is small)
    from_mets <- head(sample(met_pool), min(need_more, length(met_pool)))
    locs <- c(locs, from_mets)
    need_more <- need_more - length(from_mets)
    # Fill remaining from generic pool
    if (need_more > 0) {
      from_generic <- sample(generic_pool, size = need_more, replace = TRUE)
      locs <- c(locs, from_generic)
    }
  }
  locs
}

# --- Helper: TUDIR for a given location --------------------------------------
lung_dirs <- c(
  "Right Upper Lobe (RUL)", "Right Middle Lobe (RML)", "Right Lower Lobe (RLL)",
  "Left Upper Lobe (LUL)", "Left Lower Lobe (LLL)"
)

get_tudir <- function(loc) {
  if_else(loc == "Lung", sample(lung_dirs, 1), NA_character_)
}

# --- Helper: non-target site pool excluding already-used target locations ----
all_candidate_sites <- c(
  "Lung", "Brain", "Liver", "Bone",
  "Lymph Node", "Adrenal Gland", "Chest Wall",
  "Pleura", "Kidney", "Spleen"
)

build_nontarget_locations <- function(n_nt, target_locs) {
  pool <- setdiff(all_candidate_sites, target_locs)
  if (length(pool) == 0) pool <- c("Pleura", "Kidney", "Spleen")
  sample(pool, size = min(n_nt, length(pool)), replace = FALSE)
}

# --- Per-subject record builder ----------------------------------------------

build_subject_tu <- function(row) {
  usubjid       <- row$USUBJID
  studyid       <- row$STUDYID
  n_target      <- row$n_target_lesions
  brain         <- row$brain_mets
  liver         <- row$liver_mets
  bone          <- row$bone_mets
  exstdtc       <- row$EXSTDTC

  # Shared per-subject values
  tu_method  <- sample(c("CT", "PET/CT", "MRI"), 1, prob = c(0.70, 0.20, 0.10))
  offset_days <- sample(1:28, 1)
  tudtc       <- as.character(as.Date(exstdtc) - offset_days)

  records <- list()

  # --- TARGET lesion records ------------------------------------------------
  target_locs <- build_target_locations(n_target, brain, liver, bone)

  target_recs <- tibble(
    USUBJID  = usubjid,
    STUDYID  = studyid,
    TUTESTCD = "TUASSESS",
    TUTEST   = "Tumor Identification",
    TUORRES  = "TARGET",
    TULNKID  = paste0("T0", seq_along(target_locs)),
    TULOC    = target_locs,
    TUDIR    = map_chr(target_locs, get_tudir),
    TUMETHOD = tu_method,
    VISITNUM = 1,
    VISIT    = "Baseline RECIST assessment",
    TUDTC    = tudtc
  )
  records[["target"]] <- target_recs

  # --- NON-TARGET lesion records (70% of subjects) --------------------------
  has_nontarget <- runif(1) < 0.70
  if (has_nontarget) {
    n_nt       <- sample(1:2, 1)
    nt_locs    <- build_nontarget_locations(n_nt, target_locs)
    nt_dirs    <- map_chr(nt_locs, get_tudir)

    nt_recs <- tibble(
      USUBJID  = usubjid,
      STUDYID  = studyid,
      TUTESTCD = "TUASSESS",
      TUTEST   = "Tumor Identification",
      TUORRES  = "NON-TARGET",
      TULNKID  = paste0("NT0", seq_along(nt_locs)),
      TULOC    = nt_locs,
      TUDIR    = nt_dirs,
      TUMETHOD = tu_method,
      VISITNUM = 1,
      VISIT    = "Baseline RECIST assessment",
      TUDTC    = tudtc
    )
    records[["nontarget"]] <- nt_recs
  }

  # --- METS records (one per met site flag that is TRUE) --------------------
  met_sites <- c(
    if (brain) "Brain" else character(0),
    if (liver) "Liver" else character(0),
    if (bone)  "Bone"  else character(0)
  )

  if (length(met_sites) > 0) {
    met_recs <- tibble(
      USUBJID  = usubjid,
      STUDYID  = studyid,
      TUTESTCD = "METS",
      TUTEST   = "First date of metastatic disease for cancer primary",
      TUORRES  = "METASTASIS",
      TULNKID  = paste0("M0", seq_along(met_sites)),
      TULOC    = met_sites,
      TUDIR    = NA_character_,
      TUMETHOD = NA_character_,
      VISITNUM = NA_real_,
      VISIT    = NA_character_,
      TUDTC    = as.character(as.Date(exstdtc) - sample(30:365, length(met_sites), replace = TRUE))
    )
    records[["mets"]] <- met_recs
  }

  # Bind all record types for this subject
  subj_tu <- bind_rows(records)

  # TUSEQ: sequential across all record types per subject
  subj_tu %>%
    mutate(
      DOMAIN  = "TU",
      TUSEQ   = row_number()
    )
}

# --- Build full TU dataset ---------------------------------------------------

tu_raw <- purrr::map_dfr(
  seq_len(nrow(subjects)),
  function(i) build_subject_tu(as.list(subjects[i, ]))
)

# --- Final variable order and STUDYID placement ------------------------------

tu <- tu_raw %>%
  dplyr::select(
    STUDYID, DOMAIN, USUBJID, TUSEQ,
    TUTESTCD, TUTEST, TUORRES,
    TULNKID, TULOC, TUDIR,
    TUMETHOD, VISITNUM, VISIT, TUDTC
  )

# --- Apply variable labels ---------------------------------------------------

label_map <- list(
  STUDYID  = "Study Identifier",
  DOMAIN   = "Domain Abbreviation",
  USUBJID  = "Unique Subject Identifier",
  TUSEQ    = "Sequence Number",
  TUTESTCD = "Tumor Identification Short Name",
  TUTEST   = "Tumor Identification",
  TUORRES  = "Original Assessment",
  TULNKID  = "Link ID",
  TULOC    = "Location",
  TUDIR    = "Directionality",
  TUMETHOD = "Method",
  VISITNUM = "Visit Number",
  VISIT    = "Visit Name",
  TUDTC    = "Date/Time of Assessment"
)

for (v in names(label_map)) {
  attr(tu[[v]], "label") <- label_map[[v]]
}

# --- Validation checks -------------------------------------------------------

message("--- TU Validation ---")

# 1. All USUBJIDs in DM
unmatched_subj <- setdiff(unique(tu$USUBJID), dm$USUBJID)
if (length(unmatched_subj) > 0) {
  stop("USUBJIDs in TU not found in DM: ", paste(unmatched_subj, collapse = ", "),
       call. = FALSE)
}
message("PASS: All USUBJIDs found in DM (", n_distinct(tu$USUBJID), " subjects)")

# 2. TUSEQ unique per USUBJID
seq_check <- tu %>%
  group_by(USUBJID) %>%
  summarise(n_seq = n(), n_uniq = n_distinct(TUSEQ), .groups = "drop") %>%
  dplyr::filter(n_seq != n_uniq)
if (nrow(seq_check) > 0) {
  stop("TUSEQ is not unique within USUBJID for: ",
       paste(seq_check$USUBJID, collapse = ", "), call. = FALSE)
}
message("PASS: TUSEQ unique within every USUBJID")

# 3. TARGET records have TUORRES = "TARGET"
target_check <- tu %>%
  dplyr::filter(stringr::str_starts(TULNKID, "T0"), !str_starts(TULNKID, "T0\\d")) %>%
  nrow()
# Simpler: check TULNKID T0x <=> TUORRES TARGET
target_mismatch <- tu %>%
  dplyr::filter(stringr::str_detect(TULNKID, "^T0[0-9]+$"), TUORRES != "TARGET")
if (nrow(target_mismatch) > 0) {
  stop("TARGET TULNKID records with unexpected TUORRES.", call. = FALSE)
}
message("PASS: All T0x TULNKID records have TUORRES = 'TARGET'")

# 4. NT0x <=> NON-TARGET
nt_mismatch <- tu %>%
  dplyr::filter(stringr::str_detect(TULNKID, "^NT0[0-9]+$"), TUORRES != "NON-TARGET")
if (nrow(nt_mismatch) > 0) {
  stop("NON-TARGET TULNKID mismatch.", call. = FALSE)
}
message("PASS: All NT0x TULNKID records have TUORRES = 'NON-TARGET'")

# 5. M0x <=> METASTASIS
m_mismatch <- tu %>%
  dplyr::filter(stringr::str_detect(TULNKID, "^M0[0-9]+$"), TUORRES != "METASTASIS")
if (nrow(m_mismatch) > 0) {
  stop("METS TULNKID mismatch.", call. = FALSE)
}
message("PASS: All M0x TULNKID records have TUORRES = 'METASTASIS'")

# 6. TUDTC < EXSTDTC for all records
tu_date_check <- tu %>%
  left_join(ex_dates, by = "USUBJID") %>%
  dplyr::filter(!is.na(TUDTC), !is.na(EXSTDTC)) %>%
  dplyr::filter(as.Date(TUDTC) >= as.Date(EXSTDTC))
if (nrow(tu_date_check) > 0) {
  warning(nrow(tu_date_check), " record(s) have TUDTC >= EXSTDTC — check date offsets.",
          call. = FALSE)
} else {
  message("PASS: All TUDTC values are before EXSTDTC")
}

# --- Summary -----------------------------------------------------------------

message("\n--- TU Record Summary ---")
message("Total records: ", nrow(tu))
message("Subjects: ", n_distinct(tu$USUBJID))
tu %>%
  count(TUORRES, name = "n_records") %>%
  print()

message("\nTUTESTCD distribution:")
tu %>% count(TUTESTCD) %>% print()

message("\nTUMETHOD distribution (TARGET/NON-TARGET only):")
tu %>%
  dplyr::filter(TUORRES %in% c("TARGET", "NON-TARGET")) %>%
  count(TUMETHOD) %>%
  print()

# --- Write outputs -----------------------------------------------------------

# Save as RDS for downstream TR domain
saveRDS(tu, "cohort/output-data/sdtm/tu.rds")
message("Saved: cohort/output-data/sdtm/tu.rds")

# Write XPT
haven::write_xpt(tu, "cohort/output-data/sdtm/tu.xpt", version = 5)
message("Saved: cohort/output-data/sdtm/tu.xpt")

message("\nDone. TU domain simulation complete.")
