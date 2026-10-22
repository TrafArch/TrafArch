"""Table, schema and row multiset differences with raw values preserved."""

from collections import Counter
import json

from .common import (inspect_database, open_readonly, original_schema, sha256,
                     sorted_rows)
from .packages import FILENAMES, MANIFEST


def diff_databases(before, after, original_only=False):
    left, right = inspect_database(before), inspect_database(after)
    left_tables = {t["table"]: t for t in left["tables"]}
    right_tables = {t["table"]: t for t in right["tables"]}
    names = set(left_tables) | set(right_tables)
    if original_only:
        names -= {"reference_package", "reference_documents"}
    tables = []
    a, b = open_readonly(before), open_readonly(after)
    try:
        for name in sorted(names):
            if left_tables.get(name) == right_tables.get(name):
                continue
            old = Counter(sorted_rows(a, name)) if name in left_tables else Counter()
            new = Counter(sorted_rows(b, name)) if name in right_tables else Counter()
            tables.append({"table": name, "before": left_tables.get(name), "after": right_tables.get(name),
                           "removed": [{"row": json.loads(row), "count": n} for row, n in sorted((old - new).items())],
                           "added": [{"row": json.loads(row), "count": n} for row, n in sorted((new - old).items())]})
        old_schema, new_schema = original_schema(a), original_schema(b)
        if original_only:
            for name in ("reference_package", "reference_documents"):
                old_schema.pop(("table", name), None)
                new_schema.pop(("table", name), None)
        schema_changes = [{"type": key[0], "name": key[1], "before": old_schema.get(key), "after": new_schema.get(key)}
                          for key in sorted(set(old_schema) | set(new_schema)) if old_schema.get(key) != new_schema.get(key)]
    finally:
        a.close()
        b.close()
    return {"equal": not tables and not schema_changes, "byte_equal": left["file_sha256"] == right["file_sha256"],
            "original_only": original_only, "before_sha256": left["file_sha256"], "after_sha256": right["file_sha256"],
            "table_changes": tables, "schema_changes": schema_changes, "unchanged_tables": len(names) - len(tables)}


def diff_paths(before, after, original_only=False):
    if before.is_file() and after.is_file():
        return diff_databases(before, after, original_only)
    from .common import require
    require(before.is_dir() and after.is_dir(), "diff requires two SQLite files or two package directories")
    packages = {protocol: diff_databases(before / name, after / name, original_only)
                for protocol, name in FILENAMES.items()}
    result = {"packages": packages, "equal": all(p["equal"] for p in packages.values()),
              "byte_equal": all(p["byte_equal"] for p in packages.values())}
    if (before / MANIFEST).is_file() and (after / MANIFEST).is_file():
        result["manifest_byte_equal"] = sha256(before / MANIFEST) == sha256(after / MANIFEST)
        if not original_only:
            result["equal"] &= result["manifest_byte_equal"]
            result["byte_equal"] &= result["manifest_byte_equal"]
    return result
