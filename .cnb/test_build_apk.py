import hashlib
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import build_apk


BADGING = """package: name='com.kajolno.TrafArch' versionCode='2345' versionName='2.0.0-beta2'
application-label:'TrafArch'
launchable-activity: name='com.kajolno.TrafArch.MainActivity' label='' icon=''
"""
SIGNATURE = ("Number of signers: 1\n"
             "V2 Signer: certificate SHA-256 digest: 3b86c43104ea366997126a8d1600a34b3ccaf83c212a30159eb0853e2e1312b5")


class ApkVerificationTest(unittest.TestCase):
    def check_identity(self, badging=BADGING, manifest="", signature=SIGNATURE):
        build_apk.check_identity(badging, manifest, signature, "2.0.0-beta2", 2345)

    def test_release_identity(self):
        self.check_identity()

    def test_rejects_wrong_package_version_code_version_name_or_label(self):
        for expected in ("com.kajolno.TrafArch", "2345", "2.0.0-beta2", "application-label:'TrafArch'"):
            with self.subTest(field=expected), self.assertRaises(ValueError):
                self.check_identity(badging=BADGING.replace(expected, "unexpected"))

    def test_rejects_wrong_or_extra_signer(self):
        for signature in (SIGNATURE.replace("3b86", "1234"), SIGNATURE.replace("signers: 1", "signers: 2"),
                          SIGNATURE + "\n" + SIGNATURE.splitlines()[1].replace("3b86", "1234")):
            with self.subTest(signature=signature), self.assertRaises(ValueError):
                self.check_identity(signature=signature)

    def test_rejects_debug_test_only_and_dependent_split_apks(self):
        for attribute in ("debuggable", "testOnly", "isSplitRequired"):
            with self.subTest(attribute=attribute), self.assertRaises(ValueError):
                self.check_identity(manifest=f"A: android:{attribute}(0x01010272)=(type 0x12)0xffffffff")
        with self.assertRaises(ValueError):
            self.check_identity(manifest='A: split="config.arm64_v8a" (Raw: "config.arm64_v8a")')

    def test_abi_checks_require_the_flutter_runtime_and_app_for_each_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "sample.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                for name in ("lib/arm64-v8a/libflutter.so", "lib/arm64-v8a/libapp.so"):
                    archive.writestr(name, b"fixture")
            build_apk.check_native_libraries(apk, {"arm64-v8a"})
            with self.assertRaises(ValueError):
                build_apk.check_native_libraries(apk, {"armeabi-v7a", "arm64-v8a", "x86_64"})
            with zipfile.ZipFile(apk, "a") as archive:
                archive.writestr("lib/x86_64/libflutter.so", b"fixture")
            with self.assertRaises(ValueError):
                build_apk.check_native_libraries(apk, {"arm64-v8a", "x86_64"})
            with self.assertRaises(ValueError):
                build_apk.check_native_libraries(apk, {"arm64-v8a"})


class BuildOutputTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(temp.name)
        Path("pubspec.yaml").write_text("version: 2.0.0-beta2+2345\n", encoding="utf-8")
        self.flutter_output = Path("build/app/outputs/flutter-apk")
        self.flutter_output.mkdir(parents=True)

    def simulate_flutter(self, command, *, check):
        self.assertTrue(check)
        self.assertEqual(command[:2], ["flutter", "build"])
        self.assertIn("--release", command)
        self.assertIn("--no-pub", command)
        self.assertEqual(command[command.index("--target") + 1], "lib/main.dart")
        self.assertEqual(command[command.index("--target-platform") + 1], "android-arm,android-arm64,android-x64")
        if "--split-per-abi" in command:
            files = {f"app-{abi}-release.apk": [abi] for abi in ("armeabi-v7a", "arm64-v8a", "x86_64")}
        else:
            files = {"app-release.apk": ["armeabi-v7a", "arm64-v8a", "x86_64"]}
        for name, abis in files.items():
            with zipfile.ZipFile(self.flutter_output / name, "w") as archive:
                for abi in abis:
                    for library in ("libapp.so", "libflutter.so"):
                        archive.writestr(f"lib/{abi}/{library}", b"fixture")
        Path("pubspec.yaml").write_text("version: 2.0.0-beta2+2346\n", encoding="utf-8")

    def run_build(self, mode, signing=SIGNATURE):
        def android_tools(command, **kwargs):
            tool = Path(command[0]).stem
            if tool == "aapt":
                return BADGING if command[2] == "badging" else ""
            if tool == "apksigner":
                return signing
            self.assertEqual(tool, "zipalign")
            return ""

        with patch.dict(os.environ, ANDROID_HOME=os.getcwd()), \
                patch("subprocess.run", side_effect=self.simulate_flutter), \
                patch("subprocess.check_output", side_effect=android_tools), patch("builtins.print"):
            build_apk.build(mode)

    def check_published(self, mode, variants):
        self.run_build(mode)
        directory = Path("build/cnb-apk")
        apks = sorted(directory.glob("*.apk"))
        self.assertEqual([f"TrafArch-2.0.0-beta2-2345-{abi}.apk" for abi in sorted(variants)],
                         [apk.name for apk in apks])
        manifest = directory / f"SHA256SUMS-2345-{mode}.txt"
        self.assertEqual(sorted(manifest.read_text().splitlines()),
                         sorted(f"{hashlib.sha256(apk.read_bytes()).hexdigest()}  {apk.name}" for apk in apks))

    def test_split_publishes_all_three_checked_apks(self):
        self.check_published("split", ["armeabi-v7a", "arm64-v8a", "x86_64"])

    def test_universal_publishes_one_checked_apk(self):
        self.check_published("universal", ["universal"])

    def test_a_failed_signature_publishes_nothing_and_removes_stale_attachments(self):
        output = Path("build/cnb-apk")
        output.mkdir()
        (output / "stale.apk").write_bytes(b"fixture")
        with self.assertRaisesRegex(ValueError, "certificate"):
            self.run_build("split", signing=SIGNATURE.replace("3b86", "1234"))
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
