"""Capture the actual SPM resolution without treating the version range as a lock."""

import json
from pathlib import Path


def main() -> None:
    source = Path("Cost.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    raw = source.read_bytes()
    resolved = json.loads(raw)
    pins = resolved["pins"]
    by_identity = {pin["identity"].lower(): pin for pin in pins}
    if len(pins) != 2 or set(by_identity) != {"grdb.swift", "libwebp-xcode"}:
        raise SystemExit("Expected only GRDB and the explicitly approved libwebp codec")
    if not by_identity["grdb.swift"]["state"]["version"].startswith("7."):
        raise SystemExit("GRDB must resolve within the approved 7.x range")
    if by_identity["libwebp-xcode"]["state"]["version"] != "1.6.0":
        raise SystemExit("libwebp must resolve to the approved exact version 1.6.0")
    Path("build/Package.resolved").write_bytes(raw)
    evidence = {"packages": [{"identity": pin["identity"], "url": pin["location"],
                              "version": pin["state"]["version"], "revision": pin["state"]["revision"]} for pin in pins]}
    Path("build/dependency-resolution.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence))


if __name__ == "__main__":
    main()
