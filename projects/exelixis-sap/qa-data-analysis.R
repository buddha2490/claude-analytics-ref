# QA Data Analysis
# Purpose: Load and analyze SDTM and ADaM datasets for quality checks
# Author: Auto-generated
# Date: 2026-03-27

# --- Load packages -----------------------------------------------------------

library(tidyverse)
library(dplyr)
library(magrittr)
library(glue)

# Suppress namespace conflict messages
suppressPackageStartupMessages({
  library(pharmaRTF)
  library(huxtable)
})

# --- Load SDTM datasets ------------------------------------------------------

# Get vector of SDTM RDS files from sdtm subdirectory
sdtm_files <- list.files("projects/exelixis-sap/output-data/sdtm", pattern = ".rds", full.names = TRUE)

# Extract domain names (uppercase, without .rds extension)
sdtm_names <- basename(sdtm_files) %>%
  tools::file_path_sans_ext() %>%
  toupper()

# Load SDTM datasets into named list
sdtm <- lapply(sdtm_files, readRDS)
names(sdtm) <- sdtm_names

# --- Load ADaM datasets ------------------------------------------------------

# Get vector of ADaM RDS files from adam subdirectory
adam_files <- list.files("projects/exelixis-sap/output-data/adam", pattern = "\\.rds$", full.names = TRUE)

# Extract dataset names (uppercase, without .rds extension)
adam_names <- basename(adam_files) %>%
  tools::file_path_sans_ext() %>%
  toupper()

# Load ADaM datasets into named list
adam <- lapply(adam_files, readRDS)
names(adam) <- adam_names

# --- Summary -----------------------------------------------------------------

message("SDTM datasets loaded: ", paste(names(sdtm), collapse = ", "))
message("ADaM datasets loaded: ", paste(names(adam), collapse = ", "))


