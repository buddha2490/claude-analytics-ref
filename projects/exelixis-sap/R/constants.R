# Validation Verdict Constants

#' Validation Verdict Values
#'
#' Standard verdict values used across validation functions
#' @keywords internal
VERDICT_PASS <- "PASS"
VERDICT_FAIL <- "FAIL"
VERDICT_WARNING <- "WARNING"
VERDICT_BLOCKING <- "BLOCKING"

#' Validation Severity Levels
#'
#' Standard severity levels used across validation functions
#' @keywords internal
SEVERITY_INFO <- "INFO"
SEVERITY_WARNING <- "WARNING"
SEVERITY_CRITICAL <- "CRITICAL"

# CDISC Domain Constants

#' Common SDTM Domains
#'
#' Standard SDTM domain codes per CDISC SDTM-IG
#' @keywords internal
SDTM_DOMAINS <- c(
  "DM", "AE", "CM", "EX", "LB", "VS", "EG", "MH", "DS", "SV",
  "QS", "EC", "EH", "FA", "IE", "IS", "PE", "PR", "SC", "SE",
  "SU", "TA", "TD", "TE", "TI", "TS", "TV"
)

# Unresolved Indicator Keywords

#' Keywords Indicating Unresolved Items
#'
#' Common keywords used to mark incomplete or pending work
#' @keywords internal
UNRESOLVED_KEYWORDS <- c("TODO", "TBD", "PENDING", "UNRESOLVED")

#' Regex Pattern for Unresolved Items
#'
#' Combined pattern to detect unresolved items in plan documents
#' @keywords internal
UNRESOLVED_PATTERN <- sprintf(
  "\\[\\s*\\]|\\b(%s)\\b|Status.*Open",
  paste(UNRESOLVED_KEYWORDS, collapse = "|")
)
