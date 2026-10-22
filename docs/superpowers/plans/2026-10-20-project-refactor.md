# TrafArch approved refactor implementation plan

Spec: `../specs/2026-10-20-project-refactor-design.md` (approved by user).
Baseline: `8a4818e7d4dc848432a3e39a69195255138a3b95` plus six preserved fixes.
Working branch: `refactor/offline-modules-20261020`.

## Global constraints

- Superseding user authorization on 2026-10-21 requires full automated tests, Android compilation and matching source/APK delivery. Earlier no-test statements describe historical scope only. No emulator/device launch or physical-card test has been performed.
- No commits, push or publication in this implementation. Preserve previous source exports and all existing uncommitted fixes.
- TU and CU are independently usable packages. Preserve every original table, row, identifier, leading zero, source field and encoded line number.
- Runtime reads project-owned published packages; no HTTP fetching, runtime CSV adaptation, runtime index construction or writes to reference assets.
- Never infer CU decoded carrier/type from CJ/T331 instruction bytes 06/09. Missing required context cannot match a constrained rule.
- Preserve archive names, fingerprints, custom names, legacy snapshots and raw malformed content. Migrate additively before writes.
- Shanghai +8 CNY report remains unverified; do not subtract 800 fen.
- Preserve parser IDs and native channel names/message compatibility. No unsupported new card-read capabilities.

## Contracts

Reference package version 1 retains all original SQLite schema/content and adds `reference_package(key TEXT PRIMARY KEY,value TEXT NOT NULL)` and `reference_documents(name TEXT PRIMARY KEY,json TEXT NOT NULL)`. Metadata keys: `format_version=1`, `protocol=TU|CU`, `content_version`, `tool_version`. Documents use the existing JSON domain schemas, but TU `card_prefixes` and `cities` are normalized at build time; other documents are `issuers`, `terminal_rules`, `card_meta`; CU has `card_catalog`. Sources, priorities and conflicts are explicit in the build manifest. No CU query requires TU. Published assets retain `assets/data/TrafArch_Database_TU.sqlite` and `_CU.sqlite`, with sidecar `reference_manifest.json` mapping protocol to asset basename, SHA256, bytes, content version and per-table counts. Hash the final bytes after closure. Never modify original tables to generate display data.

Runtime installer validates manifest and package metadata, uses a content-hash filename under `trafarch_reference`, installs atomically, opens read-only, and exposes explicit errors. `reference_user.sqlite` owns TU override/report tables and migration markers; migration reads old `trafarch_db/trafarch_database_tu.sqlite` before any asset upgrade. DB ownership belongs to the reference controller, not static singletons.

Reference queries carry namespace, region, original keys and source evidence. CU station lookup uses `station_lookup` directly, with strict context and ambiguity; routes and prefix dictionaries are exposed as separate lookups. Historical Shenzhen bus lookup requires region 5180, decoded carrier 1, lookup enabled, no station match, known timestamp before 1735675200000.

Archive schema 6 repairs actual columns and backfills legacy scalar snapshots into batches idempotently before any new save. Snapshot 3 is a strict versioned envelope with context and raw evidence. `ArchiveHistory` is the shared detail/export query. Pending saves have stable attempt IDs, confirmed/cancelled only by that ID.

Session generation belongs to ScanController and native session identity belongs to NfcSessionController. Old async completions cannot publish or close a newer connection. CardReadCoordinator returns typed outcomes. Settings, QR, reference data and archive have independent controllers; AppDependencies owns disposal.

## Task 1: Baseline and execution setup

Preserve existing dirty repairs; mark design approved; create implementation branch, plan and ledger. Record input file/table hashes from existing audit. Review protocol/UI audits. Expected: previous fixes remain. Initial no-test scope was later superseded by the 2026-10-21 authorization.

## Task 2: Offline reference tooling and packages

Write `tools/reference_data/` Python-standard-library CLI (`inspect`, `build`, `validate`, `import-csv`, `diff`), freeze local inputs under `data/reference/sources/`, project additions under `data/reference/overrides/`, and source manifest. Preserve source databases byte-for-byte. Build normalized package documents and indexed read-only SQLite packages atomically. Reject unspecified conflicts, malformed input and URLs. Document reproducible commands. Execute build/validate/diff and compare all original table hashes to baseline; perform repeat-build byte comparison. Add CLI failure-preservation and reproducibility evidence; final automated tests follow the superseding authorization.

## Task 3: Runtime reference layer and user-data migration

Replace runtime rebuilders/CSV parser with package readers. Separate TU/CU cities and sources. Add typed match status/provenance/raw line fields. Implement strict CU station/route/prefix/bus lookups. Migrate overrides/reports transactionally with markers and freshness checks. Close resources explicitly and preserve unavailable/migration status. Update knowledge page to use capability interfaces and show versions/counts/source/errors. Verify via static analysis and code/data review.

## Task 4: Archive compatibility and history

Implement schema 6, legacy snapshot backfill, strict snapshot 1/2/3 decoding with diagnostics and retained raw content. Preserve raw location/operator fields. Unify history detail/export and archived currency/context. Handle missing/deleted/error states distinctly. Capture pendingSaveId in dialogs. Keep existing identity/fingerprint algorithms. Verify source branches, real SQLite migrations, reopen/freshness/idempotence and full automated tests.

## Task 5: Native session/platform split

Split Android MainActivity into NFC session/channel, QR scanner, export handlers. Preserve existing channel contracts, adding optional session IDs accepted by existing callers. Bind every pending discovery and transceive to its session; sequential command scheduling, cancellation/disposal cannot close a successor session. Preserve partial evidence and error codes. Compile Kotlin/Gradle, run Lint and build repair Release/Debug APKs under the superseding authorization.

## Task 6: Application controllers and acquisition

Extract ScanController, CardReadCoordinator, QrController, SettingsController, ArchiveController, ReferenceDataController and AppDependencies. Use typed protocol outcomes and attempt-local generation guards through parsing, publication and save. Centralize resource lifecycle. Separate current scan presentation/naming. Preserve zero balances and mixed bank application result. Review cancellation/partial data paths.

## Task 7: Protocol and file ownership migration

Move files to approved app/protocols/platform/features/shared layout using reviewed map; update every import/export/test path and generated part placement. Put payment core beneath protocols, remove transit-owned bank marker. Share APDU mechanics through explicit family policy without erasing differences. Keep protocol modules free of Flutter platform dependencies; retain raw evidence. Delete old implementations and unused runtime adapters, without forwarding-file forests.

## Task 8: UI, documentation, complete verification and delivery

Split home/expert/trip components; move work out of widget build; safe release error screen. Review all baseline infos; resolve those suitable without suppression and document retained ones. Full analyzer must report zero errors/warnings. Fresh independent review of completed implementation and fix important findings. Export full source, applicable patch, architecture/migration/tooling notes, manifests and SHA256s. Verify patch reconstructs exported source. Run full Flutter tests and Android builds. Verify APK signatures/alignment/identity/assets and patch/source reconstruction; report unexecuted device/card verification explicitly.

## Review focus

Unknown CU context, namespace collisions (TU1210 vs CU1210), leading zeros and raw line codes, source-table loss, canceled/replaced NFC sessions, migrated override freshness/counts, fresh versus upgraded archive schema, invalid/future snapshot payload retention, partial scans, late dialog confirmations, database close during initialization, byte reproducibility, and complete source patch reconstruction.
