---
name: databricks
description: Auto-invoked when the user asks about connecting to Databricks, querying tables, pulling data, browsing schemas, or writing Databricks/Spark R code. Covers DBI/ODBC (con) and sparklyr (sc) patterns, navigation, schema inspection, and performance best practices.
---

# Databricks Skill

This skill governs R code that interacts with Databricks. It fires automatically
whenever the user asks about connecting, querying, browsing, or pulling data from
Databricks.

## Two Connection Objects

Every session uses two pre-established objects (created in `.Rprofile`):

| Object | Driver | Use for |
|--------|--------|---------|
| `con` | DBI / ODBC (`odbc::databricks()`) | All data retrieval: `tbl()`, `collect()`, `dbGetQuery()`, schema/catalog listing |
| `sc` | sparklyr Databricks Connect | Native Spark operations only: `sdf_nrow()`, `sdf_dim()`, `sdf_ncol()` |

**Default to `con` for all data work.** Use `sc` only when a sparklyr-specific
function (`sdf_*`) is required.

## Namespace

Databricks uses a three-part identifier: `<catalog>.<schema>.<table>`

- Default catalog: `development`
- There is **no default schema** — always specify schema explicitly
- Preferred way to reference a table in dplyr: `in_catalog("development", "ads", "table_name")`

## Connecting

### sparklyr (sc)

```r
# Helper to resolve cluster name → cluster_id via Databricks REST API
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

# Set default catalog and schema — prevents SCHEMA_NOT_FOUND errors
DBI::dbExecute(sc, "USE CATALOG development")
DBI::dbExecute(sc, "USE SCHEMA ads")
```

### DBI / ODBC (con)

```r
options(odbc.no_config_override = TRUE)  # prevents ~/.odbc.ini conflicts
con <- DBI::dbConnect(
  odbc::databricks(),
  httpPath = Sys.getenv("DATABRICKS_HTTP")
)
```

All connection credentials come from environment variables — never hardcode.

## Listing and Navigating

```r
# Tables in a schema
dbGetQuery(con, "SHOW TABLES IN development.ads")

# Full table listing with types
dbGetQuery(con, "
  SELECT table_catalog, table_schema, table_name, table_type
  FROM   development.information_schema.tables
  WHERE  table_schema = 'ads'
  ORDER  BY table_name
")

# All schemas in a catalog
dbGetQuery(con, "SHOW SCHEMAS IN development")

# All catalogs on the cluster
dbGetQuery(con, "SHOW CATALOGS")

# Current catalog and schema for this session
dbGetQuery(con, "SELECT current_catalog()")
dbGetQuery(con, "SELECT current_schema()")
```

## Connecting to Tables

### dplyr / dbplyr (lazy — preferred)

```r
# Creates a lazy remote tibble — no data pulled yet
my_tbl <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot"))

# Transformations are translated to SQL and run on Databricks
my_tbl |>
  filter(line_ongoing_flag == "Yes") |>
  select(patientid, line_name, line_regimen_class) |>
  collect()  # <-- data arrives in R here
```

### DBI raw SQL

```r
result_df <- dbGetQuery(con, "
  SELECT patientid, line_name, line_regimen_class, line_start_date
  FROM   development.ads.enriched_lung_lot
  WHERE  line_ongoing_flag = 'Yes'
  ORDER  BY patientid
")
```

## Schema / Metadata Inspection

```r
# Column names only
colnames(tbl(con, in_catalog("development", "ads", "enriched_lung_lot")))

# Column names, types, and comments
dbGetQuery(con, "DESCRIBE TABLE development.ads.enriched_lung_lot")

# Full column metadata from information_schema
dbGetQuery(con, "
  SELECT column_name, data_type, is_nullable, ordinal_position
  FROM   development.information_schema.columns
  WHERE  table_schema = 'ads'
  AND    table_name   = 'enriched_lung_lot'
  ORDER  BY ordinal_position
")

# Zero-row pull — inspect R type mapping without loading data
schema_df <- dbGetQuery(con, "SELECT * FROM development.ads.enriched_lung_lot LIMIT 0")
glimpse(schema_df)

# Table-level metadata (Delta tables)
dbGetQuery(con, "DESCRIBE DETAIL development.ads.enriched_lung_lot")
```

## Table Dimensions

```r
# Row count
tbl(con, in_catalog("development", "ads", "enriched_lung_lot")) |>
  count() |> pull(n) |> as.integer()

# Column names and count
col_names <- colnames(tbl(con, in_catalog("development", "ads", "enriched_lung_lot")))
length(col_names)

# Rows and columns together (sparklyr only)
tbl_sc <- tbl(sc, in_catalog("development", "ads", "enriched_lung_lot"))
sdf_dim(tbl_sc)  # returns c(n_rows, n_cols)
```

