-- =====================================================================
-- 04 AP DATAMART: where the AP business logic lives
--   AP_AGING_BUCKETS     reference table: the 6 official aging buckets
--   DM_AP_OPEN_ITEMS     open vendor items with net due date, days past due, aging bucket, USD amount
--   DM_AP_AGING_SUMMARY  open amount and item count by company code, vendor country and bucket
--   DM_AP_VENDOR         AP vendor list for reporting
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{DATAMART}};

CREATE OR REPLACE TABLE AP_AGING_BUCKETS (
  BUCKET_ORDER NUMBER(2)    COMMENT 'Bucket order: sort order of the bucket.',
  BUCKET_NAME  VARCHAR(20)  COMMENT 'Aging bucket: name of the bucket.',
  MIN_DAYS     NUMBER(6)    COMMENT 'Minimum days past due: lower bound (inclusive).',
  MAX_DAYS     NUMBER(6)    COMMENT 'Maximum days past due: upper bound (inclusive).',
  DESCRIPTION  VARCHAR(200) COMMENT 'Bucket description: what the bucket means.'
) COMMENT = 'Official AP aging buckets (approved definition, BRD v1.2). Days past due = as-of date - net due date.';

INSERT INTO AP_AGING_BUCKETS VALUES
  (1, 'Not yet due', -99999, 0,     'Open item whose net due date is today or in the future.'),
  (2, '1-30',        1,      30,    'Open item 1 to 30 days past its net due date.'),
  (3, '31-60',       31,     60,    'Open item 31 to 60 days past its net due date.'),
  (4, '61-90',       61,     90,    'Open item 61 to 90 days past its net due date.'),
  (5, '91-180',      91,     180,   'Open item 91 to 180 days past its net due date.'),
  (6, 'Over 180',    181,    99999, 'Open item more than 180 days past its net due date.');

CREATE OR REPLACE TABLE DM_AP_OPEN_ITEMS (
  AS_OF_DATE          DATE         COMMENT 'As-of date: date the aging was calculated (datamart load date).',
  AP_LINE_ID          VARCHAR(30)  COMMENT 'AP line ID: company code-document number-fiscal year-line item.',
  COMPANY_CODE        VARCHAR(4)   COMMENT 'Company code: legal entity of the invoice.',
  COMPANY_NAME        VARCHAR(50)  COMMENT 'Company name: name of the company code.',
  VENDOR_ID           VARCHAR(10)  COMMENT 'Vendor ID: vendor account of the invoice.',
  VENDOR_NAME         VARCHAR(80)  COMMENT 'Vendor name: vendor master name, or the payee name for one-time vendors. One-time payee names are masked.',
  IS_ONE_TIME_VENDOR  BOOLEAN      COMMENT 'One-time vendor flag: TRUE when the invoice was posted to the one-time vendor account.',
  VENDOR_COUNTRY_CODE VARCHAR(3)   COMMENT 'Vendor country code: payee country for one-time vendors, otherwise the vendor master country.',
  VENDOR_COUNTRY_NAME VARCHAR(50)  COMMENT 'Vendor country: payee country for one-time vendors (SAP_BSEC), otherwise the vendor master country (SAP_LFA1).',
  DOCUMENT_NUMBER     VARCHAR(10)  COMMENT 'Document number: accounting document number.',
  DOCUMENT_TYPE_DESC  VARCHAR(30)  COMMENT 'Document type: vendor invoice or vendor credit memo.',
  INVOICE_REFERENCE   VARCHAR(16)  COMMENT 'Invoice reference: vendor invoice number.',
  DOCUMENT_DATE       DATE         COMMENT 'Document date: invoice date.',
  POSTING_DATE        DATE         COMMENT 'Posting date: date posted in the ledger.',
  NET_DUE_DATE        DATE         COMMENT 'Net due date: baseline date + payment term days.',
  DAYS_PAST_DUE       NUMBER(6)    COMMENT 'Days past due: as-of date - net due date. Zero or negative = not yet due.',
  AGING_BUCKET        VARCHAR(20)  COMMENT 'Aging bucket: bucket of days past due, from AP_AGING_BUCKETS.',
  AGING_BUCKET_ORDER  NUMBER(2)    COMMENT 'Aging bucket order: sort order of the bucket.',
  IS_OVERDUE          BOOLEAN      COMMENT 'Overdue flag: TRUE when days past due > 0.',
  PAYMENT_BLOCK       VARCHAR(1),
  AMOUNT_LOCAL        NUMBER(15,2) COMMENT 'Open amount (local currency): signed open amount in company code currency.',
  LOCAL_CURRENCY      VARCHAR(5)   COMMENT 'Local currency: company code currency.',
  AMOUNT_USD          NUMBER(15,2) COMMENT 'Open amount (USD): local amount x USD exchange rate of the company code.',
  DM_LOAD_TS          TIMESTAMP_NTZ COMMENT 'Datamart load time: when the datamart load last wrote the row.'
) COMMENT = 'AP open items with aging. Source: EDW.FACT_ACCOUNTS_PAYABLE_GLOBAL (open items only) + DIM_VENDOR + DIM_COMPANY_CODE + AP_AGING_BUCKETS. Grain: one row per open vendor line item.';

