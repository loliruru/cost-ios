"""Capture the actual SPM resolution without treating the version range as a lock."""

import json
from pathlib import Path


def main() -> None:
    source = Path("Cost.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    raw = source.read_bytes()
    resolved = json.loads(raw)
    pins = resolved["pins"]
    if len(pins) != 1 or pins[0]["identity"].lower() not in {"grdb.swift", "grdb"}:
        raise SystemExit("Expected GRDB as the only resolved application dependency")
    pin = pins[0]
    if not pin["state"]["version"].startswith("7."):
        raise SystemExit("GRDB must resolve within the approved 7.x range")
    Path("build/Package.resolved").write_bytes(raw)
    evidence = {"packages": [{"identity": pin["identity"], "url": pin["location"],
                              "version": pin["state"]["version"], "revision": pin["state"]["revision"]}]}
    Path("build/dependency-resolution.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence))


if __name__ == "__main__":
    main()
