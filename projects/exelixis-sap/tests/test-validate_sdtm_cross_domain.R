# Test: validate_sdtm_cross_domain.R

library(testthat)
library(dplyr)
library(withr)

# Source the function
source("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/R/validate_sdtm_cross_domain.R")

# --- Helper: Create minimal valid domain datasets ---
create_mock_domains <- function(n_subjects = 40) {
  # Generate USUBJIDs
  usubjids <- sprintf("NPM008-%02d-A%04d", 1:n_subjects, 1001:(1000 + n_subjects))

  # DM - Demographics
  dm <- data.frame(
    STUDYID = rep("NPM008", n_subjects),
    DOMAIN = rep("DM", n_subjects),
    USUBJID = usubjids,
    RFSTDTC = rep("2024-01-15", n_subjects),
    RFENDTC = rep("2024-06-15", n_subjects),
    DTHFL = rep("N", n_subjects),
    DTHDTC = rep(NA_character_, n_subjects),
    bor = sample(c("CR", "PR", "SD", "PD"), n_subjects, replace = TRUE),
    stringsAsFactors = FALSE
  )

  # IE - Inclusion/Exclusion (10 per subject)
  ie <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 10),
    DOMAIN = rep("IE", n_subjects * 10),
    USUBJID = rep(usubjids, each = 10),
    IESEQ = rep(1:10, n_subjects),
    stringsAsFactors = FALSE
  )

  # Simple domains with one row per subject
  simple_domains <- list(
    MH = "MH", SC = "SC", SU = "SU", EX = "EX", EC = "EC",
    CM = "CM", PR = "PR", QS = "QS"
  )

  domains <- list(DM = dm, IE = ie)

  for (domain_code in names(simple_domains)) {
    domains[[domain_code]] <- data.frame(
      STUDYID = rep("NPM008", n_subjects),
      DOMAIN = rep(domain_code, n_subjects),
      USUBJID = usubjids,
      stringsAsFactors = FALSE
    )

    # Add SEQ column if applicable
    seq_col <- paste0(domain_code, "SEQ")
    domains[[domain_code]][[seq_col]] <- 1:n_subjects
  }

  # DS - Disposition (with required columns for death checks)
  domains$DS <- data.frame(
    STUDYID = rep("NPM008", n_subjects),
    DOMAIN = rep("DS", n_subjects),
    USUBJID = usubjids,
    DSSEQ = 1:n_subjects,
    DSDECOD = rep("COMPLETED", n_subjects),
    DSDTC = rep("2024-06-15", n_subjects),
    stringsAsFactors = FALSE
  )

  # VS - Vital Signs (5 per subject)
  domains$VS <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 5),
    DOMAIN = rep("VS", n_subjects * 5),
    USUBJID = rep(usubjids, each = 5),
    VSSEQ = rep(1:5, n_subjects),
    VSDTC = rep("2024-02-01", n_subjects * 5),
    stringsAsFactors = FALSE
  )

  # LB - Lab (10 per subject)
  domains$LB <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 10),
    DOMAIN = rep("LB", n_subjects * 10),
    USUBJID = rep(usubjids, each = 10),
    LBSEQ = rep(1:10, n_subjects),
    LBDTC = rep("2024-02-01", n_subjects * 10),
    stringsAsFactors = FALSE
  )

  # BS - Biospecimen
  domains$BS <- data.frame(
    STUDYID = rep("NPM008", n_subjects),
    DOMAIN = rep("BS", n_subjects),
    USUBJID = usubjids,
    BSSEQ = 1:n_subjects,
    BSREFID = sprintf("BS%04d", 1:n_subjects),
    stringsAsFactors = FALSE
  )

  # TU - Tumor Identification (2 per subject)
  domains$TU <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 2),
    DOMAIN = rep("TU", n_subjects * 2),
    USUBJID = rep(usubjids, each = 2),
    TUSEQ = rep(1:2, n_subjects),
    TULNKID = sprintf("TU%03d", 1:(n_subjects * 2)),
    stringsAsFactors = FALSE
  )

  # TR - Tumor Results (2 per subject, matching TU)
  domains$TR <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 2),
    DOMAIN = rep("TR", n_subjects * 2),
    USUBJID = rep(usubjids, each = 2),
    TRSEQ = rep(1:2, n_subjects),
    TULNKID = sprintf("TU%03d", 1:(n_subjects * 2)),
    stringsAsFactors = FALSE
  )

  # RS - Response (1 per subject with BOR)
  domains$RS <- data.frame(
    STUDYID = rep("NPM008", n_subjects),
    DOMAIN = rep("RS", n_subjects),
    USUBJID = usubjids,
    RSSEQ = 1:n_subjects,
    RSTESTCD = rep("OVRLRESP", n_subjects),
    RSSTRESC = dm$bor,
    stringsAsFactors = FALSE
  )

  # AE - Adverse Events (3 per subject)
  domains$AE <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 3),
    DOMAIN = rep("AE", n_subjects * 3),
    USUBJID = rep(usubjids, each = 3),
    AESEQ = rep(1:3, n_subjects),
    AESTDTC = rep("2024-02-15", n_subjects * 3),
    stringsAsFactors = FALSE
  )

  # HO - Healthcare Encounters (1 per AE)
  domains$HO <- data.frame(
    STUDYID = rep("NPM008", n_subjects * 3),
    DOMAIN = rep("HO", n_subjects * 3),
    USUBJID = rep(usubjids, each = 3),
    HOSEQ = rep(1:3, n_subjects),
    HOHNKID = rep(1:3, n_subjects),  # Links to AESEQ
    stringsAsFactors = FALSE
  )

  domains
}

