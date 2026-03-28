# Open CDISC / Methodology Questions — NPM-008 Exelixis XB010-100

**Study:** NPM-008 / Exelixis XB010-100 NSCLC ECA
**Last updated:** 2026-03-27 (SAP review + plan review complete)

This file tracks methodology decisions that were made with known uncertainty and open questions that remain unresolved. Both types require future review as the analysis evolves.

---

## Resolved Decisions (Flagged for Revisit)

These decisions have been made for the first-pass implementation. Each is annotated in the relevant program code. All should be reviewed before a final analysis cut.

| # | Question | Dataset(s) | Decision Made | Rationale | Revisit Trigger |
|---|----------|------------|---------------|-----------|-----------------|
| R1 | **Charlson Comorbidity Index version** — Original 1987 Charlson weights or updated Quan 2011 weights? | ADSL (CCISCORE) | **Use Quan 2011 updated weights** | More widely validated for administrative/claims data; better ICD-10 mapping | Final analysis; if clinical team specifies 1987 weights in SAP revision |
| R2 | **CCI scoring source** — Derive from ICD-10 codes or MedDRA preferred terms in MH.MHTERM? | ADSL (CCISCORE) | **Derive from MH.MHTERM** (MedDRA/verbatim terms) | ICD-10 codes not available in SDTM MH domain for this study | Revisit if ICD-10 mapped terms become available in MH.MHTERM or MHBODSYS |
| R3 | **RECIST 1.1 BOR confirmation requirement** — Confirmed response (two consecutive CR/PR assessments) or single best assessment? | ADRS (BOR), ADTTE (DOR) | **Confirmed response required — ≥28-day interval between two assessments** | SAP Section explicitly states: *"Both CR and PR will be confirmed based on RECIST1.1, and the minimum interval between 2 assessments should be no less than 4 weeks (28 days)"*. User confirmed on 2026-03-27 to follow SAP over earlier draft decision. | SAP revision; if clinical team explicitly downgrades to single best assessment in a future SAP version |
| R4 | **ADTTE month conversion factor** — days/30.4375, days/30, or other? | ADTTE (PFS, OS, DOR) | **days / 30.4375** | SAP explicitly uses this formula for all three TTE parameters (PFS, OS, DOR). | SAP revision only |
| R5 | **NPM LoT Algorithm — NSCLC-specific parameters** — 45-day window, 120-day treatment gap, switching rule | ADLOT, ADSL (INDEXFL, PRIORLN), ADTTE (STARTDT) | **Window = 45 days; Treatment gap = 120 days; Switching = 'no' (NSCLC)** | SAP contains NSCLC-specific LoT definition. Line starts on first valid antineoplastic administration. Ends on: last administration, OR new drug added outside the 45-day window, OR >120-day gap from ALL drugs, OR death. Index line = line matching EX domain drugs (≥2L). | SAP revision; if data team defines different gap/window parameters |
| R6 | **AE-HO linkage key** — Is HO linked to AE on USUBJID + AESEQ, or USUBJID + date overlap? | ADAE (HOSPDUR) | **Join on USUBJID + HO.HOHNKID == as.character(AE.AESEQ)** | Confirmed by inspecting sim_ho.R — HOHNKID stores the AE sequence number as character. HO columns: STUDYID, DOMAIN, USUBJID, HOSEQ, HOTERM, HOSTDTC, HOENDTC, HOHNKID. | Only if HO domain structure changes |
| R7 | **Flag convention (Y/blank vs Y/N)** — Should flag variables use ADaM standard 'Y'/blank or 'Y'/'N'? | All datasets | **Use Y/blank (ADaM standard)** — `ifelse(condition, "Y", NA_character_)` | ADaM-IG defines flag variables as Y or blank. Using Y/N is non-standard and causes issues with ADaM compliance checks. | Only if NPM-008 data dictionary explicitly mandates Y/N in a future revision |
| R8 | **ADRS AVAL numeric coding** — Is the 1=CR, 2=PR, 3=SD, 4=PD, 5=NE convention intentional? | ADRS | **Yes, intentional study-specific convention** (lower number = better response) | Not a CDISC standard coding; specific to NPM-008 analysis plan. Add `# NOTE: Study-specific AVAL coding` comment in code. | SAP revision or if CDISC publishes a standard numeric coding for oncology response |

---

## Open Questions (Unresolved — Blocking or High-Impact)

These must be resolved before finalizing the affected programs.

| # | Question | Dataset(s) | Impact | Status | Owner |
|---|----------|------------|--------|--------|-------|
*All blocking open questions resolved as of 2026-03-27. See Resolved Decisions table (R3, R4, R5).*

---

## Warning-Level Questions (Should Clarify)

Lower urgency but should be resolved during or before Wave 1/2 implementation.

| # | Question | Dataset(s) | Notes |
|---|----------|------------|-------|
| ~~W1~~ | ~~AE-HO linkage key~~ | ~~ADAE~~ | **RESOLVED — moved to R6** |
| ~~W2~~ | ~~Flag convention~~ | ~~All~~ | **RESOLVED — moved to R7** |
| ~~W3~~ | ~~ADTTE month conversion factor~~ | ~~ADTTE~~ | **RESOLVED — moved to R4** |
| W4 | **LOTENDRSN mapping** — Exact mapping from CM.CMRSDISC and DS.DSTERM values to LOTENDRSN categories | ADLOT | May need a manual mapping table; agent should explore CM and DS values first |
| W5 | **Neoadjuvant vs adjuvant definition** — Is it based on temporal relationship to surgery date (from PR domain), or on specific treatment category codes? | ADSL (NEOADJFL, ADJUVFL, NEOADJTRT, ADJUVTRT) | Affects derivation logic for pre-index treatment history |
| W6 | **ADBS ADaM compliance** — ADBS is not a standard ADaM dataset name. Should it follow BDS structure, or is it a custom dataset? | ADBS | Affects required variables and structure |
| ~~W7~~ | ~~ADRS AVAL numeric coding~~ | ~~ADRS~~ | **RESOLVED — moved to R8** |

---

## How to Use This File

- **Programmers:** Before implementing a derivation listed above, check this file for the current decision status. If a question is still OPEN and your derivation depends on it, flag it in your dev log and implement a reasonable default with a code comment.
- **Code comments:** Every decision in the "Resolved Decisions" table must have a corresponding `# REVISIT:` comment in the program code pointing back to this file.
- **Updates:** When a question is resolved, move it from "Open Questions" to "Resolved Decisions" and record the decision, rationale, and trigger for future revision.
