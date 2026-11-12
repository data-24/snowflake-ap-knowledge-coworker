"""
Creates the three SYNTHETIC project documents used by the POC (BRD, FSD, governance standard).
They play the role of the "supplementary" documents next to Snowflake metadata.
Run:  python tools/make_documents.py   ->  docs/*.pdf
"""
import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
styles = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=styles["Heading1"], fontSize=16, spaceAfter=6)
H2 = ParagraphStyle("H2", parent=styles["Heading2"], fontSize=12.5, spaceBefore=10, spaceAfter=4)
H3 = ParagraphStyle("H3", parent=styles["Heading3"], fontSize=11, spaceBefore=6, spaceAfter=2)
P = ParagraphStyle("P", parent=styles["BodyText"], fontSize=9.8, leading=13.5, spaceAfter=5)
SMALL = ParagraphStyle("S", parent=P, fontSize=8.5, textColor=colors.HexColor("#555555"))
CELL = ParagraphStyle("C", parent=P, fontSize=8.6, leading=11, spaceAfter=0)


def table(rows, widths):
    data = [[Paragraph(str(c), CELL) for c in r] for r in rows]
    t = Table(data, colWidths=[w * cm for w in widths], repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EEF5")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#B0B8C4")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.HexColor("#777777"))
    canvas.drawString(2 * cm, 1.2 * cm, "SYNTHETIC DOCUMENT - created for a proof of concept. Not a real company document.")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"{doc.title} - page {doc.page}")
    canvas.restoreState()


def build(file_name, title, story):
    doc = SimpleDocTemplate(os.path.join(OUT, file_name), pagesize=A4, title=title,
                            leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.8 * cm, bottomMargin=2 * cm)
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print("created", file_name)


def header(title, meta):
    return [Paragraph(title, H1), Paragraph(meta, SMALL), Spacer(1, 6)]


# ---------------------------------------------------------------------
# 1. Business Requirements Document: AP Aging
# ---------------------------------------------------------------------
brd = header("Business Requirements Document: Accounts Payable Aging Reporting",
             "Document ID BRD-AP-AGING · Version 1.2 · Status: Approved · Approved 14 March 2025 by the AP Finance Data Owner (role) · "
             "Prepared by the AP Data Steward (role)")
