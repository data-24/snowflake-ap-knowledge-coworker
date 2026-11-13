# =====================================================================
# run.py: builds the AP Knowledge Fabric POC in order.
#   1. reads each .sql file in sql/
#   2. replaces every {{NAME}} with the value from config.py
#   3. runs each statement in Snowflake
#
# In a Snowsight Workspace notebook (same folder):
#     import run
#     run.run()            # build everything (about 5-10 minutes)
#     run.check()          # what was built
#     run.demo_masking()   # same query as power user and as business user
# =====================================================================
import glob
import os
import re

import config

FOLDER = os.path.dirname(os.path.abspath(__file__))

SQL_FILES = [
    "00_cortex_access.sql",          # optional (ACCOUNTADMIN): cross-region models
    "01_setup.sql",
    "02_landing_sap.sql",
    "03_edw.sql",
    "04_datamart.sql",
    "05_reporting_and_refresh.sql",
    "06_governance.sql",
    "06b_classification.sql",        # optional: Snowflake sensitive-data classification
    "06c_keys.sql",                  # primary / business keys (warnings only on re-runs)
    "07_knowledge_fabric.sql",
    "08_documents_and_search.sql",
    "09_semantic_view.sql",
    "10_agent.sql",
    "11_evaluation.sql",
    "12_access.sql",                 # warnings only
    "13_snowflake_intelligence.sql", # optional
]
# In these files a failing statement is reported and skipped instead of stopping the build
SOFT_FILES = {"00_cortex_access.sql", "06b_classification.sql", "06c_keys.sql", "12_access.sql", "13_snowflake_intelligence.sql"}


def get_session():
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        # Outside Snowflake: uses the default connection in ~/.snowflake/connections.toml
        from snowflake.snowpark import Session
        return Session.builder.getOrCreate()


session = get_session()


def fill_names(sql):
    """{{DATABASE}} -> POC_AP_KNOWLEDGE_FABRIC, using config.py"""
    return re.sub(r"\{\{(\w+)\}\}", lambda m: str(getattr(config, m.group(1))), sql)


def split_statements(sql):
    """Split on ';' but not inside quotes, $$ blocks or -- comments."""
    statements, current, i = [], "", 0
    in_quote = in_dollar = False
    while i < len(sql):
        if not in_quote and sql.startswith("$$", i):
            in_dollar = not in_dollar
            current += "$$"
            i += 2
            continue
        ch = sql[i]
        if not in_quote and not in_dollar and sql.startswith("--", i):
            end = sql.find("\n", i)
            i = len(sql) if end == -1 else end
            continue
        if ch == "'" and not in_dollar:
            in_quote = not in_quote
        if ch == ";" and not in_quote and not in_dollar:
            if current.strip():
                statements.append(current.strip())
            current = ""
        else:
            current += ch
        i += 1
    if current.strip():
        statements.append(current.strip())
    return statements


def upload_documents():
    """Put the synthetic PDFs from docs/ on the documents stage."""
    stage = f"{config.DATABASE}.{config.KF}.{config.DOCS_STAGE}"
    session.sql(f"CREATE STAGE IF NOT EXISTS {stage} ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE') "
                f"DIRECTORY = (ENABLE = TRUE)").collect()
    files = sorted(glob.glob(os.path.join(FOLDER, "docs", "*.pdf")))
    for path in files:
        session.file.put(path, f"@{stage}", auto_compress=False, overwrite=True)
    session.sql(f"ALTER STAGE {stage} REFRESH").collect()
    on_stage = session.sql(f"SELECT COUNT(*) AS N FROM DIRECTORY(@{stage}) WHERE RELATIVE_PATH ILIKE '%.pdf'").collect()[0]["N"]
    print(f"📄 {len(files)} PDFs uploaded, {on_stage} on the stage")
    if on_stage == 0:
        raise RuntimeError("No PDFs on the stage. Upload the 4 files in docs/ in Snowsight: Catalog -> "
                           f"{config.DATABASE} -> {config.KF} -> Stages -> {config.DOCS_STAGE} -> + Files, then run again "
                           "from 08: run.run(run.SQL_FILES[10:])")


