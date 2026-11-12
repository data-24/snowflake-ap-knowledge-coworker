-- =====================================================================
-- 12 ACCESS: what each persona can use
--   Business user: reporting views + Knowledge Fabric + the agent (sensitive values masked)
--   Power user:    everything above + landing, EDW and datamart (sensitive values unmasked)
-- (run.py treats a failing statement in this file as a warning, so one missing privilege does not stop the build)
-- =====================================================================
GRANT USAGE ON WAREHOUSE {{WAREHOUSE}} TO ROLE {{BUSINESS_ROLE}};
GRANT USAGE ON DATABASE {{DATABASE}} TO ROLE {{BUSINESS_ROLE}};
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE {{BUSINESS_ROLE}};

GRANT USAGE ON SCHEMA {{DATABASE}}.{{REPORTING}} TO ROLE {{BUSINESS_ROLE}};
GRANT SELECT ON ALL VIEWS IN SCHEMA {{DATABASE}}.{{REPORTING}} TO ROLE {{BUSINESS_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{KF}} TO ROLE {{BUSINESS_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{KF}} TO ROLE {{BUSINESS_ROLE}};
GRANT SELECT ON SEMANTIC VIEW {{DATABASE}}.{{KF}}.{{SEMANTIC_VIEW}} TO ROLE {{BUSINESS_ROLE}};
GRANT USAGE ON CORTEX SEARCH SERVICE {{DATABASE}}.{{KF}}.{{CATALOG_SEARCH}} TO ROLE {{BUSINESS_ROLE}};
GRANT USAGE ON CORTEX SEARCH SERVICE {{DATABASE}}.{{KF}}.{{DOCS_SEARCH}} TO ROLE {{BUSINESS_ROLE}};
GRANT USAGE ON AGENT {{DATABASE}}.{{KF}}.{{AGENT}} TO ROLE {{BUSINESS_ROLE}};
GRANT READ ON STAGE {{DATABASE}}.{{KF}}.{{DOCS_STAGE}} TO ROLE {{BUSINESS_ROLE}};

-- The datamart is needed by business users only through the reporting views (views run with owner's rights),
-- so they get no direct access to landing, EDW or datamart tables.
GRANT USAGE ON SCHEMA {{DATABASE}}.{{LANDING}} TO ROLE {{POWER_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{EDW}} TO ROLE {{POWER_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{DATAMART}} TO ROLE {{POWER_ROLE}};
GRANT USAGE ON SCHEMA {{DATABASE}}.{{GOVERNANCE}} TO ROLE {{POWER_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{LANDING}} TO ROLE {{POWER_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{EDW}} TO ROLE {{POWER_ROLE}};
GRANT SELECT ON ALL TABLES IN SCHEMA {{DATABASE}}.{{DATAMART}} TO ROLE {{POWER_ROLE}};
