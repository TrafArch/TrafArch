#!/usr/bin/env python3
"""Publish a developer-maintained TU city-table database and restore baseline CU.

Offline standard-library tool. Never executes source SQL scripts or source code.
Only existing provenance, count metadata and package-version rows are maintained;
all developer city rows and their identifiers remain byte-for-byte values.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile

FILES = {"TU": "TrafArch_Database_TU.sqlite", "CU": "TrafArch_Database_CU.sqlite"}
RAIL_FIELDS = {"M0.W.a", "M0.a0.a", "M0.e0.a", "M0.i0.a"}
MUTABLE_TABLES = {"record_provenance", "source_metadata", "reference_package"}


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def readonly(path):
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    return closing(db)


def counts(db):
    return {r[0]: db.execute("SELECT count(*) FROM " + quote(r[0])).fetchone()[0]
            for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def schema(db):
    return [tuple(r) for r in db.execute(
        "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name")]


def table_rows(db, table):
    return Counter(canonical(list(r)) for r in db.execute("SELECT * FROM " + quote(table)))


def validate(path, spec, protocol):
    data = path.read_bytes()
    if len(data) != spec["bytes"] or digest(data) != spec["sha256"]:
        raise ValueError(protocol + ": manifest digest/size mismatch")
    with readonly(path) as db:
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError(protocol + ": integrity_check failed")
        if db.execute("PRAGMA foreign_key_check").fetchall():
            raise ValueError(protocol + ": foreign key violation")
        metadata = dict(db.execute("SELECT key,value FROM reference_package"))
        if metadata.get("protocol") != protocol or metadata.get("format_version") != "1" or metadata.get("content_version") != spec["content_version"]:
            raise ValueError(protocol + ": reference_package mismatch")
        if counts(db) != spec["tables"]:
            raise ValueError(protocol + ": table counts differ from manifest")
        if "community_reference_rows" in spec["tables"]:
            raise ValueError("Central community table is not accepted")


def maintain(db, source_hash):
    """Keep city data authoritative and complete existing maintenance metadata."""
    db.row_factory = sqlite3.Row
    added = []
    changed_counts = []
    type_counts = Counter()
    total = 0
    for region in db.execute("SELECT * FROM regions").fetchall():
        table = region["table_name"]
        rows = db.execute("SELECT * FROM " + quote(table)).fetchall()
        current_counts = Counter(row["transport_type"] for row in rows)
        type_counts.update(current_counts)
        total += len(rows)
        summary = f"region_{region['region_id']}_transport_summary"
        for item in db.execute("SELECT * FROM " + quote(summary)).fetchall():
            expected = current_counts[item["transport_type"]]
            if item["station_count"] != expected:
                db.execute("UPDATE " + quote(summary) + " SET station_count=? WHERE transport_type=?", (expected, item["transport_type"]))
                changed_counts.append({"table": summary, "type": item["transport_type"], "before": item["station_count"], "after": expected})
        for row in rows:
            if db.execute("SELECT 1 FROM record_provenance WHERE table_name=? AND station_id=?", (table, row["station_id"])).fetchone():
                continue
            if row["source_field"] not in RAIL_FIELDS or row["transport_type"] != "metro":
                raise ValueError(f"Unreviewed missing provenance: {table}/{row['station_id']}")
            raw = json.dumps(list(row), ensure_ascii=False, separators=(",", ":"))
            basis = "Developer-maintained TU city table; original source_field and source_key retained; source SHA256=" + source_hash
            db.execute("INSERT INTO record_provenance VALUES(?,?,?,?,?,?,?,?,?,?)", (
                table, row["station_id"], table, row["station_id"], "TU", "native", "station_mapping", "TU", basis, digest(raw.encode())))
            added.append({"city": region["region_code"], "table": table, **dict(row)})
    actual_view = db.execute("SELECT count(*) FROM all_records").fetchone()[0]
    if actual_view != total:
        raise ValueError(f"all_records omits or duplicates city rows: {actual_view}/{total}")
    source_metadata = dict(db.execute("SELECT name,value FROM source_metadata"))
    replacements = {"station_count": str(total),
                    "transport_type_counts": canonical({k: v for k, v in type_counts.items() if k in {"metro", "bus", "brt", "intercity_rail"}}),
                    "unknown_transport_type_count": str(sum(v for k, v in type_counts.items() if k not in {"metro", "bus", "brt", "intercity_rail"}))}
    for key, value in replacements.items():
        if key not in source_metadata:
            raise ValueError("Missing existing count metadata: " + key)
        if source_metadata[key] != value:
            changed_counts.append({"table": "source_metadata", "key": key, "before": source_metadata[key], "after": value})
            db.execute("UPDATE source_metadata SET value=? WHERE name=?", (value, key))
    return added, changed_counts, total


def replace_set(publications, directory):
    backups = []
    for index, (_, destination) in enumerate(publications):
        backup = directory / f"backup-{index}"
        if destination.exists():
            shutil.copyfile(destination, backup)
            backups.append(backup)
        else:
            backups.append(None)
    done = []
    try:
        for index, (source, destination) in enumerate(publications):
            os.replace(source, destination)
            done.append(index)
    except BaseException:
        errors = []
        for index in reversed(done):
            try:
                if backups[index] is None:
                    publications[index][1].unlink(missing_ok=True)
                else:
                    shutil.copyfile(backups[index], publications[index][1])
            except OSError as error:
                errors.append(str(error))
        if errors:
            raise RuntimeError("Publication and rollback failed: " + "; ".join(errors))
        raise


def run(source_db, baseline_dir, asset_dir, report, verify=False, fixture_output=None):
    source_db, baseline_dir, asset_dir, report = (p.resolve() for p in (source_db, baseline_dir, asset_dir, report))
    if report.is_relative_to(asset_dir) or report == source_db or report.is_relative_to(baseline_dir):
        raise ValueError("Report must be outside inputs and published assets")
    if source_db.is_relative_to(asset_dir) or source_db.is_relative_to(baseline_dir):
        raise ValueError("Developer source must remain separate from published and baseline packages")
    baseline_path = baseline_dir / "reference_manifest.json"
    baseline_bytes = baseline_path.read_bytes()
    manifest = json.loads(baseline_bytes)
    for protocol in FILES:
        validate(baseline_dir / FILES[protocol], manifest["packages"][protocol], protocol)
    source_hash = digest(source_db.read_bytes())
    tool_hash = digest(Path(__file__).read_bytes())
    with readonly(source_db) as source, readonly(baseline_dir / FILES["TU"]) as baseline:
        if schema(source) != schema(baseline):
            raise ValueError("Developer TU schema differs from accepted city-table schema")
        if table_rows(source, "reference_documents") != table_rows(baseline, "reference_documents"):
            raise ValueError("Developer source changes frozen runtime documents; independent review required")
        if source.execute("PRAGMA user_version").fetchone()[0] != baseline.execute("PRAGMA user_version").fetchone()[0]:
            raise ValueError("Developer source changes user_version")
        city_changes = []
        for region in source.execute("SELECT * FROM regions"):
            before_rows = table_rows(baseline, region["table_name"])
            after_rows = table_rows(source, region["table_name"])
            additions = sum((after_rows - before_rows).values())
            removals = sum((before_rows - after_rows).values())
            if additions or removals:
                city_changes.append({"city": region["region_code"], "table": region["table_name"],
                    "added": additions, "removed": removals,
                    "before": sum(before_rows.values()), "after": sum(after_rows.values())})
    if fixture_output:
        fixture_output = fixture_output.resolve()
        if fixture_output == source_db or fixture_output.is_relative_to(asset_dir) or fixture_output.is_relative_to(baseline_dir):
            raise ValueError("Fixture must not overwrite input or asset")
    report.parent.mkdir(parents=True, exist_ok=True)
    frozen = report.parent / "frozen-inputs"
    frozen.mkdir(exist_ok=True)
    frozen_baseline = frozen / "baseline"
    frozen_baseline.mkdir(exist_ok=True)
    frozen_paths = [(source_db, frozen / source_db.name), (baseline_path, frozen_baseline / baseline_path.name),
                    *[(baseline_dir / name, frozen_baseline / name) for name in FILES.values()]]
    for src, destination in frozen_paths:
        if destination.exists() and destination.read_bytes() != src.read_bytes():
            raise ValueError("Frozen input would be overwritten: " + str(destination))
        if not destination.exists():
            shutil.copyfile(src, destination)
    asset_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="trafarch-city-stage-", dir=asset_dir.parent) as temp:
        stage = Path(temp)
        tu_path = stage / FILES["TU"]
        shutil.copyfile(source_db, tu_path)
        version = digest(canonical({"source": source_hash, "baseline_manifest": digest(baseline_bytes), "publisher": tool_hash, "sqlite_version": sqlite3.sqlite_version}).encode())
        with closing(sqlite3.connect(tu_path)) as db:
            with db:
                added, changed_counts, total = maintain(db, source_hash)
                db.execute("UPDATE reference_package SET value=? WHERE key='content_version'", (version,))
        with readonly(source_db) as source, readonly(tu_path) as published:
            if schema(source) != schema(published):
                raise ValueError("Publisher changed developer schema")
            for table in counts(source):
                if table not in MUTABLE_TABLES and not table.endswith("_transport_summary"):
                    if table_rows(source, table) != table_rows(published, table):
                        raise ValueError("Developer table changed: " + table)
            if published.execute("PRAGMA user_version").fetchone()[0] != source.execute("PRAGMA user_version").fetchone()[0]:
                raise ValueError("Publisher changed user_version")
            spec = manifest["packages"]["TU"]
            spec.update(file=FILES["TU"], sha256=digest(tu_path.read_bytes()), bytes=tu_path.stat().st_size, content_version=version, tables=counts(published))
        shutil.copyfile(baseline_dir / FILES["CU"], stage / FILES["CU"])
        descriptor = {"id": "developer_tu_city_database", "protocol": "TU", "kind": "sqlite", "file": source_db.name,
                      "sha256": source_hash, "bytes": source_db.stat().st_size, "content_version": source_hash,
                      "origin": "User-supplied developer-maintained database; authoritative city rows including removals; no inferred row restoration", "priority": 500}
        manifest["sources"].append(descriptor)
        manifest["city_database_update"] = {"source": descriptor, "publisher_sha256": tool_hash,
            "baseline_manifest_sha256": digest(baseline_bytes), "sqlite_version": sqlite3.sqlite_version,
            "provenance_rows_added": len(added), "count_updates": changed_counts,
            "city_business_rows_preserved": True, "cu_restored_to_baseline": True}
        for protocol in FILES:
            validate(stage / FILES[protocol], manifest["packages"][protocol], protocol)
        manifest_path = stage / "reference_manifest.json"
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
        publications = [(stage / name, asset_dir / name) for name in FILES.values()] + [(manifest_path, asset_dir / manifest_path.name)]
        matches = all(dst.exists() and dst.read_bytes() == src.read_bytes() for src, dst in publications)
        if verify and not matches:
            raise ValueError("Published set differs from reproducible developer source revision")
        if not verify and not matches:
            replace_set(publications, stage)
        for protocol in FILES:
            validate(asset_dir / FILES[protocol], manifest["packages"][protocol], protocol)
        if fixture_output:
            fixture_output.parent.mkdir(parents=True, exist_ok=True)
            fixture_output.write_text(json.dumps({"source_sha256": source_hash, "rows": added}, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
        result = {"source_sha256": source_hash, "source_file": source_db.name, "frozen_inputs": str(frozen),
                  "provenance_rows_added": len(added), "added_rows_by_city": dict(Counter(r["city"] for r in added)),
                  "count_updates": changed_counts, "city_rows_total": total, "city_business_rows_preserved": True,
                  "city_changes": city_changes,
                  "schema_preserved": True, "cu_restored_byte_identical": True, "idempotent": matches,
                  "verify_only": verify, "packages": manifest["packages"]}
        report.write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("source-db", "baseline-dir", "asset-dir", "report"):
        parser.add_argument("--" + flag, required=True, type=Path)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--fixture-output", type=Path)
    args = parser.parse_args()
    try:
        result = run(args.source_db, args.baseline_dir, args.asset_dir, args.report, args.verify, args.fixture_output)
    except (ValueError, OSError, sqlite3.Error) as error:
        parser.exit(2, "Publication rejected: " + str(error) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "packages"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