def run_statement(file, statement):
    try:
        session.sql(statement).collect()
        return True
    except Exception as error:
        # Semantic view: if the verified queries are rejected, create it without them and say so
        if "AI_VERIFIED_QUERIES" in statement:
            print(f"⚠️  {file}: verified queries rejected ({str(error)[:200]}). Creating the semantic view without them; "
                  "add them in the semantic view editor (Verified queries).")
            session.sql(statement[:statement.index("AI_VERIFIED_QUERIES")]).collect()
            return True
        if file in SOFT_FILES:
            print(f"⚠️  {file}: skipped one statement ({str(error)[:160]})\n    {statement[:120]}")
            return False
        print(f"❌ {file} failed on:\n{statement[:600]}\n\n{error}")
        raise


def run(files=SQL_FILES):
    """Build everything. To run just some files: run(["09_semantic_view.sql", "10_agent.sql"])"""
    session.sql(f"USE ROLE {config.ADMIN_ROLE}").collect()
    for file in files:
        if file.startswith("08"):
            upload_documents()
        sql = fill_names(open(os.path.join(FOLDER, "sql", file)).read())
        ok = all([run_statement(file, s) for s in split_statements(sql)])
        print(f"{'✅' if ok else '🟡'} {file}")
        if file.startswith("07"):
            print("   " + session.sql(f"SELECT COUNT(*) AS N FROM {config.DATABASE}.{config.KF}.KF_COLUMNS")
                  .collect()[0]["N"].__str__() + " columns catalogued")
    print("\nDone. Next: run.check(), then open AI & ML -> Agents (or Snowflake Intelligence).")


def refresh(suggest_descriptions=False):
    """Re-read all Snowflake metadata into the Knowledge Fabric (after any change to the model)."""
    result = session.sql(f"CALL {config.DATABASE}.{config.KF}.REFRESH_KNOWLEDGE_FABRIC({suggest_descriptions})").collect()
    print(result[0][0])


def check():
    """One row per component with its count."""
    db, kf = config.DATABASE, f"{config.DATABASE}.{config.KF}"
    return session.sql(f"""
        SELECT 'Landing: SAP_BSEG rows' AS ITEM, COUNT(*) AS N FROM {db}.{config.LANDING}.SAP_BSEG
        UNION ALL SELECT 'EDW: AP fact rows (vendor lines)', COUNT(*) FROM {db}.{config.EDW}.FACT_ACCOUNTS_PAYABLE_GLOBAL
        UNION ALL SELECT 'Datamart: open items', COUNT(*) FROM {db}.{config.DATAMART}.DM_AP_OPEN_ITEMS
        UNION ALL SELECT 'Datamart: aging buckets used', COUNT(DISTINCT AGING_BUCKET) FROM {db}.{config.DATAMART}.DM_AP_OPEN_ITEMS
        UNION ALL SELECT 'KF: objects', COUNT(*) FROM {kf}.KF_OBJECTS
        UNION ALL SELECT 'KF: columns', COUNT(*) FROM {kf}.KF_COLUMNS
        UNION ALL SELECT 'KF: masked columns (direct + inherited)', COUNT_IF(IS_MASKED) FROM {kf}.KF_COLUMNS
        UNION ALL SELECT 'KF: columns without description', COUNT_IF(NOT HAS_DESCRIPTION) FROM {kf}.KF_COLUMNS
        UNION ALL SELECT 'KF: AI description drafts', COUNT(*) FROM {kf}.KF_DESCRIPTION_SUGGESTIONS
        UNION ALL SELECT 'KF: objects with tags read', COUNT(DATA_DOMAIN) FROM {kf}.KF_OBJECTS
        UNION ALL SELECT 'KF: lineage steps (mapping sheet)', COUNT(*) FROM {kf}.KF_LINEAGE_PATHS
        UNION ALL SELECT 'KF: Snowflake lineage rows (may lag hours)', COUNT(*) FROM {kf}.KF_SYSTEM_LINEAGE
        UNION ALL SELECT 'KF: refresh jobs', COUNT(*) FROM {kf}.KF_REFRESH_SCHEDULE
        UNION ALL SELECT 'KF: impact rows (downstream)', COUNT(*) FROM {kf}.KF_IMPACT
        UNION ALL SELECT 'KF: requirements', COUNT(*) FROM {kf}.KF_REQUIREMENTS
        UNION ALL SELECT 'KF: requirement trace rows', COUNT(*) FROM {kf}.KF_REQUIREMENT_TRACE
        UNION ALL SELECT 'KF: mapping changes', COUNT(*) FROM {kf}.KF_MAPPING_CHANGE_LOG
        UNION ALL SELECT 'KF: reporting view cards', COUNT(*) FROM {kf}.KF_REPORTING_VIEWS
        UNION ALL SELECT 'KF: columns with a key role', COUNT(KEY_ROLE) FROM {kf}.KF_COLUMNS
        UNION ALL SELECT 'KF: SAP T-code mappings (phase 2 preview)', COUNT(*) FROM {kf}.KF_SAP_TCODE_MAP
        UNION ALL SELECT 'KF: SAP fields in reuse assessment', COUNT(*) FROM {kf}.KF_REUSE_ASSESSMENT
        UNION ALL SELECT 'KF: catalog entries (search)', COUNT(*) FROM {kf}.KF_CATALOG
        UNION ALL SELECT 'Docs: pages parsed', COUNT(*) FROM {kf}.KF_DOC_PAGES
        UNION ALL SELECT 'Docs: chunks', COUNT(*) FROM {kf}.KF_DOC_CHUNKS
    """).to_pandas()


