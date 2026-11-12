-- =====================================================================
-- 00 CORTEX ACCESS (optional, needs ACCOUNTADMIN): lets Cortex use models hosted in other regions.
-- Only needed when the account region does not host the model in config.AI_MODEL / the agent's model.
-- Ask the account admin to run it if your role cannot.
-- =====================================================================
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
