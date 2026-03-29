# SDTM Domain Validation Log

**Study:** NPM-008 / Exelixis XB010-101 NSCLC ECA
**Date:** 2026-03-29

---

### DM — 2026-03-29 13:56:54

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### AE — 2026-03-29 13:56:58

- **Wave:** 2
- **Rows:** 131
- **Columns:** 17
- **Validation:** PASS
- **Checks:** 12/13 PASS, 1 WARNING
- **Notes:**
  - Avg AEs per subject: 3.27
  - Subjects with AEs: 40 / 40

**Warnings:**

- **U8**: Row count within expected range
  - Detail: Actual: 131, Expected: [200, 800]

---

### DS — 2026-03-29 13:57:02

- **Wave:** 1
- **Rows:** 40
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 15/15 PASS

---

### MH — 2026-03-29 13:57:14

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### DM — 2026-03-29 13:57:52

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### IE — 2026-03-29 13:57:52

- **Wave:** 1
- **Rows:** 400
- **Columns:** 10
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - 10 criteria per subject: 5 inclusion + 5 exclusion
  - All subjects meet eligibility (enrolled population)

---

### MH — 2026-03-29 13:57:52

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### SC — 2026-03-29 13:57:52

- **Wave:** 1
- **Rows:** 120
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - 3 records per subject: EDUC, MARISTAT, INCOME
  - SCDTC set to RFICDTC (consent date)

---

### BS — 2026-03-29 13:57:52

- **Wave:** 2
- **Rows:** 113
- **Columns:** 12
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - Specimen collection dates match biomarker LB test dates
  - All subjects have FFPEBL and FFPESL; HE slides present for ~80%

---

### TR — 2026-03-29 13:57:53

- **Wave:** 3
- **Rows:** 566
- **Columns:** 14
- **Validation:** PASS
- **Checks:** 15/16 PASS, 1 WARNING
- **Notes:**
  - Lesion size trajectories driven by BOR from DM latent
  - RECIST constraints enforced: PR <= 70% baseline, PD >= 120% nadir + 5mm
  - Visit schedule: baseline + every 6 weeks until PFS event

**Warnings:**

- **D6**: Measurement dates within reasonable window of treatment period
  - Detail: 9 record(s) outside expected date range

---

### RS — 2026-03-29 13:57:54

- **Wave:** 4
- **Rows:** 195
- **Columns:** 13
- **Validation:** PASS
- **Checks:** 16/16 PASS
- **Notes:**
  - RECIST 1.1 responses derived from TR tumor measurement trajectories
  - Clinician-stated BOR matches DM latent variable for all subjects
  - Early progressors (baseline-only RECIST) have PD in CLINRES only

---

### AE — 2026-03-29 13:57:54

- **Wave:** 2
- **Rows:** 131
- **Columns:** 17
- **Validation:** PASS
- **Checks:** 12/13 PASS, 1 WARNING
- **Notes:**
  - Avg AEs per subject: 3.27
  - Subjects with AEs: 40 / 40

**Warnings:**

- **U8**: Row count within expected range
  - Detail: Actual: 131, Expected: [200, 800]

---

### HO — 2026-03-29 13:57:54

- **Wave:** 3
- **Rows:** 10
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/14 PASS, 1 WARNING
- **Notes:**
  - One HO record per AESHOSP='Y' AE
  - HOHNKID links to AESEQ

**Warnings:**

- **U8**: Row count within expected range
  - Detail: Actual: 10, Expected: [20, 60]

---

### DS — 2026-03-29 13:57:54

- **Wave:** 1
- **Rows:** 40
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 15/15 PASS

---

### DM — 2026-03-29 14:48:14

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### IE — 2026-03-29 14:48:14

- **Wave:** 1
- **Rows:** 400
- **Columns:** 10
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - 10 criteria per subject: 5 inclusion + 5 exclusion
  - All subjects meet eligibility (enrolled population)

---

### MH — 2026-03-29 14:48:15

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### SC — 2026-03-29 14:48:15

- **Wave:** 1
- **Rows:** 120
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - 3 records per subject: EDUC, MARISTAT, INCOME
  - SCDTC set to RFICDTC (consent date)

