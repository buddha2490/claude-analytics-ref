# Common Setup for SDTM Simulation Programs
#
# This file consolidates shared configuration and function loading
# used across all sim_*.R programs.

# --- Load Required Libraries ----------------------------------------------------

library(dplyr)
library(tidyr)
library(lubridate)
library(haven)


### Set relative path
if (basename(getwd()) !=  "exelixis-sap") {

  setwd("projects/exelixis-sap/")

}

# --- Load Validation Functions --------------------------------------------------

source("R/validate_sdtm_domain.R")
source("R/log_sdtm_result.R")

# --- Define Common Paths --------------------------------------------------------

DATA_DIR <- "output-data/sdtm"
LOG_DIR <- "output-data/logs"

# Ensure directories exist
if (!dir.exists(DATA_DIR)) {
  dir.create(DATA_DIR, recursive = TRUE)
}
if (!dir.exists(LOG_DIR)) {
  dir.create(LOG_DIR, recursive = TRUE)
}

# --- Load CT Reference if Available ---------------------------------------------

if (file.exists(file.path(DATA_DIR, "ct_reference.rds"))) {
  ct_reference <- readRDS(file.path(DATA_DIR, "ct_reference.rds"))
  message("Loaded CT reference: ", file.path(DATA_DIR, "ct_reference.rds"))
} else {
  ct_reference <- NULL
  message("No CT reference found. Skipping controlled terminology checks.")
}

# --- Common Configuration -------------------------------------------------------

STUDY_ID <- "NPM008"
USUBJID_PATTERN <- "^NPM008-\\d{2}-[A-Z]\\d{4}$"

message("SDTM simulation setup complete")
message("  Data directory: ", DATA_DIR)
message("  Log directory: ", LOG_DIR)
