# Test: validate_sdtm_domain.R

library(testthat)
library(dplyr)
library(stringr)

# Source the function
source("/Users/briancarter/Rdata/claude-analytics-ref/projects/exelixis-sap/R/validate_sdtm_domain.R")

# --- Create mock DM reference dataset ---
create_mock_dm <- function() {
  data.frame(
    STUDYID = rep("NPM008", 3),
    DOMAIN = rep("DM", 3),
    USUBJID = c("NPM008-01-A0001", "NPM008-02-B0002", "NPM008-03-C0003"),
    RFSTDTC = c("2024-01-15", "2024-01-20", "2024-01-25"),
    RFENDTC = c("2024-06-15", "2024-07-20", "2024-08-25"),
    stringsAsFactors = FALSE
  )
}

# --- Create valid test domain dataset ---
create_valid_ae <- function() {
  data.frame(
    STUDYID = rep("NPM008", 6),
    DOMAIN = rep("AE", 6),
    USUBJID = rep(c("NPM008-01-A0001", "NPM008-02-B0002", "NPM008-03-C0003"), each = 2),
    AESEQ = c(1, 2, 1, 2, 1, 2),
    AESTDTC = c("2024-02-01", "2024-03-01", "2024-02-10", "2024-03-10", "2024-02-15", "2024-03-15"),
    AESEV = rep(c("MILD", "MODERATE"), 3),
    stringsAsFactors = FALSE
  )
}

# === Test U1: DOMAIN column matches domain_code ===
test_that("U1: DOMAIN column missing triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae() %>% select(-DOMAIN)

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U1: DOMAIN mismatch triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$DOMAIN[1] <- "CM"

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U1: DOMAIN match passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u1_check <- result$checks[result$checks$check_id == "U1", ]

  expect_equal(u1_check$result, "PASS")
})

# === Test U2: STUDYID is constant and equals NPM008 ===
test_that("U2: STUDYID missing triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae() %>% select(-STUDYID)

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U2: STUDYID not NPM008 triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$STUDYID <- "WRONG001"

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U2: Multiple STUDYIDs trigger FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$STUDYID[1] <- "NPM009"

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U2: STUDYID = NPM008 passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u2_check <- result$checks[result$checks$check_id == "U2", ]

  expect_equal(u2_check$result, "PASS")
})

# === Test U3: USUBJID matches regex ===
test_that("U3: Invalid USUBJID format triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$USUBJID[1] <- "INVALID-ID"

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U3: Valid USUBJID format passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u3_check <- result$checks[result$checks$check_id == "U3", ]

  expect_equal(u3_check$result, "PASS")
})

# === Test U4: All USUBJIDs exist in dm_ref ===
test_that("U4: USUBJID not in DM triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$USUBJID[1] <- "NPM008-99-Z9999"

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U4: All USUBJIDs in DM passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u4_check <- result$checks[result$checks$check_id == "U4", ]

  expect_equal(u4_check$result, "PASS")
})

# === Test U5: SEQ is unique integer within each USUBJID ===
test_that("U5: Duplicate SEQ within USUBJID triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$AESEQ[2] <- 1  # Duplicate SEQ for same USUBJID

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U5: Non-numeric SEQ triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$AESEQ <- as.character(ae_df$AESEQ)

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U5: Unique SEQ within USUBJID passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u5_check <- result$checks[result$checks$check_id == "U5", ]

  expect_equal(u5_check$result, "PASS")
})

test_that("U5: Missing SEQ column passes (acceptable)", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae() %>% select(-AESEQ)

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u5_check <- result$checks[result$checks$check_id == "U5", ]

  expect_equal(u5_check$result, "PASS")
  expect_true(str_detect(u5_check$detail, "not present"))
})

# === Test U6: No NA in required variables ===
test_that("U6: NA in USUBJID triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$USUBJID[1] <- NA

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U6: NA in STUDYID triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$STUDYID[1] <- NA

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U6: No NA in required variables passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u6_check <- result$checks[result$checks$check_id == "U6", ]

  expect_equal(u6_check$result, "PASS")
})

# === Test U7: All DTC columns match ISO 8601 format ===
test_that("U7: Invalid date format triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$AESTDTC[1] <- "01/02/2024"  # Wrong format

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U7: Valid ISO 8601 dates pass", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u7_check <- result$checks[result$checks$check_id == "U7", ]

  expect_equal(u7_check$result, "PASS")
})

