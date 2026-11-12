-- =====================================================================
-- 08 DOCUMENTS + CORTEX SEARCH
--   KF_DOCUMENTS stage      the 4 synthetic PDFs (BRD, FSD, governance standard, process and EDW standards) - run.py uploads them
--   KF_DOC_PAGES / CHUNKS   AI_PARSE_DOCUMENT (LAYOUT, page split) -> SPLIT_TEXT_RECURSIVE_CHARACTER
--   {{CATALOG_SEARCH}}      Cortex Search over the metadata catalog (objects, columns, lineage, terms, jobs)
--   {{DOCS_SEARCH}}         Cortex Search over the document chunks
-- =====================================================================
USE WAREHOUSE {{WAREHOUSE}};
USE SCHEMA {{DATABASE}}.{{KF}};

CREATE STAGE IF NOT EXISTS {{DOCS_STAGE}}
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE') DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Synthetic AP project documents (BRD, FSD, governance standard)';
ALTER STAGE {{DOCS_STAGE}} REFRESH;

CREATE OR REPLACE TABLE KF_DOCUMENT_CATALOG (
  FILE_NAME VARCHAR, DOC_TITLE VARCHAR, DOC_TYPE VARCHAR, DOC_VERSION VARCHAR, DOC_STATUS VARCHAR, DOC_OWNER VARCHAR
) COMMENT = 'One row per project document: title, type, version and status (shown as the citation).';

INSERT INTO KF_DOCUMENT_CATALOG VALUES
  ('BRD_AP_Aging_v1.2.pdf', 'BRD: Accounts Payable Aging Reporting', 'Business requirements', '1.2', 'Approved', 'AP Finance Data Owner (role)'),
  ('FSD_AP_Datamart_v1.0.pdf', 'FSD: Accounts Payable Datamart', 'Functional specification', '1.0', 'Approved', 'AP Data Steward (role)'),
  ('AP_Data_Governance_Standard_v1.1.pdf', 'AP Data Governance and Access Standard', 'Governance standard', '1.1', 'Approved', 'AP Finance Data Owner (role)'),
  ('AP_Process_and_EDW_Standards_v1.0.pdf', 'AP Process Overview and EDW Development Standards', 'Process and standards', '1.0', 'Approved', 'AP Data Steward (role)');

CREATE OR REPLACE TABLE KF_DOC_PAGES COMMENT = 'One row per document page (AI_PARSE_DOCUMENT, LAYOUT mode)' AS
WITH parsed AS (
  SELECT RELATIVE_PATH AS FILE_NAME,
         TRY_PARSE_JSON(TO_VARCHAR(
           AI_PARSE_DOCUMENT(TO_FILE('@{{DATABASE}}.{{KF}}.{{DOCS_STAGE}}', RELATIVE_PATH),
                             {'mode': 'LAYOUT', 'page_split': TRUE}))) AS PARSED
  FROM DIRECTORY(@{{DATABASE}}.{{KF}}.{{DOCS_STAGE}})
  WHERE RELATIVE_PATH ILIKE '%.pdf'
)
SELECT p.FILE_NAME, pg.value:index::INT + 1 AS PAGE_NUMBER, pg.value:content::STRING AS PAGE_TEXT, CURRENT_TIMESTAMP() AS PARSED_AT
FROM parsed p, LATERAL FLATTEN(input => p.PARSED:pages) pg;

CREATE OR REPLACE TABLE KF_DOC_CHUNKS COMMENT = 'Searchable document chunks with title, version and page' AS
WITH chunks AS (
  SELECT p.FILE_NAME, p.PAGE_NUMBER, c.index + 1 AS CHUNK_NUMBER, c.value::STRING AS CHUNK
  FROM KF_DOC_PAGES p,
       LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(p.PAGE_TEXT, 'markdown', {{CHUNK_SIZE}}, {{CHUNK_OVERLAP}})) c
  WHERE LENGTH(TRIM(p.PAGE_TEXT)) > 30
)
SELECT c.FILE_NAME || '#p' || c.PAGE_NUMBER || '-' || c.CHUNK_NUMBER AS CHUNK_ID,
       c.FILE_NAME, COALESCE(d.DOC_TITLE, c.FILE_NAME) AS DOC_TITLE, d.DOC_TYPE, d.DOC_VERSION, d.DOC_STATUS,
       c.PAGE_NUMBER, c.CHUNK AS CHUNK_TEXT,
       COALESCE(d.DOC_TITLE, c.FILE_NAME) || ' (version ' || COALESCE(d.DOC_VERSION, '?') || ', ' || COALESCE(d.DOC_STATUS, '?')
         || ', page ' || c.PAGE_NUMBER || ')\n' || c.CHUNK AS SEARCH_TEXT
FROM chunks c LEFT JOIN KF_DOCUMENT_CATALOG d ON d.FILE_NAME = c.FILE_NAME;

-- Metadata catalog search: finds the right object / column / term from everyday words
CREATE OR REPLACE CORTEX SEARCH SERVICE {{CATALOG_SEARCH}}
  ON SEARCH_TEXT
  ATTRIBUTES ASSET_TYPE, DATA_LAYER, OBJECT_NAME
  WAREHOUSE = {{WAREHOUSE}}
  TARGET_LAG = '1 day'
  COMMENT = 'Knowledge Fabric catalog: AP objects, columns (with lineage and masking), business terms, relationships, refresh jobs'
AS
  SELECT ASSET_ID, ASSET_TYPE, ASSET_NAME, DATA_LAYER, OBJECT_NAME, COLUMN_NAME, BUSINESS_NAME, SEARCH_TEXT
  FROM {{DATABASE}}.{{KF}}.KF_CATALOG;

-- Document search: BRD / FSD / governance standard
CREATE OR REPLACE CORTEX SEARCH SERVICE {{DOCS_SEARCH}}
  ON SEARCH_TEXT
  ATTRIBUTES DOC_TITLE, DOC_TYPE
  WAREHOUSE = {{WAREHOUSE}}
  TARGET_LAG = '1 day'
  COMMENT = 'AP project documents: business requirements, functional specification, governance standard'
AS
  SELECT CHUNK_ID, DOC_TITLE, DOC_TYPE, DOC_VERSION, DOC_STATUS, PAGE_NUMBER, FILE_NAME, SEARCH_TEXT
  FROM {{DATABASE}}.{{KF}}.KF_DOC_CHUNKS;