---

### DM — 2026-03-29 15:01:20

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### IE — 2026-03-29 15:01:20

- **Wave:** 1
- **Rows:** 400
- **Columns:** 10
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - 10 criteria per subject: 5 inclusion + 5 exclusion
  - All subjects meet eligibility (enrolled population)

---

### MH — 2026-03-29 15:01:21

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### SC — 2026-03-29 15:01:21

- **Wave:** 1
- **Rows:** 120
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - 3 records per subject: EDUC, MARISTAT, INCOME
  - SCDTC set to RFICDTC (consent date)

---

### BS — 2026-03-29 15:01:21

- **Wave:** 2
- **Rows:** 113
- **Columns:** 12
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - Specimen collection dates match biomarker LB test dates
  - All subjects have FFPEBL and FFPESL; HE slides present for ~80%

---

### TR — 2026-03-29 15:01:23

- **Wave:** 3
- **Rows:** 566
- **Columns:** 14
- **Validation:** PASS
- **Checks:** 15/16 PASS, 1 WARNING
- **Notes:**
  - Lesion size trajectories driven by BOR from DM latent
  - RECIST constraints enforced: PR <= 70% baseline, PD >= 120% nadir + 5mm
  - Visit schedule: baseline + every 6 weeks until PFS event

**Warnings:**

- **D6**: Measurement dates within reasonable window of treatment period
  - Detail: 9 record(s) outside expected date range

---

### RS — 2026-03-29 15:01:23

- **Wave:** 4
- **Rows:** 195
- **Columns:** 13
- **Validation:** PASS
- **Checks:** 16/16 PASS
- **Notes:**
  - RECIST 1.1 responses derived from TR tumor measurement trajectories
  - Clinician-stated BOR matches DM latent variable for all subjects
  - Early progressors (baseline-only RECIST) have PD in CLINRES only

---

### AE — 2026-03-29 15:01:24

- **Wave:** 2
- **Rows:** 131
- **Columns:** 17
- **Validation:** PASS
- **Checks:** 12/13 PASS, 1 WARNING
- **Notes:**
  - Avg AEs per subject: 3.27
  - Subjects with AEs: 40 / 40

**Warnings:**

- **U8**: Row count within expected range
  - Detail: Actual: 131, Expected: [200, 800]

---

### HO — 2026-03-29 15:01:24

- **Wave:** 3
- **Rows:** 10
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/14 PASS, 1 WARNING
- **Notes:**
  - One HO record per AESHOSP='Y' AE
  - HOHNKID links to AESEQ

**Warnings:**

- **U8**: Row count within expected range
  - Detail: Actual: 10, Expected: [20, 60]

---

### DS — 2026-03-29 15:01:24

- **Wave:** 1
- **Rows:** 40
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 15/15 PASS

---

### DM — 2026-03-29 15:40:17

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### IE — 2026-03-29 15:40:17

- **Wave:** 1
- **Rows:** 400
- **Columns:** 10
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - 10 criteria per subject: 5 inclusion + 5 exclusion
  - All subjects meet eligibility (enrolled population)

---

### MH — 2026-03-29 15:40:18

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### SC — 2026-03-29 15:40:18

- **Wave:** 1
- **Rows:** 120
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - 3 records per subject: EDUC, MARISTAT, INCOME
  - SCDTC set to RFICDTC (consent date)

---

### BS — 2026-03-29 15:40:19

- **Wave:** 2
- **Rows:** 113
- **Columns:** 12
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - Specimen collection dates match biomarker LB test dates
  - All subjects have FFPEBL and FFPESL; HE slides present for ~80%

---

### TR — 2026-03-29 15:40:20

- **Wave:** 3
- **Rows:** 566
- **Columns:** 14
- **Validation:** PASS
- **Checks:** 15/16 PASS, 1 WARNING
- **Notes:**
  - Lesion size trajectories driven by BOR from DM latent
  - RECIST constraints enforced: PR <= 70% baseline, PD >= 120% nadir + 5mm
  - Visit schedule: baseline + every 6 weeks until PFS event

