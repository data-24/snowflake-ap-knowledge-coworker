-- =====================================================================
-- 02 LANDING: SAP-like Accounts Payable tables, synthetic data
--   SAP_T001   company codes              SAP_T005T  country names
--   SAP_LFA1   vendor master (general)    SAP_LFB1   vendor per company code (payment terms)
--   SAP_LFBK   vendor bank details        SAP_BKPF   accounting document header
--   SAP_BSEG   accounting document lines  SAP_BSEC   one-time vendor data per invoice line
-- Column comments follow one convention:  "<Business name>: <description>"
-- A few comments are left out ON PURPOSE to show documentation gaps in the catalog.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{LANDING}};

-- ---------------------------------------------------------------------
-- Company codes
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_T001 (
  BUKRS VARCHAR(4)  COMMENT 'Company code: four-character key of the legal entity that posts the invoice.',
  BUTXT VARCHAR(50) COMMENT 'Company name: name of the company code.',
  LAND1 VARCHAR(3)  COMMENT 'Company country: country key of the company code.',
  WAERS VARCHAR(5)  COMMENT 'Local currency: currency in which the company code keeps its books.',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Company code master (SAP-like T001). Replicated from the ERP by the replication tool. Synthetic.';

INSERT INTO SAP_T001 VALUES
  ('1000', 'Company 1000 - US Operations',        'US', 'USD', CURRENT_TIMESTAMP()),
  ('2000', 'Company 2000 - UK Operations',        'GB', 'GBP', CURRENT_TIMESTAMP()),
  ('3000', 'Company 3000 - Germany Operations',   'DE', 'EUR', CURRENT_TIMESTAMP()),
  ('4000', 'Company 4000 - India Operations',     'IN', 'INR', CURRENT_TIMESTAMP()),
  ('5000', 'Company 5000 - Singapore Operations', 'SG', 'SGD', CURRENT_TIMESTAMP());

-- ---------------------------------------------------------------------
-- Country names
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_T005T (
  SPRAS VARCHAR(1)  COMMENT 'Language key: language of the text (E = English).',
  LAND1 VARCHAR(3)  COMMENT 'Country key: two-letter ISO country code.',
  LANDX VARCHAR(50) COMMENT 'Country name: country name in the given language.',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Country names (SAP-like T005T). Used to translate country keys into country names.';

INSERT INTO SAP_T005T
SELECT 'E', column1, column2, CURRENT_TIMESTAMP() FROM VALUES
  ('US', 'United States'), ('GB', 'United Kingdom'), ('DE', 'Germany'), ('IN', 'India'),
  ('SG', 'Singapore'), ('FR', 'France'), ('MX', 'Mexico'), ('CA', 'Canada'),
  ('JP', 'Japan'), ('CN', 'China'), ('IT', 'Italy'), ('BR', 'Brazil');

-- Helper list used only to generate synthetic vendors (country, city, legal-form suffix)
CREATE OR REPLACE TEMPORARY TABLE _GEO (IDX INT, LAND1 VARCHAR, CITY VARCHAR, SUFFIX VARCHAR) AS
SELECT column1, column2, column3, column4 FROM VALUES
  (0, 'US', 'Phoenix', 'Inc'), (1, 'US', 'Houston', 'LLC'), (2, 'US', 'Chicago', 'Inc'),
  (3, 'GB', 'Bristol', 'Ltd'), (4, 'DE', 'Hamburg', 'GmbH'), (5, 'IN', 'Bengaluru', 'Pvt Ltd'),
  (6, 'SG', 'Singapore', 'Pte Ltd'), (7, 'FR', 'Toulouse', 'SAS'), (8, 'MX', 'Queretaro', 'SA de CV'),
  (9, 'CA', 'Montreal', 'Inc'), (10, 'JP', 'Nagoya', 'KK'), (11, 'CN', 'Shanghai', 'Co Ltd'),
  (12, 'IT', 'Turin', 'SpA'), (13, 'BR', 'Sao Paulo', 'Ltda');

-- ---------------------------------------------------------------------
-- Vendor master (general data)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_LFA1 (
  LIFNR VARCHAR(10) COMMENT 'Vendor number: unique key of the vendor (supplier) account.',
  NAME1 VARCHAR(80) COMMENT 'Vendor name: legal name of the vendor.',
  LAND1 VARCHAR(3)  COMMENT 'Vendor country: country key of the vendor address in the vendor master. Empty for one-time vendors, whose country is captured on each invoice in SAP_BSEC.',
  ORT01 VARCHAR(40) COMMENT 'Vendor city: city of the vendor address.',
  KTOKK VARCHAR(4)  COMMENT 'Vendor account group: KRED = regular vendor, CPD = one-time vendor.',
  STCD1 VARCHAR(20) COMMENT 'Vendor tax number: tax registration number of the vendor. Restricted, masked.',
  LOEVM VARCHAR(1)  COMMENT 'Deletion flag: X = vendor marked for deletion.',
  ERDAT DATE        COMMENT 'Vendor created on: date the vendor record was created.',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Vendor master general data (SAP-like LFA1). One row per vendor. Synthetic.';

INSERT INTO SAP_LFA1
SELECT LPAD(TO_VARCHAR(100000 + v.N), 10, '0'),
       ARRAY_CONSTRUCT('Apex', 'Summit', 'Northgate', 'Precision', 'Bluewater', 'Atlas', 'Vertex', 'Harbor',
                       'Pioneer', 'Silverline', 'Keystone', 'Orbit')[MOD(ABS(HASH(v.N, 'p')), 12)]::VARCHAR
         || ' ' ||
       ARRAY_CONSTRUCT('Components', 'Logistics', 'Metals', 'Electronics', 'Services', 'Composites', 'Tooling',
                       'Systems', 'Fasteners', 'Coatings')[MOD(ABS(HASH(v.N, 's')), 10)]::VARCHAR
         || ' ' || g.SUFFIX,
       g.LAND1,
       g.CITY,
       'KRED',
       g.LAND1 || LPAD(TO_VARCHAR(MOD(ABS(HASH(v.N, 'tax')), 1000000000)), 9, '0'),
       IFF(MOD(ABS(HASH(v.N, 'del')), 100) < 3, 'X', NULL),
       DATEADD(day, -MOD(ABS(HASH(v.N, 'created')), 3000), CURRENT_DATE()),
       CURRENT_TIMESTAMP()
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N FROM TABLE(GENERATOR(ROWCOUNT => {{VENDOR_COUNT}}))) v
JOIN _GEO g ON g.IDX = MOD(ABS(HASH(v.N, 'geo')), 14);

-- One-time vendor account: name, country and tax number are captured per invoice in SAP_BSEC
INSERT INTO SAP_LFA1 VALUES
  ('0000999999', 'One-time vendor (CPD)', NULL, NULL, 'CPD', NULL, NULL, '2015-01-01', CURRENT_TIMESTAMP());

-- ---------------------------------------------------------------------
-- Vendor per company code (payment terms, reconciliation account)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_LFB1 (
  LIFNR VARCHAR(10) COMMENT 'Vendor number: key of the vendor account.',
  BUKRS VARCHAR(4)  COMMENT 'Company code: company code in which the vendor is set up.',
  AKONT VARCHAR(10) COMMENT 'Reconciliation account: general ledger account that collects all AP postings for the vendor.',
  ZTERM VARCHAR(4)  COMMENT 'Payment terms: default payment terms key (N30 = net 30 days, IMMD = due immediately).',
  ZWELS VARCHAR(10),
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Vendor company-code data (SAP-like LFB1). One row per vendor and company code.';

INSERT INTO SAP_LFB1
SELECT v.LIFNR, c.BUKRS, '0000211000',
       IFF(v.KTOKK = 'CPD', 'IMMD',
           ARRAY_CONSTRUCT('N30', 'N30', 'N30', 'N45', 'N60', 'N60', 'N90', 'IMMD')[MOD(ABS(HASH(v.LIFNR, 'zterm')), 8)]::VARCHAR),
       ARRAY_CONSTRUCT('T', 'T', 'C', 'TC')[MOD(ABS(HASH(v.LIFNR, c.BUKRS)), 4)]::VARCHAR,
       CURRENT_TIMESTAMP()
FROM SAP_LFA1 v CROSS JOIN SAP_T001 c;

-- ---------------------------------------------------------------------
-- Vendor bank details (table comment deliberately missing: a documentation gap)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_LFBK (
  LIFNR VARCHAR(10) COMMENT 'Vendor number: key of the vendor account.',
  BANKS VARCHAR(3)  COMMENT 'Bank country: country key of the vendor bank.',
  BANKL VARCHAR(15) COMMENT 'Bank key: identifier of the vendor bank (synthetic).',
  BANKN VARCHAR(18) COMMENT 'Bank account number: vendor bank account. Restricted, masked.',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
);

INSERT INTO SAP_LFBK
SELECT LIFNR, LAND1, 'BK' || LPAD(TO_VARCHAR(MOD(ABS(HASH(LIFNR, 'bank')), 100000)), 6, '0'),
       LPAD(TO_VARCHAR(MOD(ABS(HASH(LIFNR, 'acct')), 10000000000)), 12, '0'), CURRENT_TIMESTAMP()
FROM SAP_LFA1 WHERE KTOKK = 'KRED';

-- ---------------------------------------------------------------------
-- Invoices: generated once in a temporary table, then written to BKPF / BSEG / BSEC
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE _INVOICES AS
WITH d AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N FROM TABLE(GENERATOR(ROWCOUNT => {{INVOICE_COUNT}}))),
base AS (
  SELECT N,
         ARRAY_CONSTRUCT('1000', '1000', '2000', '3000', '4000', '5000')[MOD(ABS(HASH(N, 'bukrs')), 6)]::VARCHAR AS BUKRS,
         TO_VARCHAR(5100000000 + N) AS BELNR,
         IFF(MOD(ABS(HASH(N, 'otv')), 100) < 4, '0000999999',
             LPAD(TO_VARCHAR(100001 + MOD(ABS(HASH(N, 'vendor')), {{VENDOR_COUNT}})), 10, '0')) AS LIFNR,
         IFF(MOD(ABS(HASH(N, 'type')), 100) < 93, 'KR', 'KG') AS BLART,          -- KR invoice, KG credit memo
         DATEADD(day, -MOD(ABS(HASH(N, 'age')), 420), CURRENT_DATE()) AS BLDAT,
         ROUND(150 + POW(MOD(ABS(HASH(N, 'amt')), 1000) / 1000.0, 3) * 180000, 2) AS AMOUNT,
         MOD(ABS(HASH(N, 'delay')), 95) - 25 AS PAY_DELAY_DAYS,                 -- paid 25 days early .. 69 days late
         MOD(ABS(HASH(N, 'dispute')), 100) < 7 AS IS_DISPUTED,                   -- never paid: stays open
         'INV-' || LPAD(TO_VARCHAR(MOD(ABS(HASH(N, 'ref')), 10000000)), 7, '0') AS XBLNR
  FROM d
)
SELECT b.*,
       DATEADD(day, MOD(ABS(HASH(b.N, 'post')), 6), b.BLDAT) AS BUDAT,
       t.WAERS,
       f.ZTERM,
       CASE f.ZTERM WHEN 'N30' THEN 30 WHEN 'N45' THEN 45 WHEN 'N60' THEN 60 WHEN 'N90' THEN 90 ELSE 0 END AS ZBD1T,
       DATEADD(day, CASE f.ZTERM WHEN 'N30' THEN 30 WHEN 'N45' THEN 45 WHEN 'N60' THEN 60 WHEN 'N90' THEN 90 ELSE 0 END
                    + b.PAY_DELAY_DAYS, b.BLDAT) AS PAY_DATE
FROM base b
JOIN SAP_T001 t ON t.BUKRS = b.BUKRS
JOIN SAP_LFB1 f ON f.BUKRS = b.BUKRS AND f.LIFNR = b.LIFNR;

-- ---------------------------------------------------------------------
-- Accounting document header
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_BKPF (
  BUKRS VARCHAR(4)  COMMENT 'Company code: company code of the document.',
  BELNR VARCHAR(10) COMMENT 'Document number: accounting document number, unique per company code and fiscal year.',
  GJAHR NUMBER(4)   COMMENT 'Fiscal year: fiscal year of the document.',
  BLART VARCHAR(2)  COMMENT 'Document type: KR = vendor invoice, KG = vendor credit memo, KZ = vendor payment.',
  BLDAT DATE        COMMENT 'Document date: invoice date on the vendor document.',
  BUDAT DATE        COMMENT 'Posting date: date the document was posted in the ledger.',
  WAERS VARCHAR(5)  COMMENT 'Document currency: currency of the document.',
  XBLNR VARCHAR(16) COMMENT 'Invoice reference: vendor invoice number quoted on the document.',
  USNAM VARCHAR(12) COMMENT 'Entered by: user who posted the document (synthetic user id).',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Accounting document header (SAP-like BKPF). One row per accounting document. Synthetic.';

INSERT INTO SAP_BKPF
SELECT BUKRS, BELNR, YEAR(BUDAT), BLART, BLDAT, BUDAT, WAERS, XBLNR,
       'APCLERK' || LPAD(TO_VARCHAR(MOD(ABS(HASH(N, 'user')), 12) + 1), 2, '0'), CURRENT_TIMESTAMP()
FROM _INVOICES;

-- ---------------------------------------------------------------------
-- Accounting document lines: line 001 = vendor line (KOART K), line 002 = expense line (KOART S)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_BSEG (
  BUKRS VARCHAR(4)  COMMENT 'Company code: company code of the document.',
  BELNR VARCHAR(10) COMMENT 'Document number: accounting document number.',
  GJAHR NUMBER(4)   COMMENT 'Fiscal year: fiscal year of the document.',
  BUZEI VARCHAR(3)  COMMENT 'Line item: line number within the accounting document.',
  KOART VARCHAR(1)  COMMENT 'Account type: K = vendor (accounts payable), S = general ledger, D = customer.',
  LIFNR VARCHAR(10) COMMENT 'Vendor number: vendor of the line (vendor lines only).',
  SHKZG VARCHAR(1)  COMMENT 'Debit/credit indicator: H = credit, S = debit. A vendor invoice credits the vendor (H).',
  DMBTR NUMBER(15,2) COMMENT 'Amount in local currency: line amount in the company code currency (always positive; sign comes from SHKZG).',
  WRBTR NUMBER(15,2) COMMENT 'Amount in document currency: line amount in the document currency.',
  HKONT VARCHAR(10),
  ZFBDT DATE        COMMENT 'Baseline date: date from which payment terms are counted (here the document date).',
  ZBD1T NUMBER(3)   COMMENT 'Payment term days: number of days after the baseline date until the invoice is due.',
  ZTERM VARCHAR(4)  COMMENT 'Payment terms: payment terms key copied from the vendor at posting.',
  ZLSPR VARCHAR(1)  COMMENT 'Payment block: A = blocked for payment (for example disputed invoice).',
  AUGDT DATE        COMMENT 'Clearing date: date the item was paid/cleared. Empty = open item.',
  AUGBL VARCHAR(10) COMMENT 'Clearing document: payment document that cleared the item.',
  SGTXT VARCHAR(50),
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'Accounting document line items (SAP-like BSEG). Vendor lines have account type K. Synthetic.';

INSERT INTO SAP_BSEG
SELECT BUKRS, BELNR, YEAR(BUDAT), '001', 'K', LIFNR,
       IFF(BLART = 'KR', 'H', 'S'), AMOUNT, AMOUNT, '0000211000',
       BLDAT, ZBD1T, ZTERM, IFF(IS_DISPUTED, 'A', NULL),
       IFF(NOT IS_DISPUTED AND PAY_DATE <= CURRENT_DATE(), PAY_DATE, NULL),
       IFF(NOT IS_DISPUTED AND PAY_DATE <= CURRENT_DATE(), TO_VARCHAR(1500000000 + N), NULL),
       IFF(BLART = 'KR', 'Vendor invoice ', 'Credit memo ') || XBLNR, CURRENT_TIMESTAMP()
FROM _INVOICES
UNION ALL
SELECT BUKRS, BELNR, YEAR(BUDAT), '002', 'S', NULL,
       IFF(BLART = 'KR', 'S', 'H'), AMOUNT, AMOUNT,
       ARRAY_CONSTRUCT('0000600100', '0000600200', '0000610000', '0000620500')[MOD(ABS(HASH(N, 'gl')), 4)]::VARCHAR,
       NULL, NULL, NULL, NULL, NULL, NULL, 'Expense ' || XBLNR, CURRENT_TIMESTAMP()
FROM _INVOICES;

-- ---------------------------------------------------------------------
-- One-time vendor data: the real payee of an invoice posted to the one-time vendor account
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SAP_BSEC (
  BUKRS VARCHAR(4)  COMMENT 'Company code: company code of the document.',
  BELNR VARCHAR(10) COMMENT 'Document number: accounting document number.',
  GJAHR NUMBER(4)   COMMENT 'Fiscal year: fiscal year of the document.',
  BUZEI VARCHAR(3)  COMMENT 'Line item: vendor line the one-time data belongs to.',
  NAME1 VARCHAR(80) COMMENT 'One-time vendor name: name of the payee on this invoice. May be a private person: restricted, masked.',
  LAND1 VARCHAR(3)  COMMENT 'One-time vendor country: country key of the payee on this invoice.',
  ORT01 VARCHAR(40) COMMENT 'One-time vendor city: city of the payee on this invoice.',
  STCD1 VARCHAR(20) COMMENT 'One-time vendor tax number: tax number of the payee. Restricted, masked.',
  _REPLICATED_AT TIMESTAMP_NTZ COMMENT 'Replicated at: when the replication tool last wrote the row.'
) COMMENT = 'One-time vendor data per document line (SAP-like BSEC). Only for invoices posted to account group CPD.';

INSERT INTO SAP_BSEC
SELECT i.BUKRS, i.BELNR, YEAR(i.BUDAT), '001',
       ARRAY_CONSTRUCT('Alex', 'Sam', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Jamie')[MOD(ABS(HASH(i.N, 'fn')), 8)]::VARCHAR
         || ' ' ||
       ARRAY_CONSTRUCT('Reed', 'Patel', 'Garcia', 'Chen', 'Muller', 'Rossi', 'Silva', 'Kowalski')[MOD(ABS(HASH(i.N, 'ln')), 8)]::VARCHAR,
       g.LAND1, g.CITY,
       g.LAND1 || LPAD(TO_VARCHAR(MOD(ABS(HASH(i.N, 'otvtax')), 1000000000)), 9, '0'),
       CURRENT_TIMESTAMP()
FROM _INVOICES i JOIN _GEO g ON g.IDX = MOD(ABS(HASH(i.N, 'otvgeo')), 14)
WHERE i.LIFNR = '0000999999';

DROP TABLE IF EXISTS _GEO;
DROP TABLE IF EXISTS _INVOICES;