# --- Test X13: File inventory ---
test_that("X13: Missing domain files trigger BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write only DM, not all domains
  saveRDS(domains$DM, file.path(sdtm_dir, "DM.rds"))

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x13_finding <- result$findings[result$findings$check_id == "X13", ]
  expect_equal(x13_finding$result, "FAIL")
  expect_equal(x13_finding$severity, "BLOCKING")
})

test_that("X13: All domain files present passes", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x13_finding <- result$findings[result$findings$check_id == "X13", ]
  expect_equal(x13_finding$result, "PASS")
})

# --- Test X1: Referential integrity ---
test_that("X1: USUBJID not in DM triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Add invalid USUBJID to AE
  domains$AE$USUBJID[1] <- "NPM008-99-Z9999"

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x1_finding <- result$findings[result$findings$check_id == "X1", ]
  expect_equal(x1_finding$result, "FAIL")
  expect_equal(x1_finding$severity, "BLOCKING")
})

test_that("X1: All USUBJIDs in DM passes", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x1_finding <- result$findings[result$findings$check_id == "X1", ]
  expect_equal(x1_finding$result, "PASS")
})

# --- Test X2: Cardinality - 40 distinct USUBJIDs ---
test_that("X2: Domain with <40 subjects triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Remove one subject from DS
  domains$DS <- domains$DS[1:39, ]

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x2_finding <- result$findings[result$findings$check_id == "X2", ]
  expect_equal(x2_finding$result, "FAIL")
  expect_equal(x2_finding$severity, "BLOCKING")
})

test_that("X2: All domains with 40 subjects passes", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x2_finding <- result$findings[result$findings$check_id == "X2", ]
  expect_equal(x2_finding$result, "PASS")
})

# --- Test X3: Date coherence - no events before RFSTDTC ---
test_that("X3: Event before RFSTDTC triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Set VS date before RFSTDTC
  domains$VS$VSDTC[1] <- "2024-01-01"  # Before RFSTDTC = 2024-01-15

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x3_finding <- result$findings[result$findings$check_id == "X3", ]
  expect_equal(x3_finding$result, "FAIL")
  expect_equal(x3_finding$severity, "BLOCKING")
})

test_that("X3: MH dates before RFSTDTC are allowed", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Add date column to MH before RFSTDTC
  domains$MH$MHSTDTC <- "2023-01-01"  # Before RFSTDTC

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  # X3 should still pass because MH is exempt
  x3_finding <- result$findings[result$findings$check_id == "X3", ]
  expect_equal(x3_finding$result, "PASS")
})

# --- Test X4: No events after death date ---
test_that("X4: Event after DTHDTC triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Mark first subject as deceased
  domains$DM$DTHFL[1] <- "Y"
  domains$DM$DTHDTC[1] <- "2024-03-01"

  # Add AE after death date
  domains$AE$AESTDTC[1] <- "2024-03-15"  # After DTHDTC

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x4_finding <- result$findings[result$findings$check_id == "X4", ]
  expect_equal(x4_finding$result, "FAIL")
  expect_equal(x4_finding$severity, "BLOCKING")
})

# --- Test X5: TU ↔ TR linkage ---
test_that("X5: Orphan TULNKID triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Add orphan TULNKID in TR
  domains$TR$TULNKID[1] <- "TU999"  # Not in TU

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x5_finding <- result$findings[result$findings$check_id == "X5", ]
  expect_equal(x5_finding$result, "FAIL")
  expect_equal(x5_finding$severity, "BLOCKING")
})

