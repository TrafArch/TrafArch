"""Build release APKs in the provisioned CNB workspace and verify before publishing."""
import argparse
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path


ABIS = ("armeabi-v7a", "arm64-v8a", "x86_64")
# Public fingerprint from docs/UPGRADE_HANDOFF_20261021.md.
CERTIFICATE = "3b86c43104ea366997126a8d1600a34b3ccaf83c212a30159eb0853e2e1312b5"


def source_version():
    pubspec = Path("pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:[ \t]*([0-9A-Za-z.-]+)\+(\d+)[ \t]*$", pubspec, re.MULTILINE)
    if not match:
        raise ValueError("Expected a version name and build number in pubspec.yaml")
    return match[1], int(match[2])


def check_identity(badging, manifest, signatures, version, code):
    expected = f"package: name='com.kajolno.TrafArch' versionCode='{code}' versionName='{version}'"
    if not any(line == expected or line.startswith(expected + " ") for line in badging.splitlines()):
        raise ValueError(f"Expected com.kajolno.TrafArch {version}+{code} in the APK manifest")
    if "application-label:'TrafArch'" not in badging.splitlines() or "launchable-activity:" not in badging:
        raise ValueError("APK must be labelled TrafArch and have a launcher activity")
    for attribute in ("debuggable", "testOnly", "isSplitRequired"):
        value = re.search(rf"A: android:{attribute}(?:\([^)]*\))?=([^\r\n]+)", manifest)
        if value and value[1].strip() not in ("(type 0x12)0x0", '"false"'):
            raise ValueError(f"APK has an incompatible manifest attribute: {attribute}")
    if re.search(r"A: split(?:\([^)]*\))?=", manifest):
        raise ValueError("APK declares itself a dependent split")
    digests = re.findall(r"^(?:V[\d.]+ )?Signer(?: #\d+)?:? certificate SHA-256 digest: ([\da-f]+)$",
                         signatures, re.I | re.M)
    if "Number of signers: 1" not in signatures.splitlines() or {s.lower() for s in digests} != {CERTIFICATE}:
        raise ValueError("APK must have exactly the original developer certificate")


def check_native_libraries(apk, expected_abis):
    with zipfile.ZipFile(apk) as archive:
        libraries = {name for name in archive.namelist() if re.fullmatch(r"lib/[^/]+/[^/]+\.so", name)}
        actual_abis = {name.split("/")[1] for name in libraries}
        if actual_abis != expected_abis:
            raise ValueError(f"{apk.name} contains {sorted(actual_abis)}, expected {sorted(expected_abis)}")
        for abi in expected_abis:
            if not {f"lib/{abi}/libapp.so", f"lib/{abi}/libflutter.so"} <= libraries:
                raise ValueError(f"{apk.name} lacks the compiled Flutter application or engine for {abi}")
        if archive.testzip() is not None:
            raise ValueError(f"ZIP checksum failed for {apk.name}")


def verify_apk(apk, build_tools, version, code, abis):
    def run(tool, *args):
        if os.name == "nt":
            tool += ".bat" if tool == "apksigner" else ".exe"
        return subprocess.check_output([str(build_tools / tool), *args], text=True, encoding="utf-8")

    badging = run("aapt", "dump", "badging", str(apk))
    manifest = run("aapt", "dump", "xmltree", str(apk), "AndroidManifest.xml")
    signatures = run("apksigner", "verify", "--verbose", "--print-certs", str(apk))
    check_identity(badging, manifest, signatures, version, code)
    check_native_libraries(apk, abis)
    run("zipalign", "-c", "-P", "16", "4", str(apk))


def build(mode):
    version, code = source_version()
    sdk = os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"]
    build_tools = Path(sdk) / "build-tools" / "37.0.0"
    output = Path("build/cnb-apk")
    if output.exists():
        shutil.rmtree(output)
    if mode == "split":
        products = [(f"app-{abi}-release.apk", abi, {abi}) for abi in ABIS]
    else:
        products = [("app-release.apk", "universal", set(ABIS))]
    flutter_output = Path("build/app/outputs/flutter-apk")
    for filename, _, _ in products:
        (flutter_output / filename).unlink(missing_ok=True)
    command = ["flutter", "build", "apk", "--release", "--no-pub", "--target", "lib/main.dart",
               "--target-platform", "android-arm,android-arm64,android-x64"]
    if mode == "split":
        command.append("--split-per-abi")
    subprocess.run(command, check=True)
    if source_version() != (version, code + 1):
        raise ValueError("Gradle did not reserve the next build number")

    with tempfile.TemporaryDirectory(dir=output.parent, prefix=".cnb-apk-") as temporary:
        staging = Path(temporary) / "verified"
        staging.mkdir()
        checksums = []
        for filename, variant, abis in products:
            apk = flutter_output / filename
            verify_apk(apk, build_tools, version, code, abis)
            name = f"TrafArch-{version}-{code}-{variant}.apk"
            destination = staging / name
            shutil.copyfile(apk, destination)
            hasher = hashlib.sha256()
            with destination.open("rb") as contents:
                for chunk in iter(lambda: contents.read(1024 * 1024), b""):
                    hasher.update(chunk)
            digest = hasher.hexdigest()
            checksums.append(f"{digest}  {name}\n")
            print(f"{name}  TrafArch  com.kajolno.TrafArch  versionCode={code}  "
                  f"versionName={version}  ABIs={','.join(sorted(abis))}  certificateSHA256={CERTIFICATE}  SHA256={digest}")
        (staging / f"SHA256SUMS-{code}-{mode}.txt").write_text("".join(checksums), encoding="ascii")
        staging.rename(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("split", "universal"))
    build(parser.parse_args().mode)
