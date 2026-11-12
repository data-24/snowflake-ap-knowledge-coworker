-- =====================================================================
-- 13 SNOWFLAKE INTELLIGENCE (optional): show the agent in Snowflake's chat screen.
-- If this fails on the account, add it in Snowsight instead:
--   AI & ML -> Agents -> AP Knowledge Co-worker -> add to Snowflake Intelligence.
-- =====================================================================
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE {{BUSINESS_ROLE}};
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT {{DATABASE}}.{{KF}}.{{AGENT}};