brd += [
    Paragraph("1. Purpose and scope", H2),
    Paragraph("This document defines the business requirements for Accounts Payable (AP) aging reporting across all company codes. "
              "AP aging shows how much the organisation owes its vendors and how late those amounts are, so that the AP team, "
              "treasury and the controllers can prioritise payments, manage cash and follow up on disputed invoices.", P),
    Paragraph("In scope: open vendor invoices and credit memos of all company codes, aging by days past due, amounts in local "
              "currency and in USD, vendor and one-time vendor attributes. Out of scope: customer (receivables) aging, parked "
              "(not yet posted) documents and cash forecasting.", P),
    Paragraph("2. Business context", H2),
    Paragraph("Vendor invoices are posted in the ERP. Every invoice creates a vendor line item (account type K) that stays "
              "<b>open</b> until it is paid or otherwise cleared. Aging is calculated on open items only. The reporting "
              "dashboards read the AP reporting views; all business rules are applied in the AP datamart so that every "
              "dashboard shows the same numbers.", P),
    Paragraph("3. Requirements", H2),
    Paragraph("3.1 Definitions", H3),
    table([["Term", "Definition"],
           ["Open item", "A vendor line item without a clearing date (it has not been paid or cleared)."],
           ["Net due date", "Baseline date plus the payment term days of the invoice. The baseline date is normally the invoice "
                            "(document) date."],
           ["As-of date", "The date on which aging is measured. For the daily datamart it is the date of the load."],
           ["Days past due", "As-of date minus net due date, in days. Zero or a negative number means the item is not yet due."]],
          [3.5, 13.5]),
    Spacer(1, 6),
    Paragraph("3.2 Aging buckets (official, version 1.2)", H3),
    Paragraph("Every open item is assigned to exactly one of the following six buckets, based on its days past due:", P),
    table([["Order", "Bucket", "Days past due", "Meaning"],
           ["1", "Not yet due", "0 or less", "Due today or in the future"],
           ["2", "1-30", "1 to 30", "Up to one month late"],
           ["3", "31-60", "31 to 60", "One to two months late"],
           ["4", "61-90", "61 to 90", "Two to three months late"],
           ["5", "91-180", "91 to 180", "Three to six months late"],
           ["6", "Over 180", "181 or more", "More than six months late; review for dispute or write-off"]],
          [1.4, 2.6, 3, 10]),
    Spacer(1, 6),
    Paragraph("Note: version 1.0 of this document used four buckets (0-30, 31-60, 61-90 and 90+) and did not separate items that "
              "are not yet due. Those buckets are <b>superseded</b> and must not be used.", P),
    Paragraph("3.3 Currency", H3),
    Paragraph("Amounts are shown in the local currency of the company code and converted to US dollars with the company code "
              "exchange rate maintained in the EDW. Credit memos reduce the open amount (they are negative).", P),
    Paragraph("3.4 Inclusions and exclusions", H3),
    Paragraph("Cleared items are excluded. Items with a payment block (for example disputed invoices) are included and flagged. "
              "Invoices posted to the one-time vendor account are included; for these the vendor name and vendor country are "
              "taken from the payee details captured on the invoice, not from the vendor master.", P),
    Paragraph("3.5 Data freshness", H3),
    Paragraph("The AP datamart must be refreshed once a day and be available by 04:00 UTC. The reporting views add no logic and "
              "therefore always show the latest datamart load. Intraday changes are visible the next day.", P),
    Paragraph("3.6 Requirement list", H3),
    table([["ID", "Requirement", "Priority"],
           ["AP-R01", "Show every open vendor item of all company codes in one place.", "Must"],
           ["AP-R02", "Calculate days past due from the net due date (baseline date + payment term days), not from the "
                      "invoice date.", "Must"],
           ["AP-R03", "Assign every open item to exactly one of the six approved aging buckets.", "Must"],
           ["AP-R04", "Show open amounts in company code currency and in USD using the company code exchange rate.", "Must"],
           ["AP-R05", "Include credit memos as negative open amounts.", "Must"],
           ["AP-R06", "Include and flag items with a payment block.", "Should"],
           ["AP-R07", "For one-time vendors use the payee name and country captured on the invoice.", "Must"],
           ["AP-R08", "Apply the vendor payment terms of the company code to calculate the due date.", "Must"],
           ["AP-R09", "Refresh the AP datamart daily; available by 04:00 UTC.", "Must"],
           ["AP-R10", "Mask tax numbers, bank accounts and one-time payee names for business users.", "Must"],
           ["AP-R11", "Summarise open amount and item count by company code, vendor country and aging bucket.", "Must"],
           ["AP-R12", "Show the overdue amount, possibly excluding blocked items (see open question 2).", "Could"]],
          [1.8, 13, 2.2]),
    Paragraph("4. Users and access", H2),
    Paragraph("AP business users may see vendor names, countries, amounts and aging, but vendor tax numbers, bank account numbers "
              "and the names of one-time payees (who can be private persons) must be masked. AP power users and data engineers "
              "may see the full values. See the AP Data Governance and Access Standard.", P),
    Paragraph("5. Open questions", H2),
    table([["#", "Question", "Status"],
           ["1", "Should parked documents be shown as a separate bucket?", "Deferred to a later release"],
           ["2", "Should the overdue amount exclude items with a payment block?", "Open: definition in draft, awaiting the "
                                                                                 "AP Finance Data Owner"]],
          [0.8, 11, 5.2]),
    Paragraph("6. Change history", H2),
    table([["Version", "Date", "Change"],
           ["1.0", "June 2024", "First version: four buckets (0-30, 31-60, 61-90, 90+)."],
           ["1.1", "November 2024", "Added the bucket Not yet due; days past due defined from the net due date."],
           ["1.2", "March 2025", "Split 90+ into 91-180 and Over 180 (six buckets). Approved by the AP Finance Data Owner."]],
          [2, 3, 12]),
]

