-- =====================================================================
-- 01 SETUP: warehouse, database, one schema per layer, two persona roles
-- =====================================================================
CREATE WAREHOUSE IF NOT EXISTS {{WAREHOUSE}}
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'AP Knowledge Fabric POC (synthetic data)';
USE WAREHOUSE {{WAREHOUSE}};

CREATE DATABASE IF NOT EXISTS {{DATABASE}}
  COMMENT = 'POC: Knowledge Fabric over an SAP-like Accounts Payable model. Synthetic data only.';

CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{LANDING}}
  COMMENT = 'Landing layer: SAP-like AP tables as written by the replication tool (synthetic).';
CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{EDW}}
  COMMENT = 'EDW layer: global AP fact (vendor line items) and conformed master dimensions.';
CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{DATAMART}}
  COMMENT = 'AP datamart: open items, aging buckets and aging summary. All AP business logic lives here.';
CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{REPORTING}}
  COMMENT = 'Reporting layer: views for BI tools. Select and rename only, no business logic.';
CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{GOVERNANCE}}
  COMMENT = 'Tags and masking policies for the AP data product.';
CREATE SCHEMA IF NOT EXISTS {{DATABASE}}.{{KF}}
  COMMENT = 'Knowledge Fabric: metadata catalog, lineage, glossary, documents, search, semantic view and agent.';

-- Two personas from the requirement: power users and new (business) users
CREATE ROLE IF NOT EXISTS {{POWER_ROLE}}    COMMENT = 'AP power user / data engineer: sees unmasked values';
CREATE ROLE IF NOT EXISTS {{BUSINESS_ROLE}} COMMENT = 'AP business user: reporting + knowledge layer, sensitive values masked';
GRANT ROLE {{BUSINESS_ROLE}} TO ROLE {{POWER_ROLE}};
GRANT ROLE {{POWER_ROLE}} TO ROLE SYSADMIN;

SET my_user = CURRENT_USER();
GRANT ROLE {{POWER_ROLE}} TO USER IDENTIFIER($my_user);
GRANT ROLE {{BUSINESS_ROLE}} TO USER IDENTIFIER($my_user);