def demo_masking():
    """The same reporting query as power user and as business user."""
    sql = (f"SELECT VENDOR_ID, VENDOR_NAME, VENDOR_COUNTRY, TAX_ID, BANK_ACCOUNT "
           f"FROM {config.DATABASE}.{config.REPORTING}.VW_AP_VENDOR ORDER BY VENDOR_ID LIMIT 3")
    out = {}
    for role in (config.POWER_ROLE, config.BUSINESS_ROLE):
        session.sql(f"USE ROLE {role}").collect()
        session.sql(f"USE WAREHOUSE {config.WAREHOUSE}").collect()
        out[role] = session.sql(sql).to_pandas()
    session.sql(f"USE ROLE {config.ADMIN_ROLE}").collect()
    for role, df in out.items():
        print(f"\n--- {role} ---\n{df.to_string(index=False)}")
    return out


def impact_preview(changed_column="LAND1", changed_object="SAP_LFA1"):
    """Everything downstream of a column: columns, dashboards, reports, extracts."""
    return session.sql(f"""
        SELECT DISTANCE, AFFECTED_LAYER, AFFECTED_TYPE, AFFECTED_OBJECT, AFFECTED_COLUMN, OWNER
        FROM {config.DATABASE}.{config.KF}.KF_IMPACT
        WHERE CHANGED_COLUMN = '{changed_column}' AND CHANGED_OBJECT ILIKE '%{changed_object}'
        ORDER BY DISTANCE, AFFECTED_OBJECT""").to_pandas()


def view_card(view="VW_AP_OPEN_ITEMS"):
    """The data dictionary card of one reporting view, one attribute per row."""
    df = session.sql(f"SELECT * FROM {config.DATABASE}.{config.KF}.KF_REPORTING_VIEWS WHERE VIEW_NAME = '{view}'").to_pandas()
    return df.T.rename(columns={0: view}) if not df.empty else df


def lineage_preview(report_column="VENDOR_COUNTRY", report_object="VW_AP_OPEN_ITEMS"):
    """Hop-by-hop lineage of a reporting field, straight from the Knowledge Fabric."""
    return session.sql(f"""
        SELECT HOP, TARGET_OBJECT || '.' || TARGET_COLUMN AS TARGET, SOURCE_OBJECT || '.' || SOURCE_COLUMN AS SOURCE,
               MAPPING_TYPE, TRANSFORMATION_RULE, IS_ORIGIN
        FROM {config.DATABASE}.{config.KF}.KF_LINEAGE_PATHS
        WHERE REPORT_COLUMN = '{report_column}' AND REPORT_OBJECT ILIKE '%{report_object}'
        ORDER BY HOP, SOURCE""").to_pandas()