# ---------------------------------------------------------------------
# 2. Functional Specification: AP Datamart
# ---------------------------------------------------------------------
fsd = header("Functional Specification: Accounts Payable Datamart",
             "Document ID FSD-AP-DM · Version 1.0 · Status: Approved · Owner: AP Data Steward (role)")
fsd += [
    Paragraph("1. Overview", H2),
    Paragraph("The AP datamart turns raw ERP accounting data into reporting-ready AP open items and aging. Data flows through four "
              "layers: <b>SAP landing</b> (tables replicated from the ERP by the replication tool) &rarr; <b>EDW</b> (global AP "
              "fact and master dimensions) &rarr; <b>AP datamart</b> (open items, aging, summary) &rarr; <b>AP reporting views</b> "
              "(read by the BI tool). All AP business logic lives in the datamart; the reporting views only select and rename.", P),
    Paragraph("2. Source tables (SAP landing)", H2),
    table([["Table", "SAP meaning", "Used for"],
           ["SAP_BKPF", "Accounting document header", "Document type, document and posting date, currency, invoice reference"],
           ["SAP_BSEG", "Accounting document line items", "Vendor lines (account type K): amount, debit/credit, baseline date, "
                                                          "payment terms, clearing date, payment block"],
           ["SAP_BSEC", "One-time vendor data per document line", "Payee name, country, city and tax number of invoices posted "
                                                                   "to the one-time vendor account"],
           ["SAP_LFA1", "Vendor master, general data", "Vendor name, country, city, account group, tax number"],
           ["SAP_LFB1", "Vendor master, company code data", "Payment terms, reconciliation account"],
           ["SAP_LFBK", "Vendor bank details", "Bank country and bank account number"],
           ["SAP_T001", "Company codes", "Company name, country and local currency"],
           ["SAP_T005T", "Country names", "Translating country keys into country names"]],
          [2.6, 4.6, 9.8]),
    Paragraph("3. EDW objects", H2),
    table([["Object", "Grain", "Built from"],
           ["FACT_ACCOUNTS_PAYABLE_GLOBAL", "One row per vendor line item, all company codes", "SAP_BSEG (account type K) + "
                                                                                          "SAP_BKPF + SAP_BSEC + SAP_T005T"],
           ["DIM_VENDOR", "One row per vendor", "SAP_LFA1 + SAP_T005T + SAP_LFBK"],
           ["DIM_COMPANY_CODE", "One row per company code", "SAP_T001 + SAP_T005T, plus the USD exchange rate"]],
          [5.6, 5.4, 6]),
    Paragraph("4. Datamart objects", H2),
    table([["Object", "Grain", "Notes"],
           ["DM_AP_OPEN_ITEMS", "One row per open vendor line item", "Net due date, days past due, aging bucket, USD amount"],
           ["DM_AP_AGING_SUMMARY", "As-of date x company code x vendor country x bucket", "Item count and open amount in USD"],
           ["DM_AP_VENDOR", "One row per vendor", "Vendor list for reporting"],
           ["AP_AGING_BUCKETS", "One row per bucket", "Reference table holding the six approved buckets (BRD v1.2)"]],
          [4.6, 6, 6.4]),
    Paragraph("Reporting views: VW_AP_OPEN_ITEMS, VW_AP_AGING_SUMMARY and VW_AP_VENDOR, one per datamart table, with business "
              "column names (for example VENDOR_COUNTRY_NAME is exposed as VENDOR_COUNTRY and AMOUNT_USD as OPEN_AMOUNT_USD).", P),
    Paragraph("5. Field derivations", H2),
    Paragraph("5.1 Dates and payment terms", H3),
    Paragraph("NET_DUE_DATE = baseline date (BSEG.ZFBDT) + payment term days (BSEG.ZBD1T). IS_OPEN_ITEM is true when the clearing "
              "date (BSEG.AUGDT) is empty. Payment terms keys: N30, N45, N60, N90 = net 30/45/60/90 days, IMMD = due immediately. "
              "A payment block value of A (BSEG.ZLSPR) means the item is blocked for payment.", P),
    Paragraph("5.2 Vendor attributes and one-time vendors", H3),
    Paragraph("Regular vendors take their name and country from the vendor master (LFA1.NAME1 and LFA1.LAND1, the country key "
              "translated to a name with T005T). Invoices posted to the <b>one-time vendor account</b> (account group CPD) carry "
              "the real payee on the invoice in SAP_BSEC, joined on company code, document number, fiscal year and line item. "
              "Rule: <b>vendor country = BSEC.LAND1 for one-time vendors, otherwise LFA1.LAND1</b>. The same rule applies to the "
              "vendor name. In the EDW the payee values are stored in FACT_ACCOUNTS_PAYABLE_GLOBAL.ONE_TIME_VENDOR_COUNTRY_CODE / "
              "_NAME and ONE_TIME_VENDOR_NAME; the datamart picks the right value in DM_AP_OPEN_ITEMS.VENDOR_COUNTRY_NAME.", P),
    Paragraph("Clarification: an early draft referred to the one-time vendor data as part of BSEG. This is incorrect: the payee "
              "details are in BSEC; BSEG only holds the line item with the one-time vendor account number.", P),
    Paragraph("5.3 Amounts and currency", H3),
    Paragraph("AMOUNT_LOCAL = BSEG.DMBTR with the sign from the debit/credit indicator BSEG.SHKZG: credit (H) is positive "
              "(the amount is owed to the vendor), debit (S) is negative (credit memo). AMOUNT_USD = AMOUNT_LOCAL x the USD exchange "
              "rate of the company code, rounded to 2 decimals.", P),
    Paragraph("6. Join keys", H2),
    table([["From", "To", "Keys"],
           ["SAP_BSEG", "SAP_BKPF", "BUKRS, BELNR, GJAHR"],
           ["SAP_BSEG", "SAP_BSEC", "BUKRS, BELNR, GJAHR, BUZEI"],
           ["SAP_BSEG", "SAP_LFA1", "LIFNR"],
           ["SAP_LFA1", "SAP_LFB1 / SAP_LFBK", "LIFNR"],
           ["FACT_ACCOUNTS_PAYABLE_GLOBAL", "DIM_VENDOR / DIM_COMPANY_CODE", "VENDOR_ID / COMPANY_CODE"],
           ["DM_AP_OPEN_ITEMS", "AP_AGING_BUCKETS", "DAYS_PAST_DUE between MIN_DAYS and MAX_DAYS"]],
          [5.4, 5.6, 6]),
    Paragraph("7. Orchestration and refresh", H2),
    Paragraph("The landing tables are replicated continuously (about every 15 minutes). The EDW load (LOAD_EDW) runs daily at "
              "02:00 UTC. The datamart load (LOAD_AP_DATAMART) runs immediately after a successful EDW load, normally finishing "
              "around 02:15 UTC, well inside the 04:00 UTC availability target. If the EDW load fails, the datamart load does not "
              "run and the reporting views keep showing the previous day. The metadata catalog (Knowledge Fabric) is refreshed "
              "after the datamart load.", P),
    Paragraph("8. Data quality checks", H2),
    Paragraph("(1) The open amount in DM_AP_OPEN_ITEMS equals the open amount of the fact for the same as-of date. "
              "(2) Every open item has exactly one aging bucket. (3) No open item has an empty net due date. "
              "(4) Every company code has a USD exchange rate.", P),
]

