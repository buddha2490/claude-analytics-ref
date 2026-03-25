---
description: Scaffold a new R project with renv, .Rprofile, and main.R
---

# R Project Scaffolding

When the user invokes this skill, scaffold a complete R project in the current working directory. Follow every step below exactly.

## 1. Create Directory Structure

Create the following directories with `.gitkeep` placeholder files so they are tracked by git even when empty:

```
R/
data/
tests/
```

Place an empty `.gitkeep` file in each directory.

## 2. Initialize renv

**Important:** Initialize renv and install packages *before* creating `.Rprofile`. The `.Rprofile` tries to load packages on startup, so if it exists before the packages are installed, `renv::init()` will fail.

Run the following shell commands to initialize `renv` and add the required packages:

```bash
Rscript -e '
  renv::init(bare = TRUE)
  packages <- c(
    "conflicted",
    "pysparklyr",
    "sparklyr",
    "tidyverse",
    "ggplot2",
    "plotly",
    "DBI",
    "odbc",
    "dbplyr",
    "haven",
    "httr2",
    "testthat",
    "admiral",
    "xportr",
    "metacore",
    "metatools",
    "gt",
    "pharmaRTF",
    "huxtable"
  )
  renv::install(packages)
  renv::snapshot()
'
```

After running, confirm that `renv.lock` was created. If `renv` is not installed, install it first with `Rscript -e 'install.packages("renv")'`.

**Note:** `renv::init()` will create its own `.Rprofile` containing `source("renv/activate.R")`. This will be overwritten in the next step — that is expected.

## 3. Create .Rprofile

Create `.Rprofile` in the project root with the following content. This file auto-loads core packages when R starts. Write this file *after* renv init completes so that packages are available to load:

```r
# .Rprofile - Auto-load project packages on R startup

library(conflicted)
library(pysparklyr)
library(sparklyr)
library(tidyverse)
library(DBI)
library(odbc)
library(dbplyr)

options(renv.config.ppm.enabled = FALSE)

# Set repos FIRST so renv bootstrap can reach CRAN
local({
  options(
    repos = c(
      CRAN   = "https://packagemanager.posit.co/cran/latest",
      syapse = "https://packagemanager.posit.npowermedicine.com/internal/latest"
    ),
    pkgType = "binary"
  )
})

Sys.setenv(RENV_DOWNLOAD_METHOD = "curl")

options(download.file.method = "curl")

options(download.file.extra = paste(
  "--netrc",
  '-fsSL -w "%{stderr}curl: HTTP %{http_code} %{url_effective}\n"'
))

# Activate renv ONCE, after repos are configured
source("renv/activate.R")

options(saveworkspace = "no")

conflict_prefer("filter", "dplyr", quiet = TRUE)

.get_cluster_id <- function(cluster_name) {
  response <- httr2::request(
    paste0("https://", Sys.getenv("DATABRICKS_HOST"), "/api/2.0/clusters/list")
  ) |>
    httr2::req_auth_bearer_token(Sys.getenv("DATABRICKS_TOKEN")) |>
    httr2::req_perform()

  clusters <- httr2::resp_body_json(response)$clusters
  match    <- Filter(function(c) c$cluster_name == cluster_name, clusters)

  if (length(match) == 0) stop("Cluster not found: ", cluster_name)
  match[[1]]$cluster_id
}

sc <- connect_databricks()

options(odbc.no_config_override = TRUE)
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP")
)
```

## 4. Create main.R

Create `main.R` in the project root with the following content:

```r
# =============================================================================
# Project: [Project Name]
# Author:  [Author]
# Date:    [Date]
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Description
# -----------------------------------------------------------------------------
# [Describe the purpose and goals of this project here.]
#
# Key objectives:
#   - [Objective 1]
#   - [Objective 2]
#   - [Objective 3]


# -----------------------------------------------------------------------------
# 2. renv Environment
# -----------------------------------------------------------------------------
# This project uses renv to manage package dependencies. The renv.lock file
# records the exact package versions used, ensuring reproducibility.
#
# To add a new package to the project:
#   renv::install("package_name")
#   renv::snapshot()
#
# To restore the environment on a different computer (after pulling from Git):
#   renv::restore()
#
# To check the status of your renv environment:
#   renv::status()


# -----------------------------------------------------------------------------
# 3. Functions
# -----------------------------------------------------------------------------
# Source all functions from the /R directory. Each function file should contain
# one primary function with roxygen2 documentation tags.

r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
invisible(lapply(r_files, source))


# -----------------------------------------------------------------------------
# 4. Data Loading
# -----------------------------------------------------------------------------
# This section loads any source data required for analysis. Place raw data
# files in the /data directory.

# Example:
# df <- readr::read_csv("data/source_data.csv")


# -----------------------------------------------------------------------------
# 5. Main Code
# -----------------------------------------------------------------------------
# This is the main analysis section. Write the primary analytic code here,
# calling functions sourced from the /R directory as needed.


# -----------------------------------------------------------------------------
# 6. Output
# -----------------------------------------------------------------------------
# Save any output data, tables, figures, or reports generated by the analysis.

# Example:
# readr::write_csv(results, "data/output_results.csv")
# ggsave("output/figure1.png", plot = fig1, width = 10, height = 6)
```

## 5. Create .gitignore

Create or append to `.gitignore` to handle R and renv files properly:

```
# R
.Rhistory
.Rdata
.RData
.Ruserdata

# renv
renv/library/
renv/staging/
renv/sandbox/
```

**Important:** Do NOT add `renv.lock` or `renv/activate.R` to `.gitignore` — these must be committed so collaborators can restore the environment.

## 6. Confirm Completion

After scaffolding, list the created files and directories so the user can verify the structure. Remind the user:

- Open R in the project root to auto-load packages via `.Rprofile`
- Add functions as individual `.R` files in the `/R` directory
- Add unit tests in the `/tests` directory
- Run `renv::snapshot()` after installing any new packages
