# =============================================================================
# Databricks Connection Examples
# =============================================================================
# Purpose : Demonstrate common database interaction patterns against a
#           Databricks/Spark backend using DBI and dplyr/dbplyr.
# Assumes : `con` and `sc` are already available (created in .Rprofile).
#
# con  — ODBC connection via odbc::databricks(). Use for all data retrieval:
#         tbl(), collect(), dbGetQuery(), listing tables/schemas/catalogs.
# sc   — Spark Connect via sparklyr. Use for native Spark operations only:
#         sdf_nrow(), sdf_dim(), sdf_ncol().
#
# NOTE: Databricks uses a three-part namespace: <catalog>.<schema>.<table>
#       This connection defaults to catalog = "development".
#       There is no "default" schema in this catalog — always specify schema.
# =============================================================================

library(conflicted)
library(DBI)
library(dplyr)
library(dbplyr)
library(sparklyr)

conflict_prefer("filter", "dplyr")


# ---- 0. Connecting to databricks
# these are both odbc and sparklyr connections


# -----------------------------------------------------------------------------
# Helper: Look up a Databricks cluster ID by cluster name
# -----------------------------------------------------------------------------
# Keywords : get cluster id by name, databricks REST API, list clusters,
#            DATABRICKS_HOST, DATABRICKS_TOKEN, httr2 databricks, cluster lookup
# Purpose  : Translates a human-readable cluster name (e.g. "data-analytics")
#            into the cluster_id string required by spark_connect().
#            Uses the Databricks Clusters REST API v2.0.
# Returns  : A single character string — the cluster_id for the named cluster.
# Errors   : Stops with a descriptive message if the cluster name is not found.
# Note     : DATABRICKS_HOST should be the hostname only (no https://).
#            DATABRICKS_TOKEN is a Personal Access Token (PAT).
# -----------------------------------------------------------------------------
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


# -----------------------------------------------------------------------------
# Connection 1: sparklyr — Spark / DataFrame API via Databricks Connect
# -----------------------------------------------------------------------------
# Keywords : spark_connect databricks, sparklyr databricks_connect, sc object,
#            pysparklyr, Spark session R, databricks connect sparklyr method,
#            tbl() in_catalog(), dplyr remote table, spark dataframe R
# Purpose  : Opens a Spark session via Databricks Connect (Python-backed).
#            The resulting `sc` object is used with:
#              - tbl(sc, in_catalog("catalog", "schema", "table"))
#              - DBI::dbGetQuery(sc, "SELECT ...")
#              - DBI::dbExecute(sc, "USE CATALOG ...")
# Note     : After connecting, set the default catalog and schema with
#            USE CATALOG and USE SCHEMA to avoid SCHEMA_NOT_FOUND errors.
#            The cluster must be running before calling spark_connect().
# -----------------------------------------------------------------------------
sc <- spark_connect(
  cluster_id = .get_cluster_id("data-analytics"),
  method     = "databricks_connect"
)

# Set default Unity Catalog namespace for this session.
# Required when the cluster's default schema does not exist; prevents
# "SCHEMA_NOT_FOUND: development.default cannot be found" errors.
DBI::dbExecute(sc, "USE CATALOG development")
DBI::dbExecute(sc, "USE SCHEMA ads")


# -----------------------------------------------------------------------------
# Connection 2: DBI/ODBC — SQL API via Databricks ODBC driver
# -----------------------------------------------------------------------------
# Keywords : DBI dbConnect databricks, odbc databricks() driver, ODBC connection,
#            DATABRICKS_HTTP, httpPath, SQL connection R databricks, con object,
#            odbc.no_config_override, DBI SQL databricks
# Purpose  : Opens a pure SQL connection using the Databricks ODBC driver.
#            The resulting `con` object is used with:
#              - DBI::dbGetQuery(con, "SELECT ...")
#              - DBI::dbReadTable(con, "table_name")
#            This is an alternative to `sc` when you want standard SQL without
#            the Spark/DataFrame layer. Uses httpPath (warehouse or cluster
#            HTTP path) from the DATABRICKS_HTTP environment variable.
# Note     : odbc.no_config_override = TRUE prevents the ODBC driver from
#            reading ~/.odbc.ini, which can cause conflicts on shared machines.
# -----------------------------------------------------------------------------
options(odbc.no_config_override = TRUE)
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP")
)



