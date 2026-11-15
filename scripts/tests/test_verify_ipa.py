import importlib.util
from pathlib import Path
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location("verify_ipa", Path(__file__).resolve().parents[1] / "verify_ipa.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VerifyIPATests(unittest.TestCase):
    def make_ipa(self, folder: Path, *, platform: int = 2, executable_mode: int = 0o755,
                 app: str = "Cost.app", signed: bool = False) -> Path:
        info = {"CFBundleIdentifier": "com.personal.cost", "CFBundlePackageType": "APPL",
                "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "Cost",
                "MinimumOSVersion": "18.0", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}
        commands = struct.pack("<6I", 0x32, 24, platform, 18 << 16, 0, 0)
        if signed:
            commands += struct.pack("<4I", 0x1D, 16, 0, 0)
        binary = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, 2 if signed else 1, len(commands), 0, 0) + commands
        path = folder / "fixture.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(f"Payload/{app}/Info.plist", plistlib.dumps(info))
            executable = zipfile.ZipInfo(f"Payload/{app}/Cost")
            executable.create_system = 3
            executable.external_attr = (stat.S_IFREG | executable_mode) << 16
            archive.writestr(executable, binary)
        return path

    def test_valid_unsigned_device_structure(self):
        with tempfile.TemporaryDirectory() as folder:
            result = MODULE.verify_ipa(self.make_ipa(Path(folder)))
            self.assertEqual(result["architecture"], "arm64")
            self.assertTrue(result["unsigned"])

    def test_arm64_simulator_cannot_pass_as_device(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "iOS devices"):
                MODULE.verify_ipa(self.make_ipa(Path(folder), platform=7))

    def test_wrong_payload_application_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "only application"):
                MODULE.verify_ipa(self.make_ipa(Path(folder), app="Other.app"))

    def test_lost_execute_permission_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "permission"):
                MODULE.verify_ipa(self.make_ipa(Path(folder), executable_mode=0o644))

    def test_signed_executable_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "unsigned executable"):
                MODULE.verify_ipa(self.make_ipa(Path(folder), signed=True))

    def test_path_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.make_ipa(Path(folder))
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("Payload/../outside", "invalid")
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                MODULE.verify_ipa(path)


if __name__ == "__main__":
    unittest.main()
