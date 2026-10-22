# Frozen offline reference sources

`sources/original-20261020/` contains byte-for-byte copies of the seven original
`assets/data/` inputs, captured **before** the Task 2 package build. Never copy
published packages back into this directory. Neither build nor import overwrites
these files. Historical third-party attribution, source fields, encoded identifiers,
and JSON notes remain in the snapshots.

`sources/baseline-data-content.json` is an unchanged copy of the independent audit
at `../work/refactor-20261020/baseline-data-content.json` (relative to the repository).
It fingerprints all 90 TU and 20 CU original tables. Row serialization is UTF-8,
compact JSON arrays in declared column order, with BLOBs represented by
`{"base64":"..."}`. Sort serialized row bytes lexicographically, feed each length
as an unsigned 8-byte big-endian integer followed by its bytes into SHA-256.
Duplicate rows are retained. Column names and row counts are compared separately.

`sources.json` pins source bytes, SHA-256, namespace, role, version and default
priority. The referenced policy configures per-field/per-domain priorities; these
take precedence over the source's descriptive default. A higher integer wins.
`overrides/normalization_policy.json` also pins the three reviewed content decisions
to their full candidate hashes (including the preserved legacy currency choice).
New or changed equal-priority conflicts fail.
Changing a pinned decision's candidates requires an explicit review and update.

`overrides/card_prefixes.json` starts empty. New reviewed TU prefix supplements can
be supplied using the existing `entries` schema; update their source hash and
version explicitly. CSV import never auto-registers or publishes data.

Full usage, limits, package contract and rollback behavior:
`docs/REFERENCE_DATA_TOOLING.md` in the repository.
