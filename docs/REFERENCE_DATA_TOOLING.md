# Offline reference data tooling

Developer-maintained TU city databases use the tracked offline publisher
documented in [CITY_DATABASE_UPDATE.md](CITY_DATABASE_UPDATE.md). Station records
remain in each existing city table. The former shared community table and its
importer have been removed; CU is restored to its preceding published package.

The Python standard-library CLI builds TU and CU independently usable SQLite
assets from frozen local inputs. It performs no network requests and invokes no
Flutter, Gradle, Android, emulator, device, or test commands. Python 3.11 or newer
is required. Run the examples from the repository root.

The TU lookup regression uses the tracked frozen source in
`test/fixtures/reference/tu-lookup-20261021.json`, with provenance documented
beside it. Its hash is checked against the published manifest before assertions;
running Flutter tests does not require the ignored local `data/` directory.

## Published contract

Outputs retain the runtime asset names:

* `assets/data/TrafArch_Database_TU.sqlite`
* `assets/data/TrafArch_Database_CU.sqlite`
* `assets/data/reference_manifest.json`

Each package preserves every original table, row, index, view, raw identifier,
source field and `PRAGMA user_version`. The baseline build appends these two
publication tables; current developer city updates retain this structure:

```sql
CREATE TABLE reference_package(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE reference_documents(name TEXT PRIMARY KEY,json TEXT NOT NULL);
```

Metadata contains exactly four string-valued keys: `format_version` = `1`,
`protocol` = `TU` or `CU`, `content_version`, and `tool_version` = `1.0.0`.
Runtime documents are canonical compact JSON:

| Protocol | Document | Schema |
|---|---|---|
| TU | `card_prefixes` | `{"entries":[{"prefix","cardName","city","issuer","currency","province"}],"cardKinds":{...}}` |
| TU | `cities` | `{"entries":[{"code":"...","name":"...","province":null}]}` |
| TU | `issuers` | Existing issuer-fingerprint JSON, including metadata and `entries` |
| TU | `terminal_rules` | Existing terminal-rule JSON, including metadata and `rules` |
| TU | `card_meta` | Existing card-kind/currency metadata JSON |
| CU | `card_catalog` | Existing CU catalog (all entries/status fields unchanged), plus `issuerNames` and `nameOverrides` arrays of verbatim snake_case row objects from `cu_card_names` and `cu_name_overrides` |

The manifest has required top-level `format_version:1`, `tool_version`,
`sources:[...]`, and `packages:{TU:{...},CU:{...}}`. Each package contains `file`
(basename), final closed-file `sha256`, `bytes`, `content_version`, and
`tables:{table_name:row_count}`. Additional audit fields record `normalization`
(priorities, decisions, every conflict, field provenance, raw prefix records,
diagnostics), policy/baseline/tool hashes and the SQLite engine version. Runtime
consumers may ignore these additional audit fields.

The CU package's `station_lookup`, `terminal_index`, `stations`, `routes`,
`cu_prefix_dictionary`, `bus_routes`, rule tables and source provenance are all
local to that file. TU is not attached or queried. No `kb_*` rebuild is required:
runtime queries use the preserved original tables and indexes. This tool does not
edit Dart runtime behavior or install packages onto devices.

## Source and normalization policy

The seven files in `data/reference/sources/original-20261020/` were frozen from
the original assets before the first build. Their pinned hashes are checked on
every build/validation. The baseline copy under `sources/` is byte-identical to
the independent pre-refactor audit; rebuilding never regenerates that baseline.
Do not overwrite a frozen snapshot. A later source revision gets a new directory,
explicit source manifest changes and a reviewed baseline change.