**Warnings:**

- **D6**: Measurement dates within reasonable window of treatment period
  - Detail: 9 record(s) outside expected date range

---

### RS — 2026-03-29 15:40:20

- **Wave:** 4
- **Rows:** 195
- **Columns:** 13
- **Validation:** PASS
- **Checks:** 16/16 PASS
- **Notes:**
  - RECIST 1.1 responses derived from TR tumor measurement trajectories
  - Clinician-stated BOR matches DM latent variable for all subjects
  - Early progressors (baseline-only RECIST) have PD in CLINRES only

---

### AE — 2026-03-29 15:40:20

- **Wave:** 2
- **Rows:** 131
- **Columns:** 17
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Avg AEs per subject: 3.27
  - Subjects with AEs: 40 / 40

---

### HO — 2026-03-29 15:40:21

- **Wave:** 3
- **Rows:** 10
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - One HO record per AESHOSP='Y' AE
  - HOHNKID links to AESEQ

---

### DS — 2026-03-29 15:40:21

- **Wave:** 1
- **Rows:** 40
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 15/15 PASS

---

### DM — 2026-03-29 16:29:38

- **Wave:** 0
- **Rows:** 40
- **Columns:** 38
- **Validation:** PASS
- **Checks:** 15/15 PASS
- **Notes:**
  - DTHFL=Y: 28 subjects (70.0%)
  - BOR: PR=5, CR=0, SD=16, PD=17, NE=2

---

### IE — 2026-03-29 16:29:38

- **Wave:** 1
- **Rows:** 400
- **Columns:** 10
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - 10 criteria per subject: 5 inclusion + 5 exclusion
  - All subjects meet eligibility (enrolled population)

---

### MH — 2026-03-29 16:29:38

- **Wave:** 1
- **Rows:** 156
- **Columns:** 9
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Records per subject — min: 3, max: 6, median: 4.0

---

### SC — 2026-03-29 16:29:38

- **Wave:** 1
- **Rows:** 120
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - 3 records per subject: EDUC, MARISTAT, INCOME
  - SCDTC set to RFICDTC (consent date)

---

### BS — 2026-03-29 16:29:38

- **Wave:** 2
- **Rows:** 113
- **Columns:** 12
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - Specimen collection dates match biomarker LB test dates
  - All subjects have FFPEBL and FFPESL; HE slides present for ~80%

---

### TR — 2026-03-29 16:29:39

- **Wave:** 3
- **Rows:** 566
- **Columns:** 14
- **Validation:** PASS
- **Checks:** 15/16 PASS, 1 WARNING
- **Notes:**
  - Lesion size trajectories driven by BOR from DM latent
  - RECIST constraints enforced: PR <= 70% baseline, PD >= 120% nadir + 5mm
  - Visit schedule: baseline + every 6 weeks until PFS event

**Warnings:**

- **D6**: Measurement dates within reasonable window of treatment period
  - Detail: 9 record(s) outside expected date range

---

### RS — 2026-03-29 16:29:39

- **Wave:** 4
- **Rows:** 195
- **Columns:** 13
- **Validation:** PASS
- **Checks:** 16/16 PASS
- **Notes:**
  - RECIST 1.1 responses derived from TR tumor measurement trajectories
  - Clinician-stated BOR matches DM latent variable for all subjects
  - Early progressors (baseline-only RECIST) have PD in CLINRES only

---

### AE — 2026-03-29 16:29:40

- **Wave:** 2
- **Rows:** 131
- **Columns:** 17
- **Validation:** PASS
- **Checks:** 13/13 PASS
- **Notes:**
  - Avg AEs per subject: 3.27
  - Subjects with AEs: 40 / 40

---

### HO — 2026-03-29 16:29:40

- **Wave:** 3
- **Rows:** 10
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 14/14 PASS
- **Notes:**
  - One HO record per AESHOSP='Y' AE
  - HOHNKID links to AESEQ

---

### DS — 2026-03-29 16:29:40

- **Wave:** 1
- **Rows:** 40
- **Columns:** 8
- **Validation:** PASS
- **Checks:** 15/15 PASS

---

