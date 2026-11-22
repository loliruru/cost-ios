"""Build a synthetic legacy Room database and package it with Android's wire APIs."""

import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
from tempfile import TemporaryDirectory

from generate_phase8_schema import ROOT, SCHEMAS


def generate(root, java):
    schema = json.loads((root / SCHEMAS / "1.json").read_text(encoding="utf-8"))["database"]
    with TemporaryDirectory(prefix="cost-phase8-fixture-") as temporary:
        stage = Path(temporary)
        database = sqlite3.connect(stage / "database.sqlite")
        try:
            database.execute("PRAGMA foreign_keys = ON")
            for entity in schema["entities"]:
                for sql in [entity["createSql"], *(index["createSql"] for index in entity.get("indices", []))]:
                    database.execute(sql.replace("${TABLE_NAME}", entity["tableName"]))
            for sql in schema["setupQueries"]:
                database.execute(sql)
            database.execute("PRAGMA user_version = 1")
            database.execute("INSERT INTO currencies VALUES ('CNY','FIAT','CNY','CNY',2,1,0,1)")
            database.execute("INSERT INTO categories VALUES ('fixture-category','Sample','EXPENSE',NULL,'other','gray',0,0,0,0)")
            database.execute("INSERT INTO accounts VALUES ('fixture-account','Sample','CNY','wallet','gray',0,1,0,0,0)")
            database.execute(
                """INSERT INTO transactions (
                id, transaction_type, original_amount_minor, original_scale, original_currency_code,
                base_currency_code, base_scale, exchange_rate_text, converted_base_amount_minor,
                rate_provider, valuation_method, category_id, account_id, occurred_at_epoch_millis,
                occurred_zone_id, occurred_local_epoch_day, note, source_type,
                created_at_epoch_millis, updated_at_epoch_millis
                ) VALUES ('fixture-transaction','EXPENSE',9223372036854775807,2,'CNY','CNY',2,'1',
                9223372036854775807,'IDENTITY','IDENTITY','fixture-category','fixture-account',0,'UTC',0,
                ?,'MANUAL',0,0)""",
                ('=1+1, "synthetic"\r\n账本',),
            )
            database.commit()
        finally:
            database.close()
        (stage / "settings.json").write_bytes(b'{"anomaly_enabled":false,"base_currency_code":"CNY"}')
        files = {}
        for name in ("database.sqlite", "settings.json"):
            payload = (stage / name).read_bytes()
            files[name] = {"size": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
        (stage / "manifest.json").write_text(
            json.dumps({"format": 1, "schema": 1, "files": files, "visual_assets": []}),
            encoding="utf-8",
        )
        fixture = subprocess.check_output([java, str(ROOT / "scripts/PortableBackupFixture.java"), str(stage)], text=True)
    return json.dumps(json.loads(fixture), indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("android_root", type=Path)
    parser.add_argument("--java", default="java")
    args = parser.parse_args()
    (ROOT / "CostTests/Fixtures/PortableBackupV1.json").write_text(
        generate(args.android_root, args.java), encoding="utf-8", newline="\n"
    )


if __name__ == "__main__":
    main()