The preceding TU revision is `sources/user-tu-afdaca5f8ff3-source-v3/`, derived from
user upload SHA256 `afdaca5f8ff314437f82f8fd0bc06fb70575409e467457e2186e281ac834fcd3`.
All uploaded station rows are preserved. Only Fuzhou two-line source metadata,
transport summary and provenance are corrected, along with the upload's accidental
Chuzhou summary count (121 restored to its actual 14); stale package tables are removed
from the new source copy and recreated by the CLI. This does not independently
verify official station codes or operating status. The new baseline retains the
original CU inventory. LF copies of `card_prefixes.json` and `tu-lookup-20261021.json`
retain their existing pinned hashes without modifying CRLF checkout originals.
The local ignored `tools/revise_uploaded_tu.py` reproduces the source revision;
run it with the upload path before the normal build workflow in a clean checkout.

The current TU source revision is `sources/tu-shenzhen-compat-20261025/`. It copies
that preceding frozen TU database and freezes `tu-shenzhen-5840.sqlite` (SHA256
`2bea9a453673e5a32615abc561f424722539878721860f7046989d8c5af5852e`).
The local ignored `tools/import_shenzhen_tu_compat.py` reproduces the import from
the pre-import `sources.json`; it refuses to overwrite an existing revision:

```powershell
python -X utf8 -m tools.import_shenzhen_tu_compat D:\iteam\TripReader-1.7.17-cn\analysis\reference-data\tu-shenzhen-5840.sqlite
python -X utf8 -m tools.reference_data build
python -X utf8 -m tools.reference_data validate
```

All 326 simplified-Chinese rows and raw values are preserved, including
`source_field=M0.y.b`, `source_key=5180...`, and `source_region_code=5840`.
There are 295 named station records and 31 prefix/operator records; nine unknown
transport types remain NULL. These are **compatibility data, not native TU codes**.
The reviewed rule from `C0597u0.java:592-596` applies only to TU city `5840`, a
16-HEX POS beginning `00000002`, and longest-prefix lookup (minimum length 5)
of `5180 + POS.substring(8)`. Region 42 identifies 深圳 / 广东 / 5840 while
`region_aliases` explicitly retains dictionary ownership under 5180.
Per-row provenance uses `copy_role=compatibility_copy` and
`native_namespace=lookup_key_namespace=local_terminal_or_route`.
`all_records` appends the provenance-joined rows; `native_records` filters
`copy_role='native'` so compatibility entries cannot be presented as native.
The transport summary retains the four known types; unknown counts are recorded
separately in metadata. Global counts are recomputed from actual records (41
regions, 7,811 dictionary records), correcting stale inherited totals without
changing the original 40 city tables. The CU baseline is retained unchanged.

Publication verification on 2026-10-25: after the user closed Navicat's database
connection, the normal `build` and `validate` commands successfully published to
`assets/data/`. Integrity, foreign keys and manifest provenance checks passed.
The TU package SHA256 is
`6632ff0aa4511eeb0d85cfe97da28203045aa2782f9d065c69eb8178ae4a517c`.
The separate `assets/shenzhen-compat-verification/` output is not used at runtime.

The preceding multilingual CU revision is `sources/cu-card-names-20261025/`. It copies the
original frozen CU file without changing any of its 20 tables, indexes, views or
user_version, then adds five tables. The baseline updates CU only; TU's source
and baseline inventory remain unchanged. The frozen incoming `cu-card-names.sqlite`
SHA256 is `82ca546ab9f16106b672bfc03641319a0cde046c406f3c11e78ec4fc7aa49ff8`.
The ignored local importer refuses to overwrite revisions:

```powershell
python -X utf8 -m tools.import_cu_card_names D:\iteam\TripReader-1.7.17-cn\analysis\reference-data\cu-card-names.sqlite
python -X utf8 -m tools.reference_data build
python -X utf8 -m tools.reference_data validate
```

Reproduce the import from the pre-import `sources.json` in a separate checkout.
`tools/` is ignored by git: retain/distribute the importer and modified
`tools/reference_data/normalize.py` separately when handing off the data.

The current CU revision is `sources/cu-card-names-zh-cn-20261025/`.
From the preceding revision's `sources.json`, reproduce it with:

```powershell
python -X utf8 -m tools.import_cu_card_names --simplify-zh-cn
python -X utf8 -m tools.reference_data build
python -X utf8 -m tools.reference_data validate
```

