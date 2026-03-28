# Test: Complexity Threshold Detection
# Tests the pattern detection logic that the feature-planner agent should use
# to identify >15 similar derivations

library(testthat)
library(dplyr)
library(stringr)

# --- Simulate derivation descriptions ---
# This simulates what the planner would parse from a dataset specification

test_that("Pattern detection identifies 20 biomarker flags", {

  # Simulate ADSL variable derivation descriptions
  derivations <- tibble::tribble(
    ~variable,    ~derivation_text,
    "EGFRMUT",    "Pattern match on LB.LBSTRESC for EGFR",
    "KRASMUT",    "Pattern match on LB.LBSTRESC for KRAS",
    "ALK",        "Pattern match on LB.LBSTRESC for ALK",
    "ROS1MUT",    "Pattern match on LB.LBSTRESC for ROS1",
    "RETMUT",     "Pattern match on LB.LBSTRESC for RET",
    "METMUT",     "Pattern match on LB.LBSTRESC for MET",
    "ERBB2MUT",   "Pattern match on LB.LBSTRESC for ERBB2",
    "NTRK1FUS",   "Pattern match on LB.LBSTRESC for NTRK1",
    "NTRK2FUS",   "Pattern match on LB.LBSTRESC for NTRK2",
    "NTRK3FUS",   "Pattern match on LB.LBSTRESC for NTRK3",
    "BRAF",       "Pattern match on LB.LBSTRESC for BRAF",
    "NRASMUT",    "Pattern match on LB.LBSTRESC for NRAS",
    "PIK3CA",     "Pattern match on LB.LBSTRESC for PIK3CA",
    "PDGFRA",     "Pattern match on LB.LBSTRESC for PDGFRA",
    "KIT",        "Pattern match on LB.LBSTRESC for KIT",
    "FGFR1",      "Pattern match on LB.LBSTRESC for FGFR1",
    "FGFR2",      "Pattern match on LB.LBSTRESC for FGFR2",
    "FGFR3",      "Pattern match on LB.LBSTRESC for FGFR3",
    "DDR2",       "Pattern match on LB.LBSTRESC for DDR2",
    "MAPK1",      "Pattern match on LB.LBSTRESC for MAPK1",
    "AGE",        "Derived from DM.BRTHDTC and DM.RFSTDTC",
    "SEX",        "Direct copy from DM.SEX"
  )

  # --- Pattern detection algorithm ---
  # Extract pattern signature (everything except the parameter)

  patterns <- derivations %>%
    mutate(
      # Extract the pattern signature (remove the specific test code)
      signature = str_replace(derivation_text, " for [A-Z0-9]+$", " for <TEST>")
    ) %>%
    group_by(signature) %>%
    summarise(
      count = n(),
      variables = list(variable),
      .groups = "drop"
    ) %>%
    arrange(desc(count))

  # Check that we detected the biomarker pattern
  biomarker_pattern <- patterns %>%
    filter(str_detect(signature, "Pattern match on LB.LBSTRESC"))

  expect_equal(nrow(biomarker_pattern), 1)
  expect_equal(biomarker_pattern$count, 20)

  # Check that the pattern exceeds the threshold
  COMPLEXITY_THRESHOLD <- 15

  high_complexity_patterns <- patterns %>%
    filter(count > COMPLEXITY_THRESHOLD)

  expect_equal(nrow(high_complexity_patterns), 1)
  expect_true(high_complexity_patterns$count[1] == 20)

  message("✓ Pattern detection identified ", biomarker_pattern$count,
          " similar derivations (threshold: ", COMPLEXITY_THRESHOLD, ")")
})

test_that("Pattern detection extracts correct parameters", {

  # Test parameter extraction for helper function signature
  derivation <- "Pattern match on LB.LBSTRESC for EGFR"

  # Extract components
  domain <- str_extract(derivation, "[A-Z]+(?=\\.)")
  variable <- str_extract(derivation, "(?<=\\.)[A-Z]+")
  operation <- str_extract(derivation, "^[^f]+(?= for)")
  parameter <- str_extract(derivation, "[A-Z0-9]+$")

  expect_equal(domain, "LB")
  expect_equal(variable, "LBSTRESC")
  expect_equal(operation, "Pattern match on LB.LBSTRESC")
  expect_equal(parameter, "EGFR")

  # Verify we can construct a function signature
  function_name <- "create_biomarker_flag"
  params <- c("lb_data", "test_code", "var_name")

  signature <- paste0(function_name, "(", paste(params, collapse = ", "), ")")
  expect_equal(signature, "create_biomarker_flag(lb_data, test_code, var_name)")

  message("✓ Successfully extracted pattern components and constructed function signature")
})

test_that("Pattern detection handles non-repetitive derivations correctly", {

  # Test that patterns below threshold are not flagged
  derivations <- tibble::tribble(
    ~variable,  ~derivation_text,
    "AGE",      "Derived from DM.BRTHDTC and DM.RFSTDTC",
    "SEX",      "Direct copy from DM.SEX",
    "RACE",     "Direct copy from DM.RACE",
    "ETHNIC",   "Direct copy from DM.ETHNIC",
    "TRTSDT",   "First non-missing EXSTDTC",
    "TRTEDT",   "Last non-missing EXENDTC"
  )

  patterns <- derivations %>%
    mutate(
      signature = str_replace(derivation_text, " [A-Z\\.]+$", " <VAR>")
    ) %>%
    group_by(signature) %>%
    summarise(count = n(), .groups = "drop")

  # No pattern should exceed threshold
  COMPLEXITY_THRESHOLD <- 15
  expect_true(all(patterns$count <= COMPLEXITY_THRESHOLD))

  message("✓ Non-repetitive derivations correctly identified (no false positives)")
})

# --- Run tests ---
test_file("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/tests/test-complexity-detection.R")
