import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/home/presentation/felica_summary_panel.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_result_panel.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/scan/application/card_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/models/amusement_ic_data.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';

import 'support/test_database.dart';

// Synthetic code and identifiers only; these do not belong to a physical card.
const _accessCode = '50101234567890123456';
const _groupedCode = '5010 1234 5678 9012 3456';
const _idm = '012E000000000001';
const _complete = AmusementIcData(
  accessCode: _accessCode,
  issuer: 'SEGA Aime',
  dataFormatCode: 0x0078,
  spad0Hex: '00000000000000000000000000000000',
  idBlockHex: '01234567890123456789000000000000',
);
const _partial = AmusementIcData(
  dataFormatCode: 99,
  spad0Hex: '00000000000000000000000000000000',
  note: '未知数据格式，尚未解析 Access Code。',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home and expert summary exposes full selectable access code separately from IDm',
    (tester) async {
      await tester.pumpWidget(_page(FelicaSummaryPanel(felica: _card())));
      expect(find.text('SEGA Aime'), findsOneWidget);
      expect(find.text(_idm), findsOneWidget);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text(_accessCode), findsOneWidget);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data),
        containsAll([_groupedCode, _accessCode]),
      );
      expect(find.textContaining('余额'), findsNothing);
      expect(find.textContaining('币种'), findsNothing);
      expect(find.text('交易记录'), findsNothing);
    },
  );

  testWidgets(
    'full access code remains selectable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: FelicaSummaryPanel(felica: _card()),
            ),
          ),
        ),
      );
      for (final code in [_groupedCode, _accessCode]) {
        final value = find.text(code);
        await tester.ensureVisible(value);
        expect(value.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(value);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final data in <AmusementIcData?>[_partial, null]) {
    testWidgets(
      'incomplete summary keeps IDm separate and explains missing access code (${data == null ? 'missing' : 'unknown format'})',
      (tester) async {
        await tester.pumpWidget(
          _page(FelicaSummaryPanel(felica: _card(data: data))),
        );
        expect(find.text(_idm), findsOneWidget);
        expect(find.text('Access Code 未读取'), findsOneWidget);
        expect(find.text(_accessCode), findsNothing);
        expect(find.text(_groupedCode), findsNothing);
        if (data?.note case final String note) {
          expect(find.text(note), findsOneWidget);
        }
        expect(find.textContaining('余额'), findsNothing);
        expect(find.textContaining('币种'), findsNothing);
      },
    );
  }

  test('diagnostic identity preserves access code without making IDm a card number', () {
    final captured = jsonDecode(
      jsonEncode(captureCardInfo(FelicaReadOutcome(_card()))),
    ) as Map;
    expect(captured['accessCode'], _accessCode);
    expect(captured['issuer'], 'SEGA Aime');
    expect(captured['idm'], _idm);
    expect(captured['cardNumber'], isNull);
    final partial = captureCardInfo(FelicaReadOutcome(_card(data: _partial)));
    expect(partial['accessCode'], isNull);
    expect(partial['cardNumber'], isNull);
    expect(partial['idm'], _idm);
  });

  test('parser diagnostics and recovery JSON freeze access code and original block evidence', () {
    final outcome = FelicaReadOutcome(_card());
    final records =
        jsonDecode(jsonEncode(captureParserRecords(outcome).toList())) as List;
    final record = records.cast<Map>().singleWhere(
      (row) => row['fieldCategory'] == 'amusementIc',
    );
    expect(record['parserId'], 'felica.amusementIc');
    final fields = record['fields'] as Map;
    expect(fields['accessCode'], _accessCode);
    expect(fields['issuer'], 'SEGA Aime');
    expect(fields['dataFormatCode'], 0x0078);
    expect(fields['idBlockHex'], '01234567890123456789000000000000');
    final capture = jsonDecode(jsonEncode(captureReadResult(outcome))) as Map;
    expect(capture['amusementIc'], fields);
    expect(capture['idm'], _idm);
    expect(capture['wallets'], isEmpty);
    expect(capture['transactions'], isEmpty);

    final partial = jsonDecode(
      jsonEncode(captureReadResult(FelicaReadOutcome(_card(data: _partial)))),
    ) as Map;
    expect((partial['amusementIc'] as Map)['accessCode'], isNull);
    expect((partial['amusementIc'] as Map)['dataFormatCode'], 99);
    expect((partial['amusementIc'] as Map)['note'], _partial.note);
  });

  testWidgets(
    'memory restart displays automatically saved access code without NFC replay or duplicate saves',
    (tester) async {
      final memory = _Memory();
      final nfc = _Nfc();
      final app = _app(memory, nfc);
      await tester.runAsync(() async {
        await app.init();
        final outcome = FelicaReadOutcome(_card());
        app.scan.outcome = outcome;
        await app.scan.onCompleted!(
          outcome,
          'amusement-ic-read',
          outcome.card.scannedAt,
          () => true,
        );
        expect(app.pendingCardSave, isNull);
        expect(await app.handleMemoryPressure(true), isTrue);
        expect(
          await app.cardRepository.db
              .select(app.cardRepository.db.savedCards)
              .get(),
          hasLength(1),
        );
        expect(
          await app.cardRepository.db
              .select(app.cardRepository.db.cardReadBatches)
              .get(),
          hasLength(1),
        );
      });
      final captured = RecoveryState.decode(memory.text!).capture!;
      expect((captured.summary['decoded'] as Map)['amusementIc'], isA<Map>());
      expect(captured.canSave, isFalse);
      app.dispose();

      // A restart retains the same archive. Reuse its real in-memory database
      // while replacing all app state; testDatabase owns its single teardown.
      final restored = _app(memory, nfc, database: app.cardRepository.db);
      await tester.runAsync(restored.init);
      await tester.pumpWidget(_page(RecoveryResultPanel(app: restored)));
      expect(find.text(_accessCode), findsOneWidget);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text('SEGA Aime'), findsOneWidget);
      expect(find.text(_idm), findsOneWidget);
      expect(find.text('保存这次读取'), findsNothing);
      expect(find.textContaining('读取时余额'), findsNothing);
      expect(nfc.scans, 0);
      expect(nfc.commands, isEmpty);
      await tester.runAsync(() async {
        expect(
          await restored.cardRepository.db
              .select(restored.cardRepository.db.savedCards)
              .get(),
          hasLength(1),
        );
        expect(
          await restored.cardRepository.db
              .select(restored.cardRepository.db.cardReadBatches)
              .get(),
          hasLength(1),
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'partial recovery uses frozen unknown-format note and never derives access code from raw bytes',
    (tester) async {
      final at = DateTime.now();
      final memory = _Memory()
        ..text = RecoveryState(
          savedAt: at,
          tab: 0,
          capture: RecoveryCapture(
            readAt: at,
            summary: const {
              'cardName': 'Amusement IC',
              'idm': _idm,
              'decoded': {
                'productType': 'amusementIc',
                'amusementIc': {
                  'accessCode': null,
                  'dataFormatCode': 99,
                  'note': '未知数据格式，尚未解析 Access Code。',
                  'idBlockHex': '01234567890123456789000000000000',
                },
              },
            },
            frames: const [],
          ),
        ).encode();
      final nfc = _Nfc();
      final app = _app(memory, nfc);
      await tester.runAsync(app.init);
      await tester.pumpWidget(_page(RecoveryResultPanel(app: app)));
      expect(find.text('Access Code 未读取'), findsOneWidget);
      expect(find.text(_partial.note!), findsOneWidget);
      expect(find.text(_idm), findsOneWidget);
      expect(find.text(_accessCode), findsNothing);
      expect(find.text(_groupedCode), findsNothing);
      expect(find.text('保存这次读取'), findsNothing);
      expect(nfc.scans, 0);
      expect(nfc.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

FelicaScanResult _card({AmusementIcData? data = _complete}) => FelicaScanResult(
  cardType: 'amusementIc',
  displayName: 'Amusement IC',
  cardProductType: FelicaCardType.amusementIc,
  idm: _idm,
  scannedAt: DateTime(2026, 11, 16, 12),
  amusementIc: data,
  statuses: [
    FelicaReadStatus(
      stage: 'Amusement IC',
      state: data?.accessCode == null
          ? FelicaReadState.partial
          : FelicaReadState.success,
      message: data?.accessCode == null ? '读取未完成' : '读取成功',
    ),
  ],
);

Widget _page(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

AppDependencies _app(_Memory memory, _Nfc nfc, {AppDatabase? database}) {
  final app = AppDependencies(
    database: database ?? testDatabase(),
    memoryPlatform: memory,
    channel: nfc,
    bundle: MissingTestAssets(),
    settingsStore: MemorySettingsStore({SettingsKeys.autoSaveEnabled: 'true'}),
    logger: AppLogger(store: MemoryLogStore()),
  );
  addTearDown(() {
    if (!app.disposed) app.dispose();
  });
  return app;
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

class _Nfc implements NfcChannel {
  int scans = 0;
  final commands = <List<int>>[];
  @override
  Future<NfcScanResult?> scanOnce() async {
    scans++;
    return null;
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async {
    commands.add(List.of(apdu));
    return [0x6A, 0x82];
  }
}