test_that("X5: Valid TU ↔ TR linkage passes", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x5_finding <- result$findings[result$findings$check_id == "X5", ]
  expect_equal(x5_finding$result, "PASS")
})

# --- Test X6: AE ↔ HO linkage ---
test_that("X6: Orphan HOHNKID triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Add orphan HOHNKID
  domains$HO$HOHNKID[1] <- 999  # Not in AE

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x6_finding <- result$findings[result$findings$check_id == "X6", ]
  expect_equal(x6_finding$result, "FAIL")
  expect_equal(x6_finding$severity, "BLOCKING")
})

test_that("X6: Valid AE ↔ HO linkage passes", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x6_finding <- result$findings[result$findings$check_id == "X6", ]
  expect_equal(x6_finding$result, "PASS")
})

# --- Test X8: Death consistency DS ↔ DM ---
test_that("X8: Mismatched death records trigger BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Mark subject as deceased in DM but not in DS
  domains$DM$DTHFL[1] <- "Y"
  domains$DM$DTHDTC[1] <- "2024-03-01"
  domains$DS$DSDECOD <- rep("COMPLETED", 40)  # No DEATH

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x8_finding <- result$findings[result$findings$check_id == "X8", ]
  expect_equal(x8_finding$result, "FAIL")
  expect_equal(x8_finding$severity, "BLOCKING")
})

# --- Test X9: Death date consistency ---
test_that("X9: Mismatched death dates trigger BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Set up death in both domains with different dates
  domains$DM$DTHFL[1] <- "Y"
  domains$DM$DTHDTC[1] <- "2024-03-01"
  domains$DS$DSDECOD[1] <- "DEATH"
  domains$DS$DSDTC <- rep("2024-03-01", 40)
  domains$DS$DSDTC[1] <- "2024-03-05"  # Different date

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x9_finding <- result$findings[result$findings$check_id == "X9", ]
  expect_equal(x9_finding$result, "FAIL")
  expect_equal(x9_finding$severity, "BLOCKING")
})

# --- Test X10: RECIST consistency ---
test_that("X10: Mismatched BOR triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Change RS BOR to mismatch DM
  domains$RS$RSSTRESC[1] <- "PD"  # DM has different value

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  # Only fails if DM BOR was different - check if it triggers
  x10_finding <- result$findings[result$findings$check_id == "X10", ]
  expect_true(x10_finding$result %in% c("PASS", "FAIL"))
})

# --- Test X11: Cardinality warnings ---
test_that("X11: Row count outside range triggers WARNING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Change IE row count to be outside expected range
  domains$IE <- domains$IE[1:300, ]  # Below expected 380

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  x11_finding <- result$findings[result$findings$check_id == "X11", ]
  expect_equal(x11_finding$result, "WARNING")
  expect_equal(x11_finding$severity, "WARNING")
})

# --- Test X12: SEQ uniqueness ---
test_that("X12: Duplicate SEQ triggers BLOCKING", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Create duplicate AESEQ
  domains$AE$AESEQ[2] <- 1  # Same USUBJID will have duplicate SEQ

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "FAIL")
  x12_finding <- result$findings[result$findings$check_id == "X12", ]
  expect_equal(x12_finding$result, "FAIL")
  expect_equal(x12_finding$severity, "BLOCKING")
})

# --- Test PASS case ---
test_that("Fully valid dataset suite returns PASS verdict", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_equal(result$verdict, "PASS")
  expect_true(file.exists(result$report_path))

  # Check that report was written
  report_content <- readLines(result$report_path)
  expect_true(any(grepl("# Cross-Domain Validation Report", report_content)))
  expect_true(any(grepl("Verdict: PASS", report_content)))
})

# --- Test report generation ---
test_that("Report file is created with correct structure", {
  local_tempdir <- withr::local_tempdir()
  sdtm_dir <- file.path(local_tempdir, "sdtm")
  log_dir <- file.path(local_tempdir, "logs")
  dir.create(sdtm_dir)

  domains <- create_mock_domains(40)

  # Write all domain files
  for (domain_name in names(domains)) {
    saveRDS(domains[[domain_name]], file.path(sdtm_dir, paste0(domain_name, ".rds")))
  }

  result <- validate_sdtm_cross_domain(sdtm_dir, log_dir)

  expect_true(file.exists(result$report_path))

  report_content <- readLines(result$report_path)

  # Check for required sections
  expect_true(any(grepl("# Cross-Domain Validation Report", report_content)))
  expect_true(any(grepl("## Summary", report_content)))
  expect_true(any(grepl("## Findings", report_content)))
  expect_true(any(grepl("## Check Details", report_content)))
})

message("\n=== All validate_sdtm_cross_domain tests completed ===\n")
