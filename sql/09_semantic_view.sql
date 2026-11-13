-- =====================================================================
-- 09 SEMANTIC VIEW over the Knowledge Fabric (Cortex Analyst)
--   Lets the agent answer structured metadata questions with SQL: lists, counts, filters
--   ("which fields are masked in the datamart", "how many columns have no description",
--    "full lineage of VENDOR_COUNTRY", "which job refreshes the datamart").
--   The model describes METADATA, not AP business values.
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};

CREATE OR REPLACE SEMANTIC VIEW {{DATABASE}}.{{KF}}.{{SEMANTIC_VIEW}}

TABLES (
  ap_objects AS {{DATABASE}}.{{KF}}.KF_OBJECTS PRIMARY KEY (OBJECT_KEY)
    WITH SYNONYMS ('tables', 'views', 'objects', 'data assets')
    COMMENT = 'One row per table or view of the AP model (layers: Landing, EDW, Datamart, Reporting), from Snowflake metadata.',
  ap_columns AS {{DATABASE}}.{{KF}}.KF_COLUMNS PRIMARY KEY (COLUMN_KEY)
    WITH SYNONYMS ('columns', 'fields', 'attributes')
    COMMENT = 'One row per column of the AP model with business name, description, sensitivity and masking.',
  field_lineage AS {{DATABASE}}.{{KF}}.KF_LINEAGE_PATHS PRIMARY KEY (PATH_STEP_ID)
    WITH SYNONYMS ('lineage', 'data lineage', 'where does it come from', 'provenance')
    COMMENT = 'Every reporting column traced hop by hop back to the SAP landing columns. Hop 1 = reporting <- datamart.',
  field_mapping AS {{DATABASE}}.{{KF}}.KF_FIELD_MAPPING PRIMARY KEY (MAPPING_ID)
    WITH SYNONYMS ('mapping sheet', 'source to target mapping', 'transformation rules')
    COMMENT = 'Mapping sheet: one row per target column and source column with the transformation rule.',
  object_relationships AS {{DATABASE}}.{{KF}}.KF_ASSET_RELATIONSHIPS PRIMARY KEY (RELATIONSHIP_ID)
    WITH SYNONYMS ('joins', 'connections', 'data flow', 'dependencies')
    COMMENT = 'How objects join (Join) and how data flows between them (Loads into).',
  business_glossary AS {{DATABASE}}.{{KF}}.KF_GLOSSARY PRIMARY KEY (TERM)
    WITH SYNONYMS ('glossary', 'definitions', 'business terms', 'KPI definitions')
    COMMENT = 'Business terms with definition, calculation, owner and approval status.',
  refresh_jobs AS {{DATABASE}}.{{KF}}.KF_REFRESH_SCHEDULE PRIMARY KEY (TASK_NAME)
    WITH SYNONYMS ('refresh schedule', 'load jobs', 'tasks', 'pipelines')
    COMMENT = 'Snowflake tasks that load the AP model, with schedule and the objects they refresh.',
  impact AS {{DATABASE}}.{{KF}}.KF_IMPACT PRIMARY KEY (IMPACT_ID)
    WITH SYNONYMS ('impact analysis', 'downstream', 'what is affected', 'dependencies downstream', 'used by')
    COMMENT = 'For every column: each downstream column, dashboard, report and extract that depends on it. Filter on changed_object / changed_column.',
  report_usage AS {{DATABASE}}.{{KF}}.KF_REPORT_USAGE PRIMARY KEY (CONSUMER_NAME, OBJECT_KEY, COLUMN_NAME)
    WITH SYNONYMS ('reports', 'dashboards', 'extracts', 'consumers')
    COMMENT = 'Dashboards, reports and extracts that read the reporting views, one row per consumer and column.',
  requirements AS {{DATABASE}}.{{KF}}.KF_REQUIREMENTS PRIMARY KEY (REQ_ID)
    WITH SYNONYMS ('business requirements', 'BRD requirements')
    COMMENT = 'AP reporting requirements with ID, text, priority and status.',
  requirement_trace AS {{DATABASE}}.{{KF}}.KF_REQUIREMENT_TRACE PRIMARY KEY (TRACE_ID)
    WITH SYNONYMS ('traceability', 'requirement trace')
    COMMENT = 'Which objects and columns implement or expose each requirement.',
  mapping_changes AS {{DATABASE}}.{{KF}}.KF_MAPPING_CHANGE_LOG PRIMARY KEY (CHANGE_ID)
    WITH SYNONYMS ('change log', 'mapping history', 'audit log', 'what changed')
    COMMENT = 'History of mapping changes: what, why, requirement, who prepared, reviewed (gate) and approved.',
  reporting_views AS {{DATABASE}}.{{KF}}.KF_REPORTING_VIEWS PRIMARY KEY (VIEW_KEY)
    WITH SYNONYMS ('data dictionary card', 'view card', 'reporting view details', 'view profile')
    COMMENT = 'One row per reporting view with every data dictionary attribute: description, data class, owners, refresh, keys, masked columns, datamart source, upstream, SAP source fields, consumers, key filters, KPIs, alternative views, requirements.',
  key_filters AS {{DATABASE}}.{{KF}}.KF_KEY_FILTERS PRIMARY KEY (FILTER_ID)
    WITH SYNONYMS ('filters', 'report filters', 'extract filters')
    COMMENT = 'Key filters per reporting view, applied in the EDW load, datamart load, view definition or a report.',
  sap_tcodes AS {{DATABASE}}.{{KF}}.KF_SAP_TCODE_MAP PRIMARY KEY (MAP_ID)
    WITH SYNONYMS ('T-codes', 'transaction codes', 'SAP transactions', 'SAP source fields')
    COMMENT = 'Phase 2 preview: SAP T-code -> SAP table and field -> ingested? -> EDW object/column, with mapping status and owner.',
  reuse_assessment AS {{DATABASE}}.{{KF}}.KF_REUSE_ASSESSMENT PRIMARY KEY (SAP_TABLE, SAP_FIELD)
    WITH SYNONYMS ('reuse', 'can we reuse', 'already exists', 'new replication', 'gap analysis', 'requirement assessment')
    COMMENT = 'Per SAP field: ingested or not, EDW/datamart and reporting columns that use it, reports using it, T-codes, and the reuse decision (reuse / extend EDW / new replication).'
)

