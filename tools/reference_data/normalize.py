"""Build runtime JSON with reviewed priorities; retain every input in provenance."""

from __future__ import annotations

from collections import defaultdict
import re

from .common import canonical, digest, open_readonly, quote, require, DataError


def digits(value):
    require(value is None or isinstance(value, str), "Identifiers must be strings, never numbers")
    return re.sub(r"[^0-9]", "", value or "")


def text(value):
    require(value is None or isinstance(value, str), "Expected string or null")
    return value


class Resolver:
    def __init__(self, policy):
        self.policy = policy
        self.conflicts = []
        self.provenance = []
        self.diagnostics = []
        self.used_decisions = set()

    def candidate(self, channel, ref, value):
        priority = self.policy["priorities"].get(channel)
        require(type(priority) is int, f"Explicit integer priority missing: {channel}")
        return {"channel": channel, "ref": ref, "priority": priority, "value": value}

    def choose(self, scope, key, candidates):
        require(bool(candidates), f"No candidates for {scope}/{key}")
        candidates = sorted(candidates, key=lambda c: c["ref"])
        values = {canonical(c["value"]) for c in candidates}
        highest = max(c["priority"] for c in candidates)
        top = [c for c in candidates if c["priority"] == highest]
        decision_key = scope + ":" + key
        signature = digest(candidates)
        decision = self.policy["decisions"].get(decision_key)
        selected = None
        resolution = "equal_values"
        if decision is not None:
            require(isinstance(decision, dict), f"Decision must be an object: {decision_key}")
            self.used_decisions.add(decision_key)
            require(decision.get("candidates_sha256") == signature,
                    f"Stale decision (candidates changed): {decision_key}")
            require(bool(decision.get("reason")), f"Decision needs reason: {decision_key}")
            selected = next((c for c in candidates if c["ref"] == decision.get("winner")), None)
            require(selected is not None, f"Unknown decision winner: {decision_key}")
            resolution = "configured_decision"
        elif len({canonical(c["value"]) for c in top}) == 1:
            selected = top[0]
            resolution = "configured_source_priority" if len(values) > 1 else "equal_values"
        if len(values) > 1:
            self.conflicts.append({"id": decision_key, "candidates_sha256": signature,
                                   "candidates": candidates, "resolution": resolution if selected else "unresolved",
                                   "winner": selected["ref"] if selected else None})
        self.provenance.append({"scope": scope, "key": key, "candidates": candidates,
                                "winner": selected["ref"] if selected else None})
        return selected["value"] if selected is not None else None

    def finish(self):
        unused = set(self.policy["decisions"]) - self.used_decisions
        require(not unused, "Stale or unused decisions: " + ", ".join(sorted(unused)))
        unresolved = [c["id"] for c in self.conflicts if c["resolution"] == "unresolved"]
        return {"priorities": self.policy["priorities"], "decisions": self.policy["decisions"],
                "conflicts": self.conflicts, "provenance": self.provenance,
                "diagnostics": self.diagnostics, "unresolved": unresolved}


def table_records(path, table):
    connection = open_readonly(path)
    try:
        cursor = connection.execute("SELECT * FROM " + quote(table) + " ORDER BY rowid")
        names = [d[0] for d in cursor.description]
        return [dict(zip(names, row)) for row in cursor]
    finally:
        connection.close()


def entry_list(document, key="entries"):
    require(isinstance(document, dict) and isinstance(document.get(key), list),
            f"Expected document object with {key} list")
    require(all(isinstance(e, dict) for e in document[key]), f"Malformed {key} entry")
    return document[key]


