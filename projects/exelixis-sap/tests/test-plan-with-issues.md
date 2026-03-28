# Test Plan with Known Issues

## Datasets

### ADSL (101 variables)

Demographics, baseline characteristics, biomarker flags, comorbidities.

Derivations:
- EGFRFL: EGFR biomarker flag
- KRASFL: KRAS biomarker flag
- ALKFL: ALK biomarker flag
- BRAFFL: BRAF biomarker flag
- ROS1FL: ROS1 biomarker flag
- MET FL: MET biomarker flag
- HER2FL: HER2 biomarker flag
- RET FL: RET biomarker flag

### ADRS (45 variables)

Response dataset.

### ADAE (35 variables)

Adverse events.

### ADLB (50 variables)

Laboratory values.

Complexity: HIGH

## Open Questions

- [ ] How should we handle missing MHDTC dates?
- TODO: Confirm biomarker test codes
