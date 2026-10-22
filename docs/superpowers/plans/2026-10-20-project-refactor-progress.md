# Refactor execution ledger

Approved design: `../specs/2026-10-20-project-refactor-design.md`.
Plan: `2026-10-20-project-refactor.md`.
Baseline: `8a4818e7d4dc848432a3e39a69195255138a3b95`.
Branch: `refactor/offline-modules-20261020`. Final handoff date: 2026-10-21.

## Current authorization

The user delegated implementation decisions, requested a categorized Changelog, and on 2026-10-21 explicitly required complete testing plus matching source and APK packages for physical-card testing. This supersedes earlier cancellation/no-test/no-build instructions. Historical intermediate reports retain their original scope. No commits, push, publication, device installation/launch or physical-card operations were performed.

## Completed work

| Task | State | Acceptance evidence |
|---|---|---|
| 1 Baseline | complete | Approved plan, dedicated branch, dirty repairs and prior backups preserved. |
| 2 Offline tooling/data | complete | Five CLI commands, frozen sources, independent TU/CU packages, original 90/20 tables retained, same-engine byte reproducibility. |
| 3 Reference runtime | complete | Read-only content-addressed installation, namespace/context/provenance, independent CU, transactional user migration and visible errors; runtime contract regressions pass. |
| 4 Archive | complete | Schema 6 actual-column repair, v3 snapshots, shared history, malformed/future raw retention, pending-save ownership, persisted per-field observation times; old v1-v6 DDL/reopen/delete regressions pass. |
| 5 Native | complete | MainActivity split into 11 Kotlin files, session/FIFO/retirement ownership, metadata/error preservation; Kotlin compilation and Android builds pass. |
| 6 Controllers | complete | AppDependencies, scan/coordinator/reference/archive/settings/QR/diagnostics ownership, partial results and disposal; cancellation/runtime/widget regressions pass. |
| 7 Ownership migration | complete | 159 file migrations, 216 Dart libraries, 652 internal edges; no missing own imports, cycles, reverse protocol imports or old implementations. |
| 8 UI/docs/verification/delivery | complete | Component split, categorized Changelog, full tests/analyzer/builds/Lint, signatures/assets, complete source export and patch reconstruction checks; exact receipts accompany delivery. |

## Findings closed during final verification

- Earlier independent source review found two P2 gaps in TU identity-file partial preservation and late local-card failures. Both were fixed; eight targeted regressions and the full suite pass.
- Independent archive tests found same-content deduplication losing observation freshness. A transaction-owned auxiliary table now records maximum per-field observation times independently of immutable batches. Migration tests pass 29/29, with an additional persistent-file reopen/delete regression. A follow-up review also found legacy fallback timestamps overriding persisted times; v2/v5/v6 migration/reopen tests failed before the fix and pass after explicit times were merged before legacy fallback.
- Logging transition markers, published-document fixture contracts, terminal-bank-I/O expectations and widget SQLite fakeAsync/resource ownership were corrected. Assertions were preserved and strengthened.
- Android Lint camera-feature errors and unused/duplicate resources were corrected. A resource move required a clean rebuild; intermediate AAPT cache failure is retained as historical evidence.

## Final evidence

`docs/REFACTOR_VALIDATION_20261021.md` records the refactor results and earlier parallel-install APK evidence. The current same-package delivery record is `docs/UPGRADE_HANDOFF_20261021.md`. Full logs/JSON, independent review and its follow-up, APK source-input fingerprints, patch reconstruction receipt and SHA256s accompany the handoff. Earlier failure logs are not final acceptance results.

611 Flutter tests pass, analyzer reports no issues, and arm64 repair APKs build. Native unit task is NO-SOURCE; there are no fabricated native test counts. Android Lint non-blocking warnings and Gradle/plugin deprecations are explicitly documented.

Physical-card compatibility, original Shanghai +8 root cause, production-signature upgrade and real Android lifecycle interleavings still require device testing. No fixed -800 fen workaround, unsupported Octopus service, or new bank/FeliCa archive policy was introduced.

## 2026-10-21 follow-up: same-package upgrade delivery

The user requires the original package ID for in-place upgrade testing and explicitly chose developer signing with the original key. Remove validation package/name suffixes. Keep source build 2066 and let the arm64 split versionCode be 4066, above the supplied original APK's 4059. Add explicit unsignedApk for unsigned Release/Debug handoff; retain repairBuild only for private-config independence and no automatic bump. Original release certificate was verified, but its private key is absent; no claim of original signing or device upgrade is made. Current receipts and signing steps are in UPGRADE_HANDOFF_20261021.md and the separate upgrade output directory. Earlier repair APK evidence remains historical.

The user further requires every future change to preserve both the APK display name `TrafArch` and package ID `com.kajolno.TrafArch`. This is recorded in the project-root AGENTS.md and README and applies to Debug, Release and validation builds. Both new APK manifests were checked against these exact values.

## 2026-10-21 follow-up: field bugs and complete city integration audit (active)

The user reported Taiyuan route 864 appearing as 0016, Shanghai 100 CNY appearing as 108, saved trips opening as JSON, and Octopus China T-Union 50 HKD appearing as 42.25 CNY. The latter was confirmed against Octopus App and its mini-program; HK$50 remains the acceptance target. The phone is unavailable while the user is in class, so further balance APDU evidence cannot currently be supplied.

- Taiyuan: complete 174-key TripReader city branch added; unchanged user HEX resolves to route 864 while retaining 0016 and unknown station 0000. Regional station rows are distinct from code-based route fallback.
- Home balance: current parsed observation is used directly; stale analysis and independent TU/CU amounts cannot replace or add to it. Shanghai physical +8 root cause is not reproduced, so no real-card resolution claim or fixed subtraction is made.
- Archive trips: use shared trip cards, source/mode filters and readable details; raw JSON is a secondary diagnostic. Additional review fixed empty type names and zero fields creating fictitious entry/exit sides.
- Raw Data: preserve the full session instead of showing only the last 20 messages, which hid SELECT and balance responses.
- Octopus: preserve the TU reported integer separately from the HKD account. No real HKD balance or FX decoder has been verified; do not call the HK$50 bug fixed or relabel 4225 as HKD. New captures retain versioned interpretation; legacy payloads remain unchanged.
- User expanded scope to ALL cities: audit TU bus code branches, TU rail/station queries and CU rules independently against the frozen original TripReader implementation and packaged data. Record data presence, actual runtime integration, omitted rules and evidence gaps separately. Implement supported omissions before final validation/build/export.

Earlier upgrade APKs and source ZIPs predate these field fixes. Re-run complete tests, analysis, Android builds/Lint, input/manifest/asset verification and source reconstruction before replacing delivery artifacts. Current working evidence is ../work/upgrade-20261021; no commit, push or device operation is authorized by these audits.
