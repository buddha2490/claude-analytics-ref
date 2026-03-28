---
name: npm008_biomarker_terminology
description: NPM-008 LB domain uses ALTERED/NOT ALTERED for mutation status
type: reference
---

LB biomarker values in NPM-008 use "ALTERED"/"NOT ALTERED"/"NOT TESTED"/"VUS", not the CDISC standard "POSITIVE"/"DETECTED"/"NEGATIVE".

**Pattern matching rules:**
- ALTERED → Y (mutation present)
- NOT ALTERED → N (wild-type)
- NOT TESTED → NA (not evaluated)
- VUS → NA (variant of unknown significance)

**Check order matters:** Must check "NOT ALTERED" and "NOT TESTED" BEFORE "ALTERED" to avoid substring matching bugs.

Applies to: EGFRMUT, KRASMUT, ALK, ROS1MUT, RETMUT, METMUT, ERBB2MUT, NTRK1FUS, NTRK2FUS, NTRK3FUS in ADSL and any future biomarker-related datasets.
