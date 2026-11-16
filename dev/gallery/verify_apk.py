"""Verify a built preview APK; no signing passwords are read by this tool."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile


def elf_load_alignment(binary: bytes) -> bool:
    """Check every ELF64 PT_LOAD segment, independently of ZIP alignment."""
    if binary[:6] != b'\x7fELF\x02\x01' or len(binary) < 64:
        return False
    offset = struct.unpack_from('<Q', binary, 32)[0]
    size, count = struct.unpack_from('<HH', binary, 54)
    if size < 56 or count == 0 or offset + size * count > len(binary):
        return False
    alignments = [
        struct.unpack_from('<Q', binary, offset + index * size + 48)[0]
        for index in range(count)
        if struct.unpack_from('<I', binary, offset + index * size)[0] == 1
    ]
    return bool(alignments) and all(value >= 16384 and value % 16384 == 0 for value in alignments)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-version-code", type=int, required=True,
                        help="Latest known consumed Android versionCode; new APK must be higher")
    parser.add_argument("--expected-build-number", type=int, required=True)
    parser.add_argument("--expected-version-name", default="1.0.2-beta.2")
    args = parser.parse_args()
    apk = args.apk.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def run(name: str, *arguments: str) -> str:
        command = [str(args.build_tools / name), *arguments]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", env=os.environ.copy())
        text = result.stdout + result.stderr
        (output / f"{name.split('.')[0]}-{'-'.join(arguments[:2])}.txt").write_text(text, encoding="utf-8")
        if result.returncode:
            raise SystemExit(f"{name} verification failed; inspect public verification log")
        return text

    badging = run("aapt.exe", "dump", "badging", str(apk))
    manifest = run("aapt.exe", "dump", "xmltree", str(apk), "AndroidManifest.xml")
    signatures = run("apksigner.bat", "verify", "--verbose", "--print-certs", str(apk))
    run("zipalign.exe", "-c", "-P", "16", "-v", "4", str(apk))
    identity = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    if identity is None:
        raise SystemExit("Missing APK package metadata")
    label = re.search(r"application-label:'([^']+)'", badging)
    certificate = re.search(r"certificate SHA-256 digest:\s*([a-fA-F0-9]+)", signatures)
    expected_certificate = "3b86c43104ea366997126a8d1600a34b3ccaf83c212a30159eb0853e2e1312b5"
    with zipfile.ZipFile(apk) as archive:
        abis = sorted({name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')})
        crc_ok = archive.testzip() is None
        native_alignment = {
            name: elf_load_alignment(archive.read(name))
            for name in archive.namelist()
            if name.startswith('lib/') and name.endswith('.so')
        }
        gallery_assets = all(f"assets/flutter_assets/assets/gallery/{name}" in archive.namelist()
                             for name in ("fixtures.json", "tunion-logo.svg", "footprints-map.svg"))
    code = int(identity.group(2))
    result = {
        "artifact": apk.name,
        "applicationLabel": label.group(1) if label else None,
        "applicationId": identity.group(1),
        "versionCode": code,
        "versionName": identity.group(3),
        "abis": abis,
        "certificateSha256": certificate.group(1).lower() if certificate else None,
        "originalDeveloperSignature": certificate is not None and certificate.group(1).lower() == expected_certificate,
        "firebaseInitProviderAbsent": "com.google.firebase.provider.FirebaseInitProvider" not in manifest,
        "analyticsComponentsAbsent": "AppMeasurement" not in manifest,
        "releaseNotDebuggable": re.search(r"android:debuggable.*0xffffffff", manifest) is None,
        "zipCrcPassed": crc_ok,
        "zipAlignment16KiBPassed": True,
        "elfLoadAlignment16KiB": native_alignment,
        "galleryAssetsPresent": gallery_assets,
        "minimumVersionCodeExclusive": args.min_version_code,
        "expectedBuildNumber": args.expected_build_number,
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "screenshotsAndVisualComparison": "deferred at user request",
        "deviceInstallation": "not performed",
    }
    result["checks"] = {
        "applicationLabel": result["applicationLabel"] == "TrafArch",
        "applicationId": result["applicationId"] == "com.kajolno.TrafArch",
        "versionName": result["versionName"] == args.expected_version_name,
        "versionCodeAdvances": code > args.min_version_code,
        "versionCodeMatchesBuildNumber": code == args.expected_build_number,
        "originalDeveloperSignature": result["originalDeveloperSignature"],
        "arm64Only": abis == ["arm64-v8a"],
        "firebaseInitProviderAbsent": result["firebaseInitProviderAbsent"],
        "analyticsComponentsAbsent": result["analyticsComponentsAbsent"],
        "releaseNotDebuggable": result["releaseNotDebuggable"],
        "zipCrcPassed": crc_ok,
        "zipAlignment16KiBPassed": result["zipAlignment16KiBPassed"],
        "elfLoadAlignment16KiBPassed": bool(native_alignment) and all(native_alignment.values()),
        "galleryAssetsPresent": gallery_assets,
    }
    result["passed"] = all(result["checks"].values())
    (output / "apk-verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(f"{result['sha256']}  {apk.name}\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result["passed"]:
        failed = ", ".join(key for key, passed in result["checks"].items() if not passed)
        raise SystemExit(f"APK verification failed: {failed}")


if __name__ == "__main__":
    main()
