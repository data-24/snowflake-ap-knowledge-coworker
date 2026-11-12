-- =====================================================================
-- 03 EDW: global AP fact and master dimensions
--   DIM_COMPANY_CODE               company codes + synthetic USD exchange rate
--   DIM_VENDOR                     vendor master: country, tax number, bank account
--   FACT_ACCOUNTS_PAYABLE_GLOBAL   one row per vendor line item (SAP_BSEG where account type = K)
-- Tables are created once (comments, tags and masking stay on them); the load procedure
-- refreshes them with INSERT OVERWRITE, so the metadata is never lost on a reload.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{EDW}};

CREATE OR REPLACE TABLE DIM_COMPANY_CODE (
  COMPANY_CODE         VARCHAR(4)   COMMENT 'Company code: legal entity that posts the invoice.',
  COMPANY_NAME         VARCHAR(50)  COMMENT 'Company name: name of the company code.',
  COMPANY_COUNTRY_CODE VARCHAR(3)   COMMENT 'Company country code: country key of the company code.',
  COMPANY_COUNTRY_NAME VARCHAR(50)  COMMENT 'Company country: country name of the company code.',
  LOCAL_CURRENCY       VARCHAR(5)   COMMENT 'Local currency: currency of the company code books.',
  USD_EXCHANGE_RATE    NUMBER(12,6) COMMENT 'USD exchange rate: synthetic fixed rate used to convert local currency to USD (1 local unit = rate USD).',
  EDW_LOAD_TS          TIMESTAMP_NTZ COMMENT 'EDW load time: when the EDW load last wrote the row.'
) COMMENT = 'Company code dimension. Source: SAP_T001 + SAP_T005T. Grain: one row per company code.';

CREATE OR REPLACE TABLE DIM_VENDOR (
  VENDOR_ID            VARCHAR(10)  COMMENT 'Vendor ID: vendor number from the vendor master.',
  VENDOR_NAME          VARCHAR(80)  COMMENT 'Vendor name: legal name of the vendor.',
  VENDOR_COUNTRY_CODE  VARCHAR(3)   COMMENT 'Vendor country code: country key of the vendor address (vendor master). Empty for the one-time vendor account.',
  VENDOR_COUNTRY_NAME  VARCHAR(50)  COMMENT 'Vendor country: country name of the vendor address (vendor master).',
  VENDOR_CITY          VARCHAR(40)  COMMENT 'Vendor city: city of the vendor address.',
  VENDOR_ACCOUNT_GROUP VARCHAR(4)   COMMENT 'Vendor account group: KRED = regular vendor, CPD = one-time vendor.',
  IS_ONE_TIME_VENDOR   BOOLEAN      COMMENT 'One-time vendor flag: TRUE when the account group is CPD. The real payee is stored per invoice.',
  VENDOR_TAX_ID        VARCHAR(20)  COMMENT 'Vendor tax ID: tax registration number. Restricted, masked.',
  VENDOR_BANK_COUNTRY  VARCHAR(3)   COMMENT 'Vendor bank country: country of the vendor bank.',
  VENDOR_BANK_ACCOUNT  VARCHAR(18)  COMMENT 'Vendor bank account: bank account number. Restricted, masked.',
  IS_DELETED           BOOLEAN      COMMENT 'Deleted vendor flag: TRUE when the vendor is marked for deletion.',
  VENDOR_CREATED_DATE  DATE         COMMENT 'Vendor created date: date the vendor was created.',
  EDW_LOAD_TS          TIMESTAMP_NTZ COMMENT 'EDW load time: when the EDW load last wrote the row.'
) COMMENT = 'Vendor dimension. Source: SAP_LFA1 + SAP_T005T + SAP_LFBK. Grain: one row per vendor.';