The importer refuses to overwrite an existing revision and retains the old frozen
multilingual snapshot. It drops only `name_zh_tw`, `name_en`, `name_ja` from the two
naming tables, preserving all 36 Chinese names, the Shanghai rule, and provenance
verbatim. The new baseline changes CU only. All 20 original tables and the 17
ordinary-CU number rules remain unchanged. Current schema:

* `cu_card_names` (36): `issuer_code TEXT PRIMARY KEY CHECK(length(issuer_code)=8)`,
  `name_zh_cn`, `source_field`, `source_path`
  (all TEXT NOT NULL), `source_line INTEGER NOT NULL`.
* `cu_name_overrides` (1): `rule_id TEXT PRIMARY KEY`, `issuer_code TEXT NOT NULL`
  references `cu_card_names(issuer_code)`; `requires_map_match`, `min_raw_length`,
  `byte_index`, `high_nibble` (INTEGER NOT NULL); `name_zh_cn` and `source_path`
  (TEXT NOT NULL), `source_line INTEGER NOT NULL`. The Shanghai override retains
  issuer `86982000`, map-match flag 1, minimum raw length 30, byte index 28 and
  high nibble 4. Indices are zero-based.
* `cu_recognition_steps` (7): `step_order INTEGER PRIMARY KEY`, `stage`, `logic`,
  `source_path` (TEXT NOT NULL), `source_line INTEGER NOT NULL`.
* `cu_name_metadata` (10): `key TEXT PRIMARY KEY, value TEXT NOT NULL`.
* `cu_card_number_rules` (17): `rule_id TEXT PRIMARY KEY`, nullable
  `city_code TEXT`, `branch_scope`, `logic`, `source_path`, `source_method`
  (TEXT NOT NULL), `source_line_start`, `source_line_end` (INTEGER NOT NULL).
  These are source-attributed ordinary-CU switch rules from TripReader 1.7.17-cn
  `C0304d.java:4582-4768`, method `m791g`: 16 city cases plus a NULL-city default.
  Helper names and branch exclusions are retained explicitly; these are metadata,
  not personal card numbers, executable runtime rules or an official CU registry.

`cu_name_metadata.language_order` is now `zh-CN (source language index 1)`.
Recognition step 6 describes the fixed Chinese projection, and step 5 uses the
retained Chinese override label. Other source-attributed technical English,
recognition steps and metadata are not UI translations and remain unchanged.
The generated `card_catalog.issuerNames` / `nameOverrides` contain only
`name_zh_cn` plus their existing identifiers, bounds and provenance.
Normalization validates exact naming field sets (rejecting removed language
fields), uppercase eight-hex issuer strings, uniqueness, nonempty Chinese names,
source locations, integer bounds and override issuer references. It neither
renames snake_case fields nor adds these names to legacy `entries`. No new runtime
JSON document is introduced. Rules and recognition metadata remain SQLite tables.
The shared normalizer tool hash changes both package content versions, so a CU-only
data revision also rebuilds TU bytes; this does not imply changes to TU dictionaries.

The TU prefix projection includes all **429** rows in `card_prefixes`, **428**
JSON supplement entries and **347** `issuer_city_codes` rows. All 1,204 input
records and their raw keys are preserved in manifest provenance; the original
tables and JSON snapshot bytes also remain intact. Numeric-looking identifiers
are strings throughout. The database's raw `\\r\\n310517001017` spelling is
retained even though its runtime prefix becomes `310517001017`.

The implementation follows the inspected `KnowledgeBase.fromJsonStrings`,
`_mergePrefixEntries` and `_regionCityInfos` semantics, with the approved addition
of the full prefix table and exclusion of CU cities:

| Domain | Priority (larger wins) |
|---|---|
| Prefix fields | Project supplement 500; currency metadata 400; issuer city table 300; full prefix table 200; JSON 100 |
| TU city objects | TU `regions` 300; TU issuer city table 200; JSON-derived city 100 |
| Issuer reverse lookup | Explicit decision required for differing prefixes sharing an issuer |
| Card kinds | Nonempty `card_meta.cardKinds` replaces JSON `cardKinds` as a whole, matching the current runtime |
| CU catalog | Original catalog order and status metadata preserved; divergent repeated keys require review |

