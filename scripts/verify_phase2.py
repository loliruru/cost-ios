"""Validate the actual bundled SQL, seed and layer boundaries without a Swift toolchain."""

import json
from pathlib import Path
import re
import sqlite3

ROOT = Path(__file__).resolve().parents[1]


def main():
    schema = json.loads((ROOT / "docs/reference/android-schema-v10.json").read_text(encoding="utf-8"))["database"]
    sql = (ROOT / "Cost/Resources/Database/CostSchemaV1.sql").read_text(encoding="utf-8")
    seed = json.loads((ROOT / "Cost/Resources/Database/CostSeedV1.json").read_text(encoding="utf-8"))
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.executescript(sql)
    for entity in schema["entities"]:
        table = entity["tableName"]
        actual = connection.execute(f"PRAGMA table_info({table})").fetchall()
        expected = [(f["columnName"], f["affinity"], bool(f.get("notNull", False))) for f in entity["fields"]]
        assert [(row[1], row[2], bool(row[3])) for row in actual] == expected, table
        indexes = {row[1] for row in connection.execute(f"PRAGMA index_list({table})")}
        assert {index["name"] for index in entity.get("indices", [])} <= indexes, table
    for table, records in seed.items():
        for record in records:
            columns = ",".join(record)
            placeholders = ",".join("?" for _ in record)
            connection.execute(f"INSERT OR IGNORE INTO {table} ({columns}) VALUES ({placeholders})", list(record.values()))
    assert connection.execute("SELECT COUNT(*) FROM currencies").fetchone()[0] == 15
    assert connection.execute("SELECT COUNT(*) FROM currencies WHERE is_enabled = 1").fetchone()[0] == 11
    assert connection.execute("SELECT COUNT(*) FROM account_fund_openings").fetchone()[0] == 0
    assert connection.execute("SELECT COUNT(*) FROM transactions").fetchone()[0] == 0
    assert not connection.execute("PRAGMA foreign_key_check").fetchall()
    assert connection.execute("PRAGMA application_id").fetchone()[0] == 1129272137
    assert connection.execute("PRAGMA user_version").fetchone()[0] == 1
    try:
        connection.execute("UPDATE currencies SET default_scale = 1.5 WHERE code = 'CNY'")
        raise AssertionError("SQLite accepted an inexact integer")
    except sqlite3.IntegrityError:
        pass
    # Only Model/Domain/Feature boundaries are checked; GRDB and Foundation internally may use other frameworks.
    for folder in ("Cost/Core/Model", "Cost/Core/Domain", "Cost/Feature"):
        for path in (ROOT / folder).rglob("*.swift"):
            source = path.read_text(encoding="utf-8")
            assert not re.search(r"^import (GRDB|Combine|SwiftData|UIKit|SwiftUI)\b", source, re.M) if "/Feature" not in folder else not re.search(r"^import (GRDB|Combine|SwiftData)\b", source, re.M), path
            if folder != "Cost/Feature":
                assert not re.search(r"\b(Float|Double)\b", source), path
    for path in (ROOT / "Cost").rglob("*.swift"):
        assert not re.search(r"^import (Combine|SwiftData)\b", path.read_text(encoding="utf-8"), re.M), path
    count = connection.execute("SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger'").fetchone()[0]
    print(f"PASS 18 schema tables/columns/indices, {count} storage guards, seeds, FK integrity and layer boundaries")


if __name__ == "__main__":
    main()
