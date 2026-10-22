"""Frozen input loading, package construction, and content validation."""

from __future__ import annotations

import os
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile

from . import TOOL_VERSION
from .common import (canonical, child_path, digest, local_path, open_readonly,
                     original_schema, publish_files, read_json, require, sha256,
                     verify_baseline, write_json)
from .normalize import normalize_documents, validate_documents

FILENAMES = {p: f"TrafArch_Database_{p}.sqlite" for p in ("TU", "CU")}
MANIFEST = "reference_manifest.json"
METADATA_SQL = "CREATE TABLE reference_package(key TEXT PRIMARY KEY,value TEXT NOT NULL)"
DOCUMENTS_SQL = "CREATE TABLE reference_documents(name TEXT PRIMARY KEY,json TEXT NOT NULL)"
ROLES = {"tu_database": ("TU", "sqlite"), "cu_database": ("CU", "sqlite"),
         "tu_prefixes": ("TU", "json"), "tu_meta": ("TU", "json"),
         "tu_issuers": ("TU", "json"), "tu_terminals": ("TU", "json"), "cu_catalog": ("CU", "json")}


def tool_fingerprint():
    return digest({p.name: sha256(p) for p in sorted(Path(__file__).parent.glob("*.py"))})


def load_inputs(config_path):
    config_path = local_path(config_path)
    config = read_json(config_path)
    require(isinstance(config, dict), "Source configuration must be an object")
    require(config.get("format_version") == 1, "Unsupported source configuration version")
    require(isinstance(config.get("sources"), list), "sources must be a list")
    inputs = {}
    for spec in config["sources"]:
        require(isinstance(spec, dict), "Invalid source specification")
        source_id = spec.get("id")
        require(isinstance(source_id, str) and source_id and source_id not in inputs, "Duplicate or missing source id")
        require(spec.get("protocol") in ("TU", "CU"), "Explicit TU/CU source namespace is required")
        require(spec.get("kind") in ("sqlite", "json"), "Only frozen SQLite/JSON inputs are accepted")
        require(isinstance(spec.get("origin"), str) and spec["origin"], "Source origin is required")
        require(type(spec.get("priority")) is int, "Source priority is required")
        path = child_path(config_path.parent, spec.get("file"))
        require(path.is_file(), f"Missing local source: {spec.get('file')}")
        require(sha256(path) == spec.get("sha256"), f"Frozen source hash mismatch: {source_id}")
        require(path.stat().st_size == spec.get("bytes"), f"Frozen source size mismatch: {source_id}")
        role = spec.get("role", source_id)
        if role in ROLES:
            require(role == source_id, "Required roles must use their stable source id")
            require((spec["protocol"], spec["kind"]) == ROLES[role], "Source role/namespace mismatch")
        else:
            require(role in ("tu_overrides", "tu_lookup") and spec["protocol"] == "TU" and spec["kind"] == "json",
                    f"Unsupported source role: {role}; CSV station imports require reviewed mapping")
            if role == "tu_lookup":
                require(source_id == "tu_lookup", "TU lookup role uses its stable source id")
        inputs[source_id] = {"path": path, "spec": spec}
        if spec["kind"] == "json":
            inputs[source_id]["json"] = read_json(path)
    require(set(ROLES).issubset(inputs), "Missing required frozen source roles")
    policy_path = child_path(config_path.parent, config.get("policy"))
    policy = read_json(policy_path)
    baseline_path = child_path(config_path.parent, config.get("baseline"))
    baseline = read_json(baseline_path)
    require(isinstance(baseline, dict), "Baseline must be an object")
    for protocol in FILENAMES:
        source = inputs[protocol.lower() + "_database"]["path"]
        expected = baseline.get(FILENAMES[protocol])
        require(isinstance(expected, dict), "Baseline is missing a protocol")
        require(sha256(source) == expected.get("file_sha256"), "Baseline source file hash mismatch")
        actual = verify_baseline(source, expected)
        require(actual["tables"] == expected["tables"], "Frozen original contains unexpected tables")
        require(not any(t["table"].startswith("reference_") and t["table"] in
                        ("reference_package", "reference_documents") for t in actual["tables"]),
                "Frozen input must be an original BEFORE package build")
    return config, inputs, policy, baseline, policy_path, baseline_path


