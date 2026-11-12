-- =====================================================================
-- 07 KNOWLEDGE FABRIC: one metadata catalog for the AP model
--
--   PRIMARY source = Snowflake metadata (read live by REFRESH_KNOWLEDGE_FABRIC):
--     INFORMATION_SCHEMA tables/columns + comments, tags (incl. inherited), masking policies,
--     tasks (refresh schedule), Snowflake lineage (GET_LINEAGE, from access history)
--   SUPPLEMENTARY sources = curated here, as a project team would from its documents:
--     KF_FIELD_MAPPING        mapping sheet: target column <- source column + transformation rule
--     KF_ASSET_RELATIONSHIPS  how the tables join / load into each other
--     KF_GLOSSARY             approved business terms (AP aging, buckets, vendor country ...)
--
--   OUTPUT tables the agent uses:
--     KF_OBJECTS, KF_COLUMNS, KF_LINEAGE_PATHS, KF_REFRESH_SCHEDULE, KF_SYSTEM_LINEAGE,
--     KF_DESCRIPTION_SUGGESTIONS (AI_COMPLETE drafts for missing descriptions), KF_CATALOG (search text)
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{KF}};

-- ---------------------------------------------------------------------
-- 1. Mapping sheet (supplementary): field-level lineage with transformation rules
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_FIELD_MAPPING (
  MAPPING_ID          NUMBER AUTOINCREMENT COMMENT 'Mapping ID: row number of the mapping sheet.',
  TARGET_LAYER        VARCHAR COMMENT 'Target layer: Landing, EDW, Datamart or Reporting.',
  TARGET_OBJECT       VARCHAR COMMENT 'Target object: SCHEMA.OBJECT that receives the value.',
  TARGET_COLUMN       VARCHAR COMMENT 'Target column: column that receives the value.',
  SOURCE_OBJECT       VARCHAR COMMENT 'Source object: SCHEMA.OBJECT the value comes from.',
  SOURCE_COLUMN       VARCHAR COMMENT 'Source column: column the value comes from.',
  MAPPING_TYPE        VARCHAR COMMENT 'Mapping type: Direct, Renamed, Lookup, Derived, Conditional or Aggregated.',
  TRANSFORMATION_RULE VARCHAR COMMENT 'Transformation rule: how the target value is produced, in plain English.',
  MAPPING_SOURCE      VARCHAR COMMENT 'Mapping source: document the mapping was taken from.'
) COMMENT = 'Field mapping sheet for the AP model (supplementary metadata). One row per target column and source column.';

