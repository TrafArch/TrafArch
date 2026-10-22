"""Strict, lossless offline conversion of City/Prefix,Code,Type,Line,Station CSV."""

from __future__ import annotations

from collections import defaultdict
import base64
import csv
import io
import json

from .common import digest, require, sha256
from .normalize import digits


def convert_csv(path, protocol, source_id, priority, region=None, decisions=None):
    require(protocol in ("TU", "CU"), "CSV needs explicit TU/CU namespace")
    require(source_id and type(priority) is int, "CSV needs source id and priority")
    original_bytes = path.read_bytes()
    content = original_bytes.decode("utf-8-sig")
    reader = csv.reader(io.StringIO(content, newline=""), strict=True)
    header = next(reader, None)
    require(header is not None, "CSV is empty")
    normalized = [c.strip().upper() for c in header]
    require(normalized in (["CITY", "CODE", "TYPE", "LINE", "STATION"],
                           ["PREFIX", "CODE", "TYPE", "LINE", "STATION"]),
            "CSV header must be City/Prefix,Code,Type,Line,Station")
    prefix_mode = normalized[0] == "PREFIX"
    require(not prefix_mode or bool(region), "Prefix CSV requires an explicit --region; no region inference")
    records, diagnostics, groups = [], [], defaultdict(list)
    for index, row in enumerate(reader, 1):
        require(len(row) == 5, f"CSV record {index}: expected exactly 5 columns")
        city, code, transport, line, station = (v.strip() for v in row)
        require(code, f"CSV record {index}: empty Code")
        require(not region or prefix_mode or not city or city == region,
                f"CSV record {index}: explicit region disagrees with City")
        region_code = region if prefix_mode else (city or region)
        require(region_code, f"CSV record {index}: no region; provide --region")
        key = city + code if prefix_mode else code
        record = {"record": index, "physical_line_end": reader.line_num, "protocol": protocol,
                  "region_code": region_code, "source_key": key, "source_field": normalized[0],
                  "transport_type": transport or None, "line_name": line or None,
                  "station_name": station or None, "raw_cells": row,
                  "raw_value_json": json.dumps(row, ensure_ascii=False, separators=(",", ":"))}
        records.append(record)
        groups[(region_code, key)].append(record)
        if not line and not station:
            diagnostics.append({"kind": "unnamed_record", "record": index})
    require(records, "CSV has no data records")
    decisions = decisions or {}
    require(isinstance(decisions, dict), "CSV decisions must be an object")
    used, conflicts, selected = set(), [], []
    for (city, key), candidates in sorted(groups.items()):
        decision_id = protocol + ":" + city + ":" + key
        values = {tuple(c["raw_cells"]) for c in candidates}
        winner = candidates[0]
        if len(values) > 1:
            signature = digest(candidates)
            decision = decisions.get(decision_id)
            selected_record = decision.get("winner_record") if isinstance(decision, dict) else None
            winner = next((c for c in candidates if c["record"] == selected_record), None)
            accepted = bool(decision and winner and decision.get("reason") and decision.get("candidates_sha256") == signature)
            conflicts.append({"id": decision_id, "candidates_sha256": signature,
                              "candidates": candidates, "decision": decision, "resolved": accepted})
            if accepted:
                used.add(decision_id)
            else:
                winner = None
        if winner:
            selected.append(winner["record"])
    require(not (set(decisions) - used), "CSV decisions are stale or unused")
    return {"format_version": 1, "kind": "station_csv_review", "protocol": protocol,
            "source_id": source_id, "source_sha256": sha256(path), "source_bytes": path.stat().st_size,
            "raw_source_base64": base64.b64encode(original_bytes).decode("ascii"),
            "priority": priority, "header": header, "mode": "prefix" if prefix_mode else "city",
            "records": records, "selected_records": selected, "conflicts": conflicts,
            "diagnostics": diagnostics,
            "status": "conflicts_require_decisions" if any(not c["resolved"] for c in conflicts) else "ready_for_mapping",
            "publication": "Review artifact only; explicit protocol/table/rule mapping is required before adding a new frozen source revision."}


def convert_prefix_csv(path, protocol, source_id, priority, decisions=None):
    """Produce a TU override document consumable by build after source registration."""
    require(protocol == "TU", "Card-prefix override CSV belongs only to TU")
    raw = path.read_bytes()
    reader = csv.reader(io.StringIO(raw.decode("utf-8-sig"), newline=""), strict=True)
    header = next(reader, None)
    require(header is not None and [c.strip().upper() for c in header] ==
            ["PREFIX", "ISSUER", "CARDNAME", "CITY", "PROVINCE", "CURRENCY"],
            "Prefix CSV header must be Prefix,Issuer,CardName,City,Province,Currency")
    records, groups, diagnostics = [], defaultdict(list), []
    for index, cells in enumerate(reader, 1):
        require(len(cells) == 6, f"Prefix CSV record {index}: expected 6 columns")
        prefix = digits(cells[0])
        require(prefix, f"Prefix CSV record {index}: missing prefix")
        entry = dict(zip(("prefix", "issuer", "cardName", "city", "province", "currency"),
                         (c.strip() or None for c in cells)))
        entry["prefix"] = prefix
        record = {"record": index, "physical_line_end": reader.line_num,
                  "raw_cells": cells, "entry": entry}
        records.append(record)
        groups[prefix].append(record)
        if not entry["cardName"]:
            diagnostics.append({"kind": "unnamed_prefix", "record": index})
        if not entry["city"] or len(digits(entry["issuer"])) < 4:
            diagnostics.append({"kind": "unassigned_city", "record": index})
    require(records, "CSV has no data records")
    decisions = decisions or {}
    require(isinstance(decisions, dict), "CSV decisions must be an object")
    entries, conflicts, used = [], [], set()
    for key, candidates in sorted(groups.items()):
        winner = candidates[0]
        if len({digest(c["entry"]) for c in candidates}) > 1:
            decision_id = "TU:prefix:" + key
            signature = digest(candidates)
            decision = decisions.get(decision_id)
            number = decision.get("winner_record") if isinstance(decision, dict) else None
            winner = next((c for c in candidates if c["record"] == number), None)
            accepted = bool(decision and winner and decision.get("reason") and decision.get("candidates_sha256") == signature)
            conflicts.append({"id": decision_id, "candidates_sha256": signature,
                              "candidates": candidates, "decision": decision, "resolved": accepted})
            if accepted:
                used.add(decision_id)
            else:
                winner = None
        if winner:
            entries.append(winner["entry"])
    require(not (set(decisions) - used), "CSV decisions are stale or unused")
    return {"format_version": 1, "kind": "tu_prefix_overrides", "protocol": "TU",
            "source_id": source_id, "source_sha256": sha256(path), "source_bytes": len(raw),
            "raw_source_base64": base64.b64encode(raw).decode("ascii"), "priority": priority,
            "header": header, "records": records, "entries": entries, "conflicts": conflicts,
            "diagnostics": diagnostics,
            "status": "conflicts_require_decisions" if any(not c["resolved"] for c in conflicts) else "ready_for_registration"}