# ---------------------------------------------------------------------
# 3. Data governance and access standard
# ---------------------------------------------------------------------
gov = header("AP Data Governance and Access Standard",
             "Document ID GOV-AP-01 · Version 1.1 · Status: Approved · Owner: AP Finance Data Owner (role)")
gov += [
    Paragraph("1. Purpose", H2),
    Paragraph("This standard sets out how AP data is classified, who may see what, who owns the definitions, and how metadata is "
              "maintained in Snowflake so that people and AI assistants can rely on it.", P),
    Paragraph("2. Sensitivity classes", H2),
    table([["Class", "Meaning", "Examples in AP"],
           ["Public", "May be shared outside the organisation", "None in AP"],
           ["Internal", "Default for business data", "Vendor names, countries, document numbers, aging buckets"],
           ["Confidential", "Financially sensitive", "Open amounts, invoice amounts"],
           ["Restricted", "Personal or banking data; always masked for business users", "Vendor tax numbers, vendor bank account "
                                                                                       "numbers, names of one-time payees"]],
          [2.6, 6, 8.4]),
    Paragraph("3. Masked fields", H2),
    Paragraph("Restricted fields are protected with Snowflake masking policies wherever they are stored: tax numbers "
              "(MASK_TAX_ID: last 4 characters visible), bank accounts (MASK_BANK_ACCOUNT: last 4 digits visible) and one-time "
              "payee names (MASK_PERSON_NAME, and the conditional policy MASK_ONE_TIME_PAYEE_NAME in the datamart, which masks the "
              "name only when the invoice belongs to a one-time vendor). Reporting views do not carry their own policies: they "
              "inherit the masking of the datamart columns they read.", P),
    Paragraph("4. Roles", H2),
    table([["Role", "Who", "Access"],
           ["AP_KF_POWER_USER", "AP power users, data engineers", "All layers; restricted fields unmasked"],
           ["AP_KF_BUSINESS_USER", "AP business users and new joiners", "Reporting views and the Knowledge Fabric; restricted "
                                                                         "fields masked"]],
          [4.2, 5, 7.8]),
    Paragraph("5. Ownership", H2),
    Paragraph("The AP Finance Data Owner (role) is accountable for the AP data product and approves business definitions. The AP "
              "Data Steward (role) maintains comments, tags, the glossary and the field mapping.", P),
    Paragraph("6. Definition approval", H2),
    Paragraph("New or changed business terms start as <b>Draft</b>. The steward reviews them, the owner approves them, and only "
              "then are they <b>Approved</b> in the glossary and treated as official. Descriptions drafted by AI for undocumented "
              "columns are suggestions only: they become Snowflake comments after steward approval.", P),
    Paragraph("7. Metadata standard", H2),
    Paragraph("Every table, view and column must have a comment in the form <i>Business name: description</i>. Every object "
              "carries the tags DATA_DOMAIN, DATA_PRODUCT, DATA_LAYER, SOURCE_SYSTEM, REFRESH_FREQUENCY, DATA_OWNER, DATA_STEWARD "
              "and CERTIFICATION, set at database or schema level where possible so that new objects inherit them. Restricted "
              "columns carry SENSITIVITY = Restricted and a masking policy.", P),
]