INSERT INTO KF_FIELD_MAPPING (TARGET_LAYER, TARGET_OBJECT, TARGET_COLUMN, SOURCE_OBJECT, SOURCE_COLUMN, MAPPING_TYPE, TRANSFORMATION_RULE, MAPPING_SOURCE)
SELECT column1, column2, column3, column4, column5, column6, column7, 'FSD AP Datamart v1.0, section 5 (field mapping)' FROM VALUES
-- Reporting <- Datamart (select and rename only)
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'VENDOR_COUNTRY',     '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', 'Renamed', 'Renamed only: VENDOR_COUNTRY_NAME is exposed as VENDOR_COUNTRY. No logic in the reporting layer.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'VENDOR_NAME',        '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_NAME',         'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'VENDOR_ID',          '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_ID',           'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'IS_ONE_TIME_VENDOR', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'IS_ONE_TIME_VENDOR',  'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'COMPANY_NAME',       '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'COMPANY_NAME',        'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'DOCUMENT_TYPE',      '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DOCUMENT_TYPE_DESC',  'Renamed', 'Renamed only: DOCUMENT_TYPE_DESC is exposed as DOCUMENT_TYPE.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'INVOICE_REFERENCE',  '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'INVOICE_REFERENCE',   'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'NET_DUE_DATE',       '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'NET_DUE_DATE',        'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'DAYS_PAST_DUE',      '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE',       'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'AGING_BUCKET',       '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET',        'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'IS_OVERDUE',         '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'IS_OVERDUE',          'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'PAYMENT_BLOCK',      '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'PAYMENT_BLOCK',       'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'OPEN_AMOUNT_LOCAL',  '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_LOCAL',        'Renamed', 'Renamed only: AMOUNT_LOCAL is exposed as OPEN_AMOUNT_LOCAL.'),
('Reporting', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'OPEN_AMOUNT_USD',    '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD',          'Renamed', 'Renamed only: AMOUNT_USD is exposed as OPEN_AMOUNT_USD.'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'VENDOR_COUNTRY',  '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', 'Renamed', 'Renamed only; the view keeps overdue items (IS_OVERDUE = TRUE).'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'VENDOR_NAME',     '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_NAME',         'Direct',  'Passed through (overdue items only).'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'NET_DUE_DATE',    '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'NET_DUE_DATE',        'Direct',  'Passed through (overdue items only).'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'DAYS_PAST_DUE',   '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE',       'Direct',  'Passed through; always > 0 because of the view filter IS_OVERDUE = TRUE.'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'AGING_BUCKET',    '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET',        'Direct',  'Passed through (overdue buckets only).'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'PAYMENT_BLOCK',   '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'PAYMENT_BLOCK',       'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'OPEN_AMOUNT_USD', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD',          'Renamed', 'Renamed only: AMOUNT_USD is exposed as OPEN_AMOUNT_USD (overdue items only).'),
('Reporting', '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'VENDOR_COUNTRY',  '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'VENDOR_COUNTRY_NAME', 'Renamed', 'Renamed only.'),
('Reporting', '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'AGING_BUCKET',    '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'AGING_BUCKET',     'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'OPEN_ITEM_COUNT', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'OPEN_ITEM_COUNT',  'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'OPEN_AMOUNT_USD', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'OPEN_AMOUNT_USD',  'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_VENDOR', 'VENDOR_NAME',            '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_NAME',             'Direct',  'Passed through.'),
('Reporting', '{{REPORTING}}.VW_AP_VENDOR', 'VENDOR_COUNTRY',         '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_COUNTRY_NAME',     'Renamed', 'Renamed only.'),
('Reporting', '{{REPORTING}}.VW_AP_VENDOR', 'TAX_ID',                 '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_TAX_ID',           'Renamed', 'Renamed only. Masking is inherited from the datamart column.'),
('Reporting', '{{REPORTING}}.VW_AP_VENDOR', 'BANK_ACCOUNT',           '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_BANK_ACCOUNT',     'Renamed', 'Renamed only. Masking is inherited from the datamart column.'),
-- Datamart <- EDW (AP business logic)
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_NAME', 'Conditional', 'Regular vendors: the vendor master country (DIM_VENDOR.VENDOR_COUNTRY_NAME). One-time vendors (IS_ONE_TIME_VENDOR = TRUE): the payee country captured on the invoice (FACT.ONE_TIME_VENDOR_COUNTRY_NAME).'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_NAME', 'Conditional', 'Used only for one-time vendors (account group CPD); regular vendors use the vendor master country.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_CODE', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_CODE', 'Conditional', 'Regular vendors: vendor master country key. One-time vendors: payee country key from the invoice.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_CODE', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_CODE', 'Conditional', 'Used only for one-time vendors.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_NAME', '{{EDW}}.DIM_VENDOR', 'VENDOR_NAME', 'Conditional', 'Regular vendors: vendor master name. One-time vendors: payee name from the invoice (masked).'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_NAME', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_NAME', 'Conditional', 'Used only for one-time vendors.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_ID', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'VENDOR_ID', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'IS_ONE_TIME_VENDOR', '{{EDW}}.DIM_VENDOR', 'IS_ONE_TIME_VENDOR', 'Lookup', 'Looked up from the vendor dimension on VENDOR_ID.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'COMPANY_NAME', '{{EDW}}.DIM_COMPANY_CODE', 'COMPANY_NAME', 'Lookup', 'Looked up from the company code dimension on COMPANY_CODE.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DOCUMENT_TYPE_DESC', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'DOCUMENT_TYPE_DESC', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'INVOICE_REFERENCE', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'INVOICE_REFERENCE', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'NET_DUE_DATE', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'NET_DUE_DATE', 'Direct', 'Passed through. Only open items are loaded (FACT.IS_OPEN_ITEM = TRUE).'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'NET_DUE_DATE', 'Derived', 'DAYS_PAST_DUE = AS_OF_DATE - NET_DUE_DATE in days. AS_OF_DATE = the datamart load date.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', 'Derived', 'Bucket from AP_AGING_BUCKETS where DAYS_PAST_DUE is between MIN_DAYS and MAX_DAYS: Not yet due (<= 0), 1-30, 31-60, 61-90, 91-180, Over 180.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET', '{{DATAMART}}.AP_AGING_BUCKETS', 'BUCKET_NAME', 'Lookup', 'Bucket name taken from the approved bucket reference table.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'IS_OVERDUE', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', 'Derived', 'TRUE when DAYS_PAST_DUE > 0.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'PAYMENT_BLOCK', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_BLOCK', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_LOCAL', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', 'Direct', 'Passed through for open items only.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', 'Derived', 'AMOUNT_USD = ROUND(AMOUNT_LOCAL x DIM_COMPANY_CODE.USD_EXCHANGE_RATE, 2).'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', '{{EDW}}.DIM_COMPANY_CODE', 'USD_EXCHANGE_RATE', 'Lookup', 'Exchange rate of the company code currency.'),
('Datamart', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'VENDOR_COUNTRY_NAME', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', 'Aggregated', 'Group-by column.'),
('Datamart', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'AGING_BUCKET', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET', 'Aggregated', 'Group-by column.'),
('Datamart', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'OPEN_ITEM_COUNT', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AP_LINE_ID', 'Aggregated', 'COUNT of open items per as-of date, company code, vendor country and aging bucket.'),
('Datamart', '{{DATAMART}}.DM_AP_AGING_SUMMARY', 'OPEN_AMOUNT_USD', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', 'Aggregated', 'SUM of AMOUNT_USD per as-of date, company code, vendor country and aging bucket.'),
('Datamart', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AP_LINE_ID', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AP_LINE_ID', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_NAME', '{{EDW}}.DIM_VENDOR', 'VENDOR_NAME', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_COUNTRY_NAME', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_NAME', 'Direct', 'Passed through.'),
('Datamart', '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_TAX_ID', '{{EDW}}.DIM_VENDOR', 'VENDOR_TAX_ID', 'Direct', 'Passed through (masked).'),
('Datamart', '{{DATAMART}}.DM_AP_VENDOR', 'VENDOR_BANK_ACCOUNT', '{{EDW}}.DIM_VENDOR', 'VENDOR_BANK_ACCOUNT', 'Direct', 'Passed through (masked).'),
-- EDW <- Landing
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_NAME', '{{LANDING}}.SAP_LFA1', 'LAND1', 'Lookup', 'Vendor master country key LFA1.LAND1 translated to a country name with SAP_T005T (language E).'),
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_NAME', '{{LANDING}}.SAP_T005T', 'LANDX', 'Lookup', 'Country name text, joined on LAND1 and SPRAS = E.'),
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_CODE', '{{LANDING}}.SAP_LFA1', 'LAND1', 'Direct', 'Vendor master country key.'),
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_NAME', '{{LANDING}}.SAP_LFA1', 'NAME1', 'Direct', 'Vendor master name.'),
('EDW', '{{EDW}}.DIM_VENDOR', 'IS_ONE_TIME_VENDOR', '{{LANDING}}.SAP_LFA1', 'KTOKK', 'Derived', 'TRUE when the vendor account group KTOKK = CPD.'),
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_TAX_ID', '{{LANDING}}.SAP_LFA1', 'STCD1', 'Direct', 'Vendor tax number (masked).'),
('EDW', '{{EDW}}.DIM_VENDOR', 'VENDOR_BANK_ACCOUNT', '{{LANDING}}.SAP_LFBK', 'BANKN', 'Lookup', 'Vendor bank account from SAP_LFBK, joined on LIFNR (masked).'),
('EDW', '{{EDW}}.DIM_COMPANY_CODE', 'COMPANY_NAME', '{{LANDING}}.SAP_T001', 'BUTXT', 'Direct', 'Company code name.'),
('EDW', '{{EDW}}.DIM_COMPANY_CODE', 'USD_EXCHANGE_RATE', '{{LANDING}}.SAP_T001', 'WAERS', 'Derived', 'Synthetic fixed rate per company code currency: USD 1, GBP 1.27, EUR 1.08, INR 0.012, SGD 0.74.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AP_LINE_ID', '{{LANDING}}.SAP_BSEG', 'BELNR', 'Derived', 'BUKRS-BELNR-GJAHR-BUZEI of the vendor line.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'VENDOR_ID', '{{LANDING}}.SAP_BSEG', 'LIFNR', 'Direct', 'Vendor number of the line. Only vendor lines are loaded (KOART = K).'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_NAME', '{{LANDING}}.SAP_BSEC', 'NAME1', 'Lookup', 'Payee name from SAP_BSEC, joined on BUKRS, BELNR, GJAHR, BUZEI (masked).'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_CODE', '{{LANDING}}.SAP_BSEC', 'LAND1', 'Lookup', 'Payee country key from SAP_BSEC, joined on BUKRS, BELNR, GJAHR, BUZEI.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_NAME', '{{LANDING}}.SAP_BSEC', 'LAND1', 'Lookup', 'Payee country key BSEC.LAND1 translated to a name with SAP_T005T (language E).'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_NAME', '{{LANDING}}.SAP_T005T', 'LANDX', 'Lookup', 'Country name text, joined on LAND1 and SPRAS = E.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'DOCUMENT_TYPE_DESC', '{{LANDING}}.SAP_BKPF', 'BLART', 'Derived', 'KR = Vendor invoice, KG = Vendor credit memo.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'INVOICE_REFERENCE', '{{LANDING}}.SAP_BKPF', 'XBLNR', 'Direct', 'Vendor invoice number from the document header.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'NET_DUE_DATE', '{{LANDING}}.SAP_BSEG', 'ZFBDT', 'Derived', 'NET_DUE_DATE = baseline date ZFBDT + payment term days ZBD1T.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'NET_DUE_DATE', '{{LANDING}}.SAP_BSEG', 'ZBD1T', 'Derived', 'Payment term days added to the baseline date.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'IS_OPEN_ITEM', '{{LANDING}}.SAP_BSEG', 'AUGDT', 'Derived', 'TRUE when the clearing date AUGDT is empty.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', '{{LANDING}}.SAP_BSEG', 'DMBTR', 'Derived', 'DMBTR signed with SHKZG: credit H = +DMBTR (invoice owed), debit S = -DMBTR (credit memo).'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', '{{LANDING}}.SAP_BSEG', 'SHKZG', 'Derived', 'Debit/credit indicator gives the sign.'),
('EDW', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_BLOCK', '{{LANDING}}.SAP_BSEG', 'ZLSPR', 'Direct', 'Payment block key of the line.');

-- ---------------------------------------------------------------------
-- 2. How the objects connect (supplementary)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_ASSET_RELATIONSHIPS (
  RELATIONSHIP_ID   NUMBER AUTOINCREMENT COMMENT 'Relationship ID.',
  RELATIONSHIP_TYPE VARCHAR COMMENT 'Relationship type: Join (tables are joined) or Loads into (data flows from source to target).',
  FROM_OBJECT       VARCHAR COMMENT 'From object: SCHEMA.OBJECT on the many / source side.',
  TO_OBJECT         VARCHAR COMMENT 'To object: SCHEMA.OBJECT on the one / target side.',
  JOIN_COLUMNS      VARCHAR COMMENT 'Join columns: columns used to join (for Join relationships).',
  CARDINALITY       VARCHAR COMMENT 'Cardinality: many-to-one, one-to-many, one-to-zero-or-one.',
  PROCESS           VARCHAR COMMENT 'Process: load procedure or view that moves the data.',
  DESCRIPTION       VARCHAR COMMENT 'Description: what the relationship means.'
) COMMENT = 'How the AP model objects join and load into each other (supplementary, from the FSD).';

INSERT INTO KF_ASSET_RELATIONSHIPS (RELATIONSHIP_TYPE, FROM_OBJECT, TO_OBJECT, JOIN_COLUMNS, CARDINALITY, PROCESS, DESCRIPTION)
SELECT * FROM VALUES
('Join', '{{LANDING}}.SAP_BSEG', '{{LANDING}}.SAP_BKPF', 'BUKRS, BELNR, GJAHR', 'many-to-one', NULL, 'Document lines to their document header.'),
('Join', '{{LANDING}}.SAP_BSEG', '{{LANDING}}.SAP_LFA1', 'LIFNR', 'many-to-one', NULL, 'Vendor lines (KOART = K) to the vendor master.'),
('Join', '{{LANDING}}.SAP_BSEG', '{{LANDING}}.SAP_BSEC', 'BUKRS, BELNR, GJAHR, BUZEI', 'one-to-zero-or-one', NULL, 'Vendor line to its one-time vendor data (only for one-time vendor invoices).'),
('Join', '{{LANDING}}.SAP_BSEG', '{{LANDING}}.SAP_T001', 'BUKRS', 'many-to-one', NULL, 'Document lines to the company code.'),
('Join', '{{LANDING}}.SAP_LFA1', '{{LANDING}}.SAP_LFB1', 'LIFNR', 'one-to-many', NULL, 'Vendor to its company-code settings (payment terms, reconciliation account).'),
('Join', '{{LANDING}}.SAP_LFA1', '{{LANDING}}.SAP_LFBK', 'LIFNR', 'one-to-zero-or-one', NULL, 'Vendor to its bank details.'),
('Join', '{{LANDING}}.SAP_LFA1', '{{LANDING}}.SAP_T005T', 'LAND1 (SPRAS = E)', 'many-to-one', NULL, 'Vendor country key to country name.'),
('Join', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', '{{EDW}}.DIM_VENDOR', 'VENDOR_ID', 'many-to-one', NULL, 'AP line items to the vendor dimension.'),
('Join', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', '{{EDW}}.DIM_COMPANY_CODE', 'COMPANY_CODE', 'many-to-one', NULL, 'AP line items to the company code dimension.'),
('Join', '{{DATAMART}}.DM_AP_OPEN_ITEMS', '{{DATAMART}}.AP_AGING_BUCKETS', 'DAYS_PAST_DUE BETWEEN MIN_DAYS AND MAX_DAYS', 'many-to-one', NULL, 'Open items to their aging bucket (range join).'),
('Loads into', '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Vendor lines (KOART = K) become AP fact rows.'),
('Loads into', '{{LANDING}}.SAP_BKPF', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Header fields: document type, dates, currency, invoice reference.'),
('Loads into', '{{LANDING}}.SAP_BSEC', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', NULL, NULL, '{{EDW}}.LOAD_EDW', 'One-time payee name and country.'),
('Loads into', '{{LANDING}}.SAP_T005T', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Country names for one-time payees.'),
('Loads into', '{{LANDING}}.SAP_LFA1', '{{EDW}}.DIM_VENDOR', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Vendor master general data.'),
('Loads into', '{{LANDING}}.SAP_LFBK', '{{EDW}}.DIM_VENDOR', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Vendor bank details.'),
('Loads into', '{{LANDING}}.SAP_T005T', '{{EDW}}.DIM_VENDOR', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Vendor country names.'),
('Loads into', '{{LANDING}}.SAP_T001', '{{EDW}}.DIM_COMPANY_CODE', NULL, NULL, '{{EDW}}.LOAD_EDW', 'Company codes.'),
('Loads into', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Open items only (IS_OPEN_ITEM = TRUE), with aging.'),
('Loads into', '{{EDW}}.DIM_VENDOR', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Vendor name, country, one-time flag.'),
('Loads into', '{{EDW}}.DIM_COMPANY_CODE', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Company name and USD exchange rate.'),
('Loads into', '{{DATAMART}}.AP_AGING_BUCKETS', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Aging bucket of each open item.'),
('Loads into', '{{DATAMART}}.DM_AP_OPEN_ITEMS', '{{DATAMART}}.DM_AP_AGING_SUMMARY', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Aggregated by company code, vendor country and aging bucket.'),
('Loads into', '{{EDW}}.DIM_VENDOR', '{{DATAMART}}.DM_AP_VENDOR', NULL, NULL, '{{DATAMART}}.LOAD_AP_DATAMART', 'Vendor list for reporting.'),
('Loads into', '{{DATAMART}}.DM_AP_OPEN_ITEMS', '{{REPORTING}}.VW_AP_OPEN_ITEMS', NULL, NULL, 'View definition', 'Select and rename only.'),
('Loads into', '{{DATAMART}}.DM_AP_OPEN_ITEMS', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', NULL, NULL, 'View definition', 'Select, rename and key filter IS_OVERDUE = TRUE.'),
('Loads into', '{{DATAMART}}.DM_AP_AGING_SUMMARY', '{{REPORTING}}.VW_AP_AGING_SUMMARY', NULL, NULL, 'View definition', 'Select and rename only.'),
('Loads into', '{{DATAMART}}.DM_AP_VENDOR', '{{REPORTING}}.VW_AP_VENDOR', NULL, NULL, 'View definition', 'Select and rename only.');

-- ---------------------------------------------------------------------
-- 3. Business glossary (approved definitions; ready to move into a business ontology later)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_GLOSSARY (
  TERM             VARCHAR COMMENT 'Business term.',
  DEFINITION       VARCHAR COMMENT 'Definition: what the term means in business language.',
  CALCULATION      VARCHAR COMMENT 'Calculation: how the term is calculated, if it is a measure or derived field.',
  IMPLEMENTED_IN   VARCHAR COMMENT 'Implemented in: SCHEMA.OBJECT.COLUMN where the term lives.',
  SYNONYMS         VARCHAR COMMENT 'Synonyms: other words people use for the term.',
  OWNER            VARCHAR COMMENT 'Owner: accountable role for the definition.',
  STATUS           VARCHAR COMMENT 'Status: Approved or Draft (draft = not yet approved, do not treat as official).',
  APPROVED_ON      DATE    COMMENT 'Approved on: date the definition was approved.',
  SOURCE_DOCUMENT  VARCHAR COMMENT 'Source document: where the definition is written down.'
) COMMENT = 'AP business glossary. Approved terms are the official definitions.';

INSERT INTO KF_GLOSSARY
SELECT column1, column2, column3, column4, column5, column6, column7, TRY_TO_DATE(column8), column9 FROM VALUES
('AP Aging', 'Classification of open vendor items by how many days they are past their net due date, on a given as-of date.',
 'Days past due = as-of date - net due date; each open item gets the bucket whose range contains its days past due (AP_AGING_BUCKETS).',
 '{{DATAMART}}.DM_AP_OPEN_ITEMS.AGING_BUCKET', 'aging, ageing, AP ageing, invoice aging, payables aging', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3'),
('Aging Bucket', 'The six official aging buckets: Not yet due (0 or fewer days past due), 1-30, 31-60, 61-90, 91-180 and Over 180 days past due.',
 'AP_AGING_BUCKETS: MIN_DAYS <= DAYS_PAST_DUE <= MAX_DAYS.', '{{DATAMART}}.AP_AGING_BUCKETS.BUCKET_NAME', 'bucket, aging band, ageing bucket', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.2 (replaces the 4 buckets of v1.0)'),
('Days Past Due', 'Number of days an open item is past its net due date on the as-of date. Zero or negative means not yet due.',
 'DATEDIFF(day, NET_DUE_DATE, AS_OF_DATE).', '{{DATAMART}}.DM_AP_OPEN_ITEMS.DAYS_PAST_DUE', 'DPD, days overdue, days late', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.1'),
('Net Due Date', 'The date an invoice must be paid.', 'Baseline date + payment term days (SAP_BSEG.ZFBDT + ZBD1T).',
 '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL.NET_DUE_DATE', 'due date, payment due date', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.1'),
('As-of Date', 'The date on which aging is measured. In the datamart it is the date of the daily load.', 'CURRENT_DATE at datamart load.',
 '{{DATAMART}}.DM_AP_OPEN_ITEMS.AS_OF_DATE', 'aging date, key date, reporting date', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.1'),
('Open Item', 'A vendor line item that has not been paid or otherwise cleared.', 'Clearing date (SAP_BSEG.AUGDT) is empty.',
 '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL.IS_OPEN_ITEM', 'unpaid invoice, outstanding item, open payable', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 2'),
('One-time Vendor', 'A vendor account (account group CPD) used for occasional payees. The real payee name, country and tax number are captured on each invoice (SAP_BSEC), not in the vendor master.',
 'DIM_VENDOR.IS_ONE_TIME_VENDOR = (KTOKK = CPD).', '{{EDW}}.DIM_VENDOR.IS_ONE_TIME_VENDOR', 'CPD vendor, sundry vendor, one-off payee', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 5.2'),
('Vendor Country', 'Country of the vendor an invoice is owed to. For one-time vendors it is the payee country on the invoice; for all other vendors it is the vendor master country.',
 'IFF(IS_ONE_TIME_VENDOR, SAP_BSEC.LAND1, SAP_LFA1.LAND1), translated to a name with SAP_T005T.',
 '{{REPORTING}}.VW_AP_OPEN_ITEMS.VENDOR_COUNTRY', 'supplier country, vendor nation', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 5.2'),
('Open Amount (USD)', 'Open (unpaid) amount of an item converted to US dollars. Credit memos are negative.',
 'AMOUNT_LOCAL x company code USD exchange rate, rounded to 2 decimals.', '{{DATAMART}}.DM_AP_OPEN_ITEMS.AMOUNT_USD', 'open balance, outstanding amount, AP balance', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.3'),
('Overdue Amount', 'Open amount of items that are past their net due date.', 'SUM(AMOUNT_USD) WHERE DAYS_PAST_DUE > 0. Whether blocked items are excluded is still under review.',
 '{{DATAMART}}.DM_AP_OPEN_ITEMS.AMOUNT_USD', 'past due amount, late payables', 'AP Finance Data Owner (role)', 'Draft', NULL, 'BRD AP Aging v1.2, open question 2'),
('Payment Terms', 'Agreement on when an invoice is due, for example N30 = net 30 days after the baseline date; IMMD = due immediately.', NULL,
 '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL.PAYMENT_TERMS', 'terms, ZTERM', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 5.1'),
('Payment Block', 'A flag that stops an invoice from being paid, for example while it is disputed. A = blocked.', NULL,
 '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL.PAYMENT_BLOCK', 'blocked invoice, ZLSPR, hold', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 5.1'),
('Reconciliation Account', 'General ledger control account that collects all accounts payable postings of a vendor.', NULL,
 '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL.RECONCILIATION_ACCOUNT', 'AP control account, AKONT', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 5.1'),
('AP Datamart Refresh', 'The AP datamart is refreshed once a day, immediately after the EDW load that starts at 02:00 UTC. Reporting views always show the latest datamart load.', NULL,
 '{{EDW}}.TASK_LOAD_AP_DATAMART', 'refresh frequency, load schedule, data latency', 'AP Data Steward (role)', 'Approved', '2025-03-14', 'FSD AP Datamart v1.0, section 7');

ALTER TABLE KF_GLOSSARY ADD COLUMN TERM_TYPE VARCHAR COMMENT 'KPI (a measure with a calculation) or Business term.';
INSERT INTO KF_GLOSSARY (TERM, DEFINITION, CALCULATION, IMPLEMENTED_IN, SYNONYMS, OWNER, STATUS, APPROVED_ON, SOURCE_DOCUMENT)
SELECT column1, column2, column3, column4, column5, column6, column7, TRY_TO_DATE(column8), column9 FROM VALUES
('Open Item Count', 'Number of open vendor line items.', 'COUNT of open items per as-of date, company code, vendor country and aging bucket.',
 '{{DATAMART}}.DM_AP_AGING_SUMMARY.OPEN_ITEM_COUNT', 'number of open invoices, open items', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.6 (AP-R11)'),
('Aged Open Amount by Bucket (USD)', 'Open amount in USD per aging bucket: the main figure of the aging report.', 'SUM(AMOUNT_USD) per as-of date, company code, vendor country and aging bucket.',
 '{{DATAMART}}.DM_AP_AGING_SUMMARY.OPEN_AMOUNT_USD', 'aging amount, bucket amount, aged balance', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.6 (AP-R11)'),
('Average Days Past Due', 'Average number of days overdue items are past their net due date.', 'AVG(DAYS_PAST_DUE) WHERE DAYS_PAST_DUE > 0.',
 '{{DATAMART}}.DM_AP_OPEN_ITEMS.DAYS_PAST_DUE', 'average lateness, ADPD', 'AP Finance Data Owner (role)', 'Approved', '2025-03-14', 'BRD AP Aging v1.2, section 3.1');
UPDATE KF_GLOSSARY SET TERM_TYPE = IFF(TERM IN ('Open Amount (USD)', 'Overdue Amount', 'Open Item Count', 'Aged Open Amount by Bucket (USD)',
                                                'Average Days Past Due'), 'KPI', 'Business term');

-- ---------------------------------------------------------------------
-- 3b. Requirements and traceability (supplementary, from the BRD requirement list)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_REQUIREMENTS (
  REQ_ID           VARCHAR COMMENT 'Requirement ID, e.g. AP-R03.',
  TITLE            VARCHAR COMMENT 'Short title.',
  REQUIREMENT_TEXT VARCHAR COMMENT 'What the business needs.',
  SOURCE_DOCUMENT  VARCHAR COMMENT 'Document and section the requirement comes from.',
  PRIORITY         VARCHAR COMMENT 'Must / Should / Could.',
  STATUS           VARCHAR COMMENT 'Implemented, Partly implemented or Open.'
) COMMENT = 'AP reporting requirements (BRD AP Aging v1.2, section 3.6).';

INSERT INTO KF_REQUIREMENTS SELECT * FROM VALUES
('AP-R01', 'Open items for all company codes', 'Show every open vendor item of all company codes in one place.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R02', 'Days past due from net due date', 'Calculate days past due from the net due date (baseline date + payment term days), not from the invoice date.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R03', 'Six aging buckets', 'Assign every open item to exactly one of the six approved aging buckets.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R04', 'Local currency and USD', 'Show open amounts in company code currency and in USD using the company code exchange rate.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R05', 'Credit memos reduce the balance', 'Credit memos are included as negative open amounts.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R06', 'Payment blocks flagged', 'Items with a payment block are included and flagged.', 'BRD AP Aging v1.2, 3.6', 'Should', 'Implemented'),
('AP-R07', 'One-time vendor payee details', 'For one-time vendors use the payee name and country captured on the invoice.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R08', 'Vendor payment terms', 'Apply the vendor payment terms of the company code to calculate the due date.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R09', 'Daily refresh by 04:00 UTC', 'The AP datamart is refreshed daily and available by 04:00 UTC.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R10', 'Mask restricted vendor data', 'Mask tax numbers, bank accounts and one-time payee names for business users.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R11', 'Aging summary', 'Summarise open amount and item count by company code, vendor country and aging bucket.', 'BRD AP Aging v1.2, 3.6', 'Must', 'Implemented'),
('AP-R12', 'Overdue amount excluding blocked items', 'Show the overdue amount, possibly excluding blocked items (definition still open).', 'BRD AP Aging v1.2, 5 (open question 2)', 'Could', 'Open');

CREATE OR REPLACE TABLE KF_REQUIREMENT_TRACE (
  TRACE_ID     NUMBER AUTOINCREMENT COMMENT 'Trace row ID.',
  REQ_ID       VARCHAR COMMENT 'Requirement ID.',
  OBJECT_KEY   VARCHAR COMMENT 'SCHEMA.OBJECT that implements or supports the requirement (or the task / policy).',
  COLUMN_NAME  VARCHAR COMMENT 'Column, if the trace is at column level.',
  TRACE_TYPE   VARCHAR COMMENT 'Implements (logic lives here) or Exposes (shown to users here).'
) COMMENT = 'Traceability: which objects and columns implement or expose each requirement.';

INSERT INTO KF_REQUIREMENT_TRACE (REQ_ID, OBJECT_KEY, COLUMN_NAME, TRACE_TYPE) SELECT * FROM VALUES
('AP-R01', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, 'Implements'), ('AP-R01', '{{REPORTING}}.VW_AP_OPEN_ITEMS', NULL, 'Exposes'),
('AP-R01', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'IS_OPEN_ITEM', 'Implements'),
('AP-R02', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'NET_DUE_DATE', 'Implements'), ('AP-R02', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', 'Implements'),
('AP-R02', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', 'Exposes'),
('AP-R03', '{{DATAMART}}.AP_AGING_BUCKETS', NULL, 'Implements'), ('AP-R03', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AGING_BUCKET', 'Implements'),
('AP-R03', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'AGING_BUCKET', 'Exposes'), ('AP-R03', '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'AGING_BUCKET', 'Exposes'),
('AP-R04', '{{EDW}}.DIM_COMPANY_CODE', 'USD_EXCHANGE_RATE', 'Implements'), ('AP-R04', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', 'Implements'),
('AP-R04', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'OPEN_AMOUNT_USD', 'Exposes'),
('AP-R05', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', 'Implements'),
('AP-R06', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_BLOCK', 'Implements'), ('AP-R06', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'PAYMENT_BLOCK', 'Exposes'),
('AP-R07', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_NAME', 'Implements'),
('AP-R07', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_COUNTRY_NAME', 'Implements'), ('AP-R07', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'VENDOR_NAME', 'Implements'),
('AP-R07', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'VENDOR_COUNTRY', 'Exposes'),
('AP-R08', '{{LANDING}}.SAP_LFB1', 'ZTERM', 'Implements'), ('AP-R08', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_TERMS', 'Implements'),
('AP-R08', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_TERMS_DAYS', 'Implements'),
('AP-R09', '{{EDW}}.TASK_LOAD_AP_DATAMART', NULL, 'Implements'), ('AP-R09', '{{EDW}}.TASK_LOAD_EDW', NULL, 'Implements'),
('AP-R10', '{{GOVERNANCE}}.MASK_TAX_ID', NULL, 'Implements'), ('AP-R10', '{{GOVERNANCE}}.MASK_BANK_ACCOUNT', NULL, 'Implements'),
('AP-R10', '{{GOVERNANCE}}.MASK_ONE_TIME_PAYEE_NAME', NULL, 'Implements'), ('AP-R10', '{{REPORTING}}.VW_AP_VENDOR', 'TAX_ID', 'Exposes'),
('AP-R10', '{{REPORTING}}.VW_AP_VENDOR', 'BANK_ACCOUNT', 'Exposes'),
('AP-R03', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'AGING_BUCKET', 'Exposes'), ('AP-R06', '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'PAYMENT_BLOCK', 'Exposes'),
('AP-R11', '{{DATAMART}}.DM_AP_AGING_SUMMARY', NULL, 'Implements'), ('AP-R11', '{{REPORTING}}.VW_AP_AGING_SUMMARY', NULL, 'Exposes');

-- ---------------------------------------------------------------------
-- 3c. Mapping change log (supplementary): what changed, why, and how it was reviewed
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_MAPPING_CHANGE_LOG (
  CHANGE_ID          VARCHAR COMMENT 'Change ID.',
  CHANGE_DATE        DATE    COMMENT 'Date of the change.',
  MAPPING_VERSION    VARCHAR COMMENT 'Mapping sheet version after the change.',
  TARGET_OBJECT      VARCHAR COMMENT 'Object changed (SCHEMA.OBJECT).',
  TARGET_COLUMN      VARCHAR COMMENT 'Column changed (empty = whole object).',
  CHANGE_TYPE        VARCHAR COMMENT 'New mapping, Source change, Rule change, Correction, Security.',
  CHANGE_DESCRIPTION VARCHAR COMMENT 'What changed.',
  REASON             VARCHAR COMMENT 'Why it changed.',
  RELATED_REQ        VARCHAR COMMENT 'Requirement ID(s) behind the change.',
  PREPARED_BY        VARCHAR COMMENT 'Who prepared it (role).',
  REVIEWED_BY        VARCHAR COMMENT 'Who reviewed it (role) and at which gate.',
  APPROVED_BY        VARCHAR COMMENT 'Who approved the release (role).',
  STATUS             VARCHAR COMMENT 'Released, Proposed.'
) COMMENT = 'Change history of the AP mapping sheet with reason, review gate and approval.';

INSERT INTO KF_MAPPING_CHANGE_LOG SELECT column1, TRY_TO_DATE(column2), column3, column4, column5, column6, column7, column8, column9, column10, column11, column12, column13 FROM VALUES
('CHG-001', '2024-07-15', '0.9', '{{DATAMART}}.DM_AP_OPEN_ITEMS', NULL, 'New mapping',
 'First mapping sheet drafted from FSD draft 0.8: landing -> EDW -> datamart for all AP open item fields.',
 'Initial build of the AP datamart.', 'AP-R01, AP-R02, AP-R04', 'Data Engineer (role)', 'AP Data Steward (role), Gate 1 design review',
 'AP Finance Data Owner (role)', 'Released'),
('CHG-002', '2024-09-20', '1.0', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'ONE_TIME_VENDOR_COUNTRY_CODE', 'Correction',
 'Source of one-time vendor country changed from SAP_BSEG to SAP_BSEC.LAND1 (joined on BUKRS, BELNR, GJAHR, BUZEI).',
 'UAT defect: one-time vendor invoices showed an empty vendor country. The payee details are stored in BSEC, not BSEG.', 'AP-R07',
 'Data Engineer (role)', 'AP Data Steward (role), Gate 2 test sign-off', 'AP Finance Data Owner (role)', 'Released'),
('CHG-003', '2024-11-18', '1.1', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'DAYS_PAST_DUE', 'Rule change',
 'Days past due now calculated from NET_DUE_DATE instead of DOCUMENT_DATE; bucket Not yet due added.',
 'BRD v1.1: aging must reflect payment terms, otherwise invoices on long terms look overdue.', 'AP-R02, AP-R08',
 'Data Engineer (role)', 'AP Data Steward (role), Gate 2 test sign-off', 'AP Finance Data Owner (role)', 'Released'),
('CHG-004', '2025-03-14', '1.2', '{{DATAMART}}.AP_AGING_BUCKETS', NULL, 'Rule change',
 'Bucket 90+ split into 91-180 and Over 180 (six buckets).', 'BRD v1.2: very old items need separate follow-up for dispute or write-off.',
 'AP-R03', 'AP Data Steward (role)', 'AP Data Steward (role), Gate 1 design review; Gate 2 test sign-off', 'AP Finance Data Owner (role)', 'Released'),
('CHG-005', '2025-03-14', '1.2', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', 'Source change',
 'Exchange rate source moved from a landing currency table to EDW.DIM_COMPANY_CODE.USD_EXCHANGE_RATE.',
 'One governed rate per company code in the EDW, so every report converts the same way.', 'AP-R04',
 'Data Engineer (role)', 'AP Data Steward (role), Gate 2 test sign-off', 'AP Finance Data Owner (role)', 'Released'),
('CHG-006', '2025-06-02', '1.3', '{{REPORTING}}.VW_AP_VENDOR', 'TAX_ID', 'Security',
 'View-level masking policy removed; the column now inherits masking from AP_DATAMART.DM_AP_VENDOR.VENDOR_TAX_ID.',
 'Avoid double masking and keep one policy per sensitive field (governance standard v1.1).', 'AP-R10',
 'Data Engineer (role)', 'AP Data Steward (role), Gate 2 test sign-off', 'AP Finance Data Owner (role)', 'Released'),
('CHG-007', '2025-09-10', '1.4 (proposed)', '{{DATAMART}}.DM_AP_OPEN_ITEMS', 'AMOUNT_USD', 'Rule change',
 'Proposed: add OVERDUE_AMOUNT_USD excluding items with a payment block.', 'Open question 2 in BRD v1.2.', 'AP-R12',
 'AP Data Steward (role)', 'Not yet reviewed', NULL, 'Proposed');

-- ---------------------------------------------------------------------
-- 3d. Who uses the reporting layer (dashboards, extracts) - needed for impact analysis
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_REPORT_USAGE (
  CONSUMER_NAME VARCHAR COMMENT 'Dashboard, report or extract name.',
  CONSUMER_TYPE VARCHAR COMMENT 'Dashboard, Report or Extract.',
  TOOL          VARCHAR COMMENT 'Where it runs (BI tool, file transfer).',
  AUDIENCE      VARCHAR COMMENT 'Who uses it.',
  OWNER         VARCHAR COMMENT 'Owner (role).',
  FREQUENCY     VARCHAR COMMENT 'How often it is used / produced.',
  OBJECT_KEY    VARCHAR COMMENT 'Reporting view it reads (SCHEMA.OBJECT).',
  COLUMN_NAME   VARCHAR COMMENT 'Column it reads.',
  USAGE         VARCHAR COMMENT 'Measure, Dimension, Filter or Output field.'
) COMMENT = 'Downstream consumers of the AP reporting views, one row per consumer and column.';

INSERT INTO KF_REPORT_USAGE
SELECT c.column1, c.column2, c.column3, c.column4, c.column5, c.column6, c.column7, TRIM(f.value::STRING), c.column8
FROM (SELECT * FROM VALUES
  ('AP Aging Dashboard', 'Dashboard', 'BI tool', 'AP managers, controllers', 'AP Finance Data Owner (role)', 'Daily',
   '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'Measure', 'OPEN_AMOUNT_USD,OPEN_ITEM_COUNT'),
  ('AP Aging Dashboard', 'Dashboard', 'BI tool', 'AP managers, controllers', 'AP Finance Data Owner (role)', 'Daily',
   '{{REPORTING}}.VW_AP_AGING_SUMMARY', 'Dimension', 'AGING_BUCKET,VENDOR_COUNTRY,COMPANY_NAME'),
  ('AP Open Items Worklist', 'Dashboard', 'BI tool', 'AP clerks', 'AP Data Steward (role)', 'Daily',
   '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'Output field',
   'VENDOR_NAME,VENDOR_COUNTRY,INVOICE_REFERENCE,NET_DUE_DATE,DAYS_PAST_DUE,AGING_BUCKET,PAYMENT_BLOCK,OPEN_AMOUNT_LOCAL,OPEN_AMOUNT_USD'),
  ('Treasury Weekly AP Extract', 'Extract', 'Secure file transfer (CSV)', 'Treasury cash forecasting', 'AP Finance Data Owner (role)',
   'Weekly, Monday 05:00 UTC', '{{REPORTING}}.VW_AP_OPEN_ITEMS', 'Output field',
   'COMPANY_CODE,VENDOR_ID,NET_DUE_DATE,OPEN_AMOUNT_LOCAL,LOCAL_CURRENCY,OPEN_AMOUNT_USD'),
  ('Vendor Master Audit Report', 'Report', 'BI tool', 'Internal audit, AP power users', 'AP Data Steward (role)', 'Monthly',
   '{{REPORTING}}.VW_AP_VENDOR', 'Output field', 'VENDOR_ID,VENDOR_NAME,VENDOR_COUNTRY,TAX_ID,BANK_ACCOUNT,IS_DELETED'),
  ('AP Overdue Follow-up Report', 'Report', 'BI tool', 'AP clerks, collections follow-up', 'AP Data Steward (role)', 'Daily',
   '{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'Output field',
   'VENDOR_NAME,VENDOR_COUNTRY,INVOICE_REFERENCE,DAYS_PAST_DUE,AGING_BUCKET,PAYMENT_BLOCK,OPEN_AMOUNT_USD')
) c, LATERAL FLATTEN(input => SPLIT(c.column9, ',')) f;

-- ---------------------------------------------------------------------
-- 3e. Key filters: filters built into the model and filters used by the reports
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_KEY_FILTERS (
  FILTER_ID     NUMBER AUTOINCREMENT COMMENT 'Filter ID.',
  OBJECT_KEY    VARCHAR COMMENT 'Reporting view the filter applies to (SCHEMA.OBJECT).',
  COLUMN_NAME   VARCHAR COMMENT 'Column filtered on.',
  FILTER_RULE   VARCHAR COMMENT 'The filter in plain words.',
  APPLIED_IN    VARCHAR COMMENT 'EDW load, Datamart load, View definition or Report.',
  CONSUMER_NAME VARCHAR COMMENT 'Report / extract that applies it (for report filters).'
) COMMENT = 'Key filters per reporting view: in the load, in the view, and in the reports that use it.';

INSERT INTO KF_KEY_FILTERS (OBJECT_KEY, COLUMN_NAME, FILTER_RULE, APPLIED_IN, CONSUMER_NAME) SELECT * FROM VALUES
('{{REPORTING}}.VW_AP_OPEN_ITEMS', 'KOART', 'Only vendor lines (account type K) of SAP_BSEG', 'EDW load', NULL),
('{{REPORTING}}.VW_AP_OPEN_ITEMS', 'IS_OPEN_ITEM', 'Only open (not cleared) items; cleared items are excluded in the datamart load', 'Datamart load', NULL),
('{{REPORTING}}.VW_AP_OPEN_ITEMS', 'PAYMENT_BLOCK', 'Blocked items (A) shown on a separate tab', 'Report', 'AP Open Items Worklist'),
('{{REPORTING}}.VW_AP_OPEN_ITEMS', 'NET_DUE_DATE', 'Items due in the next 90 days only', 'Report', 'Treasury Weekly AP Extract'),
('{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'KOART', 'Only vendor lines (account type K) of SAP_BSEG', 'EDW load', NULL),
('{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'IS_OPEN_ITEM', 'Only open (not cleared) items', 'Datamart load', NULL),
('{{REPORTING}}.VW_AP_OVERDUE_ITEMS', 'IS_OVERDUE', 'IS_OVERDUE = TRUE (days past due > 0)', 'View definition', NULL),
('{{REPORTING}}.VW_AP_AGING_SUMMARY', 'IS_OPEN_ITEM', 'Only open items are summarised', 'Datamart load', NULL),
('{{REPORTING}}.VW_AP_AGING_SUMMARY', 'AS_OF_DATE', 'Latest as-of date only', 'Report', 'AP Aging Dashboard'),
('{{REPORTING}}.VW_AP_AGING_SUMMARY', 'AGING_BUCKET', 'Default view hides Not yet due', 'Report', 'AP Aging Dashboard'),
('{{REPORTING}}.VW_AP_AGING_SUMMARY', 'COMPANY_CODE', 'User selects one or more company codes', 'Report', 'AP Aging Dashboard'),
('{{REPORTING}}.VW_AP_VENDOR', 'IS_DELETED', 'Vendors marked for deletion are excluded by default', 'Report', 'Vendor Master Audit Report');

-- ---------------------------------------------------------------------
-- 3f. PHASE 2 PREVIEW: SAP T-codes -> SAP tables and fields -> EDW (standard SAP names, synthetic mapping status)
--     Answers: "a request mentions T-code X - do we already have the data, or do we need new replication?"
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_SAP_TCODE_MAP (
  MAP_ID                NUMBER AUTOINCREMENT COMMENT 'Row ID.',
  TCODE                 VARCHAR COMMENT 'SAP transaction code.',
  TCODE_DESCRIPTION     VARCHAR COMMENT 'What the transaction is used for.',
  BUSINESS_PROCESS      VARCHAR COMMENT 'Business process the transaction belongs to.',
  SAP_TABLE             VARCHAR COMMENT 'SAP table behind the transaction.',
  SAP_TABLE_DESCRIPTION VARCHAR COMMENT 'SAP table description.',
  SAP_FIELD             VARCHAR COMMENT 'SAP field.',
  SAP_FIELD_DESCRIPTION VARCHAR COMMENT 'SAP field description.',
  IS_INGESTED           BOOLEAN COMMENT 'TRUE if the field is already replicated into the landing layer.',
  LANDING_OBJECT        VARCHAR COMMENT 'Landing table holding the field, if ingested.',
  RELATED_EDW_OBJECT    VARCHAR COMMENT 'EDW / datamart object that models the field, if any.',
  RELATED_EDW_COLUMN    VARCHAR COMMENT 'EDW / datamart column that models the field, if any.',
  MAPPING_STATUS        VARCHAR COMMENT 'Validated (modelled in EDW), Ingested - not modelled, Not ingested.',
  MAPPING_OWNER         VARCHAR COMMENT 'Who validates the mapping (role).',
  NOTE                  VARCHAR COMMENT 'What to do if the field is needed.'
) COMMENT = 'Phase 2 preview: SAP T-code to SAP table/field to EDW mapping with ingestion and validation status.';

INSERT INTO KF_SAP_TCODE_MAP (TCODE, TCODE_DESCRIPTION, BUSINESS_PROCESS, SAP_TABLE, SAP_TABLE_DESCRIPTION, SAP_FIELD,
                              SAP_FIELD_DESCRIPTION, IS_INGESTED, LANDING_OBJECT, RELATED_EDW_OBJECT, RELATED_EDW_COLUMN,
                              MAPPING_STATUS, MAPPING_OWNER, NOTE)
SELECT column1, column2, column3, column4, column5, column6, column7, column8, column9, column10, column11, column12,
       'AP Data Steward (role)', column13 FROM VALUES
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items); FBL1N reads it through the vendor indexes BSIK/BSAK', 'LIFNR', 'Account number of vendor', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'VENDOR_ID', 'Validated', 'Reuse the EDW fact.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items)', 'DMBTR', 'Amount in local currency', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'AMOUNT_LOCAL', 'Validated', 'Reuse; sign comes from SHKZG.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items)', 'ZFBDT', 'Baseline date for due date calculation', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'BASELINE_DATE', 'Validated', 'Reuse.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items)', 'AUGDT', 'Clearing date', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'CLEARING_DATE', 'Validated', 'Reuse; empty = open item.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items)', 'ZLSPR', 'Payment block key', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'PAYMENT_BLOCK', 'Validated', 'Reuse.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BKPF', 'Accounting document header', 'XBLNR', 'Reference document number (vendor invoice number)', TRUE, '{{LANDING}}.SAP_BKPF', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'INVOICE_REFERENCE', 'Validated', 'Reuse.'),
('FBL1N', 'Vendor line item display (open and cleared items)', 'Invoice-to-pay / AP reporting', 'BSEG', 'Accounting document segment (line items)', 'ZUONR', 'Assignment number', FALSE, NULL, NULL, NULL, 'Not ingested', 'New replication needed: add BSEG.ZUONR to the replication, then map it into the fact.'),
('FB03', 'Display accounting document', 'General ledger / AP', 'BKPF', 'Accounting document header', 'BLART', 'Document type', TRUE, '{{LANDING}}.SAP_BKPF', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'DOCUMENT_TYPE', 'Validated', 'Reuse.'),
('FB03', 'Display accounting document', 'General ledger / AP', 'BKPF', 'Accounting document header', 'BUDAT', 'Posting date in the document', TRUE, '{{LANDING}}.SAP_BKPF', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'POSTING_DATE', 'Validated', 'Reuse.'),
('FB03', 'Display accounting document', 'General ledger / AP', 'BKPF', 'Accounting document header', 'USNAM', 'User name (who posted)', TRUE, '{{LANDING}}.SAP_BKPF', NULL, NULL, 'Ingested - not modelled', 'No new replication: already in landing; extend the EDW fact if needed.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFA1', 'Vendor master (general section)', 'NAME1', 'Name 1', TRUE, '{{LANDING}}.SAP_LFA1', '{{EDW}}.DIM_VENDOR', 'VENDOR_NAME', 'Validated', 'Reuse.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFA1', 'Vendor master (general section)', 'LAND1', 'Country key', TRUE, '{{LANDING}}.SAP_LFA1', '{{EDW}}.DIM_VENDOR', 'VENDOR_COUNTRY_CODE', 'Validated', 'Reuse; one-time vendors take the country from BSEC.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFA1', 'Vendor master (general section)', 'STCD1', 'Tax number 1', TRUE, '{{LANDING}}.SAP_LFA1', '{{EDW}}.DIM_VENDOR', 'VENDOR_TAX_ID', 'Validated', 'Reuse; restricted and masked.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFA1', 'Vendor master (general section)', 'TELF1', 'First telephone number', FALSE, NULL, NULL, NULL, 'Not ingested', 'New replication needed; personal data: needs a masking decision first.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFB1', 'Vendor master (company code)', 'ZTERM', 'Terms of payment key', TRUE, '{{LANDING}}.SAP_LFB1', NULL, NULL, 'Ingested - not modelled', 'No new replication. The fact uses the terms copied to the invoice line (BSEG.ZTERM); vendor default terms are not modelled.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFB1', 'Vendor master (company code)', 'ZWELS', 'List of payment methods to be considered', TRUE, '{{LANDING}}.SAP_LFB1', NULL, NULL, 'Ingested - not modelled', 'No new replication: already in landing; extend DIM_VENDOR (per company code) if needed.'),
('FK03', 'Display vendor (accounting view)', 'Vendor master data', 'LFBK', 'Vendor master (bank details)', 'BANKN', 'Bank account number', TRUE, '{{LANDING}}.SAP_LFBK', '{{EDW}}.DIM_VENDOR', 'VENDOR_BANK_ACCOUNT', 'Validated', 'Reuse; restricted and masked.'),
('F110', 'Automatic payment run', 'Invoice-to-pay / payment', 'BSEG', 'Accounting document segment (line items)', 'AUGBL', 'Document number of the clearing document', TRUE, '{{LANDING}}.SAP_BSEG', '{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL', 'CLEARING_DOCUMENT', 'Validated', 'Reuse.'),
('F110', 'Automatic payment run', 'Invoice-to-pay / payment', 'REGUH', 'Settlement data from the payment program', 'LAUFD', 'Date on which the payment program is run', FALSE, NULL, NULL, NULL, 'Not ingested', 'New replication needed for payment run analysis.'),
('MIRO', 'Enter incoming invoice (logistics invoice verification)', 'Invoice-to-pay / invoice receipt', 'RBKP', 'Document header: invoice receipt', 'BELNR', 'Document number of an invoice document', FALSE, NULL, NULL, NULL, 'Not ingested', 'Not replicated; the posted FI document (BKPF/BSEG) is available instead.'),
('ME23N', 'Display purchase order', 'Procure-to-pay / matching', 'EKKO', 'Purchasing document header', 'EBELN', 'Purchasing document number', FALSE, NULL, NULL, NULL, 'Not ingested', 'New replication needed for three-way match analysis.'),
('FK10N', 'Vendor balance display', 'AP reporting / period-end close', 'LFC1', 'Vendor master (transaction figures)', 'UMSAV', 'Balance carried forward', FALSE, NULL, NULL, NULL, 'Not ingested', 'Not replicated; open-item balances can be derived from the AP fact instead.');

-- ---------------------------------------------------------------------
-- 4. Output tables (filled by REFRESH_KNOWLEDGE_FABRIC)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KF_OBJECTS (
  OBJECT_KEY VARCHAR COMMENT 'Object key: SCHEMA.OBJECT.', OBJECT_NAME VARCHAR COMMENT 'Object name.',
  SCHEMA_NAME VARCHAR COMMENT 'Schema name.', OBJECT_TYPE VARCHAR COMMENT 'Object type: Table or View.',
  DATA_LAYER VARCHAR COMMENT 'Data layer: Landing, EDW, Datamart or Reporting.', LAYER_ORDER NUMBER COMMENT 'Layer order: 1 Landing .. 4 Reporting.',
  DESCRIPTION VARCHAR COMMENT 'Description: object comment in Snowflake.', HAS_DESCRIPTION BOOLEAN COMMENT 'TRUE if the object has a comment.',
  AI_SUGGESTED_DESCRIPTION VARCHAR COMMENT 'AI suggested description (draft, needs steward approval) when the comment is missing.',
  ROW_COUNT NUMBER COMMENT 'Row count (tables only).', COLUMN_COUNT NUMBER COMMENT 'Number of columns.',
  MASKED_COLUMN_COUNT NUMBER COMMENT 'Number of masked columns (direct or inherited).', UNDOCUMENTED_COLUMN_COUNT NUMBER COMMENT 'Number of columns without a description.',
  DATA_DOMAIN VARCHAR COMMENT 'Data domain tag.', DATA_PRODUCT VARCHAR COMMENT 'Data product tag.', SOURCE_SYSTEM VARCHAR COMMENT 'Source system tag.',
  REFRESH_FREQUENCY VARCHAR COMMENT 'Refresh frequency tag.', REFRESHED_BY_TASK VARCHAR COMMENT 'Task that refreshes the object, if any.',
  DATA_OWNER VARCHAR COMMENT 'Data owner tag.', DATA_STEWARD VARCHAR COMMENT 'Data steward tag.', CERTIFICATION VARCHAR COMMENT 'Certification tag.',
  CREATED_AT TIMESTAMP_LTZ COMMENT 'Created at.', LAST_ALTERED TIMESTAMP_LTZ COMMENT 'Last changed (data or structure).',
  KF_REFRESHED_AT TIMESTAMP_LTZ COMMENT 'When the Knowledge Fabric read this metadata.',
  DATABASE_NAME VARCHAR COMMENT 'Database.', DATA_CLASS VARCHAR COMMENT 'Transaction, master, reference or aggregated data.',
  TECHNICAL_OWNER VARCHAR COMMENT 'Technical owner (team role).',
  UPSTREAM_OBJECTS VARCHAR COMMENT 'Objects this object is loaded from.', DOWNSTREAM_OBJECTS VARCHAR COMMENT 'Objects loaded from this object.'
) COMMENT = 'One row per table/view of the AP model, from Snowflake metadata.';

CREATE OR REPLACE TABLE KF_COLUMNS (
  COLUMN_KEY VARCHAR COMMENT 'Column key: SCHEMA.OBJECT.COLUMN.', OBJECT_KEY VARCHAR COMMENT 'Object key: SCHEMA.OBJECT.',
  SCHEMA_NAME VARCHAR, OBJECT_NAME VARCHAR, DATA_LAYER VARCHAR, COLUMN_NAME VARCHAR, ORDINAL_POSITION NUMBER, DATA_TYPE VARCHAR,
  BUSINESS_NAME VARCHAR COMMENT 'Business name: text before the colon in the column comment.',
  DESCRIPTION VARCHAR COMMENT 'Description: column comment in Snowflake.', HAS_DESCRIPTION BOOLEAN,
  SENSITIVITY VARCHAR COMMENT 'Sensitivity tag (Internal, Confidential, Restricted).',
  SEMANTIC_CATEGORY VARCHAR COMMENT 'Snowflake classification semantic category, if classified.',
  PRIVACY_CATEGORY VARCHAR COMMENT 'Snowflake classification privacy category, if classified.',
  MASKING_POLICY VARCHAR COMMENT 'Masking policy set directly on the column.',
  IS_MASKED BOOLEAN COMMENT 'TRUE if the column is masked directly or inherits masking from an upstream column.',
  MASKED_VIA VARCHAR COMMENT 'Upstream column whose masking policy applies (for views).',
  AI_SUGGESTED_DESCRIPTION VARCHAR COMMENT 'AI suggested description (draft) when the comment is missing.',
  SUGGESTION_STATUS VARCHAR COMMENT 'Status of the AI suggestion.',
  KF_REFRESHED_AT TIMESTAMP_LTZ,
  DATA_TYPE_FULL VARCHAR COMMENT 'Data type with length / precision, e.g. VARCHAR(10), NUMBER(15,2).',
  CHARACTER_LIMIT NUMBER COMMENT 'Maximum number of characters (text columns).',
  KEY_ROLE VARCHAR COMMENT 'Primary key or Business key (from constraints on tables, KEY_ROLE tag on views).',
  TECHNICAL_DESCRIPTION VARCHAR COMMENT 'Technical description: data type, key, SAP field, masking and source / transformation.'
) COMMENT = 'One row per column of the AP model, from Snowflake metadata (comments, tags, masking).';

CREATE OR REPLACE TABLE KF_LINEAGE_PATHS (
  PATH_STEP_ID NUMBER COMMENT 'Step ID.', REPORT_OBJECT VARCHAR COMMENT 'Reporting object the path starts from.',
  REPORT_COLUMN VARCHAR COMMENT 'Reporting column the path starts from.', HOP NUMBER COMMENT 'Hop: 1 = reporting <- datamart, higher = further upstream.',
  TARGET_OBJECT VARCHAR, TARGET_COLUMN VARCHAR, SOURCE_OBJECT VARCHAR, SOURCE_COLUMN VARCHAR,
  SOURCE_LAYER VARCHAR COMMENT 'Layer of the source object.', MAPPING_TYPE VARCHAR, TRANSFORMATION_RULE VARCHAR,
  IS_ORIGIN BOOLEAN COMMENT 'TRUE when the source column has no further upstream mapping (the system of record).'
) COMMENT = 'Field lineage walked from every reporting column back to the SAP landing columns (from the mapping sheet).';

CREATE OR REPLACE TABLE KF_REFRESH_SCHEDULE (
  TASK_NAME VARCHAR COMMENT 'Task name.', SCHEMA_NAME VARCHAR, SCHEDULE VARCHAR COMMENT 'Schedule (CRON) or empty when it runs after another task.',
  RUNS_AFTER VARCHAR COMMENT 'Predecessor task.', STATE VARCHAR COMMENT 'started or suspended.', WAREHOUSE VARCHAR,
  REFRESHES_OBJECTS VARCHAR COMMENT 'Objects the task refreshes.', DESCRIPTION VARCHAR, DEFINITION VARCHAR
) COMMENT = 'Refresh jobs of the AP model, read live from the Snowflake tasks.';

CREATE OR REPLACE TABLE KF_IMPACT (
  IMPACT_ID NUMBER COMMENT 'Row ID.', CHANGED_OBJECT VARCHAR COMMENT 'Object that would change (SCHEMA.OBJECT).',
  CHANGED_COLUMN VARCHAR COMMENT 'Column that would change.', CHANGED_LAYER VARCHAR COMMENT 'Layer of the changed object.',
  AFFECTED_TYPE VARCHAR COMMENT 'Column, Dashboard, Report or Extract.',
  AFFECTED_OBJECT VARCHAR COMMENT 'Downstream object (SCHEMA.OBJECT) or consumer name.',
  AFFECTED_COLUMN VARCHAR COMMENT 'Downstream column (for consumers: the reporting column they read).',
  AFFECTED_LAYER VARCHAR COMMENT 'EDW, Datamart, Reporting or Consumer.', DISTANCE NUMBER COMMENT 'Steps downstream.',
  IMPACT_PATH VARCHAR COMMENT 'Path from the changed column to the affected item.', OWNER VARCHAR COMMENT 'Owner of an affected consumer.'
) COMMENT = 'Downstream impact: for every column, every column, report and extract that depends on it (from the mapping sheet and report usage).';

CREATE OR REPLACE TABLE KF_SYSTEM_LINEAGE (
  LINEAGE_FOR VARCHAR COMMENT 'Object or column the lineage was requested for.', DIRECTION VARCHAR,
  SOURCE_OBJECT VARCHAR, TARGET_OBJECT VARCHAR, DISTANCE NUMBER, SOURCE_DOMAIN VARCHAR, RAW VARCHAR
) COMMENT = 'Lineage recorded by Snowflake itself (SNOWFLAKE.CORE.GET_LINEAGE). Can take up to a few hours to appear after loads.';

CREATE TABLE IF NOT EXISTS KF_DESCRIPTION_SUGGESTIONS (
  ASSET_KEY VARCHAR COMMENT 'SCHEMA.OBJECT or SCHEMA.OBJECT.COLUMN.', ASSET_TYPE VARCHAR,
  SUGGESTION VARCHAR COMMENT 'AI drafted description.', MODEL VARCHAR, SUGGESTED_AT TIMESTAMP_LTZ,
  STATUS VARCHAR COMMENT 'Suggested - awaiting steward approval / Approved / Rejected.'
) COMMENT = 'AI_COMPLETE drafts for objects and columns that have no description. A steward approves them before they become comments.';

CREATE OR REPLACE TABLE KF_CATALOG (
  ASSET_ID VARCHAR COMMENT 'Unique ID of the catalog entry.', ASSET_TYPE VARCHAR COMMENT 'Table, View, Column, Business term, Relationship or Refresh job.',
  ASSET_NAME VARCHAR, DATA_LAYER VARCHAR, OBJECT_NAME VARCHAR, COLUMN_NAME VARCHAR, BUSINESS_NAME VARCHAR,
  SEARCH_TEXT VARCHAR COMMENT 'Everything known about the asset, as text, for Cortex Search.'
) COMMENT = 'One searchable text entry per object, column, business term, relationship and refresh job.';

-- Raw metadata collected by the procedure (strings only)
CREATE OR REPLACE TABLE KF_RAW_TAGS (OBJECT_KEY VARCHAR, COLUMN_NAME VARCHAR, TAG_DATABASE VARCHAR, TAG_NAME VARCHAR, TAG_VALUE VARCHAR, LEVEL_RANK VARCHAR);
CREATE OR REPLACE TABLE KF_RAW_POLICIES (OBJECT_KEY VARCHAR, COLUMN_NAME VARCHAR, POLICY_NAME VARCHAR, POLICY_KIND VARCHAR);
CREATE OR REPLACE TABLE KF_RAW_KEYS (OBJECT_KEY VARCHAR, COLUMN_NAME VARCHAR, KEY_TYPE VARCHAR, KEY_SEQUENCE VARCHAR);
CREATE OR REPLACE TABLE KF_REPORTING_VIEWS (
  VIEW_KEY VARCHAR COMMENT 'SCHEMA.VIEW.', DATABASE_NAME VARCHAR, SCHEMA_NAME VARCHAR, VIEW_NAME VARCHAR,
  VIEW_DESCRIPTION VARCHAR COMMENT 'Model / view description.', DATA_CLASS VARCHAR COMMENT 'Transaction / master / reference / aggregated.',
  PORTFOLIO_DOMAIN VARCHAR COMMENT 'Portfolio / domain.', DATA_PRODUCT VARCHAR, DATA_OWNER VARCHAR COMMENT 'Data / model owner.',
  TECHNICAL_OWNER VARCHAR, DATA_STEWARD VARCHAR, CERTIFICATION VARCHAR,
  REFRESH_FREQUENCY VARCHAR, REFRESH_JOBS VARCHAR COMMENT 'Tasks that refresh the datamart source(s).',
  PRIMARY_KEY VARCHAR, BUSINESS_KEY VARCHAR, COLUMN_COUNT NUMBER, MASKED_COLUMNS VARCHAR,
  DM_SOURCE_TABLES VARCHAR COMMENT 'Datamart table(s) the view reads.',
  UPSTREAM_OBJECTS VARCHAR COMMENT 'All upstream objects back to SAP landing (from lineage).',
  SAP_SOURCE_FIELDS VARCHAR COMMENT 'SAP landing fields at the origin of the lineage.',
  DOWNSTREAM_CONSUMERS VARCHAR COMMENT 'Dashboards, reports and extracts that read the view.',
  KEY_FILTERS VARCHAR COMMENT 'Filters in the load, the view and the reports.',
  KPIS VARCHAR COMMENT 'KPI definitions and calculations available from the view.',
  ALTERNATIVE_VIEWS VARCHAR COMMENT 'Other reporting views that read the same datamart table.',
  REQUIREMENTS VARCHAR COMMENT 'Requirement IDs traced to the view.',
  TRANSFORMATION_STEPS NUMBER COMMENT 'Number of derived / lookup / conditional / aggregated steps in its lineage.',
  KF_REFRESHED_AT TIMESTAMP_LTZ
) COMMENT = 'Data dictionary card: one row per reporting view with every data dictionary attribute.';
CREATE OR REPLACE TABLE KF_RAW_TASKS (TASK_NAME VARCHAR, SCHEMA_NAME VARCHAR, SCHEDULE VARCHAR, PREDECESSORS VARCHAR, STATE VARCHAR, WAREHOUSE VARCHAR, COMMENT VARCHAR, DEFINITION VARCHAR);

-- ---------------------------------------------------------------------
-- 5. The refresh procedure: reads Snowflake metadata and rebuilds the output tables.
--    Run it after any change to the model; schedule it with TASK_REFRESH_KNOWLEDGE_FABRIC.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE REFRESH_KNOWLEDGE_FABRIC(SUGGEST_DESCRIPTIONS BOOLEAN)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
COMMENT = 'Reads comments, tags, masking policies, tasks and Snowflake lineage of the AP model into the Knowledge Fabric tables.'
EXECUTE AS CALLER
AS
$$
from snowflake.snowpark.types import StructType, StructField, StringType

DB = "{{DATABASE}}"
KF = "{{DATABASE}}.{{KF}}"
SCHEMAS = ["{{LANDING}}", "{{EDW}}", "{{DATAMART}}", "{{REPORTING}}"]
LEVEL_RANK = {"DATABASE": "1", "SCHEMA": "2", "TABLE": "3", "VIEW": "3", "COLUMN": "4"}
KEY_COLUMNS = ["{{REPORTING}}.VW_AP_OPEN_ITEMS.VENDOR_COUNTRY", "{{REPORTING}}.VW_AP_OPEN_ITEMS.AGING_BUCKET",
               "{{REPORTING}}.VW_AP_OPEN_ITEMS.OPEN_AMOUNT_USD", "{{REPORTING}}.VW_AP_VENDOR.TAX_ID"]


def rows(session, sql):
    return [r.as_dict() for r in session.sql(sql).collect()]


def save(session, table, names, data):
    schema = StructType([StructField(n, StringType()) for n in names])
    df = session.create_dataframe(data if data else [tuple([None] * len(names))], schema=schema)
    if not data:
        df = df.filter("1 = 0")
    df.write.mode("overwrite").save_as_table(KF + "." + table)


def text(value):
    return None if value is None else str(value)


def main(session, suggest_descriptions):
    notes = []
    schema_list = ", ".join("'" + s + "'" for s in SCHEMAS)
    objects = rows(session, "SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM " + DB +
                   ".INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA IN (" + schema_list + ") "
                   "AND TABLE_TYPE IN ('BASE TABLE', 'VIEW') AND LEFT(TABLE_NAME, 1) <> '_'")

    # 1. Tags (incl. inherited) and masking policies per object
    tags, policies = [], []
    for o in objects:
        key = o["TABLE_SCHEMA"] + "." + o["TABLE_NAME"]
        fqn = DB + "." + key
        domain = "VIEW" if o["TABLE_TYPE"] == "VIEW" else "TABLE"
        try:
            for r in rows(session, "SELECT * FROM TABLE(" + DB + ".INFORMATION_SCHEMA.TAG_REFERENCES('" + fqn + "', 'TABLE'))"):
                tags.append((key, "", text(r.get("TAG_DATABASE")), text(r.get("TAG_NAME")), text(r.get("TAG_VALUE")),
                             LEVEL_RANK.get(str(r.get("LEVEL", "")).upper(), "0")))
        except Exception as e:
            notes.append("tags " + key + ": " + str(e)[:120])
        try:
            for r in rows(session, "SELECT * FROM TABLE(" + DB + ".INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('" + fqn + "', 'TABLE'))"):
                tags.append((key, text(r.get("COLUMN_NAME")) or "", text(r.get("TAG_DATABASE")), text(r.get("TAG_NAME")),
                             text(r.get("TAG_VALUE")), LEVEL_RANK.get(str(r.get("LEVEL", "")).upper(), "0")))
        except Exception as e:
            notes.append("column tags " + key + ": " + str(e)[:120])
        try:
            for r in rows(session, "SELECT * FROM TABLE(" + DB + ".INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => '" +
                          fqn + "', REF_ENTITY_DOMAIN => '" + domain + "'))"):
                policies.append((key, text(r.get("REF_COLUMN_NAME")) or "",
                                 ".".join(str(r.get(k)) for k in ("POLICY_DB", "POLICY_SCHEMA", "POLICY_NAME") if r.get(k)),
                                 text(r.get("POLICY_KIND"))))
        except Exception as e:
            notes.append("policies " + key + ": " + str(e)[:120])
    save(session, "KF_RAW_TAGS", ["OBJECT_KEY", "COLUMN_NAME", "TAG_DATABASE", "TAG_NAME", "TAG_VALUE", "LEVEL_RANK"], tags)
    save(session, "KF_RAW_POLICIES", ["OBJECT_KEY", "COLUMN_NAME", "POLICY_NAME", "POLICY_KIND"], policies)

    # 2. Refresh jobs (tasks)
    tasks = []
    try:
        for r in rows(session, "SHOW TASKS IN DATABASE " + DB):
            tasks.append((text(r.get("name")), text(r.get("schema_name")), text(r.get("schedule")),
                          text(r.get("predecessors")), text(r.get("state")), text(r.get("warehouse")),
                          text(r.get("comment")), text(r.get("definition"))))
    except Exception as e:
        notes.append("tasks: " + str(e)[:120])
    save(session, "KF_RAW_TASKS", ["TASK_NAME", "SCHEMA_NAME", "SCHEDULE", "PREDECESSORS", "STATE", "WAREHOUSE",
                                   "COMMENT", "DEFINITION"], tasks)

    # 2b. Primary / unique keys declared on tables
    keys = []
    for show, key_type in (("SHOW PRIMARY KEYS IN DATABASE ", "Primary key"), ("SHOW UNIQUE KEYS IN DATABASE ", "Business key")):
        try:
            for r in rows(session, show + DB):
                if r.get("schema_name") in SCHEMAS:
                    keys.append((r.get("schema_name") + "." + r.get("table_name"), text(r.get("column_name")), key_type,
                                 text(r.get("key_sequence"))))
        except Exception as e:
            notes.append("keys: " + str(e)[:120])
    save(session, "KF_RAW_KEYS", ["OBJECT_KEY", "COLUMN_NAME", "KEY_TYPE", "KEY_SEQUENCE"], keys)

    # 3. Lineage recorded by Snowflake (may lag a few hours after the first load)
    lineage = []
    targets = [(DB + "." + o["TABLE_SCHEMA"] + "." + o["TABLE_NAME"], "TABLE")
               for o in objects if o["TABLE_SCHEMA"] in ("{{REPORTING}}", "{{DATAMART}}")]
    targets += [(DB + "." + c, "COLUMN") for c in KEY_COLUMNS]
    for name, domain in targets:
        try:
            for r in rows(session, "SELECT * FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('" + name + "', '" + domain +
                          "', 'UPSTREAM', 5))"):
                src = ".".join(str(r.get(k)) for k in ("SOURCE_OBJECT_DATABASE", "SOURCE_OBJECT_SCHEMA", "SOURCE_OBJECT_NAME")
                               if r.get(k))
                tgt = ".".join(str(r.get(k)) for k in ("TARGET_OBJECT_DATABASE", "TARGET_OBJECT_SCHEMA", "TARGET_OBJECT_NAME")
                               if r.get(k))
                if r.get("SOURCE_COLUMN_NAME"):
                    src += "." + str(r.get("SOURCE_COLUMN_NAME"))
                if r.get("TARGET_COLUMN_NAME"):
                    tgt += "." + str(r.get("TARGET_COLUMN_NAME"))
                lineage.append((name, "UPSTREAM", src, tgt, text(r.get("DISTANCE")), text(r.get("SOURCE_OBJECT_DOMAIN")),
                                str({k: str(v) for k, v in r.items()})[:4000]))
        except Exception as e:
            notes.append("lineage " + name + ": " + str(e)[:120])
    save(session, "KF_SYSTEM_LINEAGE_RAW", ["LINEAGE_FOR", "DIRECTION", "SOURCE_OBJECT", "TARGET_OBJECT", "DISTANCE",
                                            "SOURCE_DOMAIN", "RAW"], lineage)

    # 4. Build the output tables in SQL
    for statement in BUILD_SQL:
        session.sql(statement).collect()

    # 5. AI drafts for missing descriptions (only for assets that have none yet)
    if suggest_descriptions:
        try:
            for statement in SUGGEST_SQL:
                session.sql(statement).collect()
        except Exception as e:
            notes.append("AI suggestions: " + str(e)[:200])

    session.sql(CATALOG_SQL).collect()
    session.sql("INSERT OVERWRITE INTO " + KF + ".KF_CATALOG SELECT * FROM " + KF + "._TMP_CATALOG").collect()
    counts = rows(session, "SELECT (SELECT COUNT(*) FROM " + KF + ".KF_OBJECTS) AS O, (SELECT COUNT(*) FROM " + KF +
                  ".KF_COLUMNS) AS C, (SELECT COUNT(*) FROM " + KF + ".KF_SYSTEM_LINEAGE) AS L")[0]
    return ("Knowledge Fabric refreshed: " + str(counts["O"]) + " objects, " + str(counts["C"]) + " columns, " +
            str(len(tags)) + " tag links, " + str(len(policies)) + " policy links, " + str(len(tasks)) + " tasks, " +
            str(counts["L"]) + " Snowflake lineage rows." + (" Notes: " + " | ".join(notes[:8]) if notes else ""))


LAYER_SQL = ("CASE c.TABLE_SCHEMA WHEN '{{LANDING}}' THEN 'Landing' WHEN '{{EDW}}' THEN 'EDW' "
             "WHEN '{{DATAMART}}' THEN 'Datamart' ELSE 'Reporting' END")

def LAYER_OF(col):
    return ("CASE SPLIT_PART(" + col + ", '.', 1) WHEN '{{LANDING}}' THEN 'Landing' WHEN '{{EDW}}' THEN 'EDW' "
            "WHEN '{{DATAMART}}' THEN 'Datamart' WHEN '{{REPORTING}}' THEN 'Reporting' ELSE 'Other' END")


BUILD_SQL = [
    # Field lineage: walk every reporting column back through the mapping sheet
    """CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_LINEAGE (PATH_STEP_ID, REPORT_OBJECT, REPORT_COLUMN, HOP, TARGET_OBJECT, TARGET_COLUMN, SOURCE_OBJECT, SOURCE_COLUMN, SOURCE_LAYER, MAPPING_TYPE, TRANSFORMATION_RULE, IS_ORIGIN) AS
       WITH RECURSIVE walk (REPORT_OBJECT, REPORT_COLUMN, HOP, TARGET_OBJECT, TARGET_COLUMN, SOURCE_OBJECT, SOURCE_COLUMN,
                            MAPPING_TYPE, TRANSFORMATION_RULE) AS (
         SELECT TARGET_OBJECT, TARGET_COLUMN, 1, TARGET_OBJECT, TARGET_COLUMN, SOURCE_OBJECT, SOURCE_COLUMN,
                MAPPING_TYPE, TRANSFORMATION_RULE
         FROM {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING WHERE TARGET_LAYER = 'Reporting'
         UNION ALL
         SELECT w.REPORT_OBJECT, w.REPORT_COLUMN, w.HOP + 1, m.TARGET_OBJECT, m.TARGET_COLUMN, m.SOURCE_OBJECT,
                m.SOURCE_COLUMN, m.MAPPING_TYPE, m.TRANSFORMATION_RULE
         FROM walk w JOIN {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING m
           ON m.TARGET_OBJECT = w.SOURCE_OBJECT AND m.TARGET_COLUMN = w.SOURCE_COLUMN
         WHERE w.HOP < 10
       )
       SELECT ROW_NUMBER() OVER (ORDER BY w.REPORT_OBJECT, w.REPORT_COLUMN, w.HOP, w.SOURCE_OBJECT, w.SOURCE_COLUMN),
              w.REPORT_OBJECT, w.REPORT_COLUMN, w.HOP, w.TARGET_OBJECT, w.TARGET_COLUMN, w.SOURCE_OBJECT, w.SOURCE_COLUMN,
              CASE SPLIT_PART(w.SOURCE_OBJECT, '.', 1) WHEN '{{LANDING}}' THEN 'Landing' WHEN '{{EDW}}' THEN 'EDW'
                   WHEN '{{DATAMART}}' THEN 'Datamart' ELSE 'Reporting' END,
              w.MAPPING_TYPE, w.TRANSFORMATION_RULE, up.TARGET_OBJECT IS NULL
       FROM walk w
       LEFT JOIN (SELECT DISTINCT TARGET_OBJECT, TARGET_COLUMN FROM {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING) up
         ON up.TARGET_OBJECT = w.SOURCE_OBJECT AND up.TARGET_COLUMN = w.SOURCE_COLUMN""",
    "INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_LINEAGE_PATHS SELECT * FROM {{DATABASE}}.{{KF}}._TMP_LINEAGE",

    # Impact analysis: walk the mapping sheet DOWNSTREAM from every column, then add the reports that read the result
    """CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_IMPACT (IMPACT_ID, CHANGED_OBJECT, CHANGED_COLUMN, CHANGED_LAYER, AFFECTED_TYPE, AFFECTED_OBJECT, AFFECTED_COLUMN, AFFECTED_LAYER, DISTANCE, IMPACT_PATH, OWNER) AS
       WITH RECURSIVE down (CHANGED_OBJECT, CHANGED_COLUMN, AFFECTED_OBJECT, AFFECTED_COLUMN, DISTANCE, IMPACT_PATH) AS (
         SELECT SOURCE_OBJECT, SOURCE_COLUMN, TARGET_OBJECT, TARGET_COLUMN, 1,
                SOURCE_OBJECT || '.' || SOURCE_COLUMN || ' -> ' || TARGET_OBJECT || '.' || TARGET_COLUMN
         FROM {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING
         UNION ALL
         SELECT d.CHANGED_OBJECT, d.CHANGED_COLUMN, m.TARGET_OBJECT, m.TARGET_COLUMN, d.DISTANCE + 1,
                d.IMPACT_PATH || ' -> ' || m.TARGET_OBJECT || '.' || m.TARGET_COLUMN
         FROM down d JOIN {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING m
           ON m.SOURCE_OBJECT = d.AFFECTED_OBJECT AND m.SOURCE_COLUMN = d.AFFECTED_COLUMN
         WHERE d.DISTANCE < 10
       ),
       cols AS (
         SELECT CHANGED_OBJECT, CHANGED_COLUMN, AFFECTED_OBJECT, AFFECTED_COLUMN,
                MIN(DISTANCE) AS DISTANCE, MIN_BY(IMPACT_PATH, DISTANCE) AS IMPACT_PATH
         FROM down GROUP BY 1, 2, 3, 4
       ),
       allrows AS (
         SELECT CHANGED_OBJECT, CHANGED_COLUMN, 'Column' AS AFFECTED_TYPE, AFFECTED_OBJECT, AFFECTED_COLUMN,
                """ + LAYER_OF("AFFECTED_OBJECT") + """ AS AFFECTED_LAYER, DISTANCE, IMPACT_PATH, NULL AS OWNER
         FROM cols
         UNION ALL
         SELECT c.CHANGED_OBJECT, c.CHANGED_COLUMN, u.CONSUMER_TYPE, u.CONSUMER_NAME, u.OBJECT_KEY || '.' || u.COLUMN_NAME,
                'Consumer', c.DISTANCE + 1, c.IMPACT_PATH || ' -> ' || u.CONSUMER_NAME || ' (' || u.CONSUMER_TYPE || ')', u.OWNER
         FROM cols c JOIN {{DATABASE}}.{{KF}}.KF_REPORT_USAGE u
           ON u.OBJECT_KEY = c.AFFECTED_OBJECT AND u.COLUMN_NAME = c.AFFECTED_COLUMN
         UNION ALL
         SELECT OBJECT_KEY, COLUMN_NAME, CONSUMER_TYPE, CONSUMER_NAME, OBJECT_KEY || '.' || COLUMN_NAME, 'Consumer', 1,
                OBJECT_KEY || '.' || COLUMN_NAME || ' -> ' || CONSUMER_NAME || ' (' || CONSUMER_TYPE || ')', OWNER
         FROM {{DATABASE}}.{{KF}}.KF_REPORT_USAGE
       )
       SELECT ROW_NUMBER() OVER (ORDER BY CHANGED_OBJECT, CHANGED_COLUMN, DISTANCE, AFFECTED_OBJECT, AFFECTED_COLUMN),
              CHANGED_OBJECT, CHANGED_COLUMN, """ + LAYER_OF("CHANGED_OBJECT") + """, AFFECTED_TYPE, AFFECTED_OBJECT,
              AFFECTED_COLUMN, AFFECTED_LAYER, DISTANCE, IMPACT_PATH, OWNER
       FROM allrows""",
    "INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_IMPACT SELECT * FROM {{DATABASE}}.{{KF}}._TMP_IMPACT",

    # Columns: comments + effective tags (most specific level wins) + direct masking policy
    """CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_COLUMNS (COLUMN_KEY, OBJECT_KEY, SCHEMA_NAME, OBJECT_NAME, DATA_LAYER, COLUMN_NAME, ORDINAL_POSITION, DATA_TYPE, BUSINESS_NAME, DESCRIPTION, HAS_DESCRIPTION, SENSITIVITY, SEMANTIC_CATEGORY, PRIVACY_CATEGORY, MASKING_POLICY, IS_MASKED, MASKED_VIA, AI_SUGGESTED_DESCRIPTION, SUGGESTION_STATUS, KF_REFRESHED_AT, DATA_TYPE_FULL, CHARACTER_LIMIT, KEY_ROLE, TECHNICAL_DESCRIPTION) AS
       WITH t AS (
         SELECT OBJECT_KEY, COLUMN_NAME, TAG_NAME, TAG_VALUE FROM {{DATABASE}}.{{KF}}.KF_RAW_TAGS WHERE COLUMN_NAME <> ''
         QUALIFY ROW_NUMBER() OVER (PARTITION BY OBJECT_KEY, COLUMN_NAME, TAG_NAME ORDER BY TRY_TO_NUMBER(LEVEL_RANK) DESC) = 1
       ),
       tp AS (
         SELECT OBJECT_KEY, COLUMN_NAME,
                MAX(IFF(TAG_NAME = 'SENSITIVITY', TAG_VALUE, NULL)) AS SENSITIVITY,
                MAX(IFF(TAG_NAME = 'SEMANTIC_CATEGORY', TAG_VALUE, NULL)) AS SEMANTIC_CATEGORY,
                MAX(IFF(TAG_NAME = 'PRIVACY_CATEGORY', TAG_VALUE, NULL)) AS PRIVACY_CATEGORY
         FROM t GROUP BY 1, 2
       ),
       p AS (SELECT OBJECT_KEY, COLUMN_NAME, LISTAGG(POLICY_NAME, ', ') AS POLICY_NAME
             FROM {{DATABASE}}.{{KF}}.KF_RAW_POLICIES WHERE POLICY_KIND = 'MASKING_POLICY' AND COLUMN_NAME <> '' GROUP BY 1, 2)
       SELECT c.TABLE_SCHEMA || '.' || c.TABLE_NAME || '.' || c.COLUMN_NAME, c.TABLE_SCHEMA || '.' || c.TABLE_NAME,
              c.TABLE_SCHEMA, c.TABLE_NAME, """ + LAYER_SQL + """, c.COLUMN_NAME, c.ORDINAL_POSITION, c.DATA_TYPE,
              CASE WHEN c.COMMENT ILIKE '%:%' AND POSITION(':' IN c.COMMENT) <= 60 THEN TRIM(SPLIT_PART(c.COMMENT, ':', 1))
                   ELSE INITCAP(REPLACE(c.COLUMN_NAME, '_', ' ')) END,
              c.COMMENT, NULLIF(TRIM(c.COMMENT), '') IS NOT NULL,
              COALESCE(tp.SENSITIVITY, 'Internal'), tp.SEMANTIC_CATEGORY, tp.PRIVACY_CATEGORY,
              p.POLICY_NAME, p.POLICY_NAME IS NOT NULL, NULL, NULL, NULL, CURRENT_TIMESTAMP(),
              CASE WHEN c.DATA_TYPE = 'TEXT' THEN 'VARCHAR(' || c.CHARACTER_MAXIMUM_LENGTH || ')'
                   WHEN c.DATA_TYPE = 'NUMBER' THEN 'NUMBER(' || c.NUMERIC_PRECISION || ',' || c.NUMERIC_SCALE || ')'
                   ELSE c.DATA_TYPE END,
              c.CHARACTER_MAXIMUM_LENGTH, NULL, NULL
       FROM {{DATABASE}}.INFORMATION_SCHEMA.COLUMNS c
       LEFT JOIN tp ON tp.OBJECT_KEY = c.TABLE_SCHEMA || '.' || c.TABLE_NAME AND tp.COLUMN_NAME = c.COLUMN_NAME
       LEFT JOIN p  ON p.OBJECT_KEY  = c.TABLE_SCHEMA || '.' || c.TABLE_NAME AND p.COLUMN_NAME  = c.COLUMN_NAME
       WHERE c.TABLE_SCHEMA IN ('{{LANDING}}', '{{EDW}}', '{{DATAMART}}', '{{REPORTING}}') AND LEFT(c.TABLE_NAME, 1) <> '_'""",
    "INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_COLUMNS SELECT * FROM {{DATABASE}}.{{KF}}._TMP_COLUMNS",

    # Views have no policy of their own: they inherit masking from the nearest masked upstream column
    """UPDATE {{DATABASE}}.{{KF}}.KF_COLUMNS k
       SET IS_MASKED = TRUE, MASKED_VIA = x.MASKED_SOURCE
       FROM (SELECT l.REPORT_OBJECT, l.REPORT_COLUMN,
                    MIN_BY(l.SOURCE_OBJECT || '.' || l.SOURCE_COLUMN || ' (' || m.MASKING_POLICY || ')', l.HOP) AS MASKED_SOURCE
             FROM {{DATABASE}}.{{KF}}.KF_LINEAGE_PATHS l
             JOIN {{DATABASE}}.{{KF}}.KF_COLUMNS m
               ON m.OBJECT_KEY = l.SOURCE_OBJECT AND m.COLUMN_NAME = l.SOURCE_COLUMN AND m.MASKING_POLICY IS NOT NULL
             GROUP BY 1, 2) x
       WHERE k.OBJECT_KEY = x.REPORT_OBJECT AND k.COLUMN_NAME = x.REPORT_COLUMN AND k.MASKING_POLICY IS NULL""",

    # Keys: constraints on tables + KEY_ROLE tag on views
    """UPDATE {{DATABASE}}.{{KF}}.KF_COLUMNS k SET KEY_ROLE = x.KEY_ROLE
       FROM (SELECT OBJECT_KEY, COLUMN_NAME, MAX(KEY_ROLE) AS KEY_ROLE FROM (
               SELECT OBJECT_KEY, COLUMN_NAME, KEY_TYPE AS KEY_ROLE FROM {{DATABASE}}.{{KF}}.KF_RAW_KEYS
               UNION ALL
               SELECT OBJECT_KEY, COLUMN_NAME, TAG_VALUE FROM {{DATABASE}}.{{KF}}.KF_RAW_TAGS
               WHERE TAG_NAME = 'KEY_ROLE' AND COLUMN_NAME <> '') GROUP BY 1, 2) x
       WHERE k.OBJECT_KEY = x.OBJECT_KEY AND k.COLUMN_NAME = x.COLUMN_NAME""",

    # Technical description: type, key, SAP field, masking, then source and rule from the mapping sheet
    """UPDATE {{DATABASE}}.{{KF}}.KF_COLUMNS SET TECHNICAL_DESCRIPTION =
         DATA_TYPE_FULL || COALESCE(', ' || KEY_ROLE, '')
         || IFF(DATA_LAYER = 'Landing', '. SAP field ' || COLUMN_NAME || ' of SAP table ' || REPLACE(OBJECT_NAME, 'SAP_', ''), '')
         || IFF(IS_MASKED, '. Masked: ' || COALESCE(MASKING_POLICY, 'inherited from ' || MASKED_VIA), '') || '.'""",
    """UPDATE {{DATABASE}}.{{KF}}.KF_COLUMNS k SET TECHNICAL_DESCRIPTION = k.TECHNICAL_DESCRIPTION || ' Source: ' || d.SOURCES || '.'
       FROM (SELECT TARGET_OBJECT, TARGET_COLUMN,
                    LISTAGG(SOURCE_OBJECT || '.' || SOURCE_COLUMN || ' [' || MAPPING_TYPE || ': ' || TRANSFORMATION_RULE || ']', '; ') AS SOURCES
             FROM {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING GROUP BY 1, 2) d
       WHERE d.TARGET_OBJECT = k.OBJECT_KEY AND d.TARGET_COLUMN = k.COLUMN_NAME""",

    # Refresh jobs, read from the tasks
    """INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_REFRESH_SCHEDULE
       SELECT TASK_NAME, SCHEMA_NAME, NULLIF(SCHEDULE, ''),
              NULLIF(REGEXP_REPLACE(PREDECESSORS, '[\\\\[\\\\]"\\\\s]', ''), ''),
              STATE, WAREHOUSE,
              TRIM(SPLIT_PART(COMMENT, 'Refreshes:', 2)),
              TRIM(SPLIT_PART(COMMENT, 'Refreshes:', 1)), DEFINITION
       FROM {{DATABASE}}.{{KF}}.KF_RAW_TASKS""",

    """INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_SYSTEM_LINEAGE
       SELECT LINEAGE_FOR, DIRECTION, SOURCE_OBJECT, TARGET_OBJECT, TRY_TO_NUMBER(DISTANCE), SOURCE_DOMAIN, RAW
       FROM {{DATABASE}}.{{KF}}.KF_SYSTEM_LINEAGE_RAW""",

    # Objects: comments + effective tags + column statistics + refreshing task
    """CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_OBJECTS (OBJECT_KEY, OBJECT_NAME, SCHEMA_NAME, OBJECT_TYPE, DATA_LAYER, LAYER_ORDER, DESCRIPTION, HAS_DESCRIPTION, AI_SUGGESTED_DESCRIPTION, ROW_COUNT, COLUMN_COUNT, MASKED_COLUMN_COUNT, UNDOCUMENTED_COLUMN_COUNT, DATA_DOMAIN, DATA_PRODUCT, SOURCE_SYSTEM, REFRESH_FREQUENCY, REFRESHED_BY_TASK, DATA_OWNER, DATA_STEWARD, CERTIFICATION, CREATED_AT, LAST_ALTERED, KF_REFRESHED_AT, DATABASE_NAME, DATA_CLASS, TECHNICAL_OWNER, UPSTREAM_OBJECTS, DOWNSTREAM_OBJECTS) AS
       WITH t AS (
         SELECT OBJECT_KEY, TAG_NAME, TAG_VALUE FROM {{DATABASE}}.{{KF}}.KF_RAW_TAGS WHERE COLUMN_NAME = ''
         QUALIFY ROW_NUMBER() OVER (PARTITION BY OBJECT_KEY, TAG_NAME ORDER BY TRY_TO_NUMBER(LEVEL_RANK) DESC) = 1
       ),
       tp AS (
         SELECT OBJECT_KEY,
                MAX(IFF(TAG_NAME = 'DATA_DOMAIN', TAG_VALUE, NULL)) AS DATA_DOMAIN,
                MAX(IFF(TAG_NAME = 'DATA_PRODUCT', TAG_VALUE, NULL)) AS DATA_PRODUCT,
                MAX(IFF(TAG_NAME = 'DATA_LAYER', TAG_VALUE, NULL)) AS DATA_LAYER,
                MAX(IFF(TAG_NAME = 'SOURCE_SYSTEM', TAG_VALUE, NULL)) AS SOURCE_SYSTEM,
                MAX(IFF(TAG_NAME = 'REFRESH_FREQUENCY', TAG_VALUE, NULL)) AS REFRESH_FREQUENCY,
                MAX(IFF(TAG_NAME = 'DATA_OWNER', TAG_VALUE, NULL)) AS DATA_OWNER,
                MAX(IFF(TAG_NAME = 'DATA_STEWARD', TAG_VALUE, NULL)) AS DATA_STEWARD,
                MAX(IFF(TAG_NAME = 'CERTIFICATION', TAG_VALUE, NULL)) AS CERTIFICATION,
                MAX(IFF(TAG_NAME = 'DATA_CLASS', TAG_VALUE, NULL)) AS DATA_CLASS,
                MAX(IFF(TAG_NAME = 'TECHNICAL_OWNER', TAG_VALUE, NULL)) AS TECHNICAL_OWNER
         FROM t GROUP BY 1
       ),
       upo AS (SELECT TO_OBJECT AS OBJECT_KEY, LISTAGG(DISTINCT FROM_OBJECT, ', ') AS UPSTREAM
               FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS WHERE RELATIONSHIP_TYPE = 'Loads into' GROUP BY 1),
       dno AS (SELECT FROM_OBJECT AS OBJECT_KEY, LISTAGG(DISTINCT TO_OBJECT, ', ') AS DOWNSTREAM
               FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS WHERE RELATIONSHIP_TYPE = 'Loads into' GROUP BY 1),
       cs AS (SELECT OBJECT_KEY, COUNT(*) AS COLUMN_COUNT, COUNT_IF(IS_MASKED) AS MASKED, COUNT_IF(NOT HAS_DESCRIPTION) AS UNDOCUMENTED
              FROM {{DATABASE}}.{{KF}}.KF_COLUMNS GROUP BY 1),
       rt AS (SELECT TRIM(f.value::STRING) AS OBJECT_NAME, r.TASK_NAME
              FROM {{DATABASE}}.{{KF}}.KF_REFRESH_SCHEDULE r, LATERAL FLATTEN(input => SPLIT(r.REFRESHES_OBJECTS, ',')) f)
       SELECT c.TABLE_SCHEMA || '.' || c.TABLE_NAME, c.TABLE_NAME, c.TABLE_SCHEMA, IFF(c.TABLE_TYPE = 'VIEW', 'View', 'Table'),
              COALESCE(tp.DATA_LAYER, """ + LAYER_SQL + """),
              CASE COALESCE(tp.DATA_LAYER, """ + LAYER_SQL + """) WHEN 'Landing' THEN 1 WHEN 'EDW' THEN 2 WHEN 'Datamart' THEN 3 ELSE 4 END,
              c.COMMENT, NULLIF(TRIM(c.COMMENT), '') IS NOT NULL, NULL,
              c.ROW_COUNT, cs.COLUMN_COUNT, cs.MASKED, cs.UNDOCUMENTED,
              tp.DATA_DOMAIN, tp.DATA_PRODUCT, tp.SOURCE_SYSTEM, tp.REFRESH_FREQUENCY, rt.TASK_NAME,
              tp.DATA_OWNER, tp.DATA_STEWARD, tp.CERTIFICATION, c.CREATED, c.LAST_ALTERED, CURRENT_TIMESTAMP(),
              c.TABLE_CATALOG, tp.DATA_CLASS, tp.TECHNICAL_OWNER, upo.UPSTREAM, dno.DOWNSTREAM
       FROM {{DATABASE}}.INFORMATION_SCHEMA.TABLES c
       LEFT JOIN tp ON tp.OBJECT_KEY = c.TABLE_SCHEMA || '.' || c.TABLE_NAME
       LEFT JOIN upo ON upo.OBJECT_KEY = c.TABLE_SCHEMA || '.' || c.TABLE_NAME
       LEFT JOIN dno ON dno.OBJECT_KEY = c.TABLE_SCHEMA || '.' || c.TABLE_NAME
       LEFT JOIN cs ON cs.OBJECT_KEY = c.TABLE_SCHEMA || '.' || c.TABLE_NAME
       LEFT JOIN rt ON rt.OBJECT_NAME = c.TABLE_NAME
       WHERE c.TABLE_SCHEMA IN ('{{LANDING}}', '{{EDW}}', '{{DATAMART}}', '{{REPORTING}}')
         AND c.TABLE_TYPE IN ('BASE TABLE', 'VIEW') AND LEFT(c.TABLE_NAME, 1) <> '_'""",
    "INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_OBJECTS SELECT * FROM {{DATABASE}}.{{KF}}._TMP_OBJECTS",

    # Data dictionary card per reporting view (all data dictionary attributes in one row)
    """CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_VIEWS (VIEW_KEY, DATABASE_NAME, SCHEMA_NAME, VIEW_NAME, VIEW_DESCRIPTION, DATA_CLASS, PORTFOLIO_DOMAIN, DATA_PRODUCT, DATA_OWNER, TECHNICAL_OWNER, DATA_STEWARD, CERTIFICATION, REFRESH_FREQUENCY, REFRESH_JOBS, PRIMARY_KEY, BUSINESS_KEY, COLUMN_COUNT, MASKED_COLUMNS, DM_SOURCE_TABLES, UPSTREAM_OBJECTS, SAP_SOURCE_FIELDS, DOWNSTREAM_CONSUMERS, KEY_FILTERS, KPIS, ALTERNATIVE_VIEWS, REQUIREMENTS, TRANSFORMATION_STEPS, KF_REFRESHED_AT) AS
       WITH src_rows AS (
         SELECT TO_OBJECT AS VIEW_KEY, FROM_OBJECT AS DM_SOURCE FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS
         WHERE RELATIONSHIP_TYPE = 'Loads into' AND TO_OBJECT LIKE '{{REPORTING}}.%'
       ),
       src AS (SELECT VIEW_KEY, LISTAGG(DISTINCT DM_SOURCE, ', ') AS DM_SOURCES FROM src_rows GROUP BY 1),
       alt AS (SELECT a.VIEW_KEY, LISTAGG(DISTINCT b.VIEW_KEY || ' (same source ' || a.DM_SOURCE || ')', ', ') AS ALTERNATIVES
               FROM src_rows a JOIN src_rows b ON a.DM_SOURCE = b.DM_SOURCE AND a.VIEW_KEY <> b.VIEW_KEY GROUP BY 1),
       jobs AS (SELECT s.VIEW_KEY, LISTAGG(DISTINCT o.REFRESHED_BY_TASK, ', ') AS JOBS
                FROM src_rows s JOIN {{DATABASE}}.{{KF}}.KF_OBJECTS o ON o.OBJECT_KEY = s.DM_SOURCE GROUP BY 1),
       keys AS (SELECT OBJECT_KEY,
                       LISTAGG(IFF(KEY_ROLE = 'Primary key', COLUMN_NAME, NULL), ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS PK,
                       LISTAGG(IFF(KEY_ROLE = 'Business key', COLUMN_NAME, NULL), ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS BK,
                       LISTAGG(IFF(IS_MASKED, COLUMN_NAME, NULL), ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS MASKED
                FROM {{DATABASE}}.{{KF}}.KF_COLUMNS GROUP BY 1),
       up AS (SELECT REPORT_OBJECT, LISTAGG(DISTINCT SOURCE_OBJECT, ', ') AS UPSTREAM,
                     LISTAGG(DISTINCT IFF(IS_ORIGIN AND SOURCE_LAYER = 'Landing', SOURCE_OBJECT || '.' || SOURCE_COLUMN, NULL), ', ') AS SAP_FIELDS,
                     COUNT_IF(MAPPING_TYPE IN ('Derived', 'Lookup', 'Conditional', 'Aggregated')) AS RULES
              FROM {{DATABASE}}.{{KF}}.KF_LINEAGE_PATHS GROUP BY 1),
       consumers AS (SELECT OBJECT_KEY, LISTAGG(DISTINCT CONSUMER_NAME || ' (' || CONSUMER_TYPE || ')', ', ') AS CONSUMERS
                     FROM {{DATABASE}}.{{KF}}.KF_REPORT_USAGE GROUP BY 1),
       filt AS (SELECT OBJECT_KEY, LISTAGG(COLUMN_NAME || ': ' || FILTER_RULE || ' [' || APPLIED_IN || COALESCE(', ' || CONSUMER_NAME, '') || ']', '; ')
                       WITHIN GROUP (ORDER BY FILTER_ID) AS FILTERS
                FROM {{DATABASE}}.{{KF}}.KF_KEY_FILTERS GROUP BY 1),
       kpi AS (SELECT s.VIEW_KEY, LISTAGG(DISTINCT g.TERM || ' = ' || COALESCE(g.CALCULATION, g.DEFINITION) || ' (' || g.STATUS || ')', '; ') AS KPIS
               FROM src_rows s JOIN {{DATABASE}}.{{KF}}.KF_GLOSSARY g
                 ON g.TERM_TYPE = 'KPI' AND SPLIT_PART(g.IMPLEMENTED_IN, '.', 1) || '.' || SPLIT_PART(g.IMPLEMENTED_IN, '.', 2) IN (s.DM_SOURCE, s.VIEW_KEY)
               GROUP BY 1),
       req AS (SELECT OBJECT_KEY, LISTAGG(DISTINCT REQ_ID, ', ') AS REQS FROM {{DATABASE}}.{{KF}}.KF_REQUIREMENT_TRACE GROUP BY 1)
       SELECT v.OBJECT_KEY, v.DATABASE_NAME, v.SCHEMA_NAME, v.OBJECT_NAME, v.DESCRIPTION, v.DATA_CLASS, v.DATA_DOMAIN, v.DATA_PRODUCT,
              v.DATA_OWNER, v.TECHNICAL_OWNER, v.DATA_STEWARD, v.CERTIFICATION, v.REFRESH_FREQUENCY, jobs.JOBS,
              keys.PK, keys.BK, v.COLUMN_COUNT, keys.MASKED, src.DM_SOURCES, up.UPSTREAM, up.SAP_FIELDS, consumers.CONSUMERS,
              filt.FILTERS, kpi.KPIS, alt.ALTERNATIVES, req.REQS, up.RULES, CURRENT_TIMESTAMP()
       FROM {{DATABASE}}.{{KF}}.KF_OBJECTS v
       LEFT JOIN src ON src.VIEW_KEY = v.OBJECT_KEY
       LEFT JOIN alt ON alt.VIEW_KEY = v.OBJECT_KEY
       LEFT JOIN jobs ON jobs.VIEW_KEY = v.OBJECT_KEY
       LEFT JOIN keys ON keys.OBJECT_KEY = v.OBJECT_KEY
       LEFT JOIN up ON up.REPORT_OBJECT = v.OBJECT_KEY
       LEFT JOIN consumers ON consumers.OBJECT_KEY = v.OBJECT_KEY
       LEFT JOIN filt ON filt.OBJECT_KEY = v.OBJECT_KEY
       LEFT JOIN kpi ON kpi.VIEW_KEY = v.OBJECT_KEY
       LEFT JOIN req ON req.OBJECT_KEY = v.OBJECT_KEY
       WHERE v.DATA_LAYER = 'Reporting'""",
    "INSERT OVERWRITE INTO {{DATABASE}}.{{KF}}.KF_REPORTING_VIEWS SELECT * FROM {{DATABASE}}.{{KF}}._TMP_VIEWS",

    # Show existing AI drafts next to the missing descriptions
    """UPDATE {{DATABASE}}.{{KF}}.KF_COLUMNS k SET AI_SUGGESTED_DESCRIPTION = s.SUGGESTION, SUGGESTION_STATUS = s.STATUS
       FROM {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS s WHERE s.ASSET_KEY = k.COLUMN_KEY AND NOT k.HAS_DESCRIPTION""",
    """UPDATE {{DATABASE}}.{{KF}}.KF_OBJECTS o SET AI_SUGGESTED_DESCRIPTION = s.SUGGESTION
       FROM {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS s WHERE s.ASSET_KEY = o.OBJECT_KEY AND NOT o.HAS_DESCRIPTION""",
]

SUGGEST_SQL = [
    """INSERT INTO {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS
       SELECT k.COLUMN_KEY, 'Column',
              TRIM(AI_COMPLETE('{{AI_MODEL}}',
                'You document an SAP-like Accounts Payable data model. Write ONE sentence describing the column, in the form '
                || '"<Business name>: <description>". Use standard SAP meaning when the column name is an SAP field. '
                || 'If you are not sure, start with "Needs steward input:". Column: ' || k.COLUMN_NAME || ' (' || k.DATA_TYPE
                || ') in ' || k.OBJECT_KEY || '. Table description: ' || COALESCE(o.COMMENT, 'none')
                || '. Other columns: ' || cols.OTHER_COLUMNS)),
              '{{AI_MODEL}}', CURRENT_TIMESTAMP(), 'Suggested - awaiting steward approval'
       FROM {{DATABASE}}.{{KF}}.KF_COLUMNS k
       LEFT JOIN {{DATABASE}}.INFORMATION_SCHEMA.TABLES o ON o.TABLE_SCHEMA = k.SCHEMA_NAME AND o.TABLE_NAME = k.OBJECT_NAME
       LEFT JOIN (SELECT OBJECT_KEY, LISTAGG(COLUMN_NAME, ', ') AS OTHER_COLUMNS FROM {{DATABASE}}.{{KF}}.KF_COLUMNS GROUP BY 1) cols
         ON cols.OBJECT_KEY = k.OBJECT_KEY
       WHERE NOT k.HAS_DESCRIPTION
         AND k.COLUMN_KEY NOT IN (SELECT ASSET_KEY FROM {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS)""",
    """INSERT INTO {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS
       SELECT o.OBJECT_KEY, 'Object',
              TRIM(AI_COMPLETE('{{AI_MODEL}}',
                'You document an SAP-like Accounts Payable data model. Write ONE or two sentences describing the table '
                || o.OBJECT_KEY || ' (layer ' || o.DATA_LAYER || '): what one row is and what it is used for. '
                || 'Columns and their descriptions: ' || cols.COLUMN_TEXT)),
              '{{AI_MODEL}}', CURRENT_TIMESTAMP(), 'Suggested - awaiting steward approval'
       FROM {{DATABASE}}.{{KF}}.KF_OBJECTS o
       JOIN (SELECT OBJECT_KEY, LISTAGG(COLUMN_NAME || ' = ' || COALESCE(DESCRIPTION, '?'), '; ') AS COLUMN_TEXT
             FROM {{DATABASE}}.{{KF}}.KF_COLUMNS GROUP BY 1) cols ON cols.OBJECT_KEY = o.OBJECT_KEY
       WHERE NOT o.HAS_DESCRIPTION
         AND o.OBJECT_KEY NOT IN (SELECT ASSET_KEY FROM {{DATABASE}}.{{KF}}.KF_DESCRIPTION_SUGGESTIONS)""",
] + BUILD_SQL[-2:]

CATALOG_SQL = """
CREATE OR REPLACE TEMPORARY TABLE {{DATABASE}}.{{KF}}._TMP_CATALOG (ASSET_ID, ASSET_TYPE, ASSET_NAME, DATA_LAYER, OBJECT_NAME, COLUMN_NAME, BUSINESS_NAME, SEARCH_TEXT) AS
WITH path AS (
  SELECT REPORT_OBJECT, REPORT_COLUMN,
         LISTAGG('hop ' || HOP || ': ' || TARGET_OBJECT || '.' || TARGET_COLUMN || ' <- ' || SOURCE_OBJECT || '.' || SOURCE_COLUMN
                 || ' (' || MAPPING_TYPE || ')', '; ') WITHIN GROUP (ORDER BY HOP, SOURCE_OBJECT, SOURCE_COLUMN) AS PATH_TEXT,
         LISTAGG(DISTINCT IFF(IS_ORIGIN, SOURCE_OBJECT || '.' || SOURCE_COLUMN, NULL), ', ') AS ORIGIN_TEXT
  FROM {{DATABASE}}.{{KF}}.KF_LINEAGE_PATHS GROUP BY 1, 2
),
direct AS (
  SELECT TARGET_OBJECT, TARGET_COLUMN,
         LISTAGG(SOURCE_OBJECT || '.' || SOURCE_COLUMN || ' (' || MAPPING_TYPE || ': ' || TRANSFORMATION_RULE || ')', '; ') AS SOURCES
  FROM {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING GROUP BY 1, 2
),
cols AS (
  SELECT OBJECT_KEY, LISTAGG(COLUMN_NAME || ' (' || BUSINESS_NAME || ')', ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION) AS COLUMN_LIST
  FROM {{DATABASE}}.{{KF}}.KF_COLUMNS GROUP BY 1
),
feeds AS (
  SELECT TO_OBJECT AS OBJECT_KEY, LISTAGG(FROM_OBJECT, ', ') AS LOADED_FROM
  FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS WHERE RELATIONSHIP_TYPE = 'Loads into' GROUP BY 1
),
feeds_to AS (
  SELECT FROM_OBJECT AS OBJECT_KEY, LISTAGG(TO_OBJECT, ', ') AS FEEDS
  FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS WHERE RELATIONSHIP_TYPE = 'Loads into' GROUP BY 1
),
used_by AS (
  SELECT CHANGED_OBJECT, CHANGED_COLUMN,
         LISTAGG(DISTINCT IFF(AFFECTED_LAYER = 'Consumer', AFFECTED_OBJECT || ' (' || AFFECTED_TYPE || ')',
                              IFF(AFFECTED_LAYER = 'Reporting', AFFECTED_OBJECT || '.' || AFFECTED_COLUMN, NULL)), ', ') AS USED_BY
  FROM {{DATABASE}}.{{KF}}.KF_IMPACT GROUP BY 1, 2
),
req_col AS (
  SELECT OBJECT_KEY, COLUMN_NAME, LISTAGG(DISTINCT REQ_ID, ', ') AS REQS
  FROM {{DATABASE}}.{{KF}}.KF_REQUIREMENT_TRACE WHERE COLUMN_NAME IS NOT NULL GROUP BY 1, 2
),
req_obj AS (
  SELECT OBJECT_KEY, LISTAGG(DISTINCT REQ_ID, ', ') AS REQS FROM {{DATABASE}}.{{KF}}.KF_REQUIREMENT_TRACE GROUP BY 1
),
req_targets AS (
  SELECT REQ_ID, LISTAGG(OBJECT_KEY || COALESCE('.' || COLUMN_NAME, '') || ' (' || TRACE_TYPE || ')', ', ') AS TARGETS
  FROM {{DATABASE}}.{{KF}}.KF_REQUIREMENT_TRACE GROUP BY 1
),
consumers AS (
  SELECT OBJECT_KEY, LISTAGG(DISTINCT CONSUMER_NAME || ' (' || CONSUMER_TYPE || ')', ', ') AS USED_IN
  FROM {{DATABASE}}.{{KF}}.KF_REPORT_USAGE GROUP BY 1
)
SELECT 'OBJ:' || o.OBJECT_KEY, o.OBJECT_TYPE, o.OBJECT_KEY, o.DATA_LAYER, o.OBJECT_NAME, NULL, NULL,
       o.OBJECT_TYPE || ' ' || o.OBJECT_KEY || ' in the ' || o.DATA_LAYER || ' layer of the Accounts Payable model. '
       || 'Description: ' || COALESCE(o.DESCRIPTION, 'MISSING (AI draft: ' || COALESCE(o.AI_SUGGESTED_DESCRIPTION, 'none') || ')') || '. '
       || 'Refresh: ' || COALESCE(o.REFRESH_FREQUENCY, 'unknown') || COALESCE(' by task ' || o.REFRESHED_BY_TASK, '') || '. '
       || 'Owner: ' || COALESCE(o.DATA_OWNER, 'unknown') || '. Steward: ' || COALESCE(o.DATA_STEWARD, 'unknown') || '. '
       || 'Certification: ' || COALESCE(o.CERTIFICATION, 'unknown') || '. Source system: ' || COALESCE(o.SOURCE_SYSTEM, 'unknown') || '. '
       || 'Data class: ' || COALESCE(o.DATA_CLASS, 'unknown') || '. Technical owner: ' || COALESCE(o.TECHNICAL_OWNER, 'unknown') || '. '
       || 'Loaded from: ' || COALESCE(f.LOADED_FROM, 'source system') || '. Feeds: ' || COALESCE(t.FEEDS, 'nothing downstream') || '. '
       || COALESCE('Used in reports/extracts: ' || cu.USED_IN || '. ', '')
       || COALESCE('Requirements: ' || ro.REQS || '. ', '')
       || 'Masked columns: ' || COALESCE(o.MASKED_COLUMN_COUNT, 0) || ' of ' || COALESCE(o.COLUMN_COUNT, 0) || '. Columns: ' || COALESCE(c.COLUMN_LIST, '')
FROM {{DATABASE}}.{{KF}}.KF_OBJECTS o
LEFT JOIN consumers cu ON cu.OBJECT_KEY = o.OBJECT_KEY
LEFT JOIN req_obj ro ON ro.OBJECT_KEY = o.OBJECT_KEY
LEFT JOIN cols c ON c.OBJECT_KEY = o.OBJECT_KEY
LEFT JOIN feeds f ON f.OBJECT_KEY = o.OBJECT_KEY
LEFT JOIN feeds_to t ON t.OBJECT_KEY = o.OBJECT_KEY
UNION ALL
SELECT 'COL:' || k.COLUMN_KEY, 'Column', k.COLUMN_KEY, k.DATA_LAYER, k.OBJECT_NAME, k.COLUMN_NAME, k.BUSINESS_NAME,
       'Column ' || k.COLUMN_KEY || ' (business name: ' || k.BUSINESS_NAME || ', ' || COALESCE(k.DATA_TYPE_FULL, k.DATA_TYPE)
       || COALESCE(', ' || k.KEY_ROLE, '') || ', ' || k.DATA_LAYER || ' layer). '
       || 'Description: ' || COALESCE(k.DESCRIPTION, 'MISSING (AI draft: ' || COALESCE(k.AI_SUGGESTED_DESCRIPTION, 'none') || ')') || '. '
       || 'Sensitivity: ' || k.SENSITIVITY || '. Masked: '
       || CASE WHEN k.MASKING_POLICY IS NOT NULL THEN 'yes, policy ' || k.MASKING_POLICY
               WHEN k.IS_MASKED THEN 'yes, inherited from ' || k.MASKED_VIA ELSE 'no' END || '. '
       || COALESCE('Classified by Snowflake as ' || k.SEMANTIC_CATEGORY || '. ', '')
       || COALESCE('Comes from: ' || d.SOURCES || '. ', '')
       || COALESCE('Full lineage back to source: ' || p.PATH_TEXT || '. Origin (system of record): ' || p.ORIGIN_TEXT || '. ', '')
       || COALESCE('Used downstream by (impact if it changes): ' || ub.USED_BY || '. ', '')
       || COALESCE('Requirements: ' || rc.REQS || '.', '')
FROM {{DATABASE}}.{{KF}}.KF_COLUMNS k
LEFT JOIN used_by ub ON ub.CHANGED_OBJECT = k.OBJECT_KEY AND ub.CHANGED_COLUMN = k.COLUMN_NAME
LEFT JOIN req_col rc ON rc.OBJECT_KEY = k.OBJECT_KEY AND rc.COLUMN_NAME = k.COLUMN_NAME
LEFT JOIN direct d ON d.TARGET_OBJECT = k.OBJECT_KEY AND d.TARGET_COLUMN = k.COLUMN_NAME
LEFT JOIN path p ON p.REPORT_OBJECT = k.OBJECT_KEY AND p.REPORT_COLUMN = k.COLUMN_NAME
WHERE k.COLUMN_NAME NOT IN ('_REPLICATED_AT', 'EDW_LOAD_TS', 'DM_LOAD_TS')
UNION ALL
SELECT 'TERM:' || TERM, 'Business term', TERM, NULL, NULL, NULL, TERM,
       'Business term ' || TERM || ' (' || STATUS || COALESCE(', approved ' || TO_VARCHAR(APPROVED_ON), '') || '). Definition: '
       || DEFINITION || COALESCE(' Calculation: ' || CALCULATION, '') || ' Implemented in: ' || IMPLEMENTED_IN
       || '. Synonyms: ' || COALESCE(SYNONYMS, '') || '. Owner: ' || OWNER || '. Source: ' || SOURCE_DOCUMENT || '.'
FROM {{DATABASE}}.{{KF}}.KF_GLOSSARY
UNION ALL
SELECT 'REL:' || RELATIONSHIP_ID, 'Relationship', FROM_OBJECT || ' -> ' || TO_OBJECT, NULL, FROM_OBJECT, NULL, NULL,
       RELATIONSHIP_TYPE || ': ' || FROM_OBJECT || ' -> ' || TO_OBJECT
       || COALESCE(' on ' || JOIN_COLUMNS, '') || COALESCE(' (' || CARDINALITY || ')', '')
       || COALESCE(' via ' || PROCESS, '') || '. ' || DESCRIPTION
FROM {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS
UNION ALL
SELECT 'TASK:' || TASK_NAME, 'Refresh job', TASK_NAME, NULL, NULL, NULL, NULL,
       'Refresh job (task) ' || SCHEMA_NAME || '.' || TASK_NAME || ': ' || COALESCE(DESCRIPTION, '') || ' Schedule: '
       || COALESCE(SCHEDULE, 'runs after ' || RUNS_AFTER, 'not scheduled') || '. State: ' || STATE || '. Refreshes: ' || COALESCE(REFRESHES_OBJECTS, '?') || '.'
FROM {{DATABASE}}.{{KF}}.KF_REFRESH_SCHEDULE
UNION ALL
SELECT 'REQ:' || r.REQ_ID, 'Requirement', r.REQ_ID || ' ' || r.TITLE, NULL, NULL, NULL, r.TITLE,
       'Requirement ' || r.REQ_ID || ': ' || r.TITLE || '. ' || r.REQUIREMENT_TEXT || ' Priority: ' || r.PRIORITY
       || '. Status: ' || r.STATUS || '. Source: ' || r.SOURCE_DOCUMENT || '. Traced to: '
       || COALESCE(rt.TARGETS, 'nothing yet') || '.'
FROM {{DATABASE}}.{{KF}}.KF_REQUIREMENTS r
LEFT JOIN req_targets rt ON rt.REQ_ID = r.REQ_ID
UNION ALL
SELECT 'CHG:' || CHANGE_ID, 'Mapping change', CHANGE_ID, NULL, SPLIT_PART(TARGET_OBJECT, '.', 2), TARGET_COLUMN, NULL,
       'Mapping change ' || CHANGE_ID || ' (' || TO_VARCHAR(CHANGE_DATE) || ', mapping version ' || MAPPING_VERSION || ', ' || STATUS
       || ') on ' || TARGET_OBJECT || COALESCE('.' || TARGET_COLUMN, '') || '. Type: ' || CHANGE_TYPE || '. What changed: '
       || CHANGE_DESCRIPTION || ' Why: ' || REASON || ' Requirements: ' || COALESCE(RELATED_REQ, '-') || '. Prepared by '
       || PREPARED_BY || '; reviewed by ' || REVIEWED_BY || '; approved by ' || COALESCE(APPROVED_BY, 'not yet approved') || '.'
FROM {{DATABASE}}.{{KF}}.KF_MAPPING_CHANGE_LOG
UNION ALL
SELECT 'USE:' || CONSUMER_NAME, CONSUMER_TYPE, CONSUMER_NAME, 'Consumer', MAX(OBJECT_KEY), NULL, NULL,
       CONSUMER_TYPE || ' ' || CONSUMER_NAME || ' (' || MAX(TOOL) || ', ' || MAX(FREQUENCY) || ', used by ' || MAX(AUDIENCE)
       || ', owner ' || MAX(OWNER) || ') reads ' || LISTAGG(DISTINCT OBJECT_KEY || '.' || COLUMN_NAME, ', ') || '.'
FROM {{DATABASE}}.{{KF}}.KF_REPORT_USAGE GROUP BY CONSUMER_NAME, CONSUMER_TYPE
UNION ALL
SELECT 'CARD:' || VIEW_KEY, 'Reporting view card', VIEW_KEY, 'Reporting', VIEW_NAME, NULL, NULL,
       'Data dictionary card for reporting view ' || DATABASE_NAME || '.' || VIEW_KEY || '. Description: ' || COALESCE(VIEW_DESCRIPTION, '-')
       || '. Data class: ' || COALESCE(DATA_CLASS, '-') || '. Portfolio/domain: ' || COALESCE(PORTFOLIO_DOMAIN, '-') || ' / ' || COALESCE(DATA_PRODUCT, '-')
       || '. Data owner: ' || COALESCE(DATA_OWNER, '-') || '. Technical owner: ' || COALESCE(TECHNICAL_OWNER, '-')
       || '. Refresh: ' || COALESCE(REFRESH_FREQUENCY, '-') || ' (jobs: ' || COALESCE(REFRESH_JOBS, '-') || ')'
       || '. Primary key: ' || COALESCE(PRIMARY_KEY, 'none') || '. Business key: ' || COALESCE(BUSINESS_KEY, 'none')
       || '. Masked columns: ' || COALESCE(MASKED_COLUMNS, 'none') || '. Reads datamart table: ' || COALESCE(DM_SOURCE_TABLES, '-')
       || '. Upstream: ' || COALESCE(UPSTREAM_OBJECTS, '-') || '. SAP source fields: ' || COALESCE(SAP_SOURCE_FIELDS, '-')
       || '. Used by: ' || COALESCE(DOWNSTREAM_CONSUMERS, 'nothing registered') || '. Key filters: ' || COALESCE(KEY_FILTERS, 'none')
       || '. KPIs: ' || COALESCE(KPIS, 'none') || '. Alternative views on the same datamart table: ' || COALESCE(ALTERNATIVE_VIEWS, 'none')
       || '. Requirements: ' || COALESCE(REQUIREMENTS, 'none') || '.'
FROM {{DATABASE}}.{{KF}}.KF_REPORTING_VIEWS
UNION ALL
SELECT 'TCODE:' || MAP_ID, 'SAP T-code field', TCODE || ' ' || SAP_TABLE || '.' || SAP_FIELD, 'SAP', SAP_TABLE, SAP_FIELD, SAP_FIELD_DESCRIPTION,
       'SAP T-code ' || TCODE || ' (' || TCODE_DESCRIPTION || ', process: ' || BUSINESS_PROCESS || ') uses SAP table ' || SAP_TABLE
       || ' (' || SAP_TABLE_DESCRIPTION || ') field ' || SAP_FIELD || ' (' || SAP_FIELD_DESCRIPTION || '). Ingested: '
       || IFF(IS_INGESTED, 'yes, in ' || LANDING_OBJECT, 'no') || '. EDW: ' || COALESCE(RELATED_EDW_OBJECT || '.' || RELATED_EDW_COLUMN, 'not modelled')
       || '. Mapping status: ' || MAPPING_STATUS || ' (owner ' || MAPPING_OWNER || '). Action: ' || NOTE
FROM {{DATABASE}}.{{KF}}.KF_SAP_TCODE_MAP
"""
$$;

-- Keeps the catalog in sync after the nightly loads (created suspended; resume if wanted)
CREATE OR REPLACE TASK {{DATABASE}}.{{EDW}}.TASK_REFRESH_KNOWLEDGE_FABRIC
  WAREHOUSE = {{WAREHOUSE}}
  COMMENT = 'Rebuilds the Knowledge Fabric metadata after the datamart load. Refreshes: KF_OBJECTS,KF_COLUMNS,KF_CATALOG'
  AFTER {{DATABASE}}.{{EDW}}.TASK_LOAD_AP_DATAMART
AS
  CALL {{DATABASE}}.{{KF}}.REFRESH_KNOWLEDGE_FABRIC(FALSE);

-- First run: read all metadata and draft descriptions for undocumented assets with AI_COMPLETE
CALL REFRESH_KNOWLEDGE_FABRIC(TRUE);
