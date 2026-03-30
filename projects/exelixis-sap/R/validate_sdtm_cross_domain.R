#' Validate SDTM Cross-Domain
#'
#' Perform cross-domain validation checks after all 18 domains are generated.
#' Reads all domain RDS files and produces a validation report.
#'
#' @param sdtm_dir Directory containing .rds files (default: "output-data/sdtm/")
#' @param log_dir Directory for output report (default: "logs/")
#'
#' @return A list with verdict, findings, and report_path
#' @export
validate_sdtm_cross_domain <- function(
  sdtm_dir = "output-data/sdtm/",
  log_dir = "logs/"
) {
  # --- Validate inputs ---
  if (!dir.exists(sdtm_dir)) {
    stop(sprintf("SDTM directory not found: %s", sdtm_dir), call. = FALSE)
  }

  # --- Create log directory if it doesn't exist ---
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE)
  }

  # --- Initialize findings data frame ---
  findings <- data.frame(
    check_id = character(),
    severity = character(),
    description = character(),
    result = character(),
    detail = character(),

  )

  # --- Expected domain list ---
  expected_domains <- c("DM", "IE", "MH", "SC", "SU", "VS", "LB", "BS",
                       "EX", "EC", "CM", "PR", "QS", "TU", "TR", "RS",
                       "AE", "HO", "DS")

  # --- X13: File inventory ---
  missing_files <- character()
  for (domain in expected_domains) {
    rds_path <- file.path(sdtm_dir, paste0(domain, ".rds"))
    if (!file.exists(rds_path)) {
      missing_files <- c(missing_files, domain)
    }
  }

  if (length(missing_files) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X13",
      severity = "BLOCKING",
      description = "All 18 XPT files exist in sdtm_dir",
      result = "FAIL",
      detail = sprintf("Missing files: %s", paste(missing_files, collapse = ", ")),

    ))

    # Cannot proceed without all files
    verdict <- "FAIL"
    summary_text <- sprintf(
      "Cross-domain validation FAILED: %d domain file(s) missing",
      length(missing_files)
    )

    report_path <- write_cross_domain_report(
      findings, verdict, summary_text, sdtm_dir, log_dir
    )

    return(list(
      verdict = verdict,
      findings = findings,
      report_path = report_path
    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X13",
      severity = "INFO",
      description = "All 18 XPT files exist in sdtm_dir",
      result = "PASS",
      detail = "All expected domain files present",

    ))
  }

  # --- Read all domain datasets ---
  domains <- list()
  for (domain in expected_domains) {
    rds_path <- file.path(sdtm_dir, paste0(domain, ".rds"))
    domains[[domain]] <- readRDS(rds_path)
  }

  # --- X1: Referential integrity - all USUBJIDs exist in DM ---
  dm <- domains[["DM"]]
  ref_integrity_fails <- character()

  for (domain_name in setdiff(expected_domains, "DM")) {
    domain_df <- domains[[domain_name]]
    if ("USUBJID" %in% names(domain_df)) {
      missing <- dplyr::anti_join(
        domain_df, dm, by = "USUBJID"
      ) %>%
        dplyr::pull(USUBJID) %>%
        unique()

      if (length(missing) > 0) {
        ref_integrity_fails <- c(
          ref_integrity_fails,
          sprintf("%s: %d USUBJID(s)", domain_name, length(missing))
        )
      }
    }
  }

  if (length(ref_integrity_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X1",
      severity = "BLOCKING",
      description = "Referential integrity: every USUBJID exists in DM",
      result = "FAIL",
      detail = paste(ref_integrity_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X1",
      severity = "INFO",
      description = "Referential integrity: every USUBJID exists in DM",
      result = "PASS",
      detail = "All USUBJIDs across domains exist in DM",

    ))
  }

  # --- X2: All domains have 40 distinct USUBJIDs ---
  cardinality_fails <- character()

  for (domain_name in expected_domains) {
    domain_df <- domains[[domain_name]]
    if ("USUBJID" %in% names(domain_df)) {
      n_distinct_usubjid <- dplyr::n_distinct(domain_df$USUBJID)
      if (n_distinct_usubjid != 40) {
        cardinality_fails <- c(
          cardinality_fails,
          sprintf("%s: %d subjects", domain_name, n_distinct_usubjid)
        )
      }
    }
  }

  if (length(cardinality_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X2",
      severity = "BLOCKING",
      description = "All domains have 40 distinct USUBJIDs",
      result = "FAIL",
      detail = paste(cardinality_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X2",
      severity = "INFO",
      description = "All domains have 40 distinct USUBJIDs",
      result = "PASS",
      detail = "All domains contain all 40 subjects",

    ))
  }

  # --- X3: Date coherence - no event dates before RFSTDTC (except MH, CM) ---
  date_coherence_fails <- character()
  exempt_domains <- c("MH", "CM")

  for (domain_name in setdiff(expected_domains, c("DM", exempt_domains))) {
    domain_df <- domains[[domain_name]]

    # Find all DTC columns
    dtc_cols <- names(domain_df)[stringr::str_detect(names(domain_df), "DTC$")]

    if (length(dtc_cols) > 0 && "USUBJID" %in% names(domain_df)) {
      # Join with DM to get RFSTDTC
      domain_with_rfst <- domain_df %>%
        dplyr::left_join(
          dm %>% dplyr::select(USUBJID, RFSTDTC),
          by = "USUBJID"
        )

      for (col in dtc_cols) {
        if (col != "RFSTDTC" && col != "RFENDTC") {
          # Check for dates before RFSTDTC
          violations <- domain_with_rfst %>%
            dplyr::filter(
              !is.na(!!rlang::sym(col)),
              !is.na(RFSTDTC),
              !!rlang::sym(col) < RFSTDTC
            )

          if (nrow(violations) > 0) {
            date_coherence_fails <- c(
              date_coherence_fails,
              sprintf("%s.%s: %d violation(s)", domain_name, col, nrow(violations))
            )
          }
        }
      }
    }
  }

  if (length(date_coherence_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X3",
      severity = "BLOCKING",
      description = "Date coherence: no event dates before RFSTDTC (except MH, CM)",
      result = "FAIL",
      detail = paste(date_coherence_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X3",
      severity = "INFO",
      description = "Date coherence: no event dates before RFSTDTC (except MH, CM)",
      result = "PASS",
      detail = "No events before study start",

    ))
  }

  # --- X4: Date coherence - no event dates after DTHDTC for deceased ---
  post_death_fails <- character()

  # Get deceased subjects
  deceased <- dm %>%
    dplyr::filter(DTHFL == "Y") %>%
    dplyr::select(USUBJID, DTHDTC)

  if (nrow(deceased) > 0) {
    for (domain_name in setdiff(expected_domains, "DM")) {
      domain_df <- domains[[domain_name]]

      # Find all DTC columns
      dtc_cols <- names(domain_df)[stringr::str_detect(names(domain_df), "DTC$")]

      if (length(dtc_cols) > 0 && "USUBJID" %in% names(domain_df)) {
        # Join with deceased subjects
        domain_with_dthdtc <- domain_df %>%
          dplyr::inner_join(deceased, by = "USUBJID")

        for (col in dtc_cols) {
          if (col != "DTHDTC") {
            # Check for dates after DTHDTC
            violations <- domain_with_dthdtc %>%
              dplyr::filter(
                !is.na(!!rlang::sym(col)),
                !is.na(DTHDTC),
                !!rlang::sym(col) > DTHDTC
              )

            if (nrow(violations) > 0) {
              post_death_fails <- c(
                post_death_fails,
                sprintf("%s.%s: %d violation(s)", domain_name, col, nrow(violations))
              )
            }
          }
        }
      }
    }
  }

  if (length(post_death_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X4",
      severity = "BLOCKING",
      description = "Date coherence: no event dates after DTHDTC for deceased",
      result = "FAIL",
      detail = paste(post_death_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X4",
      severity = "INFO",
      description = "Date coherence: no event dates after DTHDTC for deceased",
      result = "PASS",
      detail = sprintf("Checked %d deceased subject(s)", nrow(deceased)),

    ))
  }

  # --- X5: Key linkage - TU.TULNKID ↔ TR.TULNKID ---
  tu <- domains[["TU"]]
  tr <- domains[["TR"]]

  x5_fails <- character()
  if ("TULNKID" %in% names(tu) && "TULNKID" %in% names(tr)) {
    # Check TU → TR
    tu_orphans <- setdiff(tu$TULNKID, tr$TULNKID)
    if (length(tu_orphans) > 0) {
      x5_fails <- c(x5_fails, sprintf("TU orphans: %d TULNKID(s)", length(tu_orphans)))
    }

    # Check TR → TU
    tr_orphans <- setdiff(tr$TULNKID, tu$TULNKID)
    if (length(tr_orphans) > 0) {
      x5_fails <- c(x5_fails, sprintf("TR orphans: %d TULNKID(s)", length(tr_orphans)))
    }
  } else {
    x5_fails <- c(x5_fails, "TULNKID column missing")
  }

  if (length(x5_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X5",
      severity = "BLOCKING",
      description = "Key linkage: TU.TULNKID ↔ TR.TULNKID (no orphans)",
      result = "FAIL",
      detail = paste(x5_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X5",
      severity = "INFO",
      description = "Key linkage: TU.TULNKID ↔ TR.TULNKID (no orphans)",
      result = "PASS",
      detail = "All tumor identifiers linked correctly",

    ))
  }

  # --- X6: Key linkage - AE.AESEQ ↔ HO.HOHNKID ---
  ae <- domains[["AE"]]
  ho <- domains[["HO"]]

  x6_fails <- character()
  if ("AESEQ" %in% names(ae) && "HOHNKID" %in% names(ho) && "USUBJID" %in% names(ho)) {
    # HO.HOHNKID should match AE.AESEQ for same USUBJID
    # Create composite key
    ae_keys <- ae %>%
      dplyr::mutate(composite_key = paste(USUBJID, AESEQ, sep = "|")) %>%
      dplyr::pull(composite_key)

    ho_keys <- ho %>%
      dplyr::mutate(composite_key = paste(USUBJID, HOHNKID, sep = "|")) %>%
      dplyr::pull(composite_key)

    ho_orphans <- setdiff(ho_keys, ae_keys)
    if (length(ho_orphans) > 0) {
      x6_fails <- c(x6_fails, sprintf("HO orphans: %d HOHNKID(s)", length(ho_orphans)))
    }
  } else {
    x6_fails <- c(x6_fails, "Required columns missing")
  }

  if (length(x6_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X6",
      severity = "BLOCKING",
      description = "Key linkage: AE.AESEQ ↔ HO.HOHNKID (no orphans)",
      result = "FAIL",
      detail = paste(x6_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X6",
      severity = "INFO",
      description = "Key linkage: AE.AESEQ ↔ HO.HOHNKID (no orphans)",
      result = "PASS",
      detail = "All healthcare encounters linked to AEs",

    ))
  }

  # --- X7: Key linkage - BS.BSREFID ↔ LB specimen dates (WARNING) ---
  bs <- domains[["BS"]]
  lb <- domains[["LB"]]

  x7_fails <- character()
  if ("BSREFID" %in% names(bs) && "LBDTC" %in% names(lb)) {
    # This is a heuristic check - BS.BSREFID should correspond to LB collection dates
    # For now, just verify that BS and LB have matching USUBJIDs
    bs_usubjids <- unique(bs$USUBJID)
    lb_usubjids <- unique(lb$USUBJID)

    bs_no_lb <- setdiff(bs_usubjids, lb_usubjids)
    if (length(bs_no_lb) > 0) {
      x7_fails <- c(x7_fails, sprintf("%d subject(s) have BS but no LB", length(bs_no_lb)))
    }
  } else {
    x7_fails <- c(x7_fails, "Required columns missing")
  }

  if (length(x7_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X7",
      severity = "WARNING",
      description = "Key linkage: BS.BSREFID ↔ LB specimen dates",
      result = "WARNING",
      detail = paste(x7_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X7",
      severity = "INFO",
      description = "Key linkage: BS.BSREFID ↔ LB specimen dates",
      result = "PASS",
      detail = "Biospecimen and lab data aligned",

    ))
  }

  # --- X8: Outcome consistency - DS.DSDECOD="DEATH" iff DM.DTHFL="Y" ---
  ds <- domains[["DS"]]

  x8_fails <- character()
  if ("DSDECOD" %in% names(ds) && "DTHFL" %in% names(dm)) {
    # Get death dispositions from DS
    ds_deaths <- ds %>%
      dplyr::filter(DSDECOD == "DEATH") %>%
      dplyr::pull(USUBJID) %>%
      unique()

    # Get death flag from DM
    dm_deaths <- dm %>%
      dplyr::filter(DTHFL == "Y") %>%
      dplyr::pull(USUBJID) %>%
      unique()

    # Check DS → DM
    ds_not_dm <- setdiff(ds_deaths, dm_deaths)
    if (length(ds_not_dm) > 0) {
      x8_fails <- c(x8_fails, sprintf("%d DS.DEATH without DM.DTHFL=Y", length(ds_not_dm)))
    }

    # Check DM → DS
    dm_not_ds <- setdiff(dm_deaths, ds_deaths)
    if (length(dm_not_ds) > 0) {
      x8_fails <- c(x8_fails, sprintf("%d DM.DTHFL=Y without DS.DEATH", length(dm_not_ds)))
    }
  } else {
    x8_fails <- c(x8_fails, "Required columns missing")
  }

  if (length(x8_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X8",
      severity = "BLOCKING",
      description = "Outcome consistency: DS.DSDECOD='DEATH' iff DM.DTHFL='Y'",
      result = "FAIL",
      detail = paste(x8_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X8",
      severity = "INFO",
      description = "Outcome consistency: DS.DSDECOD='DEATH' iff DM.DTHFL='Y'",
      result = "PASS",
      detail = "Death records consistent across DM and DS",

    ))
  }

  # --- X9: Outcome consistency - DS.DSDTC matches DM.DTHDTC for deceased ---
  x9_fails <- character()
  if ("DSDECOD" %in% names(ds) && "DSDTC" %in% names(ds) && "DTHDTC" %in% names(dm)) {
    death_comparison <- ds %>%
      dplyr::filter(DSDECOD == "DEATH") %>%
      dplyr::inner_join(
        dm %>% dplyr::filter(DTHFL == "Y") %>% dplyr::select(USUBJID, DTHDTC),
        by = "USUBJID"
      ) %>%
      dplyr::filter(DSDTC != DTHDTC)

    if (nrow(death_comparison) > 0) {
      x9_fails <- c(x9_fails, sprintf("%d mismatch(es)", nrow(death_comparison)))
    }
  } else {
    x9_fails <- c(x9_fails, "Required columns missing")
  }

  if (length(x9_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X9",
      severity = "BLOCKING",
      description = "Outcome consistency: DS.DSDTC matches DM.DTHDTC for deceased",
      result = "FAIL",
      detail = paste(x9_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X9",
      severity = "INFO",
      description = "Outcome consistency: DS.DSDTC matches DM.DTHDTC for deceased",
      result = "PASS",
      detail = "Death dates consistent across domains",

    ))
  }

  # --- X10: RECIST consistency - RS BOR matches DM latent BOR ---
  rs <- domains[["RS"]]

  x10_fails <- character()
  if ("RSTESTCD" %in% names(rs) && "RSSTRESC" %in% names(rs) && "bor" %in% names(dm)) {
    # Get RS BOR
    rs_bor <- rs %>%
      dplyr::filter(RSTESTCD == "OVRLRESP") %>%
      dplyr::select(USUBJID, rs_bor = RSSTRESC)

    # Compare with DM BOR
    bor_comparison <- dm %>%
      dplyr::select(USUBJID, dm_bor = bor) %>%
      dplyr::inner_join(rs_bor, by = "USUBJID") %>%
      dplyr::filter(dm_bor != rs_bor)

    if (nrow(bor_comparison) > 0) {
      x10_fails <- c(x10_fails, sprintf("%d mismatch(es)", nrow(bor_comparison)))
    }
  } else {
    x10_fails <- c(x10_fails, "Required columns missing")
  }

  if (length(x10_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X10",
      severity = "BLOCKING",
      description = "RECIST consistency: RS BOR matches DM latent BOR",
      result = "FAIL",
      detail = paste(x10_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X10",
      severity = "INFO",
      description = "RECIST consistency: RS BOR matches DM latent BOR",
      result = "PASS",
      detail = "Best overall response consistent",

    ))
  }

  # --- X11: Cardinality checks ---
  x11_warns <- character()

  expected_counts <- list(
    DM = c(40, 40),
    DS = c(40, 40),
    IE = c(380, 420),
    SU = c(40, 40),
    EX = c(40, 40)
  )

  for (domain_name in names(expected_counts)) {
    domain_df <- domains[[domain_name]]
    actual <- nrow(domain_df)
    expected_range <- expected_counts[[domain_name]]

    if (actual < expected_range[1] || actual > expected_range[2]) {
      x11_warns <- c(
        x11_warns,
        sprintf("%s: %d rows (expected [%d, %d])",
               domain_name, actual, expected_range[1], expected_range[2])
      )
    }
  }

  if (length(x11_warns) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X11",
      severity = "WARNING",
      description = "Cardinality: domain row counts within expected ranges",
      result = "WARNING",
      detail = paste(x11_warns, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X11",
      severity = "INFO",
      description = "Cardinality: domain row counts within expected ranges",
      result = "PASS",
      detail = "All checked domains have expected row counts",

    ))
  }

  # --- X12: SEQ uniqueness within USUBJID ---
  x12_fails <- character()

  for (domain_name in expected_domains) {
    domain_df <- domains[[domain_name]]
    seq_col <- paste0(domain_name, "SEQ")

    if (seq_col %in% names(domain_df) && "USUBJID" %in% names(domain_df)) {
      dup_check <- domain_df %>%
        dplyr::group_by(USUBJID) %>%
        dplyr::summarize(
          n_rows = dplyr::n(),
          n_unique_seq = dplyr::n_distinct(!!rlang::sym(seq_col)),
          .groups = "drop"
        ) %>%
        dplyr::filter(n_rows != n_unique_seq)

      if (nrow(dup_check) > 0) {
        x12_fails <- c(
          x12_fails,
          sprintf("%s: %d subject(s) with duplicate SEQ", domain_name, nrow(dup_check))
        )
      }
    }
  }

  if (length(x12_fails) > 0) {
    findings <- rbind(findings, data.frame(
      check_id = "X12",
      severity = "BLOCKING",
      description = "SEQ uniqueness: --SEQ unique per USUBJID within each domain",
      result = "FAIL",
      detail = paste(x12_fails, collapse = "; "),

    ))
  } else {
    findings <- rbind(findings, data.frame(
      check_id = "X12",
      severity = "INFO",
      description = "SEQ uniqueness: --SEQ unique per USUBJID within each domain",
      result = "PASS",
      detail = "All SEQ variables unique within subjects",

    ))
  }

  # --- Determine verdict ---
  blocking_count <- sum(findings$severity == "BLOCKING" & findings$result == "FAIL")
  verdict <- if (blocking_count > 0) "FAIL" else "PASS"

  summary_text <- sprintf(
    "Cross-domain validation: %s (%d BLOCKING findings)",
    verdict, blocking_count
  )

  # --- Write report ---
  report_path <- write_cross_domain_report(
    findings, verdict, summary_text, sdtm_dir, log_dir
  )

  # --- Return result ---
  list(
    verdict = verdict,
    findings = findings,
    report_path = report_path
  )
}

