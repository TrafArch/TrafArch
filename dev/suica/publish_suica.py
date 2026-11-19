"""Publish the supplied Suica Reader station database without transforming it.

This is a separate, offline source import. It neither opens nor changes the TU/CU
packages and does not replace their reference-data tooling. The APK is treated as
a ZIP of data; none of its code is loaded or executed.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import zipfile


APK_SHA256 = "5b407a0456f7cf4592ce2964511c642fc6352b04d6a0cc23e855a268df14a132"
DATABASE_SHA256 = "57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd"
ENTRY = "assets/suica_stationcode.db"
FILENAME = "suica_stationcode.db"


def read_source(apk: Path) -> bytes:
    with apk.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != APK_SHA256:
            raise ValueError("source APK SHA256 mismatch; this importer accepts only the reviewed source")
        source.seek(0)
        with zipfile.ZipFile(source) as archive:
            entries = [entry for entry in archive.infolist() if entry.filename == ENTRY]
            if len(entries) != 1:
                raise ValueError("source must contain exactly one original database entry")
            data = archive.read(entries[0])
    if hashlib.sha256(data).hexdigest() != DATABASE_SHA256:
        raise ValueError("source database SHA256 mismatch")
    return data


def inspect_database(data: bytes) -> dict:
    # Only a temporary byte-identical copy is opened, always read-only.
    with tempfile.TemporaryDirectory(prefix="trafarch-suica-inspect-") as temporary:
        path = Path(temporary) / FILENAME
        path.write_bytes(data)
        connection = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True)
        try:
            if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("source database integrity check failed")
            objects = connection.execute("SELECT type,name FROM sqlite_master ORDER BY type,name").fetchall()
            if objects != [
                ("index", "stationcode_index1"),
                ("index", "stationcode_index2"),
                ("table", "android_metadata"),
                ("table", "stationcode"),
            ]:
                raise ValueError("source database schema objects differ")
            columns = [(row[1], row[2].upper(), row[3], row[5]) for row in connection.execute("PRAGMA table_info(stationcode)")]
            if columns != [
                ("_id", "INTEGER", 1, 1),
                ("areacode", "INTEGER", 1, 0),
                ("linecode", "INTEGER", 1, 0),
                ("stationorder", "INTEGER", 1, 0),
                ("companyname", "TEXT", 0, 0),
                ("linename", "TEXT", 0, 0),
                ("stationname", "TEXT", 0, 0),
            ]:
                raise ValueError("source stationcode schema differs")
            tables = {
                name: connection.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]
                for name in ("android_metadata", "stationcode")
            }
            if tables != {"android_metadata": 0, "stationcode": 6435}:
                raise ValueError("source record counts differ")
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version != 20261017:
                raise ValueError("source user_version differs")
            return {"tables": tables, "user_version": version}
        finally:
            connection.close()


def package_manifest(data: bytes, inspected: dict) -> bytes:
    manifest = {
        "format_version": 1,
        "source": {
            "application": "Suica Reader",
            "apk_sha256": APK_SHA256,
            "entry": ENTRY,
            "attribution": "Original station database bundled with the user-provided Suica Reader APK; names, codes, tables and records are preserved verbatim.",
            "license_status": "Database license not established. Third-party Apache notices in the APK do not establish an Apache license for this database.",
        },
        "database": {
            "file": FILENAME,
            "sha256": DATABASE_SHA256,
            "bytes": len(data),
            **inspected,
        },
    }
    return (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def publish(apk: Path, output: Path, verify: bool) -> None:
    data = read_source(apk)
    manifest = package_manifest(data, inspect_database(data))
    target = output / FILENAME
    target_manifest = output / "manifest.json"
    if verify:
        if not target.is_file() or target.read_bytes() != data:
            raise ValueError("published database differs from the original source bytes")
        if not target_manifest.is_file() or target_manifest.read_bytes() != manifest:
            raise ValueError("published manifest differs from the reproducible source manifest")
    else:
        output.mkdir(parents=True, exist_ok=True)
        # Replace complete files only; publish the validating manifest last.
        with tempfile.TemporaryDirectory(prefix=".suica-stage-", dir=output) as staging:
            for destination, content in ((target, data), (target_manifest, manifest)):
                if destination.is_file() and destination.read_bytes() == content:
                    continue
                staged = Path(staging) / destination.name
                staged.write_bytes(content)
                os.replace(staged, destination)
    print(json.dumps({"action": "verified" if verify else "published", "database": str(target), "sha256": DATABASE_SHA256, "records": 6435}, ensure_ascii=False))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-apk", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[2] / "assets" / "suica")
    parser.add_argument("--verify", action="store_true", help="check source identity and exact publication without writing output")
    args = parser.parse_args()
    try:
        publish(args.source_apk.resolve(), args.output_dir.resolve(), args.verify)
    except (OSError, ValueError, sqlite3.Error, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