# ---- 1. Listing Database Objects --------------------------------------------

# List tables in a specific catalog and schema:
dbGetQuery(con, "SHOW TABLES IN development.ads")

# Query information_schema for full control over table listing:
dbGetQuery(con, "
  SELECT table_catalog,
         table_schema,
         table_name,
         table_type
  FROM   development.information_schema.tables
  WHERE  table_schema = 'ads'
  ORDER  BY table_name
")

# List all schemas (databases) within a catalog:
dbGetQuery(con, "SHOW SCHEMAS IN development")

# List all catalogs available on the cluster:
dbGetQuery(con, "SHOW CATALOGS")

# Find current catalog and schema for this connection:
dbGetQuery(con, "SELECT current_catalog()")
dbGetQuery(con, "SELECT current_schema()")


# ---- 2. Connecting to Tables ------------------------------------------------

# --- 2a. dplyr/dbplyr — tbl() ------------------------------------------------

# Three-part identifier using in_catalog() — preferred on Databricks.
# No data is pulled; this creates a lazy remote tibble.
my_tbl <- tbl(
  con,
  in_catalog("development", "ads", "enriched_lung_lot")
)

# Use dplyr verbs on the remote table — translated to SQL and run on
# Databricks; no data is collected until collect() is called.
my_tbl |>
  filter(line_ongoing_flag == "Yes") |>
  select(patientid, line_name, line_regimen_class) |>
  collect()

# --- 2b. DBI — raw SQL -------------------------------------------------------

# Run an arbitrary SQL query and return results as a local data frame.
result_df <- dbGetQuery(con, "
  SELECT patientid,
         line_name,
         line_regimen_class,
         line_start_date
  FROM   development.ads.enriched_lung_lot
  WHERE  line_ongoing_flag = 'Yes'
  ORDER  BY patientid
")


# ---- 3. Getting Table Dimensions (Rows and Columns) -------------------------

# --- 3a. Row count -----------------------------------------------------------

tbl_ref   <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot"))
row_count <- tbl_ref |> count() |> pull(n) |> as.integer()

# --- 3b. Column count --------------------------------------------------------

tbl_ref   <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot"))
col_names <- colnames(tbl_ref)
n_cols    <- length(col_names)

# --- 3c. Rows and columns together via sparklyr ------------------------------

# sdf_dim() requires sc (Spark Connect) — not available on con.
tbl_sc <- tbl(sc, in_catalog("development", "ads", "enriched_lung_lot"))
sdf_dim(tbl_sc)   # returns c(n_rows, n_cols)


# ---- 4. Pulling Schema / Metadata Information --------------------------------

# --- 4a. Column names ---------------------------------------------------------

tbl_ref <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot"))
colnames(tbl_ref)

# --- 4b. DESCRIBE TABLE — column names, types, and comments ------------------

dbGetQuery(con, "DESCRIBE TABLE development.ads.enriched_lung_lot")

# --- 4c. information_schema — full column metadata ----------------------------

dbGetQuery(con, "
  SELECT column_name,
         data_type,
         is_nullable,
         ordinal_position
  FROM   development.information_schema.columns
  WHERE  table_schema = 'ads'
  AND    table_name   = 'enriched_lung_lot'
  ORDER  BY ordinal_position
")

# --- 4d. Zero-row query — inspect R type mapping -----------------------------

schema_df <- dbGetQuery(
  con,
  "SELECT * FROM development.ads.enriched_lung_lot LIMIT 0"
)

glimpse(schema_df)
str(schema_df)

# --- 4e. Table-level metadata (Delta tables) ----------------------------------

dbGetQuery(con, "DESCRIBE DETAIL development.ads.enriched_lung_lot")