CREATE OR REPLACE TABLE DM_AP_AGING_SUMMARY (
  AS_OF_DATE          DATE         COMMENT 'As-of date: date the aging was calculated.',
  COMPANY_CODE        VARCHAR(4)   COMMENT 'Company code: legal entity.',
  COMPANY_NAME        VARCHAR(50)  COMMENT 'Company name: name of the company code.',
  VENDOR_COUNTRY_NAME VARCHAR(50)  COMMENT 'Vendor country: vendor or one-time payee country.',
  AGING_BUCKET        VARCHAR(20)  COMMENT 'Aging bucket: bucket of days past due.',
  AGING_BUCKET_ORDER  NUMBER(2)    COMMENT 'Aging bucket order: sort order of the bucket.',
  OPEN_ITEM_COUNT     NUMBER(10)   COMMENT 'Open item count: number of open vendor line items.',
  OPEN_AMOUNT_USD     NUMBER(18,2) COMMENT 'Open amount (USD): sum of open amounts in USD.',
  DM_LOAD_TS          TIMESTAMP_NTZ COMMENT 'Datamart load time: when the datamart load last wrote the row.'
) COMMENT = 'AP aging summary. Source: DM_AP_OPEN_ITEMS. Grain: as-of date x company code x vendor country x aging bucket.';

CREATE OR REPLACE TABLE DM_AP_VENDOR (
  VENDOR_ID           VARCHAR(10)  COMMENT 'Vendor ID: vendor number.',
  VENDOR_NAME         VARCHAR(80)  COMMENT 'Vendor name: legal name of the vendor.',
  VENDOR_COUNTRY_CODE VARCHAR(3)   COMMENT 'Vendor country code: vendor master country key.',
  VENDOR_COUNTRY_NAME VARCHAR(50)  COMMENT 'Vendor country: vendor master country name.',
  VENDOR_CITY         VARCHAR(40)  COMMENT 'Vendor city: city of the vendor address.',
  IS_ONE_TIME_VENDOR  BOOLEAN      COMMENT 'One-time vendor flag: TRUE for the one-time vendor account.',
  VENDOR_TAX_ID       VARCHAR(20)  COMMENT 'Vendor tax ID: tax registration number. Restricted, masked.',
  VENDOR_BANK_ACCOUNT VARCHAR(18)  COMMENT 'Vendor bank account: bank account number. Restricted, masked.',
  IS_DELETED          BOOLEAN      COMMENT 'Deleted vendor flag: TRUE when marked for deletion.',
  DM_LOAD_TS          TIMESTAMP_NTZ COMMENT 'Datamart load time: when the datamart load last wrote the row.'
) COMMENT = 'AP vendor list for reporting. Source: EDW.DIM_VENDOR. Grain: one row per vendor.';

-- ---------------------------------------------------------------------
-- Load procedure (called now, and daily by TASK_LOAD_AP_DATAMART right after the EDW load)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE LOAD_AP_DATAMART()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Loads the AP datamart (open items, aging, vendors) from the EDW.'
EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT OVERWRITE INTO {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS
  SELECT CURRENT_DATE(), f.AP_LINE_ID, f.COMPANY_CODE, c.COMPANY_NAME, f.VENDOR_ID,
         IFF(v.IS_ONE_TIME_VENDOR, f.ONE_TIME_VENDOR_NAME, v.VENDOR_NAME),
         v.IS_ONE_TIME_VENDOR,
         IFF(v.IS_ONE_TIME_VENDOR, f.ONE_TIME_VENDOR_COUNTRY_CODE, v.VENDOR_COUNTRY_CODE),
         IFF(v.IS_ONE_TIME_VENDOR, f.ONE_TIME_VENDOR_COUNTRY_NAME, v.VENDOR_COUNTRY_NAME),
         f.DOCUMENT_NUMBER, f.DOCUMENT_TYPE_DESC, f.INVOICE_REFERENCE, f.DOCUMENT_DATE, f.POSTING_DATE,
         f.NET_DUE_DATE,
         DATEDIFF(day, f.NET_DUE_DATE, CURRENT_DATE()),
         b.BUCKET_NAME, b.BUCKET_ORDER,
         DATEDIFF(day, f.NET_DUE_DATE, CURRENT_DATE()) > 0,
         f.PAYMENT_BLOCK, f.AMOUNT_LOCAL, f.LOCAL_CURRENCY,
         ROUND(f.AMOUNT_LOCAL * c.USD_EXCHANGE_RATE, 2),
         CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL f
  JOIN {{DATABASE}}.{{EDW}}.DIM_COMPANY_CODE c ON c.COMPANY_CODE = f.COMPANY_CODE
  JOIN {{DATABASE}}.{{EDW}}.DIM_VENDOR v ON v.VENDOR_ID = f.VENDOR_ID
  JOIN {{DATABASE}}.{{DATAMART}}.AP_AGING_BUCKETS b
    ON DATEDIFF(day, f.NET_DUE_DATE, CURRENT_DATE()) BETWEEN b.MIN_DAYS AND b.MAX_DAYS
  WHERE f.IS_OPEN_ITEM;

  INSERT OVERWRITE INTO {{DATABASE}}.{{DATAMART}}.DM_AP_AGING_SUMMARY
  SELECT AS_OF_DATE, COMPANY_CODE, COMPANY_NAME, VENDOR_COUNTRY_NAME, AGING_BUCKET, AGING_BUCKET_ORDER,
         COUNT(*), SUM(AMOUNT_USD), CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS
  GROUP BY 1, 2, 3, 4, 5, 6;

  INSERT OVERWRITE INTO {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR
  SELECT VENDOR_ID, VENDOR_NAME, VENDOR_COUNTRY_CODE, VENDOR_COUNTRY_NAME, VENDOR_CITY, IS_ONE_TIME_VENDOR,
         VENDOR_TAX_ID, VENDOR_BANK_ACCOUNT, IS_DELETED, CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{EDW}}.DIM_VENDOR;

  RETURN 'AP datamart loaded';
END;
$$;

CALL LOAD_AP_DATAMART();
