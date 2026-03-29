#!/usr/bin/env Rscript
# Build CDISC validation inventory from SDTM XPT and ADaM RDS files
# Output: inventory object saved to RDS for downstream validation

library(haven)
library(dplyr)
library(stringr)
library(here)

# --- Source helper functions ------------------------------------------------
source(here("R/summarize_numeric.R"))
source(here("R/summarize_character.R"))
source(here("R/summarize_date.R"))
source(here("R/summarize_variable.R"))
source(here("R/extract_dataset_metadata.R"))

# --- Load SDTM XPT files ----------------------------------------------------
message("Loading SDTM datasets...")
sdtm_dir <- here("projects/exelixis-sap/output-data/sdtm")
sdtm_files <- list.files(sdtm_dir, pattern = "\\.xpt$", full.names = TRUE)

sdtm_datasets <- list()
for (file in sdtm_files) {
  domain <- toupper(tools::file_path_sans_ext(basename(file)))
  message("  Loading ", domain, "...")
  sdtm_datasets[[domain]] <- read_xpt(file)
}

message("Loaded ", length(sdtm_datasets), " SDTM domains")

# --- Load ADaM RDS files ----------------------------------------------------
message("Loading ADaM datasets...")
adam_dir <- here("projects/exelixis-sap/output-data/adam")
adam_files <- list.files(adam_dir, pattern = "\\.rds$", full.names = TRUE)

adam_datasets <- list()
for (file in adam_files) {
  domain <- toupper(tools::file_path_sans_ext(basename(file)))
  message("  Loading ", domain, "...")
  adam_datasets[[domain]] <- readRDS(file)
}

message("Loaded ", length(adam_datasets), " ADaM datasets")

# --- Build inventory for each domain ----------------------------------------
build_inventory <- function(datasets, data_type) {
  message("Building ", data_type, " inventory...")

  lapply(names(datasets), function(domain) {
    message("  Processing ", domain, "...")
    ds <- datasets[[domain]]

    # Extract metadata
    metadata <- extract_dataset_metadata(ds)

    # Build summaries for each variable
    summaries <- setNames(
      lapply(names(ds), function(v) {
        summarize_variable(ds[[v]], v)
      }),
      names(ds)
    )

    list(
      domain   = domain,
      type     = data_type,
      records  = nrow(ds),
      n_vars   = ncol(ds),
      metadata = metadata,
      summaries = summaries,
      data     = ds  # Keep full dataset for cross-domain checks
    )
  }) |> setNames(names(datasets))
}

sdtm_inventory <- build_inventory(sdtm_datasets, "SDTM")
adam_inventory <- build_inventory(adam_datasets, "ADaM")

# --- Combine and save -------------------------------------------------------
inventory <- list(
  sdtm = sdtm_inventory,
  adam = adam_inventory,
  timestamp = Sys.time()
)

output_file <- here("projects/exelixis-sap/output-data/cdisc_inventory.rds")
saveRDS(inventory, output_file)
message("\nInventory saved to: ", output_file)

# --- Print summary ----------------------------------------------------------
message("\n=== Inventory Summary ===")
message("SDTM domains: ", length(sdtm_inventory))
message("ADaM datasets: ", length(adam_inventory))
message("Total domains: ", length(sdtm_inventory) + length(adam_inventory))

sdtm_records <- sum(sapply(sdtm_inventory, function(x) x$records))
adam_records <- sum(sapply(adam_inventory, function(x) x$records))
message("\nTotal SDTM records: ", format(sdtm_records, big.mark = ","))
message("Total ADaM records: ", format(adam_records, big.mark = ","))