def prepare(config_path):
    config, inputs, policy, baseline, policy_path, baseline_path = load_inputs(config_path)
    docs, report = normalize_documents(inputs, policy)
    for protocol, documents in docs.items():
        validate_documents(protocol, documents)
    return config, inputs, policy, baseline, docs, report, policy_path, baseline_path


def version_for(protocol, sources, policy, documents):
    material = {"protocol": protocol, "format_version": 1, "tool_version": TOOL_VERSION,
                "tool_sha256": tool_fingerprint(), "sqlite_version": sqlite3.sqlite_version,
                "sources": [s for s in sources if s["protocol"] == protocol],
                "policy": policy, "documents": documents}
    return digest(material)


def verify_schema(connection):
    for name, columns in (("reference_package", [("key", "TEXT", 0, 1), ("value", "TEXT", 1, 0)]),
                          ("reference_documents", [("name", "TEXT", 0, 1), ("json", "TEXT", 1, 0)])):
        actual = [(r[1], r[2], r[3], r[5]) for r in connection.execute(f'PRAGMA table_info("{name}")')]
        require(actual == columns, f"Wrong package table schema: {name}")


def validate(output, config_path, baseline_override=None):
    output = local_path(output)
    config, inputs, policy, baseline, docs, normalization, policy_path, baseline_path = prepare(config_path)
    require(not normalization["unresolved"], "Unresolved input conflicts")
    if baseline_override:
        require(read_json(local_path(baseline_override)) == baseline, "External baseline differs from frozen baseline")
    manifest = read_json(output / MANIFEST)
    require(isinstance(manifest, dict), "Published manifest must be an object")
    require(manifest.get("format_version") == 1 and manifest.get("tool_version") == TOOL_VERSION,
            "Unsupported published manifest/tool version")
    require(manifest.get("sources") == config["sources"], "Manifest source provenance differs from configuration")
    require(manifest.get("normalization") == normalization, "Manifest normalization/provenance differs")
    require(manifest.get("policy_sha256") == sha256(policy_path), "Policy digest mismatch")
    require(manifest.get("baseline_sha256") == sha256(baseline_path), "Baseline digest mismatch")
    require(manifest.get("tool_sha256") == tool_fingerprint(), "Tool source digest mismatch; rebuild packages")
    require(manifest.get("sqlite_version") == sqlite3.sqlite_version, "SQLite builder version differs")
    require(set(manifest.get("packages", {})) == {"TU", "CU"}, "Manifest must contain independent TU and CU packages")
    result = {"status": "valid", "packages": {}}
    for protocol, filename in FILENAMES.items():
        item = manifest["packages"][protocol]
        path = child_path(output, item.get("file"))
        require(item["file"] == filename, "Unexpected package basename")
        require(path.stat().st_size == item.get("bytes") and sha256(path) == item.get("sha256"),
                f"Package byte size/hash mismatch: {protocol}")
        actual = verify_baseline(path, baseline[filename])
        counts = {t["table"]: t["row_count"] for t in actual["tables"]}
        require(counts == item.get("tables"), f"Manifest table counts mismatch: {protocol}")
        expected_names = {t["table"] for t in baseline[filename]["tables"]} | {"reference_package", "reference_documents"}
        require(set(counts) == expected_names, f"Unexpected package tables: {protocol}")
        connection = open_readonly(path)
        original = open_readonly(inputs[protocol.lower() + "_database"]["path"])
        try:
            verify_schema(connection)
            old_schema = original_schema(original)
            new_schema = original_schema(connection)
            require(all(new_schema.get(k) == v for k, v in old_schema.items()), "Original schema/index/view changed")
            stored_docs = dict(connection.execute("SELECT name,json FROM reference_documents ORDER BY name"))
            require(stored_docs == {name: canonical(doc) for name, doc in docs[protocol].items()},
                    f"Runtime JSON is not the canonical build document: {protocol}")
            actual_docs = {name: json.loads(value) for name, value in stored_docs.items()}
            validate_documents(protocol, actual_docs)
            require(actual_docs == docs[protocol], f"Runtime documents differ from normalized sources: {protocol}")
            metadata = dict(connection.execute("SELECT key,value FROM reference_package"))
            content_version = version_for(protocol, config["sources"], policy, docs[protocol])
            expected_meta = {"format_version": "1", "protocol": protocol,
                             "tool_version": TOOL_VERSION, "content_version": content_version}
            require(metadata == expected_meta and item.get("content_version") == content_version,
                    f"Wrong package metadata/content version: {protocol}")
            require(connection.execute("PRAGMA user_version").fetchone() == original.execute("PRAGMA user_version").fetchone(),
                    "Original user_version changed")
        finally:
            connection.close()
            original.close()
        result["packages"][protocol] = {"sha256": item["sha256"], "content_version": item["content_version"],
                                        "original_tables_unchanged": len(baseline[filename]["tables"]),
                                        "integrity_check": actual["integrity_check"],
                                        "foreign_key_violations": actual["foreign_key_violations"],
                                        "tables": counts}
    return result