---

## Performance: collect(), compute(), and cache()

This is the most important section for writing fast Databricks code.

### The Core Rule

**Do work on Databricks, not in R.** Every `tbl()` is lazy — dplyr verbs are
translated to SQL and executed on the cluster. Only pull data into R when you
have finished filtering, joining, and aggregating. Pulling early means transferring
millions of rows over the wire; pulling late means transferring only the result.

### collect() — Pull once, work locally

**Use when:** You need to do local R operations (plotting, modeling, non-SQL
transformations) on the result of a Databricks query.

**Best practice: filter and aggregate first, then collect once.**

```r
# Good — minimal data crosses the wire
lung_active <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot")) |>
  filter(line_ongoing_flag == "Yes", !is.na(line_start_date)) |>
  select(patientid, line_name, line_start_date) |>
  collect()

# Now work locally — no more Databricks round-trips
lung_active |> ggplot(aes(x = line_start_date)) + geom_histogram()
```

```r
# Bad — pulls the full table, then filters in R
all_data <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot")) |>
  collect()

all_data |> filter(line_ongoing_flag == "Yes")  # too late — already in memory
```

**Never call `collect()` twice on the same pipeline.** Store the result in a
variable after the first `collect()`.

### compute() — Materialize a reused transformation

**Use when:** The same filtered or joined table is referenced more than once in
the same script, and re-running the transformation each time would be slow.

`compute()` materializes the lazy tbl as a temporary Spark table on the cluster.
Subsequent operations read from the materialized table instead of re-executing
the full transformation.

```r
# Materialize once — referenced by multiple downstream steps
lung_active <- tbl(con, in_catalog("development", "ads", "enriched_lung_lot")) |>
  filter(line_ongoing_flag == "Yes") |>
  left_join(
    tbl(con, in_catalog("development", "ads", "patients")),
    by = "patientid"
  ) |>
  compute(name = "tmp_lung_active")  # written to a temp Spark table

# Both downstream steps read from the temp table — no re-execution
summary_by_line  <- lung_active |> count(line_name) |> collect()
summary_by_site  <- lung_active |> count(site_id)   |> collect()
```

Use `compute()` **before the first downstream reference**, not at the end.

### cache() / tbl_cache() — Pin a full table in Spark memory

**Use when:** You are working interactively and will repeatedly query the same
Databricks table with different filters or aggregations during a session.

`tbl_cache()` (sparklyr) pins the table in Spark executor memory so it is read
from RAM rather than object storage on each query.

```r
# Pin the table in Spark memory for the session
tbl_sc <- tbl(sc, in_catalog("development", "ads", "enriched_lung_lot"))
tbl_cache(sc, "enriched_lung_lot")

# Subsequent queries hit memory — much faster than re-reading from Delta
tbl_sc |> filter(line_name == "1L")    |> count() |> collect()
tbl_sc |> filter(line_name == "2L+")   |> count() |> collect()
tbl_sc |> filter(line_ongoing_flag == "Yes") |> summarise(n = n()) |> collect()

# Unpersist when done to free cluster memory
tbl_uncache(sc, "enriched_lung_lot")
```

Use `tbl_cache()` for large reference tables that are queried repeatedly. For
one-off pulls, `collect()` is sufficient.

### Decision Guide

| Situation | Recommended pattern |
|-----------|---------------------|
| One-time pull for local analysis or plotting | Filter/aggregate → `collect()` |
| Same complex join or filter reused 2+ times | `compute()` into a temp table |
| Interactive session, same table with many different filters | `tbl_cache()` via sparklyr |
| Single aggregation (count, sum, mean) | Push to SQL in the `tbl()` chain, `collect()` the scalar |
| Full table needed locally (rare, small table) | `collect()` with no filter |

### Anti-patterns to avoid

```r
# Anti-pattern 1: collect() before filtering
df <- tbl(con, in_catalog("development", "ads", "big_table")) |> collect()
df |> filter(condition)  # condition should have been pushed to Databricks

# Anti-pattern 2: calling collect() in a loop
for (site in sites) {
  tbl(con, ...) |> filter(site_id == site) |> collect()  # N round-trips
}
# Better: collect all sites at once, then split in R
tbl(con, ...) |> filter(site_id %in% sites) |> collect() |> split(~site_id)

# Anti-pattern 3: compute() after all the work is done
result <- tbl(con, ...) |> filter(...) |> count() |> compute()  # pointless
collect(result)  # should have just called collect() directly
```
