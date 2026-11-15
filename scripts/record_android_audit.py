"""Record a reviewed, read-only source baseline. Never opens personal app data."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "core/data/schemas/com.chinokafuu.cost.core.data.database.CostDatabase/10.json"
KEY_NAMES = {
    "Money.kt", "MoneyTest.kt", "DecimalRate.kt", "DecimalRateTest.kt",
    "CostDatabase.kt", "CurrencySeedData.kt", "AccountFundsMigration.kt",
    "ManageTransactionsUseCase.kt", "ManageQuickTemplatesUseCase.kt",
    "ManageMetadataUseCase.kt", "DefaultExchangeRateRepository.kt",
    "TwelveDataExchangeRateProvider.kt", "TwelveDataCryptoPriceProvider.kt",
    "RecurringScheduleCalculator.kt", "RecurringScheduleCalculatorTest.kt",
    "ProcessRecurringTransactionsUseCase.kt", "RoomAccountFundsRepository.kt",
    "AccountFunds.kt", "AccountFundsDao.kt", "CategoryDao.kt", "TagDao.kt",
    "TransactionDao.kt", "QuickTemplateDao.kt", "RecurringRuleDao.kt",
    "StatisticsDao.kt", "RoomStatisticsRepository.kt", "ObserveStatisticsUseCase.kt",
    "AnomalyDao.kt", "DetectAnomaliesUseCase.kt", "BackupEnvelope.kt",
    "TransferDatabase.kt", "LocalDataTransferRepository.kt", "BackupPreferences.kt",
}


def git(source: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "--no-optional-locks", "-c", f"safe.directory={source.as_posix()}",
         "-C", str(source), *arguments], encoding="utf-8",
    ).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-root", type=Path, required=True)
    parser.add_argument("--date", required=True, help="Reviewed Asia/Singapore date, YYYY-MM-DD")
    args = parser.parse_args()
    source = args.android_root.resolve(strict=True)
    if source == ROOT or source in ROOT.parents or ROOT in source.parents:
        raise ValueError("Android reference and iOS repository must be separate")
    tracked = git(source, "ls-files").splitlines()
    documents = sorted(p for p in tracked if p == "AGENTS.md" or (p.startswith("docs/") and p.endswith(".md")))
    code = sorted(p for p in tracked if p.startswith("core/") and Path(p).name in KEY_NAMES)
    schema_bytes = (source / SCHEMA).read_bytes()
    schema = json.loads(schema_bytes)["database"]
    transfer_path = next(p for p in code if p.endswith("/TransferDatabase.kt"))
    transfer = (source / transfer_path).read_text(encoding="utf-8")
    table_block = re.search(r"LEDGER_TABLES = listOf\((.*?)\)", transfer, re.S)
    if table_block is None:
        raise ValueError("Cannot find Android ledger export table contract")
    ledger_tables = re.findall(r'"([a-z_]+)"', table_block.group(1))
    entities = {e["tableName"] for e in schema["entities"]}
    if schema["version"] != 10 or len(entities) != 18 or entities - set(ledger_tables) != {"restore_state"}:
        raise ValueError("Reviewed v10 schema/export boundary has changed; re-audit first")
    entries = [
        {"path": p, "sha256": hashlib.sha256((source / p).read_bytes()).hexdigest()}
        for p in sorted(set(documents + code + [SCHEMA]))
    ]
    if git(source, "diff", "HEAD", "--"):
        raise ValueError("Android tracked files differ from HEAD; record and review before snapshotting")
    schema_snapshot = schema_bytes.replace(b"\r\n", b"\n")
    manifest = {
        "formatVersion": 1,
        "auditedDate": args.date,
        "timeZone": "Asia/Singapore",
        "androidRevision": git(source, "rev-parse", "HEAD"),
        "trackedDiffClean": True,
        "existingUntrackedFilesPresent": bool(git(source, "ls-files", "--others", "--exclude-standard")),
        "androidTestsRerun": False,
        "schemaVersion": schema["version"],
        "roomIdentityHash": schema["identityHash"],
        "entityCount": len(entities),
        "exportedLedgerTables": ledger_tables,
        "documents": documents,
        "files": entries,
        "schemaSnapshot": "docs/reference/android-schema-v10.json",
        "schemaSnapshotSha256": hashlib.sha256(schema_snapshot).hexdigest(),
    }
    destination = ROOT / "docs/reference"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "android-schema-v10.json").write_bytes(schema_snapshot)
    (destination / "android-audit-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n",
    )
    print(f"Recorded {len(documents)} documents, {len(code)} code/test files, schema v10; Android read only.")


if __name__ == "__main__":
    main()
