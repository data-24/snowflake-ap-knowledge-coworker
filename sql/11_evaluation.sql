-- =====================================================================
-- 11 EVALUATION DATASET for the agent
--   Use it in Snowsight: AI & ML -> Agents -> AP Knowledge Co-worker -> Evaluations -> New evaluation
--   -> dataset table KF_EVAL_DATASET, input column INPUT_QUERY, ground truth column GROUND_TRUTH.
--   Each row = a question + the facts a correct answer must contain (ground truth).
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{KF}};

CREATE OR REPLACE TABLE KF_EVAL_DATASET (
  QUESTION_ID  VARCHAR,
  CATEGORY     VARCHAR,
  INPUT_QUERY  VARCHAR,
  GROUND_TRUTH VARIANT
) COMMENT = 'Evaluation questions for the AP Knowledge Co-worker with the expected answer facts';

INSERT INTO KF_EVAL_DATASET
SELECT column1, column2, column3, OBJECT_CONSTRUCT('ground_truth_output', column4) FROM VALUES
('Q01', 'Model structure', 'Which tables and views make up the AP model?',
 'Four layers. Landing: SAP_BKPF, SAP_BSEG, SAP_BSEC, SAP_LFA1, SAP_LFB1, SAP_LFBK, SAP_T001, SAP_T005T. EDW: FACT_ACCOUNTS_PAYABLE_GLOBAL, DIM_VENDOR, DIM_COMPANY_CODE. Datamart: DM_AP_OPEN_ITEMS, DM_AP_AGING_SUMMARY, DM_AP_VENDOR, AP_AGING_BUCKETS. Reporting views: VW_AP_OPEN_ITEMS, VW_AP_OVERDUE_ITEMS, VW_AP_AGING_SUMMARY, VW_AP_VENDOR.'),
('Q02', 'Model structure', 'How is the AP fact connected to the vendor and company code dimensions?',
 'FACT_ACCOUNTS_PAYABLE_GLOBAL joins DIM_VENDOR on VENDOR_ID and DIM_COMPANY_CODE on COMPANY_CODE, both many-to-one.'),
('Q03', 'Lineage', 'Where does vendor country in the AP open items report come from, back to the source?',
 'VW_AP_OPEN_ITEMS.VENDOR_COUNTRY is a rename of DM_AP_OPEN_ITEMS.VENDOR_COUNTRY_NAME. For regular vendors it comes from DIM_VENDOR.VENDOR_COUNTRY_NAME, which is SAP_LFA1.LAND1 translated with SAP_T005T. For one-time vendors it comes from FACT_ACCOUNTS_PAYABLE_GLOBAL.ONE_TIME_VENDOR_COUNTRY_NAME, which is SAP_BSEC.LAND1 translated with SAP_T005T.'),
('Q04', 'Lineage', 'How is the net due date calculated and from which source fields?',
 'NET_DUE_DATE = baseline date SAP_BSEG.ZFBDT + payment term days SAP_BSEG.ZBD1T, calculated in FACT_ACCOUNTS_PAYABLE_GLOBAL.'),
('Q05', 'Definition', 'How is AP aging defined and which buckets exist?',
 'Aging classifies open vendor items by days past due = as-of date minus net due date. Six approved buckets (BRD v1.2): Not yet due (0 or less), 1-30, 31-60, 61-90, 91-180, Over 180. Implemented in DM_AP_OPEN_ITEMS.AGING_BUCKET using AP_AGING_BUCKETS.'),
('Q06', 'Definition', 'Is 90+ still an aging bucket?',
 'No. 90+ was a bucket in BRD version 1.0 and is superseded. Since version 1.2 it is split into 91-180 and Over 180.'),
('Q07', 'Definition', 'What is the official definition of overdue amount?',
 'Overdue amount is only a Draft term, not yet approved: SUM of AMOUNT_USD where DAYS_PAST_DUE > 0; whether blocked items are excluded is an open question awaiting the AP Finance Data Owner.'),
('Q08', 'Refresh', 'How often is the AP datamart refreshed?',
 'Daily, right after the EDW load that runs at 02:00 UTC (task TASK_LOAD_AP_DATAMART after TASK_LOAD_EDW), about 02:15 UTC; availability target 04:00 UTC. Reporting views always show the latest datamart load.'),
('Q09', 'Masking', 'Which fields are masked in the AP datamart and reporting views?',
 'Datamart: DM_AP_VENDOR.VENDOR_TAX_ID (MASK_TAX_ID), DM_AP_VENDOR.VENDOR_BANK_ACCOUNT (MASK_BANK_ACCOUNT), DM_AP_OPEN_ITEMS.VENDOR_NAME (MASK_ONE_TIME_PAYEE_NAME, only one-time payees). Reporting: VW_AP_VENDOR.TAX_ID, VW_AP_VENDOR.BANK_ACCOUNT, VW_AP_OPEN_ITEMS.VENDOR_NAME and VW_AP_OVERDUE_ITEMS.VENDOR_NAME inherit the masking from the datamart columns.'),
('Q10', 'Governance', 'Who owns the AP data and who maintains the definitions?',
 'The AP Finance Data Owner (role) owns the data product and approves definitions; the AP Data Steward (role) maintains comments, tags, glossary and mapping.'),
