# Octopus Online Implementation Plan

> **For agentic workers:** Use subagent-driven-development for independent protocol, platform and integration tasks. Preserve existing workspace changes; no APK builds.

**Goal:** 接入用户确认的八达通联网余额、卡内汇率和显式更新操作。

**Architecture:** 纯 Dart OCAP 引擎注入 HTTP/NFC 交换；平台层管理官方端点和 NFC-F 专用会话；feature controller 管理同卡、许可、取消与两页共享展示。

**Tech Stack:** Flutter/Dart、现有 Kotlin NFC 会话、dart:io、既有 path_provider/uuid。

**Spec:** ../specs/2026-11-17-octopus-online-design.md

## Global Constraints

- 不编译 APK、不改版本；数据库与 manifest SHA256 保持不变。
- 保留原 NFC 通道契约；协议不依赖 Flutter/feature/SQLite。
- 用户授权联网读卡及按钮触发的汇率更新；普通查询拒绝额外写操作。
- 失败/注册限制/服务器拒绝如实显示，不能用参考汇率假装卡内读数。

## Review Focus

- 服务器恶意/畸形长度、无限 VM 循环必须有上限。
- 普通查询收到退款/写指令应在 NFC 发送前拒绝。
- 更新错卡、取消后迟到响应必须不能写入或覆盖结果。
- 无行程、零/负余额、缺失/过期汇率与大字号正确显示。
- 注册/业务拒绝、断卡或写后超时不能变成成功。

## Task 1: OCAP and typed result

Files: `lib/protocols/octopus/*`, `test/octopus_ocap_test.dart`.

Interface: `OctopusOperation { enquiry, updateRate }`; `OctopusOcapSession(exchangeServer, transceiveFelica, clientInputs, operation, idmHex, isCancelled).run()` returns `Map<String,dynamic>` official result. Protocol engine handles OCAP binary, VM, applet inputs/output with strict limits and read-only NFC policy. `OctopusOnlineResult.fromResponse(response, idmHex, readAt)` validates success, exact decimal balances, card identity, rate and raw date strings; unknown remains unknown.

- [x] Write failure-first wire/result/command-policy tests from APK structure.
- [x] Implement complete bounded protocol engine; no HTTP inside.
- [x] Run targeted tests and independent review.

## Task 2: Official service and local installation context

Files: `lib/platform/octopus/*`, `test/octopus_http_test.dart`.

Interface: `OctopusOnlineService.execute({required OctopusOperation operation, required String idmHex, required Future<List<int>> Function(List<int>) transceiveFelica, required bool Function() isCancelled})` returns `OctopusOnlineResult`. Keep network transport injectable for deterministic tests. Use fixed HTTPS production host, fresh GET session and OCAP POST, finite time/size/round limits; no redirects carrying card data. Device context stored outside SQLite. No credentials copied from official app.

- [x] Test HTTP URI/session/redirection/error handling and correct distinct operation paths.
- [x] Implement service/context and explicit backend refusal/registration handling.
- [x] Run targeted tests and independent review.

## Task 3: Dedicated NFC-F session

Files: Kotlin nfc handler/controller and `lib/platform/nfc/octopus_channel.dart`, channel tests, native contract doc.

Interface: `OctopusNfcChannel.scanSession(id)`, `exchangeSession(id,frame)`, `closeSession(id)` using new `transit_card_analyzer/octopus_nfc` channel, same session controller and retirement barrier. Only reader mode NFC-F selected for this entry point; existing NFC methods unchanged.

- [x] Test new channel keys, IDs, errors and native scan mode isolation.
- [x] Implement additive channel and per-session NFC-F reader preference.
- [x] Verify existing lifecycle behavior remains unchanged without APK compilation.

## Task 4: Controller, consent and UI integration

Files: `lib/features/octopus/*`, `lib/app/app_dependencies.dart`, home/trips, currency tests; CHANGELOG/current docs.

- [x] Test consent/no-network default, same-card update, no-record UI, cancellation/wrong-card and money states.
- [x] Add dedicated online controller with exclusive scan ownership, immutable result and visible error states.
- [x] Add homepage entry/results, journey balance/update button, translated instructions and HK$.
- [x] Wire lifecycle/reset through AppDependencies; keep TU amounts and archive snapshots unchanged.

## Task 5: Final verification

- [x] Independent review of bounds, privacy, card/session identity and UI correctness.
- [x] Run targeted and full Flutter tests, flutter analyze; fix relevant failures.
- [x] Verify asset hashes and git diff; report limitations and no APK build.