CREATE OR REPLACE TABLE FACT_ACCOUNTS_PAYABLE_GLOBAL (
  AP_LINE_ID                   VARCHAR(30)  COMMENT 'AP line ID: company code-document number-fiscal year-line item.',
  COMPANY_CODE                 VARCHAR(4)   COMMENT 'Company code: legal entity of the invoice.',
  DOCUMENT_NUMBER              VARCHAR(10)  COMMENT 'Document number: accounting document number.',
  FISCAL_YEAR                  NUMBER(4)    COMMENT 'Fiscal year: fiscal year of the document.',
  LINE_ITEM                    VARCHAR(3)   COMMENT 'Line item: line number within the document.',
  DOCUMENT_TYPE                VARCHAR(2)   COMMENT 'Document type: KR = vendor invoice, KG = vendor credit memo.',
  DOCUMENT_TYPE_DESC           VARCHAR(30)  COMMENT 'Document type description: business name of the document type.',
  INVOICE_REFERENCE            VARCHAR(16)  COMMENT 'Invoice reference: vendor invoice number.',
  VENDOR_ID                    VARCHAR(10)  COMMENT 'Vendor ID: vendor account the invoice is posted to.',
  ONE_TIME_VENDOR_NAME         VARCHAR(80)  COMMENT 'One-time vendor name: payee name from SAP_BSEC for one-time vendor invoices. Restricted, masked.',
  ONE_TIME_VENDOR_COUNTRY_CODE VARCHAR(3)   COMMENT 'One-time vendor country code: payee country key from SAP_BSEC.',
  ONE_TIME_VENDOR_COUNTRY_NAME VARCHAR(50)  COMMENT 'One-time vendor country: payee country name (SAP_BSEC country key translated with SAP_T005T).',
  DOCUMENT_DATE                DATE         COMMENT 'Document date: invoice date.',
  POSTING_DATE                 DATE         COMMENT 'Posting date: date posted in the ledger.',
  BASELINE_DATE                DATE         COMMENT 'Baseline date: start date for the payment terms.',
  PAYMENT_TERMS                VARCHAR(4)   COMMENT 'Payment terms: payment terms key.',
  PAYMENT_TERMS_DAYS           NUMBER(3)    COMMENT 'Payment term days: days from baseline date to due date.',
  NET_DUE_DATE                 DATE         COMMENT 'Net due date: date the invoice is due = baseline date + payment term days.',
  CLEARING_DATE                DATE         COMMENT 'Clearing date: date the item was paid. Empty = open.',
  CLEARING_DOCUMENT            VARCHAR(10)  COMMENT 'Clearing document: payment document number.',
  IS_OPEN_ITEM                 BOOLEAN      COMMENT 'Open item flag: TRUE when the item is not cleared (clearing date is empty).',
  DEBIT_CREDIT_INDICATOR       VARCHAR(1)   COMMENT 'Debit/credit indicator: H = credit (invoice), S = debit (credit memo).',
  AMOUNT_LOCAL                 NUMBER(15,2) COMMENT 'Amount (local currency): signed amount owed to the vendor; invoices positive, credit memos negative.',
  LOCAL_CURRENCY               VARCHAR(5)   COMMENT 'Local currency: company code currency.',
  PAYMENT_BLOCK                VARCHAR(1),
  RECONCILIATION_ACCOUNT       VARCHAR(10)  COMMENT 'Reconciliation account: AP control account in the general ledger.',
  EDW_LOAD_TS                  TIMESTAMP_NTZ COMMENT 'EDW load time: when the EDW load last wrote the row.'
) COMMENT = 'Global Accounts Payable fact. Source: SAP_BSEG (account type K) + SAP_BKPF + SAP_BSEC + SAP_T005T. Grain: one row per vendor line item. All company codes.';

-- ---------------------------------------------------------------------
-- Load procedure (called now, and daily by TASK_LOAD_EDW)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE LOAD_EDW()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Loads the EDW AP fact and dimensions from the SAP landing tables.'
EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT OVERWRITE INTO {{DATABASE}}.{{EDW}}.DIM_COMPANY_CODE
  SELECT t.BUKRS, t.BUTXT, t.LAND1, c.LANDX, t.WAERS,
         CASE t.WAERS WHEN 'USD' THEN 1 WHEN 'GBP' THEN 1.27 WHEN 'EUR' THEN 1.08
                      WHEN 'INR' THEN 0.012 WHEN 'SGD' THEN 0.74 END,
         CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{LANDING}}.SAP_T001 t
  LEFT JOIN {{DATABASE}}.{{LANDING}}.SAP_T005T c ON c.LAND1 = t.LAND1 AND c.SPRAS = 'E';

  INSERT OVERWRITE INTO {{DATABASE}}.{{EDW}}.DIM_VENDOR
  SELECT v.LIFNR, v.NAME1, v.LAND1, c.LANDX, v.ORT01, v.KTOKK, v.KTOKK = 'CPD',
         v.STCD1, b.BANKS, b.BANKN, COALESCE(v.LOEVM = 'X', FALSE), v.ERDAT, CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{LANDING}}.SAP_LFA1 v
  LEFT JOIN {{DATABASE}}.{{LANDING}}.SAP_T005T c ON c.LAND1 = v.LAND1 AND c.SPRAS = 'E'
  LEFT JOIN {{DATABASE}}.{{LANDING}}.SAP_LFBK b ON b.LIFNR = v.LIFNR;

  INSERT OVERWRITE INTO {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL
  SELECT l.BUKRS || '-' || l.BELNR || '-' || l.GJAHR || '-' || l.BUZEI,
         l.BUKRS, l.BELNR, l.GJAHR, l.BUZEI,
         h.BLART,
         CASE h.BLART WHEN 'KR' THEN 'Vendor invoice' WHEN 'KG' THEN 'Vendor credit memo' ELSE 'Other' END,
         h.XBLNR, l.LIFNR,
         o.NAME1, o.LAND1, oc.LANDX,
         h.BLDAT, h.BUDAT, l.ZFBDT, l.ZTERM, l.ZBD1T,
         DATEADD(day, l.ZBD1T, l.ZFBDT),
         l.AUGDT, l.AUGBL, l.AUGDT IS NULL,
         l.SHKZG,
         IFF(l.SHKZG = 'H', l.DMBTR, -l.DMBTR),
         h.WAERS, l.ZLSPR, l.HKONT, CURRENT_TIMESTAMP()
  FROM {{DATABASE}}.{{LANDING}}.SAP_BSEG l
  JOIN {{DATABASE}}.{{LANDING}}.SAP_BKPF h
    ON h.BUKRS = l.BUKRS AND h.BELNR = l.BELNR AND h.GJAHR = l.GJAHR
  LEFT JOIN {{DATABASE}}.{{LANDING}}.SAP_BSEC o
    ON o.BUKRS = l.BUKRS AND o.BELNR = l.BELNR AND o.GJAHR = l.GJAHR AND o.BUZEI = l.BUZEI
  LEFT JOIN {{DATABASE}}.{{LANDING}}.SAP_T005T oc ON oc.LAND1 = o.LAND1 AND oc.SPRAS = 'E'
  WHERE l.KOART = 'K';

  RETURN 'EDW loaded';
END;
$$;

CALL LOAD_EDW();