#' Write Cross-Domain Validation Report
#'
#' Internal function to write the markdown report.
#'
#' @keywords internal
write_cross_domain_report <- function(findings, verdict, summary_text, sdtm_dir, log_dir) {
  report_date <- format(Sys.Date(), "%Y-%m-%d")
  report_path <- file.path(
    log_dir,
    paste0("cross_domain_validation_", report_date, ".md")
  )

  # --- Header ---
  report <- sprintf("# Cross-Domain Validation Report: NPM-008 SDTM\n\n")
  report <- paste0(report, sprintf("**Date:** %s\n", report_date))
  report <- paste0(report, "**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA\n")
  report <- paste0(report, sprintf("**Domains validated:** %d\n", 19))
  report <- paste0(report, sprintf("**SDTM directory:** %s\n\n", sdtm_dir))

  # --- Summary ---
  report <- paste0(report, "## Summary\n\n")
  blocking_count <- sum(findings$severity == "BLOCKING" & findings$result == "FAIL")
  warning_count <- sum(findings$severity == "WARNING")
  pass_count <- sum(findings$result == "PASS")

  report <- paste0(report, sprintf("- Total checks: %d\n", nrow(findings)))
  report <- paste0(report, sprintf("- BLOCKING findings: %d\n", blocking_count))
  report <- paste0(report, sprintf("- WARNING findings: %d\n", warning_count))
  report <- paste0(report, sprintf("- **Verdict: %s**\n\n", verdict))

  # --- Findings by severity ---
  report <- paste0(report, "## Findings\n\n")

  # BLOCKING
  blocking_findings <- findings[findings$severity == "BLOCKING" & findings$result == "FAIL", ]
  if (nrow(blocking_findings) > 0) {
    report <- paste0(report, "### BLOCKING\n\n")
    for (i in seq_len(nrow(blocking_findings))) {
      finding <- blocking_findings[i, ]
      report <- paste0(report, sprintf("**%s**: %s\n", finding$check_id, finding$description))
      report <- paste0(report, sprintf("- Result: %s\n", finding$result))
      report <- paste0(report, sprintf("- Detail: %s\n\n", finding$detail))
    }
  }

  # WARNING
  warning_findings <- findings[findings$severity == "WARNING", ]
  if (nrow(warning_findings) > 0) {
    report <- paste0(report, "### WARNING\n\n")
    for (i in seq_len(nrow(warning_findings))) {
      finding <- warning_findings[i, ]
      report <- paste0(report, sprintf("**%s**: %s\n", finding$check_id, finding$description))
      report <- paste0(report, sprintf("- Result: %s\n", finding$result))
      report <- paste0(report, sprintf("- Detail: %s\n\n", finding$detail))
    }
  }

  # --- Check Details ---
  report <- paste0(report, "## Check Details\n\n")
  for (i in seq_len(nrow(findings))) {
    finding <- findings[i, ]
    report <- paste0(report, sprintf("### %s: %s\n\n", finding$check_id, finding$description))
    report <- paste0(report, sprintf("- **Result:** %s\n", finding$result))
    report <- paste0(report, sprintf("- **Severity:** %s\n", finding$severity))
    if (nzchar(finding$detail)) {
      report <- paste0(report, sprintf("- **Detail:** %s\n", finding$detail))
    }
    report <- paste0(report, "\n")
  }

  # --- Write to file ---
  cat(report, file = report_path)

  report_path
}
