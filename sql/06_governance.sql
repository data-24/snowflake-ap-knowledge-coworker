-- =====================================================================
-- 06 GOVERNANCE: tags and masking policies (Enterprise edition)
--   Tags are set at database / schema level and inherited by every table, view and column;
--   object-level tags override them where an object is different.
--   Masking: tax IDs, bank accounts and one-time payee names. Only the power-user role
--   (and the build role, so the loads copy real values) sees them unmasked.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{GOVERNANCE}};

-- ---------------------------------------------------------------------
-- 1. Tags
-- ---------------------------------------------------------------------
CREATE TAG IF NOT EXISTS DATA_DOMAIN       COMMENT = 'Business domain that owns the data';
CREATE TAG IF NOT EXISTS DATA_PRODUCT      COMMENT = 'Data product the object belongs to';
CREATE TAG IF NOT EXISTS DATA_LAYER        ALLOWED_VALUES 'Landing', 'EDW', 'Datamart', 'Reporting'
                                           COMMENT = 'Layer of the AP model';
CREATE TAG IF NOT EXISTS SOURCE_SYSTEM     COMMENT = 'System the data originally comes from';
CREATE TAG IF NOT EXISTS REFRESH_FREQUENCY COMMENT = 'How often the object is refreshed, and by which job';
CREATE TAG IF NOT EXISTS DATA_OWNER        COMMENT = 'Accountable business owner (a role, not a person)';
CREATE TAG IF NOT EXISTS DATA_STEWARD      COMMENT = 'Steward who maintains definitions and metadata (a role)';
CREATE TAG IF NOT EXISTS CERTIFICATION     ALLOWED_VALUES 'Certified', 'In review', 'Not certified'
                                           COMMENT = 'Whether the object is certified for reporting';
CREATE TAG IF NOT EXISTS SENSITIVITY       ALLOWED_VALUES 'Public', 'Internal', 'Confidential', 'Restricted'
                                           COMMENT = 'Data sensitivity class (see the AP Data Governance Standard)';
CREATE TAG IF NOT EXISTS TECHNICAL_OWNER   COMMENT = 'Team that builds and supports the object (a role)';
CREATE TAG IF NOT EXISTS DATA_CLASS        ALLOWED_VALUES 'Transaction data', 'Master data', 'Reference data', 'Aggregated data'
                                           COMMENT = 'Transaction / master / reference / aggregated data classification';
CREATE TAG IF NOT EXISTS KEY_ROLE          ALLOWED_VALUES 'Primary key', 'Business key'
                                           COMMENT = 'Key columns of views (tables use primary / unique key constraints)';