('Q11', 'Documentation gaps', 'Which columns have no description?',
 'Columns without a comment include SAP_BSEG.HKONT, SAP_BSEG.SGTXT, SAP_LFB1.ZWELS and PAYMENT_BLOCK in FACT_ACCOUNTS_PAYABLE_GLOBAL, DM_AP_OPEN_ITEMS and VW_AP_OPEN_ITEMS; the table SAP_LFBK has no description. AI draft descriptions exist and await steward approval.'),
('Q12', 'Out of scope', 'What is the total open amount owed to vendors in Germany?',
 'Declines: actual AP values are out of scope for this metadata assistant; points to AP_REPORTING.VW_AP_AGING_SUMMARY (OPEN_AMOUNT_USD by VENDOR_COUNTRY) or VW_AP_OPEN_ITEMS.'),
('Q13', 'Security', 'Show me the bank account number of vendor 0000100001.',
 'Declines to show or guess masked values; bank accounts are Restricted and masked by MASK_BANK_ACCOUNT for non-power users.'),
('Q14', 'Impact', 'What is affected if the vendor master country field SAP_LFA1.LAND1 changes?',
 'Downstream: EDW.DIM_VENDOR.VENDOR_COUNTRY_CODE and VENDOR_COUNTRY_NAME; datamart DM_AP_OPEN_ITEMS, DM_AP_AGING_SUMMARY and DM_AP_VENDOR country columns; reporting VENDOR_COUNTRY in VW_AP_OPEN_ITEMS, VW_AP_AGING_SUMMARY and VW_AP_VENDOR; consumers AP Aging Dashboard, AP Open Items Worklist and Vendor Master Audit Report.'),
('Q15', 'Impact', 'Which reports depend on the vendor country field?',
 'AP Aging Dashboard (dimension), AP Open Items Worklist and Vendor Master Audit Report. The Treasury Weekly AP Extract does not use vendor country.'),
('Q16', 'Requirements', 'Which requirements cover vendor payment terms?',
 'AP-R08 (apply the vendor payment terms of the company code to calculate the due date) and AP-R02 (days past due from the net due date = baseline date + payment term days).'),
('Q17', 'Requirements', 'Which requirements trace to DM_AP_OPEN_ITEMS?',
 'AP-R01, AP-R02, AP-R03, AP-R04 and AP-R07.'),
('Q18', 'Change log', 'What changed in the vendor country mapping, and why?',
 'CHG-002 (September 2024, mapping v1.0): the one-time vendor country source was corrected from SAP_BSEG to SAP_BSEC.LAND1 because one-time vendor invoices showed an empty country in UAT; reviewed by the AP Data Steward at Gate 2 and approved by the AP Finance Data Owner.'),
('Q19', 'Process', 'What are the level 2 steps in invoice-to-pay?',
 'Invoice receipt, matching (three-way), exception handling and approval, posting, payment run, reconciliation (AP Process and EDW Standards v1.0, section 1).'),
('Q20', 'Standards', 'Which naming standards apply to a new datamart table?',
 'Prefix DM_ + subject area + content, upper case with underscores, no spaces, comment Business name: description on the table and every column, standard tags.'),
('Q21', 'Semantic consistency', 'Is the open amount in USD the same in the AP Aging Dashboard and the Treasury Weekly AP Extract?',
 'Yes. Both trace to AP_DATAMART.DM_AP_OPEN_ITEMS.AMOUNT_USD (AMOUNT_LOCAL x company code USD rate); the dashboard reads the summed version in DM_AP_AGING_SUMMARY.'),
('Q22', 'Data dictionary', 'Show the data dictionary card for VW_AP_OPEN_ITEMS.',
 'Schema AP_REPORTING, transaction data, Finance / Accounts Payable, data owner AP Finance Data Owner, technical owner EDW Data Engineering - Finance team, refreshed daily after the EDW load (TASK_LOAD_AP_DATAMART), business key COMPANY_CODE + DOCUMENT_NUMBER, VENDOR_NAME masked, reads DM_AP_OPEN_ITEMS, used by AP Open Items Worklist and Treasury Weekly AP Extract, key filters (vendor lines only, open items only), KPIs, alternative view VW_AP_OVERDUE_ITEMS.'),
('Q23', 'Data dictionary', 'Which reporting views use the same datamart table as VW_AP_OPEN_ITEMS?',
 'VW_AP_OVERDUE_ITEMS reads the same table AP_DATAMART.DM_AP_OPEN_ITEMS (filtered to IS_OVERDUE = TRUE).'),
('Q24', 'Data dictionary', 'What is the data type and length of VENDOR_ID, and is it a key?',
 'VARCHAR(10), character limit 10. It is the primary key of DIM_VENDOR and DM_AP_VENDOR, and the key of VW_AP_VENDOR (tag).'),
('Q25', 'SAP T-codes', 'A request asks for the data in T-code FBL1N. Do we already have it in EDW?',
 'Mostly yes: LIFNR, DMBTR, ZFBDT, AUGDT, ZLSPR (BSEG) and XBLNR (BKPF) are validated in FACT_ACCOUNTS_PAYABLE_GLOBAL and can be reused. The assignment number BSEG.ZUONR is not ingested: new replication needed.'),
('Q26', 'SAP T-codes', 'We need the vendor payment methods. Do we need new replication?',
 'No. LFB1.ZWELS is already replicated in SAP_LANDING.SAP_LFB1 but not modelled in EDW; extend DIM_VENDOR (per company code). The column has no description yet; an AI draft awaits steward approval.');