test_that("U7: No DTC columns passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae() %>% select(-AESTDTC)

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u7_check <- result$checks[result$checks$check_id == "U7", ]

  expect_equal(u7_check$result, "PASS")
  expect_true(str_detect(u7_check$detail, "No DTC columns"))
})

# === Test U8: Row count within expected range ===
test_that("U8: Row count below range triggers WARNING", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  expect_warning(
    result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(10, 20)),
    "row count.*outside expected range"
  )

  u8_check <- result$checks[result$checks$check_id == "U8", ]
  expect_equal(u8_check$result, "WARNING")
})

test_that("U8: Row count above range triggers WARNING", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  expect_warning(
    result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(1, 3)),
    "row count.*outside expected range"
  )

  u8_check <- result$checks[result$checks$check_id == "U8", ]
  expect_equal(u8_check$result, "WARNING")
})

test_that("U8: Row count within range passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u8_check <- result$checks[result$checks$check_id == "U8", ]

  expect_equal(u8_check$result, "PASS")
})

# === Test U9: No fully duplicate rows ===
test_that("U9: Duplicate rows trigger FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df <- rbind(ae_df, ae_df[1, ])  # Add duplicate row

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10)),
    "validation FAILED"
  )
})

test_that("U9: No duplicate rows passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u9_check <- result$checks[result$checks$check_id == "U9", ]

  expect_equal(u9_check$result, "PASS")
})

# === Test U10: CT values validated ===
test_that("U10: Invalid CT value triggers FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()
  ae_df$AESEV[1] <- "EXTREME"  # Invalid value

  ct_ref <- list(AESEV = c("MILD", "MODERATE", "SEVERE"))

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10), ct_reference = ct_ref),
    "validation FAILED"
  )
})

test_that("U10: Valid CT values pass", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  ct_ref <- list(AESEV = c("MILD", "MODERATE", "SEVERE"))

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10), ct_reference = ct_ref)
  u10_check <- result$checks[result$checks$check_id == "U10", ]

  expect_equal(u10_check$result, "PASS")
})

test_that("U10: No CT reference provided passes", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))
  u10_check <- result$checks[result$checks$check_id == "U10", ]

  expect_equal(u10_check$result, "PASS")
  expect_true(str_detect(u10_check$detail, "No CT reference"))
})

# === Test domain-specific checks ===
test_that("Domain checks are executed and incorporated", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  domain_checks <- function(df, dm_ref) {
    list(
      list(
        check_id = "D1",
        description = "Custom check: row count is 6",
        result = if (nrow(df) == 6) "PASS" else "FAIL",
        detail = paste("Actual:", nrow(df))
      )
    )
  }

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10), domain_checks = domain_checks)

  d1_check <- result$checks[result$checks$check_id == "D1", ]
  expect_equal(nrow(d1_check), 1)
  expect_equal(d1_check$result, "PASS")
})

test_that("Domain checks can trigger FAIL", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  domain_checks <- function(df, dm_ref) {
    list(
      list(
        check_id = "D1",
        description = "Custom check: row count is 10",
        result = if (nrow(df) == 10) "PASS" else "FAIL",
        detail = paste("Expected 10, got:", nrow(df))
      )
    )
  }

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10), domain_checks = domain_checks),
    "validation FAILED"
  )
})

# === Test PASS case ===
test_that("Fully valid dataset returns PASS verdict", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  result <- validate_sdtm_domain(ae_df, "AE", dm_ref, c(5, 10))

  expect_equal(result$verdict, "PASS")
  expect_true(all(result$checks$result %in% c("PASS", "WARNING")))
  expect_true(str_detect(result$summary, "PASS"))
})

# === Test input validation ===
test_that("Non-data.frame domain_df triggers error", {
  dm_ref <- create_mock_dm()

  expect_error(
    validate_sdtm_domain(list(a = 1), "AE", dm_ref, c(5, 10)),
    "`domain_df` must be a data frame"
  )
})

test_that("Invalid domain_code triggers error", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  expect_error(
    validate_sdtm_domain(ae_df, c("AE", "CM"), dm_ref, c(5, 10)),
    "`domain_code` must be a single character string"
  )
})

test_that("Invalid expected_rows triggers error", {
  dm_ref <- create_mock_dm()
  ae_df <- create_valid_ae()

  expect_error(
    validate_sdtm_domain(ae_df, "AE", dm_ref, c(5)),
    "`expected_rows` must be a numeric vector of length 2"
  )
})

message("\n=== All validate_sdtm_domain tests completed ===\n")
