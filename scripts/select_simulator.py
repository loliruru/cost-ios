"""Select a real installed iPhone runtime compatible with the selected Xcode SDK."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def main() -> None:
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True,
    ).strip()
    inventory = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True,
    ))
    candidates = []
    for runtime, devices in inventory["devices"].items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-([\d-]+)", runtime)
        if not match:
            continue
        runtime_version = version(match.group(1).replace("-", "."))
        if not ((18, 0) <= runtime_version <= version(sdk)):
            continue
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((runtime_version, device["name"] == "iPhone 16", device["name"], runtime, device))
    if not candidates:
        raise SystemExit(f"No available iPhone runtime for iOS 18 through SDK {sdk}")
    _, _, _, runtime, selected = max(candidates, key=lambda item: item[:3])
    destination = f"platform=iOS Simulator,id={selected['udid']}"
    evidence = {"runtime": runtime, "name": selected["name"], "udid": selected["udid"],
                "sdk": sdk, "destination": destination}
    Path("build").mkdir(exist_ok=True)
    Path("build/simulator.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"destination={destination}\n")
    print(json.dumps(evidence))
    if selected["state"] != "Booted":
        subprocess.run(["xcrun", "simctl", "boot", selected["udid"]], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", selected["udid"], "-b"], check=True)


if __name__ == "__main__":
    main()