def normalize_documents(inputs, policy):
    require(isinstance(policy, dict), "Normalization policy must be an object")
    require(policy.get("format_version") == 1, "Unsupported policy version")
    require(isinstance(policy.get("priorities"), dict) and isinstance(policy.get("decisions"), dict),
            "Policy must configure priorities and decisions")
    resolver = Resolver(policy)
    prefix_groups = defaultdict(list)
    city_groups = defaultdict(list)
    raw_records = []
    prefix_json = inputs["tu_prefixes"]["json"]
    meta = inputs["tu_meta"]["json"]
    require(isinstance(meta, dict), "card_meta must be an object")

    def add_prefix(raw, values, channel, ref, raw_key):
        key = values["prefix"]
        raw_records.append({"ref": ref, "raw_key": raw_key, "raw": raw, "normalized_prefix": key})
        if not key:
            resolver.diagnostics.append({"kind": "missing_prefix", "ref": ref})
            return
        prefix_groups[key].append((channel, ref, values, raw_key))

    def add_city(code, name, province, channel, ref):
        if code and name:
            city_groups[code].append(resolver.candidate(channel, ref,
                                     {"code": code, "name": name, "province": province}))
        else:
            resolver.diagnostics.append({"kind": "unassigned_city", "ref": ref,
                                         "code": code, "name": name})

    for index, raw in enumerate(entry_list(prefix_json)):
        ref = f"tu_prefixes/entries/{index}"
        values = {"prefix": digits(raw.get("prefix")), "cardName": text(raw.get("cardName", raw.get("name"))),
                  "city": text(raw.get("city")), "issuer": text(raw.get("issuer")),
                  "currency": text(raw.get("currency")), "province": text(raw.get("province"))}
        add_prefix(raw, values, "tu_prefix_json", ref, raw.get("prefix"))
        issuer = digits(raw.get("issuer"))
        add_city(issuer[-4:] if len(issuer) >= 4 else "", values["city"], values["province"],
                 "tu_city_json", ref)

    for index, raw in enumerate(table_records(inputs["tu_database"]["path"], "card_prefixes")):
        ref = f"tu_database/card_prefixes/{index}"
        values = {"prefix": digits(raw["prefix"]), "cardName": text(raw["card_name"]),
                  "city": text(raw["city_name"]), "issuer": text(raw["issuer"]),
                  "currency": text(raw["currency"]), "province": text(raw["province"])}
        add_prefix(raw, values, "tu_prefix_table", ref, raw["prefix"])

    for index, raw in enumerate(table_records(inputs["tu_database"]["path"], "issuer_city_codes")):
        ref = f"tu_database/issuer_city_codes/{index}"
        issuer = digits(raw["issuer"])
        prefix = digits(raw["prefix"])
        values = {"prefix": (prefix or issuer)[:8], "cardName": text(raw["card_name"]),
                  "city": text(raw["city_name"]), "issuer": issuer}
        add_prefix(raw, values, "tu_prefix_issuer", ref, raw["prefix"])
        code = digits(raw["region_code"]) or (issuer[-4:] if len(issuer) >= 4 else "")
        add_city(code, values["city"], None, "tu_city_issuer", ref)

    for index, raw in enumerate(table_records(inputs["tu_database"]["path"], "regions")):
        add_city(raw["region_code"], raw["region_name"], raw["province"], "tu_city_region",
                 f"tu_database/regions/{index}")

    # Optional, reviewed project overrides share the runtime schemas. Empty by default.
    for input_id, item in sorted(inputs.items()):
        if item["spec"].get("role") != "tu_overrides":
            continue
        require(item["spec"]["priority"] == policy["priorities"].get("tu_project_override"),
                "Project source priority must agree with the configured override channel")
        if "priority" in item["json"]:
            require(item["json"]["priority"] == item["spec"]["priority"], "Imported override priority disagrees with source descriptor")
        for index, raw in enumerate(entry_list(item["json"])):
            values = {k: text(raw.get(k)) for k in ("cardName", "city", "issuer", "currency", "province")}
            values["prefix"] = digits(raw.get("prefix"))
            add_prefix(raw, values, "tu_project_override", f"{input_id}/entries/{index}", raw.get("prefix"))

    entries = []
    for key, group in sorted(prefix_groups.items()):
        resolver.choose("prefix_identity", key,
                        [resolver.candidate(c, r, raw_key) for c, r, _, raw_key in group])
        entry = {"prefix": key}
        for field in ("cardName", "city", "issuer", "currency", "province"):
            candidates = [resolver.candidate(c, r, v[field]) for c, r, v, _ in group
                          if v.get(field) not in (None, "") or
                          (field == "currency" and c == "tu_prefix_json" and v.get(field) is None)]
            entry[field] = resolver.choose("prefix_" + field, key, candidates) if candidates else None
        if not entry["cardName"]:
            resolver.diagnostics.append({"kind": "unnamed_prefix", "prefix": key})
        if len(key) > 8:
            resolver.diagnostics.append({"kind": "extended_prefix_preserved", "prefix": key,
                                         "note": "Existing runtime lookup checks lengths 8..6; raw extended key is retained without truncation."})
        entries.append(entry)

    currencies = meta.get("currencyByPrefix", {})
    require(isinstance(currencies, dict), "currencyByPrefix must be an object")
    for raw_key, currency in currencies.items():
        key = digits(raw_key)
        require(key and isinstance(currency, str) and currency, "Currency override needs a digit key and nonempty string")
        entry = next((e for e in entries if e["prefix"] == key), None)
        if entry is None:
            resolver.diagnostics.append({"kind": "unmatched_currency_override", "prefix": raw_key})
        else:
            candidates = [resolver.candidate("tu_meta_currency", "tu_meta/currencyByPrefix/" + raw_key, text(currency))]
            if entry["currency"] is not None:
                candidates.append(resolver.candidate("tu_prefix_table", "normalized/" + key, entry["currency"]))
            entry["currency"] = resolver.choose("prefix_currency_override", key, candidates)

    # CardPrefixTable registers the FIRST prefix for an issuer. Make that choice explicit.
    aliases = defaultdict(list)
    for entry in entries:
        issuer = digits(entry.get("issuer"))[:8]
        if issuer and entry["cardName"]:
            aliases[issuer].append(resolver.candidate("tu_issuer_alias", "normalized/" + entry["prefix"], entry["prefix"]))
    alias_winners = {key: resolver.choose("issuer_alias", key, values) for key, values in sorted(aliases.items())}
    entries.sort(key=lambda e: (digits(e.get("issuer"))[:8],
                               e["prefix"] != alias_winners.get(digits(e.get("issuer"))[:8]), e["prefix"]))
    cities = [resolver.choose("city", key, values) for key, values in sorted(city_groups.items())]

    kinds = meta.get("cardKinds") or prefix_json.get("cardKinds", {})
    require(isinstance(kinds, dict), "cardKinds must be an object")
    normalized_kinds = {}
    for key, value in kinds.items():
        require(isinstance(value, str), "cardKinds values must be strings")
        normalized = key.replace(" ", "").upper()
        require(normalized and (normalized not in normalized_kinds or normalized_kinds[normalized] == value),
                "Conflicting normalized cardKinds keys")
        normalized_kinds[normalized] = value

    cu = inputs["cu_catalog"]["json"]
    cu_codes = defaultdict(list)
    for index, entry in enumerate(entry_list(cu)):
        require(isinstance(entry.get("city"), str) and entry["city"].strip(), "CU city must be named")
        codes = {digits(entry.get("postalPrefix")), digits(entry.get("cuCityProjectCode"))} - {""}
        if not codes:
            resolver.diagnostics.append({"kind": "unassigned_cu_catalog", "ref": f"cu_catalog/entries/{index}"})
        if not entry.get("cardName"):
            resolver.diagnostics.append({"kind": "unnamed_cu_card", "ref": f"cu_catalog/entries/{index}"})
        for code in codes:
            cu_codes[code].append(resolver.candidate("cu_catalog", f"cu_catalog/entries/{index}", entry))
    for code, values in sorted(cu_codes.items()):
        winner = resolver.choose("cu_catalog", code, values)
        # Existing schema preserves every raw entry and first-registration semantics.
        if winner is not None and winner != values[0]["value"]:
            raise DataError("CU catalog resolution requires an explicitly reordered reviewed source snapshot")

    docs = {"TU": {"card_prefixes": {"entries": entries, "cardKinds": normalized_kinds},
                   "cities": {"entries": [c for c in cities if c is not None]},
                   "issuers": inputs["tu_issuers"]["json"],
                   "terminal_rules": inputs["tu_terminals"]["json"], "card_meta": meta},
            "CU": {"card_catalog": cu}}
    if 'tu_lookup' in inputs:
        from .tu_lookup import validate_lookup
        docs['TU']['tu_lookup'] = validate_lookup(inputs['tu_lookup']['json'])
    report = resolver.finish()
    report["raw_prefix_records"] = raw_records
    report["input_prefix_counts"] = {
        "card_prefixes": sum(r["ref"].startswith("tu_database/card_prefixes/") for r in raw_records),
        "json_supplements": len(entry_list(prefix_json)),
        "issuer_city_codes": sum(r["ref"].startswith("tu_database/issuer_city_codes/") for r in raw_records)}
    return docs, report