RELATIONSHIPS (
  columns_to_objects AS ap_columns (OBJECT_KEY) REFERENCES ap_objects,
  trace_to_requirements AS requirement_trace (REQ_ID) REFERENCES requirements
)

FACTS (
  ap_objects.row_count_value AS ROW_COUNT COMMENT = 'Number of rows in the table (empty for views)',
  field_lineage.hop_value AS HOP COMMENT = 'Hop number of a lineage step'
)

DIMENSIONS (
  ap_objects.object_key AS OBJECT_KEY COMMENT = 'SCHEMA.OBJECT of the table or view',
  ap_objects.object_name AS OBJECT_NAME WITH SYNONYMS = ('table name', 'view name') COMMENT = 'Name of the table or view',
  ap_objects.object_type AS OBJECT_TYPE COMMENT = 'Table or View' SAMPLE_VALUES ('Table', 'View'),
  ap_objects.data_layer AS DATA_LAYER WITH SYNONYMS = ('layer', 'zone')
    COMMENT = 'Layer of the AP model' SAMPLE_VALUES ('Landing', 'EDW', 'Datamart', 'Reporting'),
  ap_objects.layer_order AS LAYER_ORDER COMMENT = 'Order of the layer: 1 Landing, 2 EDW, 3 Datamart, 4 Reporting',
  ap_objects.object_description AS DESCRIPTION COMMENT = 'Description (comment) of the object; states source and grain',
  ap_objects.object_has_description AS HAS_DESCRIPTION COMMENT = 'TRUE if the object has a description',
  ap_objects.object_ai_suggestion AS AI_SUGGESTED_DESCRIPTION COMMENT = 'AI draft description for objects without one (not approved)',
  ap_objects.refresh_frequency AS REFRESH_FREQUENCY WITH SYNONYMS = ('refresh', 'update frequency', 'how often refreshed', 'latency')
    COMMENT = 'How often the object is refreshed (from the REFRESH_FREQUENCY tag)',
  ap_objects.refreshed_by_task AS REFRESHED_BY_TASK COMMENT = 'Snowflake task that loads the object',
  ap_objects.data_owner AS DATA_OWNER COMMENT = 'Accountable owner (role)',
  ap_objects.data_steward AS DATA_STEWARD COMMENT = 'Data steward (role)',
  ap_objects.certification AS CERTIFICATION COMMENT = 'Certified, In review or Not certified',
  ap_objects.source_system AS SOURCE_SYSTEM COMMENT = 'Source system of the data',
  ap_objects.last_altered AS LAST_ALTERED COMMENT = 'When the object data or structure last changed',
  ap_objects.database_name AS DATABASE_NAME COMMENT = 'Database of the object',
  ap_objects.data_class AS DATA_CLASS WITH SYNONYMS = ('transaction or master data', 'data classification')
    COMMENT = 'Transaction / master / reference / aggregated data' SAMPLE_VALUES ('Transaction data', 'Master data', 'Reference data', 'Aggregated data'),
  ap_objects.technical_owner AS TECHNICAL_OWNER COMMENT = 'Technical owner (team role)',
  ap_objects.upstream_objects AS UPSTREAM_OBJECTS COMMENT = 'Objects this object is loaded from',
  ap_objects.downstream_objects AS DOWNSTREAM_OBJECTS COMMENT = 'Objects loaded from this object',

  ap_columns.column_key AS COLUMN_KEY COMMENT = 'SCHEMA.OBJECT.COLUMN',
  ap_columns.column_object AS OBJECT_KEY COMMENT = 'SCHEMA.OBJECT the column belongs to',
  ap_columns.column_layer AS DATA_LAYER COMMENT = 'Layer of the column''s object' SAMPLE_VALUES ('Landing', 'EDW', 'Datamart', 'Reporting'),
  ap_columns.column_name AS COLUMN_NAME WITH SYNONYMS = ('field name', 'technical name') COMMENT = 'Technical column name',
  ap_columns.business_name AS BUSINESS_NAME WITH SYNONYMS = ('business label', 'friendly name') COMMENT = 'Business name of the column',
  ap_columns.data_type AS DATA_TYPE COMMENT = 'Snowflake data type',
  ap_columns.column_description AS DESCRIPTION COMMENT = 'Column description (comment)',
  ap_columns.has_column_description AS HAS_DESCRIPTION COMMENT = 'TRUE if the column has a description',
  ap_columns.sensitivity AS SENSITIVITY COMMENT = 'Sensitivity class' SAMPLE_VALUES ('Internal', 'Confidential', 'Restricted'),
  ap_columns.semantic_category AS SEMANTIC_CATEGORY COMMENT = 'Category assigned by Snowflake classification (if run)',
  ap_columns.masking_policy AS MASKING_POLICY COMMENT = 'Masking policy set directly on the column',
  ap_columns.is_masked AS IS_MASKED WITH SYNONYMS = ('masked', 'protected', 'hidden')
    COMMENT = 'TRUE if masked directly or through an upstream column (views inherit masking)',
  ap_columns.masked_via AS MASKED_VIA COMMENT = 'Upstream column whose masking applies to this view column',
  ap_columns.ai_suggested_description AS AI_SUGGESTED_DESCRIPTION COMMENT = 'AI draft description for undocumented columns (not approved)',
  ap_columns.data_type_full AS DATA_TYPE_FULL WITH SYNONYMS = ('field length', 'character limit', 'precision')
    COMMENT = 'Data type with length or precision, e.g. VARCHAR(10), NUMBER(15,2)',
  ap_columns.key_role AS KEY_ROLE WITH SYNONYMS = ('primary key', 'business key', 'key column')
    COMMENT = 'Primary key or Business key' SAMPLE_VALUES ('Primary key', 'Business key'),
  ap_columns.technical_description AS TECHNICAL_DESCRIPTION COMMENT = 'Technical description: type, key, SAP field, masking, source and transformation rule',

  field_lineage.report_object AS REPORT_OBJECT COMMENT = 'Reporting view the lineage starts from (SCHEMA.OBJECT)',
  field_lineage.report_column AS REPORT_COLUMN COMMENT = 'Reporting column the lineage starts from',
  field_lineage.hop AS HOP COMMENT = 'Step number: 1 = reporting <- datamart, higher = further upstream',
  field_lineage.lineage_target_object AS TARGET_OBJECT COMMENT = 'Object receiving the value in this step',
  field_lineage.lineage_target_column AS TARGET_COLUMN COMMENT = 'Column receiving the value in this step',
  field_lineage.lineage_source_object AS SOURCE_OBJECT COMMENT = 'Object the value comes from in this step',
  field_lineage.lineage_source_column AS SOURCE_COLUMN COMMENT = 'Column the value comes from in this step',
  field_lineage.source_layer AS SOURCE_LAYER COMMENT = 'Layer of the source object',
  field_lineage.lineage_mapping_type AS MAPPING_TYPE COMMENT = 'Direct, Renamed, Lookup, Derived, Conditional or Aggregated',
  field_lineage.lineage_rule AS TRANSFORMATION_RULE COMMENT = 'Transformation rule of this step',
  field_lineage.is_origin AS IS_ORIGIN COMMENT = 'TRUE when the source column is the system of record (no further upstream step)',

  field_mapping.mapping_target_layer AS TARGET_LAYER COMMENT = 'Layer of the target object',
  field_mapping.mapping_target_object AS TARGET_OBJECT COMMENT = 'Target object (SCHEMA.OBJECT)',
  field_mapping.mapping_target_column AS TARGET_COLUMN COMMENT = 'Target column',
  field_mapping.mapping_source_object AS SOURCE_OBJECT COMMENT = 'Source object (SCHEMA.OBJECT)',
  field_mapping.mapping_source_column AS SOURCE_COLUMN COMMENT = 'Source column',
  field_mapping.mapping_type AS MAPPING_TYPE COMMENT = 'Mapping type',
  field_mapping.transformation_rule AS TRANSFORMATION_RULE COMMENT = 'Transformation rule',

  object_relationships.relationship_type AS RELATIONSHIP_TYPE COMMENT = 'Join or Loads into' SAMPLE_VALUES ('Join', 'Loads into'),
  object_relationships.from_object AS FROM_OBJECT COMMENT = 'Source / many side object',
  object_relationships.to_object AS TO_OBJECT COMMENT = 'Target / one side object',
  object_relationships.join_columns AS JOIN_COLUMNS COMMENT = 'Join keys',
  object_relationships.cardinality AS CARDINALITY COMMENT = 'Cardinality of the join',
  object_relationships.process AS PROCESS COMMENT = 'Load procedure or view that moves the data',
  object_relationships.relationship_description AS DESCRIPTION COMMENT = 'What the relationship means',

  business_glossary.term AS TERM WITH SYNONYMS = ('business term', 'KPI') COMMENT = 'Business term',
  business_glossary.definition AS DEFINITION COMMENT = 'Definition in business language',
  business_glossary.calculation AS CALCULATION COMMENT = 'How it is calculated',
  business_glossary.implemented_in AS IMPLEMENTED_IN COMMENT = 'SCHEMA.OBJECT.COLUMN that implements the term',
  business_glossary.term_synonyms AS SYNONYMS COMMENT = 'Other words for the term',
  business_glossary.term_owner AS OWNER COMMENT = 'Owner of the definition',
  business_glossary.term_status AS STATUS COMMENT = 'Approved or Draft' SAMPLE_VALUES ('Approved', 'Draft'),
  business_glossary.source_document AS SOURCE_DOCUMENT COMMENT = 'Where the definition is documented',
  business_glossary.term_type AS TERM_TYPE COMMENT = 'KPI or Business term' SAMPLE_VALUES ('KPI', 'Business term'),

  refresh_jobs.task_name AS TASK_NAME COMMENT = 'Snowflake task name',
  refresh_jobs.task_schema AS SCHEMA_NAME COMMENT = 'Schema of the task',
  refresh_jobs.schedule AS SCHEDULE COMMENT = 'CRON schedule (empty when the task runs after another task)',
  refresh_jobs.runs_after AS RUNS_AFTER COMMENT = 'Predecessor task',
  refresh_jobs.task_state AS STATE COMMENT = 'started or suspended',
  refresh_jobs.refreshes_objects AS REFRESHES_OBJECTS COMMENT = 'Objects the task refreshes',
  refresh_jobs.task_description AS DESCRIPTION COMMENT = 'What the job does and when',

  impact.changed_object AS CHANGED_OBJECT COMMENT = 'Object that would change (SCHEMA.OBJECT)',
  impact.changed_column AS CHANGED_COLUMN COMMENT = 'Column that would change',
  impact.changed_layer AS CHANGED_LAYER COMMENT = 'Layer of the changed object',
  impact.affected_type AS AFFECTED_TYPE COMMENT = 'Column, Dashboard, Report or Extract' SAMPLE_VALUES ('Column', 'Dashboard', 'Report', 'Extract'),
  impact.affected_object AS AFFECTED_OBJECT COMMENT = 'Downstream object (SCHEMA.OBJECT) or dashboard / report / extract name',
  impact.affected_column AS AFFECTED_COLUMN COMMENT = 'Downstream column (for consumers: the reporting column they read)',
  impact.affected_layer AS AFFECTED_LAYER COMMENT = 'EDW, Datamart, Reporting or Consumer' SAMPLE_VALUES ('EDW', 'Datamart', 'Reporting', 'Consumer'),
  impact.impact_distance AS DISTANCE COMMENT = 'Steps downstream from the changed column',
  impact.impact_path AS IMPACT_PATH COMMENT = 'Path from the changed column to the affected item',
  impact.impact_owner AS OWNER COMMENT = 'Owner of an affected dashboard / report / extract',

  report_usage.consumer_name AS CONSUMER_NAME WITH SYNONYMS = ('report name', 'dashboard name') COMMENT = 'Dashboard, report or extract',
  report_usage.consumer_type AS CONSUMER_TYPE COMMENT = 'Dashboard, Report or Extract',
  report_usage.consumer_tool AS TOOL COMMENT = 'Where it runs',
  report_usage.consumer_audience AS AUDIENCE COMMENT = 'Who uses it',
  report_usage.consumer_owner AS OWNER COMMENT = 'Owner (role)',
  report_usage.consumer_frequency AS FREQUENCY COMMENT = 'How often it is used / produced',
  report_usage.consumer_object AS OBJECT_KEY COMMENT = 'Reporting view it reads',
  report_usage.consumer_column AS COLUMN_NAME COMMENT = 'Column it reads',
  report_usage.consumer_usage AS USAGE COMMENT = 'Measure, Dimension, Filter or Output field',

  requirements.req_id AS REQ_ID WITH SYNONYMS = ('requirement id') COMMENT = 'Requirement ID such as AP-R03',
  requirements.req_title AS TITLE COMMENT = 'Requirement title',
  requirements.req_text AS REQUIREMENT_TEXT COMMENT = 'Requirement text',
  requirements.req_source AS SOURCE_DOCUMENT COMMENT = 'Document and section',
  requirements.req_priority AS PRIORITY COMMENT = 'Must, Should or Could',
  requirements.req_status AS STATUS COMMENT = 'Implemented, Partly implemented or Open',

  requirement_trace.trace_req_id AS REQ_ID COMMENT = 'Requirement ID',
  requirement_trace.trace_object AS OBJECT_KEY COMMENT = 'Object implementing or exposing the requirement (SCHEMA.OBJECT)',
  requirement_trace.trace_column AS COLUMN_NAME COMMENT = 'Column, if traced at column level',
  requirement_trace.trace_type AS TRACE_TYPE COMMENT = 'Implements or Exposes',

  mapping_changes.change_id AS CHANGE_ID COMMENT = 'Change ID',
  mapping_changes.change_date AS CHANGE_DATE COMMENT = 'Date of the change',
  mapping_changes.mapping_version AS MAPPING_VERSION COMMENT = 'Mapping sheet version after the change',
  mapping_changes.change_object AS TARGET_OBJECT COMMENT = 'Object changed',
  mapping_changes.change_column AS TARGET_COLUMN COMMENT = 'Column changed',
  mapping_changes.change_type AS CHANGE_TYPE COMMENT = 'New mapping, Source change, Rule change, Correction or Security',
  mapping_changes.change_description AS CHANGE_DESCRIPTION COMMENT = 'What changed',
  mapping_changes.change_reason AS REASON COMMENT = 'Why it changed',
  mapping_changes.change_requirements AS RELATED_REQ COMMENT = 'Requirement IDs behind the change',
  mapping_changes.prepared_by AS PREPARED_BY COMMENT = 'Who prepared the change (role)',
  mapping_changes.reviewed_by AS REVIEWED_BY COMMENT = 'Who reviewed it and at which gate',
  mapping_changes.approved_by AS APPROVED_BY COMMENT = 'Who approved the release',
  mapping_changes.change_status AS STATUS COMMENT = 'Released or Proposed',

  reporting_views.view_key AS VIEW_KEY COMMENT = 'SCHEMA.VIEW',
  reporting_views.card_database AS DATABASE_NAME COMMENT = 'EDW database',
  reporting_views.card_schema AS SCHEMA_NAME COMMENT = 'Schema',
  reporting_views.view_name AS VIEW_NAME WITH SYNONYMS = ('reporting view') COMMENT = 'Reporting view name',
  reporting_views.view_description AS VIEW_DESCRIPTION COMMENT = 'Model / view description',
  reporting_views.card_data_class AS DATA_CLASS COMMENT = 'Transaction / master / reference / aggregated data',
  reporting_views.portfolio_domain AS PORTFOLIO_DOMAIN WITH SYNONYMS = ('portfolio', 'domain') COMMENT = 'Portfolio / domain',
  reporting_views.card_data_product AS DATA_PRODUCT COMMENT = 'Data product',
  reporting_views.card_data_owner AS DATA_OWNER COMMENT = 'Data / model owner',
  reporting_views.card_technical_owner AS TECHNICAL_OWNER COMMENT = 'Technical owner',
  reporting_views.card_refresh AS REFRESH_FREQUENCY COMMENT = 'Refresh frequency',
  reporting_views.refresh_jobs AS REFRESH_JOBS COMMENT = 'Tasks that refresh the datamart source',
  reporting_views.primary_key AS PRIMARY_KEY COMMENT = 'Primary key column(s)',
  reporting_views.business_key AS BUSINESS_KEY COMMENT = 'Business key column(s)',
  reporting_views.masked_columns AS MASKED_COLUMNS COMMENT = 'Masked columns',
  reporting_views.dm_source_tables AS DM_SOURCE_TABLES COMMENT = 'Datamart table(s) the view reads',
  reporting_views.card_upstream AS UPSTREAM_OBJECTS COMMENT = 'All upstream objects back to SAP landing',
  reporting_views.sap_source_fields AS SAP_SOURCE_FIELDS COMMENT = 'SAP landing fields at the origin of the lineage',
  reporting_views.downstream_consumers AS DOWNSTREAM_CONSUMERS COMMENT = 'Dashboards, reports and extracts using the view',
  reporting_views.card_key_filters AS KEY_FILTERS COMMENT = 'Key filters (load, view, reports)',
  reporting_views.card_kpis AS KPIS COMMENT = 'KPI definitions and calculations',
  reporting_views.alternative_views AS ALTERNATIVE_VIEWS COMMENT = 'Other reporting views on the same datamart table',
  reporting_views.card_requirements AS REQUIREMENTS COMMENT = 'Requirement IDs',

  key_filters.filter_object AS OBJECT_KEY COMMENT = 'Reporting view (SCHEMA.VIEW)',
  key_filters.filter_column AS COLUMN_NAME COMMENT = 'Column filtered on',
  key_filters.filter_rule AS FILTER_RULE COMMENT = 'The filter in plain words',
  key_filters.applied_in AS APPLIED_IN COMMENT = 'EDW load, Datamart load, View definition or Report',
  key_filters.filter_consumer AS CONSUMER_NAME COMMENT = 'Report / extract applying the filter',

  sap_tcodes.tcode AS TCODE WITH SYNONYMS = ('T-code', 'transaction code', 'transaction') COMMENT = 'SAP transaction code',
  sap_tcodes.tcode_description AS TCODE_DESCRIPTION COMMENT = 'What the transaction is used for',
  sap_tcodes.business_process AS BUSINESS_PROCESS COMMENT = 'Associated business process',
  sap_tcodes.sap_table AS SAP_TABLE COMMENT = 'SAP table',
  sap_tcodes.sap_table_description AS SAP_TABLE_DESCRIPTION COMMENT = 'SAP table description',
  sap_tcodes.sap_field AS SAP_FIELD COMMENT = 'SAP field',
  sap_tcodes.sap_field_description AS SAP_FIELD_DESCRIPTION COMMENT = 'SAP field description',
  sap_tcodes.is_ingested AS IS_INGESTED WITH SYNONYMS = ('already replicated', 'already ingested', 'available in EDW')
    COMMENT = 'TRUE if the SAP field is already replicated into landing',
  sap_tcodes.landing_object AS LANDING_OBJECT COMMENT = 'Landing table holding the field',
  sap_tcodes.related_edw_object AS RELATED_EDW_OBJECT COMMENT = 'EDW / datamart object modelling the field',
  sap_tcodes.related_edw_column AS RELATED_EDW_COLUMN COMMENT = 'EDW / datamart column modelling the field',
  sap_tcodes.mapping_status AS MAPPING_STATUS COMMENT = 'Validated, Ingested - not modelled, Not ingested'
    SAMPLE_VALUES ('Validated', 'Ingested - not modelled', 'Not ingested'),
  sap_tcodes.mapping_owner AS MAPPING_OWNER COMMENT = 'Who validates the mapping',
  sap_tcodes.tcode_note AS NOTE COMMENT = 'What to do if the field is needed (reuse, extend EDW, new replication)',

  reuse_assessment.reuse_sap_table AS SAP_TABLE COMMENT = 'SAP table (without the SAP_ prefix), e.g. BSEG, LFA1',
  reuse_assessment.reuse_sap_field AS SAP_FIELD WITH SYNONYMS = ('SAP field', 'source field') COMMENT = 'SAP field, e.g. LAND1, ZWELS',
  reuse_assessment.reuse_field_description AS FIELD_DESCRIPTION COMMENT = 'SAP field description or business name',
  reuse_assessment.reuse_landing_object AS LANDING_OBJECT COMMENT = 'Landing table holding the field, if ingested',
  reuse_assessment.reuse_is_ingested AS IS_INGESTED COMMENT = 'TRUE if the field is already replicated into landing',
  reuse_assessment.reuse_model_columns AS EDW_DATAMART_COLUMNS COMMENT = 'EDW and datamart columns built from the field',
  reuse_assessment.reuse_reporting_columns AS REPORTING_COLUMNS COMMENT = 'Reporting view columns that expose the field',
  reuse_assessment.reuse_reports AS USED_BY_REPORTS COMMENT = 'Dashboards, reports and extracts that use the field',
  reuse_assessment.reuse_tcodes AS TCODES COMMENT = 'SAP T-codes that show the field (phase 2 preview)',
  reuse_assessment.reuse_status AS REUSE_STATUS WITH SYNONYMS = ('reuse decision', 'can it be reused')
    COMMENT = 'Reuse - already in reporting views / Reuse - in EDW or datamart, not yet in reporting / Extend EDW - ingested but not modelled / New replication needed',
  reuse_assessment.reuse_action AS RECOMMENDED_ACTION COMMENT = 'What to do',
  reuse_assessment.reuse_confirm_with AS CONFIRM_WITH COMMENT = 'Who confirms the mapping'
)

