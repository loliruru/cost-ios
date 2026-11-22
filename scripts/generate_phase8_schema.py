"""Freeze the Room exchange schema from Android's checked-in schema metadata."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = "core/data/schemas/com.chinokafuu.cost.core.data.database.CostDatabase"
CURRENT = 10


def generate(source):
    histories = {}
    for version in range(1, CURRENT + 1):
        schema = json.loads((source / f"{version}.json").read_text(encoding="utf-8"))["database"]
        if schema["version"] != version:
            raise ValueError(f"Unexpected version: {schema['version']}")
        histories[str(version)] = {
            entity["tableName"]: [field["columnName"] for field in entity["fields"]]
            for entity in schema["entities"]
        }
    latest = json.loads((ROOT / "docs/reference/android-schema-v10.json").read_text(encoding="utf-8"))["database"]
    if latest != schema:
        raise ValueError("Android v10 does not match the audited snapshot")
    statements = []
    for entity in latest["entities"]:
        statements.append(entity["createSql"].replace("${TABLE_NAME}", entity["tableName"]))
        statements.extend(
            index["createSql"].replace("${TABLE_NAME}", entity["tableName"])
            for index in entity.get("indices", [])
        )
    statements.extend(latest["setupQueries"])
    statements.append(f"PRAGMA user_version = {CURRENT}")
    return json.dumps({"statements": statements, "columns": histories}, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("android_root", type=Path)
    args = parser.parse_args()
    destination = ROOT / "Cost/Resources/Database/AndroidExchangeSchema.json"
    destination.write_text(generate(args.android_root / SCHEMAS), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
