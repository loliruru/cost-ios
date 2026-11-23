"""Validate the Windows-editable foundation; this does not compile Swift or run XcodeGen."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools/python"))
try:
    import yaml
except ImportError:
    raise SystemExit("Install development tools: python -m pip install --target .tools/python -r scripts/requirements-dev.txt")


class UniqueLoader(yaml.SafeLoader):
    """Reject duplicate keys rather than silently discarding a target or setting."""


def unique_mapping(loader: UniqueLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"Duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def git(root: Path, *arguments: str, input_text: str | None = None) -> str:
    result = subprocess.run(
        ["git", "--no-optional-locks", "-c", f"safe.directory={root.as_posix()}",
         "-C", str(root), *arguments], input=input_text, capture_output=True,
        encoding="utf-8", check=False,
    )
    require(result.returncode == 0, f"Git check failed: {result.stderr.strip()}")
    return result.stdout


def verify_project() -> None:
    project = yaml.load((ROOT / "project.yml").read_text(encoding="utf-8"), Loader=UniqueLoader)
    require(project["name"] == "Cost", "Unexpected project name")
    require(project["options"]["deploymentTarget"]["iOS"] == "18.0", "Deployment target must be 18.0")
    settings = project["settings"]["base"]
    require(settings["SWIFT_VERSION"] == "6.0", "Swift 6 is required")
    require(settings["SWIFT_STRICT_CONCURRENCY"] == "complete", "Strict concurrency is required")
    require(settings["CODE_SIGNING_ALLOWED"] == "NO", "Foundation must be unsigned")
    require(set(project["packages"]) == {"GRDB", "libwebp"}, "Only GRDB and the explicitly approved WebP codec are allowed")
    require(project["packages"]["libwebp"] == {
        "url": "https://github.com/SDWebImage/libwebp-Xcode.git", "exactVersion": "1.6.0",
    }, "Unexpected WebP dependency requirement")
    require(project["packages"]["GRDB"] == {
        "url": "https://github.com/groue/GRDB.swift", "from": "7.0.0",
    }, "Unexpected GRDB dependency requirement")
    targets = project["targets"]
    require(set(targets) == {"Cost", "CostTests", "CostUITests"}, "Expected App, hosted and native UI test targets")
    require(targets["Cost"]["type"] == "application", "Cost must be an application")
    require(targets["CostTests"]["type"] == "bundle.unit-test", "Expected a unit-test bundle")
    for target in targets.values():
        require(target["platform"] == "iOS", "All targets must be iOS")
        for source in target["sources"]:
            require((ROOT / source["path"]).is_dir(), f"Missing source root: {source['path']}")
    require("Info.plist" in targets["Cost"]["sources"][0]["excludes"], "Exclude Info.plist from resources")
    app_settings = targets["Cost"]["settings"]["base"]
    require(app_settings["TARGETED_DEVICE_FAMILY"] == "1", "App target must override the iPad preset")
    require("ASSETCATALOG_COMPILER_APPICON_NAME" in app_settings, "App icon selection must override the XcodeGen preset")
    if icon_name := app_settings["ASSETCATALOG_COMPILER_APPICON_NAME"]:
        require((ROOT / f"Cost/Resources/Assets.xcassets/{icon_name}.appiconset").is_dir(), "Selected AppIcon asset is missing")
    require(targets["Cost"]["dependencies"] == [{"package": "GRDB", "product": "GRDB"}, {"package": "libwebp", "product": "libwebp"}], "App must link only approved dependencies")
    require({"target": "Cost"} in targets["CostTests"]["dependencies"], "Tests must depend on App")
    test_settings = targets["CostTests"]["settings"]["base"]
    require(test_settings["TEST_HOST"] == "$(BUILT_PRODUCTS_DIR)/Cost.app/Cost", "Wrong iPhone test host")
    require(test_settings["BUNDLE_LOADER"] == "$(TEST_HOST)", "Wrong bundle loader")
    for scheme_name in ("Cost", "CostTests"):
        scheme = project["schemes"][scheme_name]
        require(set(scheme["build"]["targets"]) <= set(targets), "Unknown scheme build target")
        require(scheme["test"]["targets"] == ["CostTests"], "Scheme must run hosted tests")
    require(targets["CostUITests"]["type"] == "bundle.ui-testing", "Expected UI testing bundle")
    require(project["schemes"]["CostUITests"]["test"]["targets"] == ["CostUITests"], "UI scheme must run native UI tests")
    with (ROOT / targets["Cost"]["settings"]["base"]["INFOPLIST_FILE"]).open("rb") as stream:
        info = plistlib.load(stream)
    require(info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)", "Bundle identity must use build settings")
    require(info["CFBundleExecutable"] == "$(EXECUTABLE_NAME)", "Missing executable substitution")
    require(info["CFBundlePackageType"] == "APPL", "Wrong bundle package type")
    require("UILaunchScreen" in info, "Missing launch-screen metadata")
    for path in (ROOT / "Cost/Resources").rglob("*"):
        if path.suffix in {".json", ".xcstrings"}:
            json.loads(path.read_text(encoding="utf-8"))
    print("PASS project YAML (unique keys), targets/schemes, plist and resource JSON")


def verify_files() -> None:
    required = ["AGENTS.md", "README.md", "Cost/App/CostApp.swift", "Cost/App/AppContainer.swift",
                "CostTests/FoundationTests.swift", "Cost/Resources/Assets.xcassets/Contents.json",
                "Cost/Resources/Localizable.xcstrings"]
    required += [f"docs/{name}.md" for name in (
        "PRODUCT_SPEC", "ARCHITECTURE", "DATA_MODEL", "DESIGN_SYSTEM",
        "IMPLEMENTATION_PLAN", "DECISIONS", "ANDROID_AUDIT",
    )]
    for path in required:
        require((ROOT / path).is_file(), f"Missing required file: {path}")
    directories = [f"Cost/Core/{name}" for name in ("Model", "Domain", "Data", "DesignSystem")]
    directories += [f"Cost/Feature/{name}" for name in (
        "Ledger", "Entry", "Templates", "Recurring", "Statistics", "Categories",
        "Accounts", "Tags", "Settings", "Backup",
    )]
    directories += [f"CostTests/Core/{name}" for name in ("ModelTests", "DomainTests", "DataTests")]
    directories += ["CostTests/Feature", ".github/workflows"]
    candidates = git(ROOT, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    for path in directories:
        require((ROOT / path).is_dir(), f"Missing planned directory: {path}")
        require(any(candidate.startswith(path + "/") for candidate in candidates),
                f"Planned directory has no trackable content (check ignore rules): {path}")
    # Only repository docs; the unchanged input plan contains illustrative paths, not actual links.
    documents = [ROOT / "AGENTS.md", ROOT / "README.md", *(ROOT / "docs").rglob("*.md")]
    for path in documents:
        for link in re.findall(r"\[[^\]]*\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
            if re.match(r"^[a-zA-Z][a-zA-Z\d+.-]*:", link) or link.startswith("#"):
                continue
            target = (path.parent / link.split("#", 1)[0]).resolve()
            require(target.is_relative_to(ROOT) and target.exists(), f"Broken doc link in {path.name}: {link}")
    print("PASS planned files/directories and local documentation links")


def verify_workflow() -> None:
    path = ROOT / ".github/workflows/build.yml"
    if not path.exists():
        return
    workflow = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueLoader)
    require(set(workflow["on"]) == {"push", "pull_request", "workflow_dispatch"}, "Unexpected workflow triggers")
    require(workflow["permissions"] == {"contents": "read"}, "Build token must be read-only")
    job = workflow["jobs"]["build"]
    require(job["runs-on"] in {"macos-15", "macos-15-intel"} and job["timeout-minutes"] == 40,
            "Unexpected build runner/timeout")
    require("secrets." not in path.read_text(encoding="utf-8"), "Unsigned build must not require user secrets")
    # Parse the actual shell blocks; never execute macOS build commands on Windows.
    bash = Path("C:/Program Files/Git/bin/bash.exe") if sys.platform == "win32" else shutil.which("bash")
    require(bool(bash) and Path(bash).is_file(), "Bash is required to syntax-check workflow scripts")
    scripts = [step["run"] for step in job["steps"] if "run" in step]
    for script in scripts:
        result = subprocess.run([str(bash), "--noprofile", "--norc", "-n"],
                                input=script.encode("utf-8"), capture_output=True)
        require(result.returncode == 0, "Workflow Bash syntax error: " + result.stderr.decode("utf-8", errors="replace"))
    print(f"PASS workflow YAML, permissions/triggers and {len(scripts)} Bash script blocks")


def verify_ignores() -> None:
    ignored = [
        "Cost.xcodeproj/project.pbxproj", "Cost.xcworkspace/contents.xcworkspacedata",
        "DerivedData/output", "build/Cost-unsigned.ipa", ".build/output", ".tools/python/tool.py",
        "local.properties", "device.local.properties", "Secrets.swift", ".env", ".env.local",
        "signing/test.p12", "test.mobileprovision", "test.cer", "private.key",
        "ledger.sqlite", "ledger.sqlite-wal", "ledger.sqlite-shm", "ledger.db", "ledger.db-wal",
        "transactions.csv", "snapshot.json.backup", "backup/data", "backups/data", "Cost.costbackup",
        "Cost.zip", "Cost.ipa", "phone.plist.pairing", "phone.pairing.plist",
        "pairing_record.plist", "phone.mobiledevicepairing", "phone.pairingfile",
        "pairing/phone.plist", "pairing_files/phone.plist", "anisette/state",
    ]
    # NUL delimiters avoid Windows text-mode CRLF changing the paths sent to Git.
    output = git(ROOT, "check-ignore", "--no-index", "--stdin", "-z", input_text="\0".join(ignored) + "\0")
    missing = set(ignored) - set(output.split("\0"))
    require(not missing, f"Sensitive/generated paths are not ignored: {sorted(missing)}")
    tracked_candidates = git(ROOT, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    forbidden_suffixes = {".sqlite", ".db", ".csv", ".ipa", ".p12", ".pfx", ".cer", ".key", ".pem", ".mobileprovision"}
    for path in tracked_candidates:
        require(Path(path).suffix.lower() not in forbidden_suffixes, f"Forbidden repository candidate: {path}")
    print(f"PASS {len(ignored)} ignore probes and repository artifact candidates")


def verify_audit(android_root: Path | None) -> None:
    manifest = json.loads((ROOT / "docs/reference/android-audit-manifest.json").read_text(encoding="utf-8"))
    snapshot_path = manifest["schemaSnapshot"]
    snapshot = (ROOT / snapshot_path).read_bytes()
    schema = json.loads(snapshot)["database"]
    require(schema["version"] == manifest["schemaVersion"] == 10, "Schema version mismatch")
    entities = {e["tableName"] for e in schema["entities"]}
    require(len(entities) == manifest["entityCount"] == 18, "Expected 18 Room entities")
    ledger = manifest["exportedLedgerTables"]
    require(len(ledger) == len(set(ledger)) == 17 and entities - set(ledger) == {"restore_state"}, "Wrong ledger boundary")
    require(hashlib.sha256(snapshot).hexdigest() == manifest["schemaSnapshotSha256"], "Schema snapshot changed")
    require(schema["identityHash"] == manifest["roomIdentityHash"], "Room identity mismatch")
    require(len(manifest["documents"]) == 19, "Expected AGENTS and 18 Android docs")
    if android_root is not None:
        android_root = android_root.resolve(strict=True)
        for item in manifest["files"]:
            require(hashlib.sha256((android_root / item["path"]).read_bytes()).hexdigest() == item["sha256"],
                    f"Android reference differs: {item['path']}")
        require(git(android_root, "rev-parse", "HEAD").strip() == manifest["androidRevision"], "Android HEAD changed")
        require(not git(android_root, "diff", "HEAD", "--").strip(), "Android tracked diff is not clean")
        print(f"PASS Android source unchanged ({len(manifest['files'])} file hashes, HEAD and tracked diff)")
    else:
        print("SKIP live Android source comparison (use --android-root to enable)")
    print("PASS schema v10 snapshot: 18 entities, 17 exported ledger tables, restore outbox excluded")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-root", type=Path)
    args = parser.parse_args()
    verify_project()
    verify_files()
    verify_workflow()
    verify_ignores()
    verify_audit(args.android_root)
    print("NOT RUN: XcodeGen generation, Swift compilation/tests, simulator/device build, IPA, device validation")


if __name__ == "__main__":
    main()