METRICS (
  ap_objects.object_count AS COUNT(OBJECT_KEY) WITH SYNONYMS = ('number of tables', 'number of objects') COMMENT = 'Number of tables and views',
  ap_objects.undocumented_object_count AS COUNT_IF(NOT HAS_DESCRIPTION) COMMENT = 'Objects without a description',
  ap_columns.column_count AS COUNT(COLUMN_KEY) WITH SYNONYMS = ('number of columns', 'number of fields') COMMENT = 'Number of columns',
  ap_columns.masked_column_count AS COUNT_IF(IS_MASKED) WITH SYNONYMS = ('number of masked fields') COMMENT = 'Masked columns (direct or inherited)',
  ap_columns.undocumented_column_count AS COUNT_IF(NOT HAS_DESCRIPTION) WITH SYNONYMS = ('missing descriptions', 'documentation gaps')
    COMMENT = 'Columns without a description',
  ap_columns.documentation_coverage AS DIV0(COUNT_IF(HAS_DESCRIPTION), COUNT(COLUMN_KEY))
    COMMENT = 'Share (0-1) of columns with a description',
  business_glossary.term_count AS COUNT(TERM) COMMENT = 'Number of business terms',
  impact.affected_consumer_count AS COUNT(DISTINCT IFF(AFFECTED_LAYER = 'Consumer', AFFECTED_OBJECT, NULL))
    WITH SYNONYMS = ('number of affected reports') COMMENT = 'Distinct dashboards, reports and extracts affected',
  requirements.requirement_count AS COUNT(REQ_ID) COMMENT = 'Number of requirements'
)

