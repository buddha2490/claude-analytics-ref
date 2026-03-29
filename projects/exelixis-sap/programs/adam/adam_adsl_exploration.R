# =============================================================================
# Exploration script for ADSL source data
# =============================================================================

library(haven)
library(dplyr)

# Read all source SDTM domains
dm <- haven::read_xpt("output-data/sdtm/dm.xpt")
mh <- haven::read_xpt("output-data/sdtm/mh.xpt")
qs <- haven::read_xpt("output-data/sdtm/qs.xpt")
su <- haven::read_xpt("output-data/sdtm/su.xpt")
sc <- haven::read_xpt("output-data/sdtm/sc.xpt")
lb <- haven::read_xpt("output-data/sdtm/lb.xpt")
ds <- haven::read_xpt("output-data/sdtm/ds.xpt")
ex <- haven::read_xpt("output-data/sdtm/ex.xpt")
pr <- haven::read_xpt("output-data/sdtm/pr.xpt")
tu <- haven::read_xpt("output-data/sdtm/tu.xpt")
adlot <- haven::read_xpt("output-data/adam/adlot.xpt")

# List all columns in each source domain
message("DM columns: ", paste(names(dm), collapse=", "))
message("MH columns: ", paste(names(mh), collapse=", "))
message("QS columns: ", paste(names(qs), collapse=", "))
message("SU columns: ", paste(names(su), collapse=", "))
message("SC columns: ", paste(names(sc), collapse=", "))
message("LB columns: ", paste(names(lb), collapse=", "))
message("DS columns: ", paste(names(ds), collapse=", "))
message("EX columns: ", paste(names(ex), collapse=", "))
message("PR columns: ", paste(names(pr), collapse=", "))
message("TU columns: ", paste(names(tu), collapse=", "))
message("ADLOT columns: ", paste(names(adlot), collapse=", "))

# Data distributions
message("\nSubject count (DM): ", n_distinct(dm$USUBJID))
message("MH record count: ", nrow(mh))
message("QS record count: ", nrow(qs))
message("LB record count: ", nrow(lb))

# Explore LBTESTCD values (for biomarker flags)
message("\nLB test codes (LBTESTCD):")
print(table(lb$LBTESTCD, useNA = "ifany"))

# Explore LBSTRESC values by test
message("\nLB results by test code:")
lb %>% group_by(LBTESTCD, LBSTRESC) %>% tally() %>% print(n = 100)

# Explore MHCAT values (for comorbidities and staging)
message("\nMH categories (MHCAT):")
print(table(mh$MHCAT, useNA = "ifany"))

# Explore MHTERM sample values
message("\nSample MHTERM values (first 20):")
print(head(unique(mh$MHTERM), 20))

# Explore QSTESTCD values (for ECOG)
message("\nQS test codes (QSTESTCD):")
print(table(qs$QSTESTCD, useNA = "ifany"))

# Explore TU test codes (for metastasis flags)
message("\nTU test codes (TUTESTCD):")
print(table(tu$TUTESTCD, useNA = "ifany"))

# Explore TU locations
message("\nTU locations (TULOC):")
print(table(tu$TULOC, useNA = "ifany"))

# Explore ADLOT INDEXFL
message("\nADLOT INDEXFL distribution:")
print(table(adlot$INDEXFL, useNA = "ifany"))

message("\n=== Exploration complete ===\n")
