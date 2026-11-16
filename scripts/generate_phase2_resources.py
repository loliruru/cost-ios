"""Freeze reviewed Android v10 storage definitions into iOS v1 resources (Android is read only)."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def trigger(name, table, timing, expression, message):
    # IS NOT 1 also rejects SQL NULL/unknown predicates rather than letting them escape validation.
    return (f"CREATE TRIGGER {name} BEFORE {timing} ON {table}\n"
            f"WHEN ({expression}) IS NOT 1\nBEGIN SELECT RAISE(ABORT, '{message}'); END;")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-root", type=Path, required=True)
    args = parser.parse_args()
    relative = "core/data/src/main/kotlin/com/chinokafuu/cost/core/data/database/CostDatabase.kt"
    raw = (args.android_root / relative).read_bytes()
    manifest = json.loads((ROOT / "docs/reference/android-audit-manifest.json").read_text(encoding="utf-8"))
    expected = next(item["sha256"] for item in manifest["files"] if item["path"] == relative)
    if hashlib.sha256(raw).hexdigest() != expected:
        raise SystemExit("Android integrity source changed; review before generating a frozen iOS migration")
    kotlin = raw.decode("utf-8")
    expressions = dict(re.findall(r'private const val (\w+) = """(.*?)"""', kotlin, re.S))
    expressions = {name: textwrap.dedent(value).strip() for name, value in expressions.items()}
    schema = json.loads((ROOT / "docs/reference/android-schema-v10.json").read_text(encoding="utf-8"))["database"]
    sql = ["-- Frozen iOS v1 schema, adapted from Android Room v10 definitions and runtime invariants.",
           f"-- Android CostDatabase.kt SHA-256: {expected}"]
    records = ["// Generated storage records. Domain and Feature must not depend on these GRDB types.",
               "import GRDB", ""]
    names = {"currencies": "CurrencyRecord", "categories": "CategoryRecord", "accounts": "AccountRecord",
             "tags": "TagRecord", "transactions": "TransactionRecord", "transaction_tags": "TransactionTagRecord",
             "visual_assets": "VisualAssetRecord", "fx_quotes": "FiatQuoteRecord", "quick_templates": "QuickTemplateRecord",
             "quick_template_tags": "QuickTemplateTagRecord", "recurring_rules": "RecurringRuleRecord",
             "recurring_rule_tags": "RecurringRuleTagRecord", "recurring_executions": "RecurringExecutionRecord",
             "crypto_price_quotes": "MarketQuoteRecord", "anomaly_feedback": "AnomalyFeedbackRecord",
             "restore_state": "RestoreStateRecord", "account_fund_openings": "AccountFundOpeningRecord",
             "account_transfers": "AccountTransferRecord"}
    for entity in schema["entities"]:
        table = entity["tableName"]
        sql.append(entity["createSql"].replace("${TABLE_NAME}", table) + ";")
        for index in entity.get("indices", []):
            sql.append(index["createSql"].replace("${TABLE_NAME}", table) + ";")
        records += [f"struct {names[table]}: Codable, FetchableRecord, PersistableRecord, Sendable {{",
                    f'    static let databaseTableName = "{table}"']
        type_checks = []
        for field in entity["fields"]:
            column = field["columnName"]
            swift_type, sql_type = ("Int64", "integer") if field["affinity"] == "INTEGER" else ("String", "text")
            not_null = field.get("notNull", False)
            records.append(f"    var {column}: {swift_type}{'' if not_null else '?'}")
            type_checks.append(f"typeof(NEW.{column}) IN ('{sql_type}'{'' if not_null else ", 'null'"})")
        records += ["}", ""]
        for timing in ("INSERT", "UPDATE"):
            sql.append(trigger(f"{table}_types_{timing.lower()}", table, timing,
                               " AND ".join(type_checks), "Invalid storage value type"))
    sql.append("CREATE UNIQUE INDEX index_accounts_single_default ON accounts(is_default) WHERE is_default = 1 AND is_archived = 0;")
    currency_check = ("NEW.code <> '' AND NEW.asset_type IN ('FIAT','CRYPTO') AND NEW.display_name <> '' "
                      "AND NEW.symbol <> '' AND NEW.default_scale BETWEEN 0 AND 18 "
                      "AND NEW.is_enabled IN (0,1) AND NEW.metadata_version > 0")
    checks = {"currencies": currency_check, "categories": expressions["CATEGORY_VALID_EXPRESSION"],
              "accounts": expressions["ACCOUNT_VALID_EXPRESSION"], "tags": expressions["TAG_VALID_EXPRESSION"],
              "transactions": expressions["TRANSACTION_VALID_EXPRESSION"],
              "visual_assets": expressions["VISUAL_ASSET_VALID_EXPRESSION"],
              "fx_quotes": expressions["FX_QUOTE_VALID_EXPRESSION"],
              "quick_templates": expressions["QUICK_TEMPLATE_VALID_EXPRESSION"],
              "recurring_rules": expressions["RECURRING_RULE_VALID_EXPRESSION"],
              "recurring_executions": expressions["RECURRING_EXECUTION_VALID_EXPRESSION"]}
    for table, expression in checks.items():
        for timing in ("INSERT", "UPDATE"):
            value = expression
            if table == "categories" and timing == "UPDATE":
                value += (" AND NOT (NEW.parent_id IS NOT NULL AND EXISTS (SELECT 1 FROM categories child WHERE child.parent_id = NEW.id))"
                          " AND NOT EXISTS (SELECT 1 FROM categories child WHERE child.parent_id = NEW.id AND child.transaction_type <> NEW.transaction_type)")
            sql.append(trigger(f"{table}_validate_{timing.lower()}", table, timing, value, "Invalid " + table))
    crypto = re.search(r'validationTrigger\("crypto_transaction_.*?, "transactions", """(.*?)"""\.trimIndent', kotlin, re.S)
    if crypto is None:
        raise SystemExit("Crypto integrity definition missing")
    for timing in ("INSERT", "UPDATE"):
        sql.append(trigger(f"crypto_transaction_{timing.lower()}", "transactions", timing,
                           textwrap.dedent(crypto.group(1)).strip(), "Invalid crypto valuation snapshot"))
    # These two tables are guarded by Android domain mappers; retain their scalar invariants in SQLite too.
    opening = ("NEW.id <> '' AND NEW.account_id <> '' AND NEW.revision >= 0 "
               "AND NEW.kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.scale BETWEEN 0 AND 18 "
               "AND ((NEW.enabled = 1 AND NEW.amount_minor IS NOT NULL AND NEW.amount_minor >= 0) "
               "OR (NEW.enabled = 0 AND NEW.amount_minor IS NULL))")
    for timing in ("INSERT", "UPDATE"):
        sql.append(trigger(f"fund_openings_validate_{timing.lower()}", "account_fund_openings", timing, opening, "Invalid funds opening"))
    transfer = ("NEW.id <> '' AND NEW.request_key <> '' AND NEW.from_account_id <> '' AND NEW.to_account_id <> '' "
                "AND NEW.from_account_id <> NEW.to_account_id AND NEW.scale BETWEEN 0 AND 18 AND NEW.principal_minor >= 0 "
                "AND NEW.from_kind IN ('AVAILABLE','INVESTMENT_COST') AND NEW.to_kind IN ('AVAILABLE','INVESTMENT_COST') "
                "AND (NEW.principal_minor > 0 OR NEW.profit_minor > 0) "
                "AND CASE WHEN NEW.profit_minor >= 0 THEN NEW.principal_minor <= 9223372036854775807 - NEW.profit_minor "
                "WHEN NEW.profit_minor = -9223372036854775808 THEN 0 ELSE NEW.principal_minor >= -NEW.profit_minor END "
                "AND (NEW.profit_minor = 0 OR (NEW.from_kind = 'INVESTMENT_COST' AND NEW.to_kind = 'AVAILABLE')) "
                "AND ((NEW.profit_minor = 0 AND NEW.profit_category_id IS NULL) OR "
                "(NEW.profit_minor <> 0 AND NEW.profit_category_id IS NOT NULL AND NEW.profit_category_id <> '')) "
                "AND NEW.zone_id <> '' AND NEW.updated_at >= NEW.created_at "
                "AND (NEW.deleted_at IS NULL OR NEW.deleted_at BETWEEN NEW.created_at AND NEW.updated_at)")
    for timing in ("INSERT", "UPDATE"):
        sql.append(trigger(f"fund_transfers_validate_{timing.lower()}", "account_transfers", timing, transfer, "Invalid account transfer"))
    sql += ["PRAGMA application_id = 1129272137;", "PRAGMA user_version = 1;"]
    destination = ROOT / "Cost/Resources/Database"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "CostSchemaV1.sql").write_text("\n\n".join(sql) + "\n", encoding="utf-8", newline="\n")
    (ROOT / "Cost/Core/Data/DatabaseRecords.swift").write_text("\n".join(records), encoding="utf-8", newline="\n")
    seed_relative = "core/data/src/main/kotlin/com/chinokafuu/cost/core/data/database/CurrencySeedData.kt"
    seed_source = (args.android_root / seed_relative).read_text(encoding="utf-8")
    currencies = []
    for kind, code, name, symbol, scale, order in re.findall(r'(fiat|crypto)\("([A-Z]+)", "([^"]+)", "([^"]+)", (\d+), (\d+)\)', seed_source):
        currencies.append(dict(code=code, asset_type="FIAT" if kind == "fiat" else "CRYPTO", display_name=name,
                               symbol=symbol, default_scale=int(scale), is_enabled=int(kind == "fiat"),
                               sort_order=int(order), metadata_version=1))
    if len(currencies) != 15:
        raise SystemExit("Reviewed currency seed count changed")
    visual = dict(icon_key="tag", color_key="neutral", icon_source="BUILT_IN", emoji=None, icon_asset_id=None,
                  background_asset_id=None, background_focus="CENTER", sort_order=0, is_archived=0,
                  created_at_epoch_millis=0, updated_at_epoch_millis=0)
    seed = {"currencies": currencies,
            "categories": [dict(visual, id="seed-expense-other", name="其他支出", transaction_type="EXPENSE", parent_id=None),
                           dict(visual, id="seed-income-other", name="其他收入", transaction_type="INCOME", parent_id=None)],
            "accounts": [dict(visual, id="seed-default-account", name="默认账户", currency_code="CNY", icon_key="wallet", is_default=1)]}
    (destination / "CostSeedV1.json").write_text(json.dumps(seed, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated 18 storage records/tables, {sum(s.startswith('CREATE TRIGGER') for s in sql)} guards and nonpersonal seed resources")


if __name__ == "__main__":
    main()
