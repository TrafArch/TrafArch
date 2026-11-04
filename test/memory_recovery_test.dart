import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/app_shell.dart';
import 'package:transit_card_analyzer/app/navigation/recovery_route_observer.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/pending_card_save.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_result_panel.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppDependencies appFor(_Memory memory, {_Nfc? nfc, SettingsStore? settings}) {
    final app = AppDependencies(
      database: testDatabase(),
      memoryPlatform: memory,
      channel: nfc ?? _Nfc(),
      bundle: MissingTestAssets(),
      settingsStore: settings ?? MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    return app;
  }

  test('recovery preserves snapshot text and observation time without archive writes', () async {
    final state = _state();
    final memory = _Memory()..text = state.encode();
    final nfc = _Nfc();
    final app = appFor(
      memory,
      nfc: nfc,
      settings: MemorySettingsStore({SettingsKeys.autoSaveEnabled: 'true'}),
    );
    await app.init();
    expect(memory.text, isNull);
    expect(app.recoveredCapture!.snapshotJson, state.capture!.snapshotJson);
    expect(app.recoveredCapture!.pending!.readAt, state.capture!.readAt);
    expect(app.recoveredCapture!.canSave, isTrue);
    expect(app.pendingCardSave, isNull); // No automatic-save dialog or write.
    expect(
      await app.cardRepository.db
          .select(app.cardRepository.db.savedCards)
          .get(),
      isEmpty,
    );
    expect(app.scan.autoScanConsumed, isTrue);
    expect(nfc.scans, 0);
    app.declineRecoveredCapture();
    expect(app.recoveredCapture!.canSave, isFalse);
    expect(await app.handleMemoryPressure(true), isTrue);
    expect(RecoveryState.decode(memory.text!).capture!.canSave, isFalse);
  });

  test('KILL does not wait for ten-second NFC close and stale discovery cannot publish', () async {
    final memory = _Memory();
    final nfc = _Nfc()..blockClose = true;
    final app = appFor(memory, nfc: nfc);
    await app.init();
    final reading = app.scanOnce();
    expect(app.scanning, isTrue);
    final clock = Stopwatch()..start();
    expect(await app.handleMemoryPressure(true), isTrue);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    final capture = RecoveryState.decode(memory.text!).capture!;
    expect(capture.interrupted, isTrue);
    expect(capture.canSave, isFalse);
    expect(app.scanning, isFalse);
    nfc.discovery.complete(
      NfcScanResult(
        uid: 'original',
        technologies: const [],
        isoDepConnected: false,
        timestamp: DateTime(2026),
      ),
    );
    expect(app.lastResult, isNull);
    nfc.closed.complete();
    await reading;
    expect(app.lastResult, isNull);
  });

  test('TRIM keeps current evidence and unsaved capture', () async {
    final memory = _Memory()..text = _state().encode();
    final app = appFor(memory);
    await app.init();
    final capture = app.recoveredCapture;
    expect(await app.handleMemoryPressure(false), isTrue);
    expect(identical(app.recoveredCapture, capture), isTrue);
    expect(app.recoveredCapture!.canSave, isTrue);
    expect(memory.writes, 0);
  });

  test('completed live read becomes a frozen recovery capture without auto-archiving', () async {
    final memory = _Memory();
    final app = appFor(memory);
    await app.init();
    const outcome = TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: '交通联合',
        transactions: [],
        selectedAidHex: 'A000000632010105',
        info: TUnionCardInfo(
          applicationSerial: '03100000000000000001',
          balanceFen: 1234,
        ),
      ),
    );
    final readAt = DateTime(2026, 11, 4, 10);
    app.scan.outcome = outcome;
    await app.scan.onCompleted!(
      outcome,
      'original-attempt',
      readAt,
      () => true,
    );
    final original = app.pendingCardSave!;
    expect(await app.handleMemoryPressure(true), isTrue);
    final restored = RecoveryState.decode(memory.text!).capture!;
    expect(restored.canSave, isTrue);
    expect(restored.snapshotJson, original.sessionDataJson);
    expect(restored.pending!.pendingSaveId, 'original-attempt');
    expect(restored.pending!.readAt, readAt);
    expect(restored.readAt, readAt);
    expect(
      await app.cardRepository.db
          .select(app.cardRepository.db.savedCards)
          .get(),
      isEmpty,
    );
  });

  test(
    'explicit save keeps captured parser version and original observation time',
    () async {
      final state = _state();
      final memory = _Memory()..text = state.encode();
      final app = appFor(memory);
      await app.init();
      await app.saveRecoveredCapture();
      expect(app.recoveredCapture!.canSave, isFalse);
      final saved = await app.cardRepository.db
          .select(app.cardRepository.db.savedCards)
          .getSingle();
      expect(saved.lastReadAt, state.capture!.readAt.millisecondsSinceEpoch);
      final batch = await app.cardRepository.db
          .select(app.cardRepository.db.cardReadBatches)
          .getSingle();
      expect(batch.parseVersion, 7);
      // Existing archive save policy adds observation metadata on explicit
      // confirmation. Original recovery text and evidence stay unchanged.
      expect(app.recoveredCapture!.snapshotJson, state.capture!.snapshotJson);
      final payload = jsonDecode(batch.payloadJson) as Map;
      final original = jsonDecode(state.capture!.snapshotJson!) as Map;
      expect(payload['rawEvidence'], original['rawEvidence']);
      expect(payload['futureField'], 17);
    },
  );

  test('failed or stalled persistence reports failure and does not accept a new scan during preparation', () async {
    final memory = _Memory();
    final nfc = _Nfc();
    final app = appFor(memory, nfc: nfc);
    await app.init();
    memory.blockWrite = Completer<void>();
    final result = app.handleMemoryPressure(true);
    await app.scanOnce();
    expect(nfc.scans, 0);
    expect(await result, isFalse);
    memory.blockWrite!.complete();
  });

  for (final invalid in ['corrupt', 'expired', 'version']) {
    test('$invalid recovery is discarded without partial state', () async {
      final text = switch (invalid) {
        'corrupt' => 'broken json',
        'expired' => _state(
          savedAt: DateTime.now().subtract(const Duration(days: 2)),
        ).encode(),
        _ => jsonEncode({
          ...jsonDecode(_state().encode()) as Map,
          'version': 99,
        }),
      };
      final memory = _Memory()..text = text;
      final app = appFor(memory);
      await app.init();
      expect(app.recoveredCapture, isNull);
      expect(memory.text, isNull);
      expect(app.recoveryNotice, contains('无法恢复'));
    });
  }

  test('new scan invalidates the previous KILL recovery file', () async {
    final memory = _Memory()..text = _state().encode();
    final nfc = _Nfc();
    final app = appFor(memory, nfc: nfc);
    await app.init();
    expect(await app.handleMemoryPressure(true), isTrue);
    expect(memory.text, isNotNull);
    final reading = app.scanOnce();
    await Future<void>.delayed(Duration.zero);
    expect(memory.text, isNull);
    nfc.discovery.complete(null);
    await reading;
  });

  test(
    'cold-start KILL cannot overwrite an unread recovery checkpoint',
    () async {
      final memory = _Memory()..text = _state().encode();
      final app = appFor(memory);
      expect(await app.handleMemoryPressure(true), isFalse);
      expect(memory.writes, 0);
      expect(memory.text, isNotNull);
    },
  );

  testWidgets('settings route survives the initial root route notification', (
    tester,
  ) async {
    final state = _state();
    final memory = _Memory()
      ..text = RecoveryState(
        savedAt: state.savedAt,
        tab: 2,
        route: '/settings',
        capture: state.capture,
      ).encode();
    final nfc = _Nfc();
    final app = appFor(memory, nfc: nfc);
    await tester.runAsync(app.init);
    final observer = RecoveryRouteObserver(app);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: AppShell(app: app, routeObserver: observer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(app.recoveryRoute, '/settings');
    expect(nfc.scans, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'restart restores selected tab, frozen result and confirmation buttons without starting NFC',
    (tester) async {
      final memory = _Memory()..text = _state().encode();
      final nfc = _Nfc();
      final app = appFor(memory, nfc: nfc);
      await tester.runAsync(app.init);
      await tester.pumpWidget(MaterialApp(home: AppShell(app: app)));
      await tester.pumpAndSettle();
      expect(find.text('上次读取结果').hitTestable(), findsOneWidget);
      expect(find.text('保存这次读取').hitTestable(), findsOneWidget);
      expect(app.recoveryTab, 1);
      expect(nfc.scans, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('Android bridge rejects stale and malformed notices before business handling', () async {
    final bridge = AndroidMemoryPlatform();
    var calls = 0;
    bridge.listen((kill) async {
      calls++;
      return kill;
    });
    addTearDown(bridge.dispose);
    const codec = StandardMethodCodec();
    Future<Object?> send(Object? args) async {
      final reply = Completer<ByteData?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            AndroidMemoryPlatform.channel.name,
            codec.encodeMethodCall(MethodCall('onMemoryPressure', args)),
            reply.complete,
          );
      return codec.decodeEnvelope((await reply.future)!);
    }

    expect(await send({'kill': true, 'expiresAtMillis': 0}), isFalse);
    expect(await send({'kill': 'true'}), isFalse);
    expect(calls, 0);
    expect(
      await send({
        'kill': true,
        'expiresAtMillis': DateTime.now()
            .add(const Duration(seconds: 2))
            .millisecondsSinceEpoch,
      }),
      isTrue,
    );
    expect(calls, 1);
  });

  testWidgets(
    'recovered pending save is explicit even with auto-save enabled',
    (tester) async {
      final memory = _Memory()..text = _state().encode();
      final app = appFor(memory);
      await tester.runAsync(app.init);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecoveryResultPanel(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('不保存'));
      await tester.pumpWidget(const SizedBox());
      expect(app.recoveredCapture!.canSave, isFalse);
      expect(
        await app.cardRepository.db
            .select(app.cardRepository.db.savedCards)
            .get(),
        isEmpty,
      );
    },
  );
}

RecoveryState _state({DateTime? savedAt}) {
  final at = DateTime(2026, 11, 4, 9, 10);
  const snapshot =
      '{ "v":3,"parseVersion":7,"trips":[],"rails":[],"buses":[],"cycle":[],"context":{},"rawEvidence":[{"raw":"0010"}],"futureField":17}';
  expect(CardSessionSnapshot.decode(snapshot), isNotNull);
  return RecoveryState(
    savedAt: savedAt ?? DateTime.now(),
    tab: 1,
    filters: const {
      'live': ['mode:metro'],
    },
    capture: RecoveryCapture(
      readAt: at,
      summary: const {'cardName': '测试交通卡', 'cardNumber': '001234'},
      frames: const [
        {
          'sessionId': 'old-session',
          'command': [0, 164],
          'response': [144, 0],
        },
      ],
      snapshotJson: snapshot,
      canSave: true,
      pending: PendingCardSave(
        pendingSaveId: 'captured-attempt',
        readAt: at,
        fingerprint: 'TU::001234',
        identity: const CardArchiveIdentity(
          cardType: 'tunion',
          officialName: '测试交通卡',
        ),
        sessionDataJson: snapshot,
      ),
    ),
  );
}

class _Memory implements MemoryPlatform {
  String? text;
  int writes = 0;
  Completer<void>? blockWrite;
  @override
  void listen(Future<bool> Function(bool kill) handler) {}
  @override
  void dispose() {}
  @override
  Future<String?> readRecovery() async => text;
  @override
  Future<void> clearRecovery() async => text = null;
  @override
  Future<void> writeRecovery(String content) async {
    writes++;
    await blockWrite?.future;
    text = content;
  }
}

class _Nfc implements NfcChannel {
  int scans = 0;
  bool blockClose = false;
  final discovery = Completer<NfcScanResult?>();
  final closed = Completer<void>();
  @override
  Future<NfcScanResult?> scanOnce() {
    scans++;
    return discovery.future;
  }

  @override
  Future<void> stopScan() async {
    if (blockClose) await closed.future;
  }

  @override
  Future<List<int>> transceive(List<int> apdu) async => [0x6A, 0x82];
}