def build(config_path, output):
    config_path, output = local_path(config_path), local_path(output)
    config, inputs, policy, baseline, docs, normalization, policy_path, baseline_path = prepare(config_path)
    require(not normalization["unresolved"], "Unresolved conflicts; run inspect --config for candidate details: "
            + ", ".join(normalization["unresolved"]))
    protected = [v["path"] for v in inputs.values()] + [config_path, policy_path, baseline_path]
    require(not output.is_relative_to(config_path.parent), "Build output cannot be inside frozen data/configuration")
    for filename in [*FILENAMES.values(), MANIFEST]:
        target = child_path(output, filename)
        require(target not in protected, "Output aliases an input")
        if target.exists():
            require(not any(os.path.samefile(target, source) for source in protected), "Output hard-links an input")
    for protocol in docs:
        validate_documents(protocol, docs[protocol])
    output.mkdir(parents=True, exist_ok=True)
    lock = output / ".reference-build.lock"
    with lock.open("x", encoding="utf-8") as handle:
        handle.write("Offline reference package publication in progress\n")
    try:
        with tempfile.TemporaryDirectory(prefix=".reference-stage-", dir=output) as temp:
            stage = Path(temp)
            manifest = {"format_version": 1, "tool_version": TOOL_VERSION,
                        "sources": config["sources"], "packages": {}, "normalization": normalization,
                        "tool_sha256": tool_fingerprint(), "sqlite_version": sqlite3.sqlite_version,
                        "policy_sha256": sha256(policy_path), "baseline_sha256": sha256(baseline_path)}
            for protocol, filename in FILENAMES.items():
                target = stage / filename
                shutil.copyfile(inputs[protocol.lower() + "_database"]["path"], target)
                content_version = version_for(protocol, config["sources"], policy, docs[protocol])
                connection = sqlite3.connect(target)
                try:
                    connection.execute("PRAGMA journal_mode=DELETE")
                    connection.execute("PRAGMA synchronous=FULL")
                    with connection:
                        connection.execute(METADATA_SQL)
                        connection.execute(DOCUMENTS_SQL)
                        metadata = {"format_version": "1", "protocol": protocol,
                                    "tool_version": TOOL_VERSION, "content_version": content_version}
                        connection.executemany("INSERT INTO reference_package VALUES (?,?)", sorted(metadata.items()))
                        connection.executemany("INSERT INTO reference_documents VALUES (?,?)",
                                               [(name, canonical(doc)) for name, doc in sorted(docs[protocol].items())])
                finally:
                    connection.close()
                actual = verify_baseline(target, baseline[filename])
                manifest["packages"][protocol] = {"file": filename, "sha256": sha256(target),
                    "bytes": target.stat().st_size, "content_version": content_version,
                    "tables": {t["table"]: t["row_count"] for t in actual["tables"]}}
            write_json(stage / MANIFEST, manifest)
            publish_files(stage, output, [*FILENAMES.values(), MANIFEST], lambda directory: validate(directory, config_path))
        return {"status": "built", "packages": manifest["packages"],
                "resolved_conflicts": len(normalization["conflicts"]), "unresolved_conflicts": 0,
                "diagnostics": len(normalization["diagnostics"])}
    finally:
        lock.unlink(missing_ok=True)
