"""Local-only paths, lossless fingerprints, and rollback-safe publication."""

from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import sqlite3
import tempfile


class DataError(ValueError):
    """A rejected input, conflict, or invalid package."""


def require(condition, message):
    if not condition:
        raise DataError(message)


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)


def sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def local_path(value):
    """CLI paths may be absolute; URL/UNC/traversal/ADS syntax is forbidden."""
    value = str(value)
    require(value and "\x00" not in value, "Empty path or NUL in path")
    normalized = value.replace("\\", "/")
    require(not normalized.startswith("//"), "Network/UNC paths are not accepted")
    require(not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", value)
            or bool(re.match(r"^[A-Za-z]:[/\\]", value)), "URLs are not accepted")
    require(".." not in normalized.split("/"), "Path traversal is not accepted")
    require(not re.search(r"%[0-9a-fA-F]{2}", value), "Encoded paths are not accepted")
    tail = normalized[2:] if re.match(r"^[A-Za-z]:/", normalized) else normalized
    require(":" not in tail, "Path streams and URL schemes are not accepted")
    return Path(value).resolve()


def child_path(root, value):
    """A manifest-controlled path cannot escape its own local directory."""
    require(isinstance(value, str), "Manifest paths must be strings")
    require(not Path(value).is_absolute() and not PureWindowsPath(value).drive,
            "Manifest paths must be relative")
    local_path(value)
    root = Path(root).resolve()
    result = (root / value.replace("\\", "/")).resolve()
    require(result.is_relative_to(root) and result != root,
            "Manifest path escapes its directory")
    return result


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    with Path(path).open(encoding="utf-8-sig") as handle:
        return json.load(handle, object_pairs_hook=_unique_object,
                         parse_constant=lambda x: (_ for _ in ()).throw(
                             DataError(f"Non-finite JSON number: {x}")))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                   indent=2, allow_nan=False) + "\n",
                          encoding="utf-8", newline="\n")


def quote(identifier):
    return '"' + identifier.replace('"', '""') + '"'


def open_readonly(path):
    connection = sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)
    connection.execute("PRAGMA query_only=ON")
    connection.execute("PRAGMA trusted_schema=OFF")
    return connection


def json_cell(value):
    return {"base64": base64.b64encode(value).decode("ascii")} if isinstance(value, bytes) else value


def sorted_rows(connection, table):
    return sorted(canonical([json_cell(v) for v in row]).encode("utf-8")
                  for row in connection.execute("SELECT * FROM " + quote(table)))


def table_inventory(connection):
    """Exact baseline algorithm: sorted UTF-8 rows prefixed by uint64be length."""
    tables = []
    for (name,) in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name").fetchall():
        rows = sorted_rows(connection, name)
        content = hashlib.sha256()
        for row in rows:
            content.update(len(row).to_bytes(8, "big"))
            content.update(row)
        tables.append({"table": name,
                       "columns": [r[1] for r in connection.execute("PRAGMA table_info(" + quote(name) + ")")],
                       "row_count": len(rows), "sorted_content_sha256": content.hexdigest()})
    return tables


def inspect_database(path):
    connection = open_readonly(path)
    try:
        return {"file_sha256": sha256(path), "bytes": Path(path).stat().st_size,
                "integrity_check": [r[0] for r in connection.execute("PRAGMA integrity_check")],
                "foreign_key_violations": [list(r) for r in connection.execute("PRAGMA foreign_key_check")],
                "tables": table_inventory(connection)}
    finally:
        connection.close()


def original_schema(connection):
    return {(r[0], r[1]): (r[2], r[3]) for r in connection.execute(
        "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")}


def verify_baseline(path, expected):
    actual = inspect_database(path)
    require(actual["integrity_check"] == ["ok"], f"Integrity failure: {path.name}")
    require(not actual["foreign_key_violations"], f"Foreign key violations: {path.name}")
    tables = {t["table"]: t for t in actual["tables"]}
    for table in expected["tables"]:
        require(tables.get(table["table"]) == table,
                f"Original table differs from baseline: {path.name}/{table['table']}")
    return actual


def publish_files(staged, destination, names, verify):
    """Validate first, replace individual files atomically, manifest last, rollback on failure.

    The caller owns an exclusive writer lock. This is exception-safe, not an OS
    transaction across files; a hard kill between replacements is detectable by
    the runtime manifest hashes. Backups survive if a rollback itself fails.
    """
    staged, destination = Path(staged), Path(destination)
    verify(staged)
    destination.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=".reference-backup-", dir=destination))
    replaced = []
    restore_failed = False
    try:
        for name in names:
            old = child_path(destination, name)
            require(not old.is_symlink(), "Cannot publish through a symlink")
            if old.exists():
                shutil.copyfile(old, backup / name)
        for name in names:
            os.replace(staged / name, destination / name)
            replaced.append(name)
        verify(destination)
    except BaseException as error:
        try:
            for name in reversed(replaced):
                if (backup / name).exists():
                    os.replace(backup / name, destination / name)
                else:
                    (destination / name).unlink(missing_ok=True)
        except OSError as rollback_error:
            restore_failed = True
            raise DataError(f"Publication failed; rollback failed; recover from {backup}: {rollback_error}") from error
        raise
    finally:
        if not restore_failed:
            shutil.rmtree(backup)
