-- =====================================================================
-- 06b CLASSIFICATION (optional, Enterprise): Snowflake's own sensitive-data classifier
--   SYSTEM$CLASSIFY inspects the columns and, with auto_tag, sets the system tags
--   SNOWFLAKE.CORE.SEMANTIC_CATEGORY and SNOWFLAKE.CORE.PRIVACY_CATEGORY.
--   The Knowledge Fabric refresh reads these tags next to our own SENSITIVITY tag.
--   If this file fails on an account, the rest of the POC still works.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
CALL SYSTEM$CLASSIFY('{{DATABASE}}.{{LANDING}}.SAP_LFA1', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('{{DATABASE}}.{{LANDING}}.SAP_BSEC', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('{{DATABASE}}.{{EDW}}.DIM_VENDOR', {'auto_tag': true});
