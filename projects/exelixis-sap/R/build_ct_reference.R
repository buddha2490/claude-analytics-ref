# =============================================================================
# Script:    build_ct_reference.R
# Purpose:   Build CDISC controlled terminology reference from RAG queries
#            and CDISC training knowledge
# Date:      2026-03-28
# =============================================================================

# CT reference list
ct_reference <- list(

  # Demographics
  SEX = c("M", "F", "U", "UNDIFFERENTIATED"),

  RACE = c(
    "AMERICAN INDIAN OR ALASKA NATIVE",
    "ASIAN",
    "BLACK OR AFRICAN AMERICAN",
    "NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER",
    "WHITE",
    "OTHER",
    "NOT REPORTED",
    "UNKNOWN"
  ),

  ETHNIC = c(
    "HISPANIC OR LATINO",
    "NOT HISPANIC OR LATINO",
    "NOT REPORTED",
    "UNKNOWN"
  ),

  # Adverse Events (from RAG C66768, C66769)
  AEOUT = c(
    "FATAL",
    "NOT RECOVERED/NOT RESOLVED",
    "RECOVERED/RESOLVED",
    "RECOVERED/RESOLVED WITH SEQUELAE",
    "RECOVERING/RESOLVING",
    "UNKNOWN"
  ),

  AESEV = c("MILD", "MODERATE", "SEVERE"),

  # NOTE: AEREL not found in RAG - using standard CDISC values
  AEREL = c(
    "NOT RELATED",
    "UNLIKELY RELATED",
    "POSSIBLY RELATED",
    "PROBABLY RELATED",
    "DEFINITELY RELATED"
  ),

  # NOTE: AEACN not found in RAG - using standard CDISC values
  AEACN = c(
    "DOSE NOT CHANGED",
    "DOSE INCREASED",
    "DOSE REDUCED",
    "DRUG INTERRUPTED",
    "DRUG WITHDRAWN",
    "NOT APPLICABLE",
    "UNKNOWN"
  ),

  # Disposition (standard values)
  DSDECOD = c(
    "COMPLETED",
    "DEATH",
    "LACK OF EFFICACY",
    "LOST TO FOLLOW-UP",
    "PHYSICIAN DECISION",
    "PROGRESSIVE DISEASE",
    "PROTOCOL DEVIATION",
    "SCREEN FAILURE",
    "STUDY TERMINATED BY SPONSOR",
    "WITHDRAWAL BY SUBJECT",
    "ADVERSE EVENT"
  ),

  # Exposure - Route from RAG (C66729)
  EXROUTE = c(
    "INTRAVENOUS",
    "INTRAVENOUS BOLUS",
    "INTRAVENOUS DRIP",
    "ORAL",
    "SUBCUTANEOUS",
    "INTRAMUSCULAR",
    "TOPICAL",
    "TRANSDERMAL",
    "INHALATION",
    "NASAL",
    "OPHTHALMIC",
    "RECTAL",
    "SUBLINGUAL",
    "BUCCAL",
    "PARENTERAL",
    "NOT APPLICABLE",
    "UNKNOWN"
  ),

  # NOTE: EXDOSFRM not found in RAG - using standard values
  EXDOSFRM = c(
    "CAPSULE",
    "CREAM",
    "GEL",
    "INJECTION",
    "PATCH",
    "POWDER",
    "SOLUTION",
    "SUSPENSION",
    "SYRUP",
    "TABLET"
  ),

  # NOTE: VSTESTCD not found in RAG - using common vital signs
  VSTESTCD = c(
    "SYSBP",   # Systolic Blood Pressure
    "DIABP",   # Diastolic Blood Pressure
    "PULSE",   # Pulse Rate
    "RESP",    # Respiratory Rate
    "TEMP",    # Temperature
    "HEIGHT",  # Height
    "WEIGHT",  # Weight
    "BMI",     # Body Mass Index
    "HR"       # Heart Rate
  ),

  # NOTE: LBTESTCD not found in RAG - using common lab tests + genomics
  LBTESTCD = c(
    # Hematology
    "HGB", "HCT", "WBC", "PLAT", "NEUT", "LYMPH", "EOS", "BASO", "MONO",
    # Chemistry
    "ALB", "ALP", "ALT", "AST", "BILI", "BUN", "CA", "CREAT", "GLUC", "K", "NA", "CL",
    # Genomics
    "PDL1", "EGFR", "ALK", "KRAS", "TP53", "ROS1", "BRAF", "MET"
  ),

  # Inclusion/Exclusion
  IECAT = c("INCLUSION", "EXCLUSION")
)

# Save to RDS
saveRDS(ct_reference, "output-data/sdtm/ct_reference.rds")

message("CT reference saved to: output-data/sdtm/ct_reference.rds")
message("Sources:")
message("  - RAG queries: RACE, ETHNIC, AEOUT, AESEV, EXROUTE")
message("  - Training knowledge: SEX, AEREL, AEACN, DSDECOD, EXDOSFRM, VSTESTCD, LBTESTCD, IECAT")
message("  - NOTE: AEREL, AEACN, EXDOSFRM, VSTESTCD, LBTESTCD not found in RAG index")