# ---------------------------------------------------------------------
# 4. AP process and EDW development standards
# ---------------------------------------------------------------------
std = header("AP Process Overview and EDW Development Standards",
             "Document ID STD-AP-EDW · Version 1.0 · Status: Approved · Owner: AP Data Steward (role)")
std += [
    Paragraph("1. Invoice-to-pay: level 2 process steps", H2),
    table([["Step", "What happens", "Data created"],
           ["1. Invoice receipt", "The vendor invoice is received and captured (scan or electronic invoice).", "Invoice image, header data"],
           ["2. Matching", "Three-way match of purchase order, goods receipt and invoice; price and quantity tolerances checked.",
            "Match result, exceptions"],
           ["3. Exception handling and approval", "Mismatches and non-PO invoices go to the budget owner for approval; "
                                                  "disputed invoices get a payment block.", "Approval record, payment block A"],
           ["4. Posting", "The approved invoice is posted: document type KR, a vendor line (account type K) on the "
                          "vendor's reconciliation account and expense lines on GL accounts.", "BKPF header, BSEG lines (BSEC for "
                                                                                                "one-time vendors)"],
           ["5. Payment run", "Due items without a payment block are paid; the payment clears the open item.",
            "Clearing date and clearing document on the vendor line"],
           ["6. Reconciliation", "AP sub-ledger is reconciled to the general ledger reconciliation account.", "Reconciliation report"]],
          [3.6, 8.4, 5]),
    Paragraph("How invoice-to-pay connects to the general ledger: at posting (step 4) the vendor line is posted to the vendor's "
              "<b>reconciliation account</b> (AP control account 0000211000), so the GL is updated at the same moment as the AP "
              "sub-ledger. Expense lines go to GL expense accounts (600000-699999) with a cost centre.", P),
    Paragraph("2. Period-end close (AP part)", H2),
    Paragraph("(1) Cut-off: invoices received up to the last working day are posted in the period. (2) Accruals for goods received "
              "but not yet invoiced. (3) AP sub-ledger to GL reconciliation on account 0000211000. (4) Aging review: items Over "
              "180 days are reviewed for dispute or write-off. (5) Controller review and period lock.", P),
    Paragraph("3. Chart of accounts (simplified, synthetic)", H2),
    Paragraph("A posting is identified by company code + GL account + cost centre. GL accounts: 1xxxxx assets, 2xxxxx liabilities "
              "(211000 = accounts payable control), 4xxxxx revenue, 6xxxxx expenses. Each company code uses the same operating "
              "chart of accounts.", P),
    Paragraph("4. EDW naming standards", H2),
    table([["Layer / object", "Standard", "Example"],
           ["Landing", "Prefix SAP_ + source table name, as replicated", "SAP_BSEG"],
           ["EDW fact / dimension", "Prefix FACT_ or DIM_, subject in business words", "FACT_ACCOUNTS_PAYABLE_GLOBAL, DIM_VENDOR"],
           ["Datamart", "Prefix DM_ + subject area + content; reference tables without prefix", "DM_AP_OPEN_ITEMS, AP_AGING_BUCKETS"],
           ["Reporting view", "Prefix VW_ + subject area", "VW_AP_OPEN_ITEMS"],
           ["Columns", "UPPER_CASE with underscores, no spaces, business words; flags start with IS_; amounts end with currency "
                       "(_USD, _LOCAL)", "IS_OPEN_ITEM, AMOUNT_USD"],
           ["Tasks / procedures", "TASK_LOAD_ / LOAD_ + target", "TASK_LOAD_EDW, LOAD_AP_DATAMART"],
           ["Metadata", "Comment 'Business name: description' on every table, view and column; standard tags (see GOV-AP-01)", "-"]],
          [3.8, 8.2, 5]),
    Paragraph("5. Change and release process (review steps)", H2),
    Paragraph("Every change to a mapping or object follows four gates: <b>Gate 1 design review</b> (steward checks the mapping "
              "sheet against the requirement), <b>pull request review</b> (a second engineer reviews the code), <b>Gate 2 test "
              "sign-off</b> (data quality checks and user acceptance test signed off by the steward), <b>Gate 3 release "
              "approval</b> (data owner approves the release). After deployment the mapping change log is updated and the "
              "Knowledge Fabric is refreshed.", P),
    Paragraph("6. Worked example: adding a field to a reporting view", H2),
    Paragraph("Request: show VENDOR_CITY in VW_AP_OPEN_ITEMS. (1) Find the source: vendor master SAP_LFA1.ORT01 for regular "
              "vendors, SAP_BSEC.ORT01 for one-time vendors, the same pattern as vendor country. (2) Add the mapping rows "
              "(landing -> EDW -> datamart -> reporting) to the mapping sheet with the rule. (3) Add the column to DIM_VENDOR / "
              "the fact, DM_AP_OPEN_ITEMS and the view, with comments. (4) Pass the gates above. (5) Record the change in the "
              "mapping change log and refresh the Knowledge Fabric.", P),
    Paragraph("7. Systems involved in AP reporting", H2),
    Paragraph("ERP (SAP ECC, synthetic) &rarr; replication tool (near real-time) &rarr; Snowflake (landing, EDW, AP datamart, "
              "reporting views) &rarr; BI tool (AP Aging Dashboard, AP Open Items Worklist, Vendor Master Audit Report) and a "
              "weekly secure file transfer extract to treasury.", P),
]

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    build("BRD_AP_Aging_v1.2.pdf", "BRD AP Aging v1.2", brd)
    build("FSD_AP_Datamart_v1.0.pdf", "FSD AP Datamart v1.0", fsd)
    build("AP_Data_Governance_Standard_v1.1.pdf", "AP Data Governance Standard v1.1", gov)
    build("AP_Process_and_EDW_Standards_v1.0.pdf", "AP Process and EDW Standards v1.0", std)
