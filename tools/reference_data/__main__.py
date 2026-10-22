"""Run with python -m tools.reference_data; never invokes network or build tools."""

from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

from . import TOOL_VERSION
from .common import DataError, child_path, inspect_database, local_path, read_json, require, write_json
from .diffing import diff_paths
from .import_csv import convert_csv, convert_prefix_csv
from .packages import FILENAMES, MANIFEST, build, prepare, validate

REPO = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO / "data/reference/sources.json"


def protected_paths(config):
    result = {Path(config).resolve()}
    data = read_json(config)
    result.update(child_path(config.parent, entry["file"]) for entry in data["sources"])
    result.update(child_path(config.parent, data[k]) for k in ("baseline", "policy"))
    result.update((REPO / "assets/data" / filename).resolve() for filename in
                  ("TrafArch_Database_TU.sqlite", "TrafArch_Database_CU.sqlite", "reference_manifest.json"))
    return result


def save_report(path, value, config):
    path = local_path(path)
    require(path.suffix.lower() == ".json", "Reports/imports must use a .json file")
    require(not path.is_relative_to(config.parent / "sources"), "Frozen sources cannot be overwritten")
    require(path not in protected_paths(config), "Report would overwrite a source/configuration/package")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".reference-report-", suffix=".json", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        write_json(temporary, value)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def parser():
    p = argparse.ArgumentParser(description="Offline, lossless TU/CU reference package tooling")
    p.add_argument("--version", action="version", version=TOOL_VERSION)
    commands = p.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Inspect a SQLite file or normalized frozen source configuration")
    inspect.add_argument("path", nargs="?")
    for name in ("build", "validate"):
        command = commands.add_parser(name)
        command.add_argument("--output-dir", default=str(REPO / "assets/data"))
        if name == "validate":
            command.add_argument("--baseline", help="Optional independent baseline content JSON")
    diff = commands.add_parser("diff")
    diff.add_argument("before")
    diff.add_argument("after")
    diff.add_argument("--original-only", action="store_true", help="Exclude only the two added package tables")
    diff.add_argument("--expect-unchanged", action="store_true", help="Exit 3 if content/schema changed")
    imported = commands.add_parser("import-csv")
    imported.add_argument("path")
    imported.add_argument("--protocol", choices=("TU", "CU"), required=True)
    imported.add_argument("--kind", choices=("stations", "card-prefixes"), default="stations")
    imported.add_argument("--source-id", required=True)
    imported.add_argument("--priority", type=int, required=True)
    imported.add_argument("--region")
    imported.add_argument("--decisions", help="Reviewed record-level decisions JSON")
    imported.add_argument("--output", required=True)
    for command in (inspect, *[commands.choices[name] for name in ("build", "validate", "diff", "import-csv")]):
        command.add_argument("--config", default=str(DEFAULT_CONFIG))
        command.add_argument("--report", help="Write complete JSON evidence atomically")
    return p


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    args = parser().parse_args()
    try:
        config = local_path(args.config)
        status = 0
        if args.report and args.command in ("build", "validate"):
            output = local_path(args.output_dir)
            require(local_path(args.report) not in {output / name for name in [*FILENAMES.values(), MANIFEST]},
                    "Report cannot replace a published package or manifest")
        if args.command == "inspect":
            if args.path:
                result = inspect_database(local_path(args.path))
            else:
                _, _, _, _, docs, report, _, _ = prepare(config)
                result = {"documents": docs, "normalization": report}
                status = 2 if report["unresolved"] else 0
        elif args.command == "build":
            result = build(config, local_path(args.output_dir))
        elif args.command == "validate":
            result = validate(local_path(args.output_dir), config, args.baseline)
        elif args.command == "diff":
            result = diff_paths(local_path(args.before), local_path(args.after), args.original_only)
            status = 3 if args.expect_unchanged and not result["equal"] else 0
        else:
            decisions = read_json(local_path(args.decisions)) if args.decisions else None
            source = local_path(args.path)
            destination = local_path(args.output)
            require(source != destination, "CSV output would overwrite its source")
            if args.kind == "card-prefixes":
                result = convert_prefix_csv(source, args.protocol, args.source_id, args.priority, decisions)
            else:
                result = convert_csv(source, args.protocol, args.source_id, args.priority, args.region, decisions)
            status = 2 if result["status"] == "conflicts_require_decisions" else 0
            if not status:
                save_report(destination, result, config)
        if args.report:
            save_report(args.report, result, config)
        if args.report:
            print(json.dumps({"command": args.command, "exit_code": status,
                              "report": str(local_path(args.report)),
                              "status": result.get("status", "different" if result.get("equal") is False else "inspected")},
                             ensure_ascii=False))
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        return status
    except (DataError, OSError, sqlite3.Error, json.JSONDecodeError, csv.Error,
            TypeError, KeyError, ValueError, UnicodeError, AttributeError) as error:
        result = {"status": "rejected", "error": str(error), "command": args.command}
        # Errors are always visible; never turn malformed data into an empty package.
        print(json.dumps(result, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
