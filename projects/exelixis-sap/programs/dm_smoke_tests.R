# =============================================================================
# Script:    dm_smoke_tests.R
# Purpose:   Wave 0 Extra Validation — DM smoke tests per plan Section 7
# Date:      2026-03-28
# =============================================================================

library(tidyverse)

# Load DM data
dm <- readRDS("output-data/sdtm/dm.rds")

message(strrep("=", 70))
message("Wave 0 Extra Validation: DM Smoke Tests")
message(strrep("=", 70))

# --- Test 1: AGE distribution -------------------------------------------------
age_mean <- mean(dm$AGE, na.rm = TRUE)
age_sd <- sd(dm$AGE, na.rm = TRUE)

age_pass <- age_mean >= 60 && age_mean <= 68 && age_sd >= 6 && age_sd <= 12
message(sprintf("✓ AGE: mean=%.1f (target [60,68]), sd=%.1f (target [6,12]) — %s",
                age_mean, age_sd, ifelse(age_pass, "PASS", "FAIL")))

# --- Test 2: SEX distribution -------------------------------------------------
sex_m_count <- sum(dm$SEX == "M", na.rm = TRUE)
sex_pass <- sex_m_count >= 18 && sex_m_count <= 26
message(sprintf("✓ SEX: M count=%d (target [18,26]) — %s",
                sex_m_count, ifelse(sex_pass, "PASS", "FAIL")))

# --- Test 3: RACE distribution ------------------------------------------------
race_white_count <- sum(dm$RACE == "WHITE", na.rm = TRUE)
race_pass <- race_white_count >= 24 && race_white_count <= 32
message(sprintf("✓ RACE: WHITE count=%d (target [24,32]) — %s",
                race_white_count, ifelse(race_pass, "PASS", "FAIL")))

# --- Test 4: DTHFL distribution -----------------------------------------------
dthfl_yes_count <- sum(dm$DTHFL == "Y", na.rm = TRUE)
dthfl_pass <- dthfl_yes_count >= 26 && dthfl_yes_count <= 30
message(sprintf("✓ DTHFL: Y count=%d (target [26,30]) — %s",
                dthfl_yes_count, ifelse(dthfl_pass, "PASS", "FAIL")))

# --- Test 5: BOR distribution -------------------------------------------------
bor_pr <- sum(dm$bor == "PR", na.rm = TRUE)
bor_sd <- sum(dm$bor == "SD", na.rm = TRUE)
bor_pd <- sum(dm$bor == "PD", na.rm = TRUE)
bor_ne <- sum(dm$bor == "NE", na.rm = TRUE)

bor_pr_pass <- bor_pr >= 5 && bor_pr <= 10
bor_sd_pass <- bor_sd >= 13 && bor_sd <= 19
bor_pd_pass <- bor_pd >= 11 && bor_pd <= 17
bor_ne_pass <- bor_ne >= 1 && bor_ne <= 5

message(sprintf("✓ BOR: PR=%d [5,10], SD=%d [13,19], PD=%d [11,17], NE=%d [1,5] — %s",
                bor_pr, bor_sd, bor_pd, bor_ne,
                ifelse(bor_pr_pass && bor_sd_pass && bor_pd_pass && bor_ne_pass, "PASS", "FAIL")))

# --- Test 6: Latent variables non-NA ------------------------------------------
latent_vars <- c("bor", "pfs_days", "os_days", "date_shift", "pdl1_status",
                 "egfr_status", "alk_status", "kras_status", "n_target_lesions",
                 "n_prior_lots", "ecog_bl", "metastatic_sites", "brain_mets",
                 "liver_mets", "bone_mets", "de_novo_met")

latent_na_count <- dm %>%
  select(all_of(latent_vars)) %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  rowSums()

latent_pass <- latent_na_count == 0
message(sprintf("✓ Latent variables: %d NA values (target 0) — %s",
                latent_na_count, ifelse(latent_pass, "PASS", "FAIL")))

# --- Test 7: RFSTDTC range ----------------------------------------------------
rfstdtc_min <- min(as.Date(dm$RFSTDTC), na.rm = TRUE)
rfstdtc_max <- max(as.Date(dm$RFSTDTC), na.rm = TRUE)

rfstdtc_pass <- rfstdtc_min >= as.Date("2022-01-01") && rfstdtc_max <= as.Date("2025-06-30")
message(sprintf("✓ RFSTDTC range: [%s, %s] (target [2022-01-01, 2025-06-30]) — %s",
                rfstdtc_min, rfstdtc_max, ifelse(rfstdtc_pass, "PASS", "FAIL")))

# --- Overall verdict ----------------------------------------------------------
message(strrep("=", 70))

all_pass <- age_pass && sex_pass && race_pass && dthfl_pass &&
            bor_pr_pass && bor_sd_pass && bor_pd_pass && bor_ne_pass &&
            latent_pass && rfstdtc_pass

if (all_pass) {
  message("✅ SMOKE TESTS: ALL PASS — Ready for Wave 1")
} else {
  message("❌ SMOKE TESTS: FAILED — Fix issues before proceeding")
  stop("DM smoke tests failed", call. = FALSE)
}

message(strrep("=", 70))