COMMENT = 'Knowledge Fabric metadata model for the AP data product: objects, columns, lineage, impact, mapping, change log, requirements, report usage, reporting view cards, key filters, SAP T-codes, relationships, glossary, refresh jobs. Metadata only, no AP business values.'

AI_SQL_GENERATION 'This model holds METADATA about the Accounts Payable data model, not AP amounts. Object keys look like SCHEMA.OBJECT (for example AP_REPORTING.VW_AP_OPEN_ITEMS). Match object and column names case-insensitively with ILIKE and partial names (for example ILIKE ''%VENDOR_COUNTRY%''). For "where does a field come from", select from field_lineage filtered on report_column (and report_object if given), ordered by hop, and show target, source, mapping type and rule. For layer order use layer_order. Show percentages with 2 decimals (multiply 0-1 shares by 100). For masked fields use is_masked = TRUE and show masking_policy and masked_via. Treat glossary terms with status Draft as not official. For "what is affected if X changes" or "which reports depend on X" use the impact table filtered on changed_object / changed_column (consumers have affected_layer = Consumer). For requirements use requirements and requirement_trace. For "what changed and why" or "how was it reviewed" use mapping_changes ordered by change_date. For everything about one reporting view (data dictionary card) use reporting_views. For SAP T-codes, SAP tables/fields, "is it already ingested" or "do we need new replication" use sap_tcodes. For KPI lists use business_glossary where term_type = KPI. For "do we already have this data / can we reuse it / do we need new replication" at SAP-field level use reuse_assessment (filter on reuse_tcodes ILIKE the T-code, or reuse_sap_field / reuse_sap_table).'