Empty prefix fields do not erase known values unless an explicit decision preserves
the legacy null currency described below. City priority selects a complete
`{code,name,province}` object; a null province from the preferred source remains
null. Neither CU `regions` nor CU `region_codes` contributes to TU cities.
Thus TU `1210` remains 石家庄 and CU `1210` remains 锦州.

Three existing content conflicts have explicit candidate-hash decisions:

* `prefix_cardName:31050608`: keep `issuer_city_codes`'s 福路通·e通卡, matching
  the existing merge; retain 福路通·易通卡 in the full table and provenance.
* `city:8210`: keep TU `regions`' 兰州 / 兰州新区, matching the existing
  region-first city lookup; retain the individual source names.
* `prefix_currency:31048500`: keep the existing runtime's null currency. The
  previously unused full prefix table says `HKD`; that raw value remains intact.
  Adopting it would change wallet-display behavior and requires a separate review.

Configured priorities resolve differing ranks and are reported. Equal-priority
different values are rejected unless `decisions` names an exact candidate and
its candidate-set SHA-256 with a reason. A changed/stale/unused decision is also
rejected. Unnamed, unassigned, unmatched currency and extended prefix records are
listed separately. Unknown names, provinces, region codes and line codes are
never guessed. Extended prefix keys are retained: the inspected runtime currently
looks up prefix lengths 8 through 6, so retaining a longer key does not claim it
is newly recognized by the application.

## CLI commands

```powershell
python -X utf8 -m tools.reference_data --help
python -X utf8 -m tools.reference_data inspect
python -X utf8 -m tools.reference_data inspect data/reference/sources/original-20261020/TrafArch_Database_TU.sqlite
python -X utf8 -m tools.reference_data build
python -X utf8 -m tools.reference_data validate
python -X utf8 -m tools.reference_data diff data/reference/sources/original-20261020/TrafArch_Database_TU.sqlite assets/data/TrafArch_Database_TU.sqlite --original-only --expect-unchanged
python -X utf8 -m tools.reference_data diff data/reference/sources/original-20261020/TrafArch_Database_CU.sqlite assets/data/TrafArch_Database_CU.sqlite --original-only --expect-unchanged
```

Every subcommand accepts `--config` and `--report <local.json>`. Reports are
written atomically; a report cannot overwrite a pinned input, policy, baseline,
or published package. `inspect` without a database emits normalized documents,
all provenance, candidates and diagnostics, including unresolved conflicts.
`validate --baseline <absolute-audit-path>` additionally compares the independent
audit to the frozen baseline copy. `diff` reports schema differences and exact
added/removed row multisets, including raw values and duplicate counts. It works
on two SQLite files or two published package directories. `--original-only`
excludes only `reference_package` and `reference_documents`.

Exit codes: `0` success; `2` rejected/malformed input or unresolved conflicts;
`3` a difference when `diff --expect-unchanged` was requested. Without that flag,
`diff` is informational and returns `0` even when differences exist.

For an independent reproducibility build, choose a local scratch directory:

```powershell
$evidence = Join-Path (Split-Path (Get-Location).Path -Parent) 'work/refactor-20261020'
python -X utf8 -m tools.reference_data build --output-dir (Join-Path $evidence 'task2-repro') --report (Join-Path $evidence 'task2-build-repeat.json')
python -X utf8 -m tools.reference_data diff assets/data (Join-Path $evidence 'task2-repro') --expect-unchanged --report (Join-Path $evidence 'task2-reproducibility.json')
```

No timestamp, random path or absolute machine path enters published content.
The content version hashes the protocol's source descriptors, policy, documents,
tool version/source digest and SQLite engine version. For byte reproducibility,
use the same frozen inputs, policy, Python tool code and SQLite engine. Different
SQLite builds are not asserted to produce identical bytes; validation records and
checks the engine version. The three output hashes must match on the repeat build.

