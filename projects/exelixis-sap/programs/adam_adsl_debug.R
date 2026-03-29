library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)

dm <- haven::read_xpt("output-data/sdtm/dm.xpt")
mh <- haven::read_xpt("output-data/sdtm/mh.xpt")

adsl <- dm %>%
  select(STUDYID, USUBJID, BRTHDTC, AGE, AGEU) %>%
  mutate(
    BRTHDT = as.numeric(as.Date(BRTHDTC))
  )

cat("After initial select (should have AGE):\n")
cat(paste(names(adsl), collapse=", "), "\n\n")

# AGENSCLC derivation
mh_nsclc <- mh %>%
  filter(MHCAT == "CANCER DIAGNOSIS",
         str_detect(MHTERM, regex("lung cancer", ignore_case = TRUE))) %>%
  group_by(USUBJID) %>%
  slice_min(order_by = as.Date(MHSTDTC), n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  mutate(NSCLC_DX_DT = as.Date(MHSTDTC)) %>%
  select(USUBJID, NSCLC_DX_DT)

adsl <- adsl %>%
  left_join(mh_nsclc, by = "USUBJID") %>%
  mutate(
    AGENSCLC = if_else(
      !is.na(NSCLC_DX_DT) & !is.na(BRTHDTC),
      as.numeric(interval(as.Date(BRTHDTC), NSCLC_DX_DT) / dyears(1)),
      NA_real_
    ),
    AGEINDEX = AGE,
    AGEINDEXGRP = if_else(AGE < 65, "<65", ">=65", missing = NA_character_)
  ) %>%
  select(-NSCLC_DX_DT, -AGE)

cat("After age block (should have AGEINDEX, no AGE):\n")
cat(paste(names(adsl), collapse=", "), "\n\n")

# Check for duplicates
cat("Duplicate column names: ", any(duplicated(names(adsl))), "\n")

# Now select final
adsl_final <- adsl %>%
  select(STUDYID, USUBJID, BRTHDTC, BRTHDT, AGEINDEX, AGEU, AGEINDEXGRP, AGENSCLC)

cat("\nAfter final select:\n")
cat(paste(names(adsl_final), collapse=", "), "\n\n")

cat("Duplicate column names in final: ", any(duplicated(names(adsl_final))), "\n")