def validate_documents(protocol, documents):
    expected = {"card_prefixes", "cities", "issuers", "terminal_rules", "card_meta"} if protocol == "TU" else {"card_catalog"}
    if protocol == 'TU' and 'tu_lookup' in documents:
        from .tu_lookup import validate_lookup
        expected.add('tu_lookup')
        validate_lookup(documents['tu_lookup'])
    require(set(documents) == expected, f"Wrong runtime document names for {protocol}")
    if protocol == "CU":
        for entry in entry_list(documents["card_catalog"]):
            require(isinstance(entry.get("city"), str) and entry["city"].strip(), "Invalid CU catalog city")
            for key in ("postalPrefix", "cuCityProjectCode", "province", "cardName", "cardNameStatus", "codeStatus", "type"):
                text(entry.get(key))
        return
    entries = entry_list(documents["card_prefixes"])
    require(len({e.get("prefix") for e in entries}) == len(entries), "Duplicate normalized prefix")
    for entry in entries:
        require(isinstance(entry.get("prefix"), str) and entry["prefix"].isascii()
                and entry["prefix"].isdigit(), "Invalid normalized prefix")
        for key in ("cardName", "issuer", "city", "currency", "province"):
            text(entry.get(key))
    require(isinstance(documents["card_prefixes"].get("cardKinds"), dict), "cardKinds missing")
    cities = entry_list(documents["cities"])
    require(len({e.get("code") for e in cities}) == len(cities), "Duplicate TU city code")
    for city in cities:
        require(set(city) == {"code", "name", "province"}, "Wrong normalized city schema")
        require(isinstance(city["code"], str) and city["code"] and isinstance(city["name"], str)
                and city["name"], "Invalid TU city")
        text(city["province"])
    issuer_keys = set()
    for entry in entry_list(documents["issuers"]):
        issuer = entry.get("issuerId")
        require(isinstance(issuer, str) and issuer, "Issuer fingerprint needs issuerId")
        key = issuer.replace(" ", "").replace(":", "").upper()
        require(key not in issuer_keys, "Duplicate issuer fingerprint needs a reviewed source decision")
        issuer_keys.add(key)
        for field in ("cityCode", "cityName", "operator", "cardFamily"):
            text(entry.get(field))
    rule_ids = set()
    for rule in entry_list(documents["terminal_rules"], "rules"):
        require(isinstance(rule.get("id"), str) and rule["id"] not in rule_ids, "Terminal rule id must be unique")
        rule_ids.add(rule["id"])
        require(type(rule.get("priority", 0)) is int, "Terminal rule priority must be an integer")
        match = rule.get("match")
        require(isinstance(match, dict) and any(match.get(k) for k in ("terminalPrefix", "cityCode", "issuerId")),
                "Terminal rule must have a specific match context")
        for value in match.values():
            text(value)
        require(isinstance(rule.get("layout", {}), dict), "Invalid terminal rule layout")
        for bounds in rule.get("layout", {}).values():
            require(isinstance(bounds, list) and len(bounds) == 2 and all(type(n) is int for n in bounds)
                    and 0 <= bounds[0] < bounds[1] <= 12, "Terminal layout must be a valid [start,end) within 12 digits")
    require(isinstance(documents["card_meta"], dict), "Invalid card_meta")