## CSV import and project supplements

Legacy compatibility accepts exactly `City,Code,Type,Line,Station` or
`Prefix,Code,Type,Line,Station`, case-insensitively. Quoted commas, quoted newlines,
UTF-8 BOM and leading zeroes are preserved. Short/extra rows, malformed quoting,
missing codes, absent region context and conflicting explicit City/region fail.
Prefix-mode station imports require `--region`; there is no inferred city from
the source key. Multiple City values stay in separate namespaces.

```powershell
python -X utf8 -m tools.reference_data import-csv local-input.csv --kind stations --protocol CU --source-id local-cu-20261021 --priority 500 --region 3100 --output data/reference/overrides/local-cu-review.json
```

This produces a **review artifact**, not a live station update. It retains all
raw cells, original file bytes in Base64, hashes, record numbers, region, raw key,
selected record references, conflicts and unknown-name diagnostics. Station CSV
cannot express the original databases' protocol-specific field mappings, terminal
context, encoded line-code rules or provenance dependencies. It must receive an
explicit mapping and a reviewed new source revision before publication. Build
rejects an unrecognized station source role instead of silently installing an
unused table or overwriting original source rows.

TU prefix imports have a directly consumable schema. Header:
`Prefix,Issuer,CardName,City,Province,Currency`.

```powershell
python -X utf8 -m tools.reference_data import-csv prefixes.csv --kind card-prefixes --protocol TU --source-id project-tu-20261021 --priority 500 --output data/reference/overrides/project-tu-20261021.json
```

After review, add a source descriptor with a unique `id`, `role:tu_overrides`,
`protocol:TU`, `kind:json`, the relative `file`, file `sha256`/`bytes`, `origin`,
`content_version`, and priority `500` to `sources.json`. Imported `entries` then
participate in the configured project override priority; original database rows
remain unchanged. Prefix supplements do not implicitly add TU city-code mappings.
An empty override document is already registered as the starting point.

For duplicate differing records, run import with `--report` to obtain candidates;
the destination is left unchanged. Provide `--decisions <local.json>` mapping
each emitted conflict id to `winner_record`, `candidates_sha256` and `reason`,
then repeat. All raw records remain in the resulting artifact, including losers.

## Failure behavior and path safety

The tool rejects URL inputs (`http:`, `https:`, `file:` and other schemes), UNC
network paths, `..` traversal components, encoded path components and alternate
data streams. Manifest paths must be relative and remain inside their manifest
directory after resolution, including symlinks. Explicit CLI paths may be local
absolute paths, so use an absolute path for evidence outside the repository.
Historical source URL strings inside JSON are attribution only; they are retained
as data and never fetched.

A build holds an exclusive output-directory lock and stages copied databases in
a temporary directory. It validates original table hashes/schema, SQLite integrity,
foreign keys, metadata, documents, counts and byte hashes **before** publication.
Each file uses `os.replace`; the manifest is replaced last. Existing files are
backed up before replacement, validation is repeated after publication, and any
exception restores previously replaced files (or removes newly created outputs).
A rollback failure preserves the backup directory and reports its location.
Frozen inputs are never mutated. A stale lock after a hard process termination
must be reviewed before removal.

This is per-file atomic replacement with exception rollback, not an OS transaction
across three filenames. Abrupt machine/process termination between replacements
can leave a detectable manifest/hash mismatch; runtime must reject it, and an
offline rebuild restores the set. Do not publish while another process edits the
source configuration. No failure-injection hooks, runtime write migrations or
database vacuum/rebuild operations are hidden in the CLI.

## Verification scope for this delivery

Task 2 uses Python AST/source review, SQLite integrity/foreign-key/content/schema
checks, CLI inspect/build/validate/diff/import, input-rejection evidence and repeat
build byte comparison. It does not run unit tests, APK builds, Gradle, emulators,
device calls, or real-card checks. Runtime integration is another task. Evidence,
changed paths and remaining limits are reported in
`../work/refactor-20261020/task2-report.md`.
