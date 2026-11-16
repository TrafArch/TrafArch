import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_result_panel.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

import 'support/test_database.dart';

FelicaReadOutcome _outcome() => FelicaReadOutcome(
  FelicaScanResult(
    cardType: 'suica',
    displayName: 'Suica',
    cardProductType: FelicaCardType.suica,
    scannedAt: DateTime(2025, 10, 20),
    transactions: [
      const SuicaRecordParser()
          .parseBlock(
            blockNumber: 0,
            bytes: [0x16, 1, 0, 0, 0x33, 0x54, 1, 1, 1, 3, 0x84, 3, 0, 0, 2, 0],
          )
          .toTransaction(),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppDependencies appFor(_Memory memory, {AppDatabase? database}) {
    final app = AppDependencies(
      database: database ?? testDatabase(),
      memoryPlatform: memory,
      bundle: MissingTestAssets(),
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(() {
      if (!app.disposed) app.dispose();
    });
    return app;
  }

  testWidgets(
    'Suica read appears on live trips even when station package is unavailable',
    (tester) async {
      final app = appFor(_Memory());
      final outcome = _outcome();
      await tester.runAsync(() async {
        await app.init();
        app.scan.outcome = outcome;
        await app.scan.onCompleted!(
          outcome,
          'suica-read',
          DateTime(2025, 10, 20),
          () => true,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TripsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无行程数据'), findsNothing);
      expect(find.textContaining('Suica'), findsWidgets);
      expect(find.textContaining('2025年10月20日'), findsWidgets);
      expect(app.pendingCardSave, isNull);
    },
  );

  test('Suica decoded evidence preserves station and date precision in recovery and diagnostics', () {
    final outcome = _outcome();
    final captured =
        (captureReadResult(outcome)['transactions'] as List).single as Map;
    expect(captured['suica'], isA<Map>());
    expect((captured['suica'] as Map)['hasTime'], isFalse);
    final record = captureParserRecords(outcome)
        .singleWhere((row) => row['fieldCategory'] == 'transactions');
    expect((record['fields'] as Map)['suica'], captured['suica']);
  });

  testWidgets(
    'Suica live presentation survives memory recovery without reference rematching or archive writes',
    (tester) async {
      final memory = _Memory();
      final app = appFor(memory);
      await tester.runAsync(() async {
        await app.init();
        final outcome = _outcome();
        app.scan.outcome = outcome;
        await app.scan.onCompleted!(
          outcome,
          'suica-read',
          outcome.card.scannedAt,
          () => true,
        );
        expect(await app.handleMemoryPressure(true), isTrue);
      });
      final capture = RecoveryState.decode(memory.text!).capture!;
      expect(capture.summary['suicaTrips'], isA<List>());
      expect(capture.canSave, isFalse);
      // Simulate a restart against the same archive while discarding app state.
      app.dispose();
      final restored = appFor(memory, database: app.cardRepository.db);
      await tester.runAsync(restored.init);
      expect(
        restored.recoveredCapture!.summary['suicaTrips'],
        capture.summary['suicaTrips'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecoveryResultPanel(app: restored),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Suica'), findsWidgets);
      expect(find.textContaining('2025年10月20日'), findsWidgets);
      await tester.runAsync(() async {
        expect(
          await restored.cardRepository.db
              .select(restored.cardRepository.db.savedCards)
              .get(),
          isEmpty,
        );
      });
    },
  );
}

class _Memory implements MemoryPlatform {
  String? text;
  @override
  void listen(Future<bool> Function(bool kill) handler) {}
  @override
  void dispose() {}
  @override
  Future<String?> readRecovery() async => text;
  @override
  Future<void> clearRecovery() async => text = null;
  @override
  Future<void> writeRecovery(String content) async => text = content;
}