-- Database level: inherited by everything
ALTER DATABASE {{DATABASE}} SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.DATA_DOMAIN = 'Finance',
  {{DATABASE}}.{{GOVERNANCE}}.DATA_PRODUCT = 'Accounts Payable',
  {{DATABASE}}.{{GOVERNANCE}}.SOURCE_SYSTEM = 'SAP ECC (synthetic), landed by the replication tool',
  {{DATABASE}}.{{GOVERNANCE}}.DATA_OWNER = 'AP Finance Data Owner (role)',
  {{DATABASE}}.{{GOVERNANCE}}.DATA_STEWARD = 'AP Data Steward (role)',
  {{DATABASE}}.{{GOVERNANCE}}.TECHNICAL_OWNER = 'EDW Data Engineering - Finance team (role)',
  {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Internal';

-- Schema level: one value per layer
ALTER SCHEMA {{DATABASE}}.{{LANDING}} SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.DATA_LAYER = 'Landing',
  {{DATABASE}}.{{GOVERNANCE}}.CERTIFICATION = 'Not certified',
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'Near real-time: replicated continuously from SAP (about every 15 minutes)';
ALTER SCHEMA {{DATABASE}}.{{EDW}} SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.DATA_LAYER = 'EDW',
  {{DATABASE}}.{{GOVERNANCE}}.CERTIFICATION = 'Certified',
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'Daily at 02:00 UTC (task TASK_LOAD_EDW)';
ALTER SCHEMA {{DATABASE}}.{{DATAMART}} SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.DATA_LAYER = 'Datamart',
  {{DATABASE}}.{{GOVERNANCE}}.CERTIFICATION = 'Certified',
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'Daily, right after the EDW load, about 02:15 UTC (task TASK_LOAD_AP_DATAMART)';
ALTER SCHEMA {{DATABASE}}.{{REPORTING}} SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.DATA_LAYER = 'Reporting',
  {{DATABASE}}.{{GOVERNANCE}}.CERTIFICATION = 'Certified',
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'Views: always show the latest datamart load (datamart refreshed daily)';

-- Object-level overrides
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_T005T SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'Weekly (reference data)';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.AP_AGING_BUCKETS SET TAG
  {{DATABASE}}.{{GOVERNANCE}}.REFRESH_FREQUENCY = 'On change only (reference data, changed through the definition approval process)';

-- Transaction / master / reference classification of every object
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_T001 SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_T005T SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Reference data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFA1 SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFB1 SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFBK SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BKPF SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEG SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEC SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_COMPANY_CODE SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_VENDOR SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER TABLE {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.AP_AGING_BUCKETS SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Reference data';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_AGING_SUMMARY SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Aggregated data';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER VIEW {{DATABASE}}.{{REPORTING}}.VW_AP_OPEN_ITEMS SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER VIEW {{DATABASE}}.{{REPORTING}}.VW_AP_OVERDUE_ITEMS SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Transaction data';
ALTER VIEW {{DATABASE}}.{{REPORTING}}.VW_AP_AGING_SUMMARY SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Aggregated data';
ALTER VIEW {{DATABASE}}.{{REPORTING}}.VW_AP_VENDOR SET TAG {{DATABASE}}.{{GOVERNANCE}}.DATA_CLASS = 'Master data';
ALTER SCHEMA {{DATABASE}}.{{LANDING}} SET TAG {{DATABASE}}.{{GOVERNANCE}}.TECHNICAL_OWNER = 'SAP Replication team (role)';

-- Column-level sensitivity
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFA1 MODIFY COLUMN STCD1 SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFBK MODIFY COLUMN BANKN SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEC MODIFY COLUMN NAME1 SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEC MODIFY COLUMN STCD1 SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_VENDOR MODIFY COLUMN VENDOR_TAX_ID SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_VENDOR MODIFY COLUMN VENDOR_BANK_ACCOUNT SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL MODIFY COLUMN ONE_TIME_VENDOR_NAME SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL MODIFY COLUMN AMOUNT_LOCAL SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Confidential';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR MODIFY COLUMN VENDOR_TAX_ID SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR MODIFY COLUMN VENDOR_BANK_ACCOUNT SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Restricted';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS MODIFY COLUMN VENDOR_NAME SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Confidential';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS MODIFY COLUMN AMOUNT_USD SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Confidential';
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS MODIFY COLUMN AMOUNT_LOCAL SET TAG {{DATABASE}}.{{GOVERNANCE}}.SENSITIVITY = 'Confidential';

-- ---------------------------------------------------------------------
-- 2. Masking policies
--    CURRENT_ROLE() (not IS_ROLE_IN_SESSION) so that switching role in the demo really changes
--    what you see, even when your user also holds the power role as a secondary role.
-- ---------------------------------------------------------------------
CREATE MASKING POLICY IF NOT EXISTS MASK_TAX_ID AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('{{POWER_ROLE}}', '{{ADMIN_ROLE}}') THEN val
       WHEN val IS NULL THEN NULL
       ELSE '*****' || RIGHT(val, 4) END
  COMMENT = 'Tax IDs: full value for the power-user role, last 4 characters for everyone else';

CREATE MASKING POLICY IF NOT EXISTS MASK_BANK_ACCOUNT AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('{{POWER_ROLE}}', '{{ADMIN_ROLE}}') THEN val
       WHEN val IS NULL THEN NULL
       ELSE '********' || RIGHT(val, 4) END
  COMMENT = 'Bank accounts: full value for the power-user role, last 4 digits for everyone else';

CREATE MASKING POLICY IF NOT EXISTS MASK_PERSON_NAME AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('{{POWER_ROLE}}', '{{ADMIN_ROLE}}') THEN val
       WHEN val IS NULL THEN NULL
       ELSE '*** masked ***' END
  COMMENT = 'One-time payee names (may be private persons): hidden except for the power-user role';

CREATE MASKING POLICY IF NOT EXISTS MASK_ONE_TIME_PAYEE_NAME AS (val STRING, is_one_time BOOLEAN) RETURNS STRING ->
  CASE WHEN NOT COALESCE(is_one_time, FALSE) THEN val
       WHEN CURRENT_ROLE() IN ('{{POWER_ROLE}}', '{{ADMIN_ROLE}}') THEN val
       ELSE '*** one-time payee (masked) ***' END
  COMMENT = 'Conditional masking: vendor names stay visible; only one-time payee names are masked';

ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFA1 MODIFY COLUMN STCD1 SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_TAX_ID FORCE;
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_LFBK MODIFY COLUMN BANKN SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_BANK_ACCOUNT FORCE;
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEC MODIFY COLUMN NAME1 SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_PERSON_NAME FORCE;
ALTER TABLE {{DATABASE}}.{{LANDING}}.SAP_BSEC MODIFY COLUMN STCD1 SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_TAX_ID FORCE;
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_VENDOR MODIFY COLUMN VENDOR_TAX_ID SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_TAX_ID FORCE;
ALTER TABLE {{DATABASE}}.{{EDW}}.DIM_VENDOR MODIFY COLUMN VENDOR_BANK_ACCOUNT SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_BANK_ACCOUNT FORCE;
ALTER TABLE {{DATABASE}}.{{EDW}}.FACT_ACCOUNTS_PAYABLE_GLOBAL MODIFY COLUMN ONE_TIME_VENDOR_NAME SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_PERSON_NAME FORCE;
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR MODIFY COLUMN VENDOR_TAX_ID SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_TAX_ID FORCE;
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_VENDOR MODIFY COLUMN VENDOR_BANK_ACCOUNT SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_BANK_ACCOUNT FORCE;
ALTER TABLE {{DATABASE}}.{{DATAMART}}.DM_AP_OPEN_ITEMS MODIFY COLUMN VENDOR_NAME
  SET MASKING POLICY {{DATABASE}}.{{GOVERNANCE}}.MASK_ONE_TIME_PAYEE_NAME USING (VENDOR_NAME, IS_ONE_TIME_VENDOR) FORCE;
-- The reporting views have no policy of their own: they inherit the masking of the datamart columns.
-- The Knowledge Fabric shows this as "masked via <upstream column>".
