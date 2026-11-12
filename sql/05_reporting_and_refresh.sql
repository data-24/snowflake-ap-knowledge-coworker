-- =====================================================================
-- 05 REPORTING VIEWS + REFRESH SCHEDULE
--   Reporting views read ONLY the datamart: select, rename and simple key filters, no business logic.
--   Tasks simulate the scheduler: EDW load daily 02:00 UTC, datamart load right after it.
--   Tasks are created SUSPENDED (no cost). Their schedule is still real metadata the agent reads.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{REPORTING}};

CREATE OR REPLACE VIEW VW_AP_OPEN_ITEMS (
  AS_OF_DATE        COMMENT 'As-of date: date the aging was calculated.',
  COMPANY_CODE      COMMENT 'Company code: legal entity of the invoice.',
  COMPANY_NAME      COMMENT 'Company name: name of the company code.',
  VENDOR_ID         COMMENT 'Vendor ID: vendor account of the invoice.',
  VENDOR_NAME       COMMENT 'Vendor name: vendor or one-time payee name (one-time payee names masked).',
  IS_ONE_TIME_VENDOR COMMENT 'One-time vendor flag: TRUE for invoices posted to the one-time vendor account.',
  VENDOR_COUNTRY    COMMENT 'Vendor country: payee country for one-time vendors, otherwise the vendor master country.',
  DOCUMENT_NUMBER   COMMENT 'Document number: accounting document number.',
  DOCUMENT_TYPE     COMMENT 'Document type: vendor invoice or vendor credit memo.',
  INVOICE_REFERENCE COMMENT 'Invoice reference: vendor invoice number.',
  DOCUMENT_DATE     COMMENT 'Document date: invoice date.',
  NET_DUE_DATE      COMMENT 'Net due date: baseline date + payment term days.',
  DAYS_PAST_DUE     COMMENT 'Days past due: as-of date - net due date.',
  AGING_BUCKET      COMMENT 'Aging bucket: Not yet due, 1-30, 31-60, 61-90, 91-180, Over 180.',
  AGING_BUCKET_ORDER COMMENT 'Aging bucket order: sort order of the bucket.',
  IS_OVERDUE        COMMENT 'Overdue flag: TRUE when days past due > 0.',
  PAYMENT_BLOCK,
  OPEN_AMOUNT_LOCAL COMMENT 'Open amount (local currency): signed open amount in company code currency.',
  LOCAL_CURRENCY    COMMENT 'Local currency: company code currency.',
  OPEN_AMOUNT_USD   COMMENT 'Open amount (USD): open amount converted to USD.'
)
COMMENT = 'AP open items with aging, for BI dashboards. Reads AP_DATAMART.DM_AP_OPEN_ITEMS only (rename, no logic).'
AS
SELECT AS_OF_DATE, COMPANY_CODE, COMPANY_NAME, VENDOR_ID, VENDOR_NAME, IS_ONE_TIME_VENDOR,
       VENDOR_COUNTRY_NAME, DOCUMENT_NUMBER, DOCUMENT_TYPE_DESC, INVOICE_REFERENCE, DOCUMENT_DATE,
       NET_DUE_DATE, DAYS_PAST_DUE, AGING_BUCKET, AGING_BUCKET_ORDER, IS_OVERDUE, PAYMENT_BLOCK,
       AMOUNT_LOCAL, LOCAL_CURRENCY, AMOUNT_USD
