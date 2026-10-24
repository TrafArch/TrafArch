# Offline reference data tooling

The Python standard-library CLI builds TU and CU independently usable SQLite
assets from frozen local inputs. It performs no network requests and invokes no
Flutter, Gradle, Android, emulator, device, or test commands. Python 3.11 or newer
is required. Run the examples from the repository root.

## Published contract

Outputs retain the runtime asset names:

* `assets/data/TrafArch_Database_TU.sqlite`
* `assets/data/TrafArch_Database_CU.sqlite`
* `assets/data/reference_manifest.json`

Each package preserves every original table, row, index, view, raw identifier,
source field and `PRAGMA user_version`. The build appends only these two tables:

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
| CU | `card_catalog` | Existing CU card catalog with confidence/status fields and all entries |

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

The current TU revision is `sources/user-tu-afdaca5f8ff3-source-v3/`, derived from
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