AI_QUESTION_CATEGORIZATION 'Questions about actual AP amounts, balances, invoices or vendors (business values) are out of scope of this metadata model: say so and explain which reporting view holds the data. Never reveal masked values.'

AI_VERIFIED_QUERIES (
  vq_model_objects AS (
    QUESTION 'Which tables and views make up the AP model, by layer?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT data_layer, object_name, object_type, object_description, refresh_frequency FROM ap_objects ORDER BY layer_order, object_name'
  ),
  vq_vendor_country_lineage AS (
    QUESTION 'Where does vendor country in the AP open items report come from?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT hop, lineage_target_object, lineage_target_column, lineage_source_object, lineage_source_column, lineage_mapping_type, lineage_rule, is_origin FROM field_lineage WHERE report_object ILIKE ''%VW_AP_OPEN_ITEMS'' AND report_column = ''VENDOR_COUNTRY'' ORDER BY hop, lineage_source_object'
  ),
  vq_aging_definition AS (
    QUESTION 'How is AP aging defined and which aging buckets exist?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT term, definition, calculation, implemented_in, term_status, source_document FROM business_glossary WHERE term IN (''AP Aging'', ''Aging Bucket'', ''Days Past Due'', ''Net Due Date'') ORDER BY term'
  ),
  vq_datamart_refresh AS (
    QUESTION 'How often is the AP datamart refreshed?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT object_name, refresh_frequency, refreshed_by_task, last_altered FROM ap_objects WHERE data_layer = ''Datamart'' ORDER BY object_name'
  ),
  vq_masked_fields AS (
    QUESTION 'Which fields are masked in the AP datamart and reporting layer?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT column_layer, column_object, column_name, business_name, sensitivity, masking_policy, masked_via FROM ap_columns WHERE is_masked AND column_layer IN (''Datamart'', ''Reporting'') ORDER BY column_layer, column_object, column_name'
  ),
  vq_documentation_gaps AS (
    QUESTION 'Which columns have no description?'
    VERIFIED_AT 1794441600
    SQL 'SELECT column_layer, column_object, column_name, ai_suggested_description FROM ap_columns WHERE NOT has_column_description ORDER BY column_layer, column_object'
  ),
  vq_joins AS (
    QUESTION 'How are the AP tables connected?'
    VERIFIED_AT 1794441600
    SQL 'SELECT relationship_type, from_object, to_object, join_columns, cardinality, process FROM object_relationships ORDER BY relationship_type, from_object'
  ),
  vq_impact_vendor_country_source AS (
    QUESTION 'What is affected if the vendor master country field SAP_LFA1.LAND1 changes?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT affected_layer, affected_type, affected_object, affected_column, impact_distance, impact_owner FROM impact WHERE changed_object ILIKE ''%SAP_LFA1'' AND changed_column = ''LAND1'' ORDER BY impact_distance, affected_object'
  ),
  vq_reports_using_vendor_country AS (
    QUESTION 'Which reports depend on the vendor country field?'
    VERIFIED_AT 1794441600
    SQL 'SELECT consumer_name, consumer_type, consumer_object, consumer_column, consumer_owner, consumer_frequency FROM report_usage WHERE consumer_column = ''VENDOR_COUNTRY'' ORDER BY consumer_name'
  ),
  vq_requirements_payment_terms AS (
    QUESTION 'Which requirements cover vendor payment terms?'
    VERIFIED_AT 1794441600
    SQL 'SELECT req_id, req_title, req_text, req_priority, req_status, req_source FROM requirements WHERE req_text ILIKE ''%payment term%'' OR req_title ILIKE ''%payment term%'' ORDER BY req_id'
  ),
  vq_requirements_for_table AS (
    QUESTION 'Which requirements trace to the AP open items datamart table?'
    VERIFIED_AT 1794441600
    SQL 'SELECT trace_req_id, trace_object, trace_column, trace_type FROM requirement_trace WHERE trace_object ILIKE ''%DM_AP_OPEN_ITEMS'' ORDER BY trace_req_id'
  ),
  vq_vendor_country_changes AS (
    QUESTION 'What changed in the vendor country mapping, and why?'
    VERIFIED_AT 1794441600
    SQL 'SELECT change_id, change_date, mapping_version, change_object, change_column, change_type, change_description, change_reason, reviewed_by, approved_by, change_status FROM mapping_changes WHERE change_column ILIKE ''%COUNTRY%'' ORDER BY change_date'
  ),
  vq_view_card AS (
    QUESTION 'Show the full data dictionary card for the AP open items reporting view'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT card_database, card_schema, view_name, view_description, card_data_class, portfolio_domain, card_data_product, card_data_owner, card_technical_owner, card_refresh, refresh_jobs, primary_key, business_key, masked_columns, dm_source_tables, card_upstream, sap_source_fields, downstream_consumers, card_key_filters, card_kpis, alternative_views, card_requirements FROM reporting_views WHERE view_name = ''VW_AP_OPEN_ITEMS'''
  ),
  vq_view_columns AS (
    QUESTION 'List the columns of VW_AP_OPEN_ITEMS with data type, key, business name, business and technical description'
    VERIFIED_AT 1794441600
    SQL 'SELECT column_name, data_type_full, key_role, business_name, column_description, technical_description, sensitivity, is_masked FROM ap_columns WHERE column_object ILIKE ''%VW_AP_OPEN_ITEMS'' ORDER BY column_name'
  ),
  vq_alternative_views AS (
    QUESTION 'Which reporting views use the same datamart table as VW_AP_OPEN_ITEMS?'
    VERIFIED_AT 1794441600
    SQL 'SELECT view_name, dm_source_tables, alternative_views FROM reporting_views WHERE view_name = ''VW_AP_OPEN_ITEMS'''
  ),
  vq_tcode_fbl1n AS (
    QUESTION 'Which SAP tables and fields are behind T-code FBL1N, and are they already in EDW?'
    VERIFIED_AT 1794441600
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT tcode, tcode_description, sap_table, sap_field, sap_field_description, is_ingested, related_edw_object, related_edw_column, mapping_status, tcode_note FROM sap_tcodes WHERE tcode = ''FBL1N'' ORDER BY sap_table, sap_field'
  ),
  vq_kpis AS (
    QUESTION 'Which KPIs are defined for AP and how are they calculated?'
    VERIFIED_AT 1794441600
    SQL 'SELECT term, calculation, implemented_in, term_status, source_document FROM business_glossary WHERE term_type = ''KPI'' ORDER BY term'
  ),
  vq_reuse_tcode AS (
    QUESTION 'Which SAP fields does T-code FBL1N use, and can we reuse them or do we need new replication?'
    VERIFIED_AT 1794528000
    ONBOARDING_QUESTION TRUE
    SQL 'SELECT reuse_sap_table, reuse_sap_field, reuse_field_description, reuse_is_ingested, reuse_model_columns, reuse_reporting_columns, reuse_status, reuse_action, reuse_confirm_with FROM reuse_assessment WHERE reuse_tcodes ILIKE ''%FBL1N%'' ORDER BY reuse_status, reuse_sap_table, reuse_sap_field'
  ),
  vq_reuse_field AS (
    QUESTION 'Is the vendor payment methods field already available, or do we need new replication?'
    VERIFIED_AT 1794528000
    SQL 'SELECT reuse_sap_table, reuse_sap_field, reuse_field_description, reuse_landing_object, reuse_is_ingested, reuse_model_columns, reuse_reporting_columns, reuse_status, reuse_action FROM reuse_assessment WHERE reuse_sap_field = ''ZWELS'''
  ),
  vq_reuse_summary AS (
    QUESTION 'How many SAP fields are reusable, need EDW extension, or need new replication?'
    VERIFIED_AT 1794528000
    SQL 'SELECT reuse_status, COUNT(*) AS sap_fields FROM reuse_assessment GROUP BY reuse_status ORDER BY reuse_status'
  )
);
