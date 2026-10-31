"""Verify a built preview APK; no signing passwords are read by this tool."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
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
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "screenshotsAndVisualComparison": "deferred at user request",
        "deviceInstallation": "not performed",
    }
    (output / "apk-verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text(f"{result['sha256']}  {apk.name}\n", encoding="utf-8")
    assert result["applicationLabel"] == "TrafArch"
    assert result["applicationId"] == "com.kajolno.TrafArch"
    assert result["originalDeveloperSignature"]
    assert result["abis"] == ["arm64-v8a"]
    assert code > 4066
    assert result["firebaseInitProviderAbsent"] and result["analyticsComponentsAbsent"]
    assert result["releaseNotDebuggable"] and crc_ok
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
