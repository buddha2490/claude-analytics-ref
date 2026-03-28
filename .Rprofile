# .Rprofile - Auto-load project packages on R startup

library(conflicted)
library(pysparklyr)
library(sparklyr)
library(tidyverse)
library(DBI)
library(odbc)
library(dbplyr)

options(renv.config.ppm.enabled = FALSE)

local({
  options(
    repos = c(
      CRAN   = "https://packagemanager.posit.co/cran/latest", # changed from NPM because our repo doesn't mirror CRAN
      syapse = "https://packagemanager.posit.npowermedicine.com/internal/latest"
    ),
    pkgType = "source"
  )
})


Sys.setenv(RENV_DOWNLOAD_METHOD = "curl")

options(saveworkspace ="no")

options(download.file.method = "curl")

options(download.file.extra = paste(
  "--netrc",
  # Follow redirects, show errors, and display the HTTP status and URL
  '-fsSL -w "%{stderr}curl: HTTP %{http_code} %{url_effective}\n"'
))


conflicts_prefer(dplyr::filter, .quiet = TRUE)

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

sc <- spark_connect(
  cluster_id = .get_cluster_id("data-analytics"),
  method     = "databricks_connect"
)

options(odbc.no_config_override = TRUE)
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP")
)
