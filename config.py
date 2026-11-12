# =====================================================================
# config.py: every name used by the POC, in ONE place.
# The SQL files use these as {{NAME}}. Change a value here and run again.
#
# Synthetic data only: SAP-like names, generated data and generated documents.
# =====================================================================

# --- Where everything is built -----------------------------------------
DATABASE = "POC_AP_KNOWLEDGE_FABRIC"     # any name you like
WAREHOUSE = "POC_AP_KF_WH"               # X-Small, auto-suspend 60 s
ADMIN_ROLE = "ACCOUNTADMIN"              # role that builds the POC (needs CREATE DATABASE/ROLE, Cortex)

# --- Schemas: one per layer of the AP model, plus governance and the knowledge layer
LANDING = "SAP_LANDING"          # SAP-like tables as landed by the replication tool
EDW = "EDW"                      # enterprise data warehouse: global AP fact + master dimensions
DATAMART = "AP_DATAMART"         # AP datamart: aging logic lives here
REPORTING = "AP_REPORTING"       # reporting views for BI (no business logic after the datamart)
GOVERNANCE = "GOVERNANCE"        # tags and masking policies
KF = "KNOWLEDGE_FABRIC"          # metadata catalog, documents, search, semantic view, agent

# --- Roles (two personas from the requirement) ---------------------------
POWER_ROLE = "AP_KF_POWER_USER"          # data engineers / power users: see unmasked values
BUSINESS_ROLE = "AP_KF_BUSINESS_USER"    # new users: reporting layer + knowledge layer, values masked

# --- AI objects -----------------------------------------------------------
DOCS_STAGE = "KF_DOCUMENTS"                  # synthetic BRD / FSD / governance PDFs
CATALOG_SEARCH = "KF_CATALOG_SEARCH_SVC"     # Cortex Search over objects, columns, lineage, glossary
DOCS_SEARCH = "KF_DOCS_SEARCH_SVC"           # Cortex Search over the parsed documents
SEMANTIC_VIEW = "KF_METADATA_MODEL"          # semantic view over the metadata tables (Cortex Analyst)
AGENT = "AP_KNOWLEDGE_COWORKER"              # Cortex Agent shown in Snowflake Intelligence
AI_MODEL = "claude-sonnet-4-5"               # AI_COMPLETE model for suggested descriptions
CHUNK_SIZE = "1200"                          # characters per document chunk
CHUNK_OVERLAP = "150"

# --- Synthetic data volume -------------------------------------------------
VENDOR_COUNT = "300"
INVOICE_COUNT = "6000"

# --- Refresh schedule (tasks are created SUSPENDED; resume only if wanted) --
EDW_SCHEDULE = "USING CRON 0 2 * * * UTC"    # EDW load daily 02:00 UTC; datamart runs right after it