FROM {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS;

CREATE OR REPLACE VIEW VW_AP_OVERDUE_ITEMS (
  AS_OF_DATE        COMMENT 'As-of date: date the aging was calculated.',
  COMPANY_CODE      COMMENT 'Company code: legal entity of the invoice.',
  COMPANY_NAME      COMMENT 'Company name: name of the company code.',
  VENDOR_ID         COMMENT 'Vendor ID: vendor account of the invoice.',
  VENDOR_NAME       COMMENT 'Vendor name: vendor or one-time payee name (one-time payee names masked).',
  VENDOR_COUNTRY    COMMENT 'Vendor country: payee country for one-time vendors, otherwise the vendor master country.',
  DOCUMENT_NUMBER   COMMENT 'Document number: accounting document number.',
  INVOICE_REFERENCE COMMENT 'Invoice reference: vendor invoice number.',
  NET_DUE_DATE      COMMENT 'Net due date: baseline date + payment term days.',
  DAYS_PAST_DUE     COMMENT 'Days past due: as-of date - net due date (always > 0 in this view).',
  AGING_BUCKET      COMMENT 'Aging bucket: 1-30, 31-60, 61-90, 91-180 or Over 180.',
  PAYMENT_BLOCK     COMMENT 'Payment block: A = blocked for payment (for example disputed).',
  OPEN_AMOUNT_USD   COMMENT 'Overdue amount (USD): open amount of the overdue item converted to USD.'
)
COMMENT = 'Overdue AP items for follow-up. Reads AP_DATAMART.DM_AP_OPEN_ITEMS only; key filter IS_OVERDUE = TRUE (rename and filter, no other logic).'
AS
SELECT AS_OF_DATE, COMPANY_CODE, COMPANY_NAME, VENDOR_ID, VENDOR_NAME, VENDOR_COUNTRY_NAME, DOCUMENT_NUMBER,
       INVOICE_REFERENCE, NET_DUE_DATE, DAYS_PAST_DUE, AGING_BUCKET, PAYMENT_BLOCK, AMOUNT_USD
FROM {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS
WHERE IS_OVERDUE;

CREATE OR REPLACE VIEW VW_AP_AGING_SUMMARY (
  AS_OF_DATE         COMMENT 'As-of date: date the aging was calculated.',
  COMPANY_CODE       COMMENT 'Company code: legal entity.',
  COMPANY_NAME       COMMENT 'Company name: name of the company code.',
  VENDOR_COUNTRY     COMMENT 'Vendor country: vendor or one-time payee country.',
  AGING_BUCKET       COMMENT 'Aging bucket: bucket of days past due.',
  AGING_BUCKET_ORDER COMMENT 'Aging bucket order: sort order of the bucket.',
  OPEN_ITEM_COUNT    COMMENT 'Open item count: number of open vendor line items.',
  OPEN_AMOUNT_USD    COMMENT 'Open amount (USD): sum of open amounts in USD.'
)
COMMENT = 'AP aging summary for BI dashboards. Reads AP_DATAMART.DM_AP_AGING_SUMMARY only (rename, no logic).'
AS
SELECT AS_OF_DATE, COMPANY_CODE, COMPANY_NAME, VENDOR_COUNTRY_NAME, AGING_BUCKET, AGING_BUCKET_ORDER,
       OPEN_ITEM_COUNT, OPEN_AMOUNT_USD
FROM {{DATABASE}}.{{DATAMART}}.DM_AP_AGING_SUMMARY;

CREATE OR REPLACE VIEW VW_AP_VENDOR (
  VENDOR_ID          COMMENT 'Vendor ID: vendor number.',
  VENDOR_NAME        COMMENT 'Vendor name: legal name of the vendor.',
  VENDOR_COUNTRY     COMMENT 'Vendor country: vendor master country name.',
  VENDOR_CITY        COMMENT 'Vendor city: city of the vendor address.',
  IS_ONE_TIME_VENDOR COMMENT 'One-time vendor flag: TRUE for the one-time vendor account.',
  TAX_ID             COMMENT 'Tax ID: vendor tax registration number. Masked for non-power users.',
  BANK_ACCOUNT       COMMENT 'Bank account: vendor bank account number. Masked for non-power users.',
  IS_DELETED         COMMENT 'Deleted vendor flag: TRUE when marked for deletion.'
)
COMMENT = 'AP vendor list for BI. Reads AP_DATAMART.DM_AP_VENDOR only (rename, no logic).'
AS
SELECT VENDOR_ID, VENDOR_NAME, VENDOR_COUNTRY_NAME, VENDOR_CITY, IS_ONE_TIME_VENDOR,
       VENDOR_TAX_ID, VENDOR_BANK_ACCOUNT, IS_DELETED
FROM {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR;

-- ---------------------------------------------------------------------
-- Refresh schedule (the comment "Refreshes: ..." is read by the Knowledge Fabric).
-- All tasks of one task graph must be in the same schema, so they all live in the EDW schema.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TASK {{DATABASE}}.{{EDW}}.TASK_LOAD_EDW
  WAREHOUSE = {{WAREHOUSE}}
  SCHEDULE = '{{EDW_SCHEDULE}}'
  COMMENT = 'Daily EDW load at 02:00 UTC, after the landing tables are replicated. Refreshes: DIM_COMPANY_CODE,DIM_VENDOR,FACT_ACCOUNTS_PAYABLE_GLOBAL'
AS
  CALL {{DATABASE}}.{{EDW}}.LOAD_EDW();

CREATE OR REPLACE TASK {{DATABASE}}.{{EDW}}.TASK_LOAD_AP_DATAMART
  WAREHOUSE = {{WAREHOUSE}}
  COMMENT = 'Runs right after TASK_LOAD_EDW (daily, about 02:15 UTC). Refreshes: DM_AP_OPEN_ITEMS,DM_AP_AGING_SUMMARY,DM_AP_VENDOR'
  AFTER {{DATABASE}}.{{EDW}}.TASK_LOAD_EDW
AS
  CALL {{DATABASE}}.{{DATAMART}}.LOAD_AP_DATAMART();
