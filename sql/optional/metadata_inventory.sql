-- =====================================================================
-- OPTIONAL: metadata inventory for a REAL account (run by the account owner)
--   Answers "which governance metadata already exists for a domain?" before building a Knowledge Fabric.
--   Needs IMPORTED PRIVILEGES on the SNOWFLAKE database (or the GOVERNANCE_VIEWER database role).
--   ACCOUNT_USAGE views can lag up to ~3 hours. Replace the database pattern below.
-- =====================================================================
SET DB_PATTERN = '%FINANCE%';   -- databases to inventory, e.g. '%FIN%'

-- 1. Objects and how well they are documented
SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_TYPE, COUNT(*) AS OBJECTS,
       COUNT_IF(COMMENT IS NOT NULL AND COMMENT <> '') AS WITH_COMMENT,
       ROUND(100 * DIV0(COUNT_IF(COMMENT IS NOT NULL AND COMMENT <> ''), COUNT(*)), 2) AS PCT_DOCUMENTED
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLES
WHERE DELETED IS NULL AND TABLE_CATALOG ILIKE $DB_PATTERN
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- 2. Column documentation
SELECT TABLE_CATALOG, TABLE_SCHEMA, COUNT(*) AS COLUMNS,
       ROUND(100 * DIV0(COUNT_IF(COMMENT IS NOT NULL AND COMMENT <> ''), COUNT(*)), 2) AS PCT_DOCUMENTED
FROM SNOWFLAKE.ACCOUNT_USAGE.COLUMNS
WHERE DELETED IS NULL AND TABLE_CATALOG ILIKE $DB_PATTERN
GROUP BY 1, 2 ORDER BY 1, 2;

-- 3. Tags in use (incl. classification system tags)
SELECT TAG_DATABASE, TAG_SCHEMA, TAG_NAME, DOMAIN, COUNT(*) AS ASSIGNMENTS, COUNT(DISTINCT TAG_VALUE) AS DISTINCT_VALUES
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE OBJECT_DELETED IS NULL AND OBJECT_DATABASE ILIKE $DB_PATTERN
GROUP BY 1, 2, 3, 4 ORDER BY ASSIGNMENTS DESC;

-- 4. Masking and row access policies and where they are applied
SELECT POLICY_KIND, POLICY_DB || '.' || POLICY_SCHEMA || '.' || POLICY_NAME AS POLICY,
       REF_DATABASE_NAME || '.' || REF_SCHEMA_NAME || '.' || REF_ENTITY_NAME AS OBJECT_NAME, REF_COLUMN_NAME, POLICY_STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE REF_DATABASE_NAME ILIKE $DB_PATTERN
ORDER BY 1, 2, 3;

-- 5. Object dependencies (views on tables) - the structural lineage
SELECT REFERENCING_DATABASE || '.' || REFERENCING_SCHEMA || '.' || REFERENCING_OBJECT_NAME AS DEPENDENT_OBJECT,
       REFERENCING_OBJECT_DOMAIN,
       REFERENCED_DATABASE || '.' || REFERENCED_SCHEMA || '.' || REFERENCED_OBJECT_NAME AS DEPENDS_ON,
       REFERENCED_OBJECT_DOMAIN, DEPENDENCY_TYPE
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE REFERENCING_DATABASE ILIKE $DB_PATTERN
ORDER BY 1;

-- 6. Classification results (sensitive data detected by Snowflake)
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_CLASSIFICATION_LATEST
WHERE DATABASE_NAME ILIKE $DB_PATTERN;

-- 7. Lineage of one object (data movement recorded by Snowflake, Enterprise edition)
-- SELECT * FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('<DB>.<SCHEMA>.<OBJECT>', 'TABLE', 'UPSTREAM', 5));

-- 8. Refresh jobs: tasks and their schedules (run per database)
-- SHOW TASKS IN DATABASE <DB>;
