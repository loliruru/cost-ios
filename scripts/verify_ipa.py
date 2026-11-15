"""Inspect an unsigned device IPA on Windows or macOS without executing its binary."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import stat
import struct
import zipfile


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def inspect_executable(binary: bytes) -> dict:
    require(len(binary) >= 32, "Truncated Mach-O executable")
    magic, cpu, _, filetype, commands, command_bytes, _, _ = struct.unpack_from("<8I", binary)
    require(magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected a 64-bit arm64 device executable")
    require(filetype == 2, "Mach-O must be an executable")
    require(32 + command_bytes <= len(binary), "Truncated Mach-O load commands")
    offset, platform, signed = 32, None, False
    for _ in range(commands):
        require(offset + 8 <= 32 + command_bytes, "Invalid load command header")
        command, size = struct.unpack_from("<2I", binary, offset)
        require(size >= 8 and offset + size <= 32 + command_bytes, "Invalid load command size")
        if command == 0x32:  # LC_BUILD_VERSION (platform 2 = iOS device; 7 = simulator)
            require(size >= 24, "Truncated LC_BUILD_VERSION")
            platform = struct.unpack_from("<I", binary, offset + 8)[0]
        if command == 0x1D:  # LC_CODE_SIGNATURE
            signed = True
        offset += size
    require(offset == 32 + command_bytes, "Mach-O command count/size mismatch")
    require(platform == 2, "Executable must target iOS devices, not a simulator")
    require(not signed, "Expected an unsigned executable")
    return {"architecture": "arm64", "platform": "iOS", "unsigned": True}


def verify_ipa(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        require(len(names) == len(set(names)), "Duplicate ZIP entries")
        for name in names:
            parts = PurePosixPath(name).parts
            require(parts and parts[0] == "Payload" and ".." not in parts and "\\" not in name,
                    "Unsafe or unexpected IPA entry")
        apps = {PurePosixPath(name).parts[1] for name in names if len(PurePosixPath(name).parts) > 1}
        require(apps == {"Cost.app"}, "Expected Payload/Cost.app as the only application")
        require(archive.testzip() is None, "Corrupt IPA entry")
        prefix = "Payload/Cost.app/"
        require(prefix + "Info.plist" in names, "Missing application Info.plist")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        require(info["CFBundleIdentifier"] == "com.personal.cost", "Wrong application bundle identifier")
        require(info["CFBundlePackageType"] == "APPL", "Wrong application package type")
        require(info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Expected device platform metadata")
        require(tuple(map(int, info["MinimumOSVersion"].split("."))) == (18, 0), "Minimum iOS must remain 18.0")
        executable = info["CFBundleExecutable"]
        require(executable == "Cost" and prefix + executable in names, "Missing application executable")
        executable_entry = archive.getinfo(prefix + executable)
        require(bool((executable_entry.external_attr >> 16) & stat.S_IXUSR), "Executable permission was lost")
        require(not any("_CodeSignature" in PurePosixPath(name).parts or name.endswith(".mobileprovision")
                        for name in names), "Signing material found in unsigned IPA")
        binary = inspect_executable(archive.read(prefix + executable))
    return {"ipa": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "application": "Payload/Cost.app/", "entries": len(entries),
            "bundleIdentifier": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"], "minimumIOS": info["MinimumOSVersion"], **binary}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = json.dumps(verify_ipa(args.ipa), indent=2) + "\n"
    if args.output:
        args.output.write_text(result, encoding="utf-8")
    print(result, end="")


if __name__ == "__main__":
    main()
