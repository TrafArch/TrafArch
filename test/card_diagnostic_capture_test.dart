import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/raw_data_panel.dart';
import 'package:flutter/material.dart';
import 'package:transit_card_analyzer/features/scan/application/card_read_coordinator.dart';
import 'package:transit_card_analyzer/features/scan/application/scan_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/settings/application/diagnostic_export.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/shared/diagnostics/raw_data_category.dart';

import 'support/test_database.dart';

// Synthetic identities and process bytes; no real passenger information.
const _process = [
  TUnionProcessRecord(
    sfi: 0x1A,
    recordNumber: 1,
    recordName: 'rail',
    raw: [1, 2],
  ),
  TUnionProcessRecord(
    sfi: 0x1A,
    recordNumber: 2,
    recordName: 'bus',
    raw: [3, 4],
  ),
  TUnionProcessRecord(
    sfi: 0x1A,
    recordNumber: 0,
    recordName: 'whole',
    raw: [5],
  ),
  TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: 7,
    recordName: 'cycle',
    raw: [6, 7],
    recordNumberIsReliable: false,
  ),
  TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: 8,
    recordName: 'blank',
    raw: [0, 0],
  ),
];

void main() {
  test('扫描日志和完整JSON保存卡号卡名卡种、分类原始APDU及全部过程记录', () async {
    final logger = AppLogger(store: MemoryLogStore())..enabled = true;
    addTearDown(logger.close);
    final channel = _Channel();
    final scan = ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: _Coordinator(),
      logEvent: (_) {},
      diagnostics: logger,
    );
    addTearDown(scan.dispose);
    await scan.scanOnce();
    final session = (await logger.readSessions()).single;
    expect(session.cardInfo?['cardNumber'], '123456');
    expect(session.cardInfo?['applicationSerialRaw'], '000000123456');
    expect(session.cardInfo?['cardName'], '合成交通联合卡');
    expect(session.cardInfo?['cardType'], CardParserIds.tunion);
    expect(session.cardInfo?['cardKindRaw'], '01');
    final exportedText = buildFullDiagnostics([session], DateTime.utc(2026));
    expect(RegExp(r'"raw":\s*\[\s*\n').hasMatch(exportedText), isFalse);
    final full = jsonDecode(exportedText) as Map;
    final exported = (full['sessions'] as List).single as Map;
    expect(exported['cardInfo'], session.cardInfo);
    final apduGroups = (exported['apduGroups'] as List).cast<Map>();
    final frames =
        apduGroups.expand((g) => g['frames'] as List).cast<Map>().toList()
          ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
    expect(frames, hasLength(channel.commands.length));
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i]['command'], channel.commands[i]);
      expect(frames[i]['raw'], [i, 0x90, 0]);
      expect(frames[i]['response'], isA<Map>());
      expect(frames[i]['protocolStage'], '合成TU读取');
    }
    expect(
      apduGroups.singleWhere(
        (g) => g['category'] == 'file1A',
      )['frames'][0]['sfi'],
      0x1A,
    );
    expect(
      apduGroups.singleWhere(
        (g) => g['category'] == 'file1E',
      )['frames'][0]['recordNumber'],
      7,
    );
    final processes = (exported['processRecords'] as List).cast<Map>();
    expect(
      processes.singleWhere(
        (g) => g['category'] == 'rail1A',
      )['records'][0]['raw'],
      [1, 2],
    );
    expect(
      processes.singleWhere(
        (g) => g['category'] == 'bus1A',
      )['records'][0]['rawHex'],
      '03 04',
    );
    expect(
      processes.singleWhere(
        (g) => g['category'] == 'other1A',
      )['records'][0]['recordNumber'],
      0,
    );
    final cycle =
        processes.singleWhere((g) => g['category'] == 'cycle1E')['records']
            as List;
    expect(cycle, hasLength(2));
    expect(cycle[0]['recordNumberIsReliable'], isFalse);
    expect(cycle[0]['isDecoded'], isFalse);
    expect(cycle[1]['isBlank'], isTrue);
    expect(exported['rawJsonl'], session.raw);
  });

  test('文件分类保留协议差别：CU的0x1A不冒充TU轨道，FeliCa不按APDU解释', () {
    expect(
      classifyRawCommand([0, 0xB2, 1, 0xD4, 0]).category,
      RawDataCategory.file1A,
    );
    expect(
      classifyRawCommand([0, 0xB2, 1, 0xD4, 0], felica: true).category,
      RawDataCategory.felica,
    );
    expect(classifyRawCommand([0, 0xB0, 0x95, 0, 0]).sfi, 0x15);
    expect(classifyRawCommand([0, 0xB0, 0x15, 0, 0]).sfi, isNull);
    expect(classifyRawCommand([0, 0xB2, 1, 0, 0]).sfi, isNull);
    expect(classifyRawCommand([]).category, RawDataCategory.other);
  });

  testWidgets('专家原始页使用同样分类且保留完整通信顺序与过程原文', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RawDataPanel(
              apduLog: const [
                '>> 00 A4 04 00 01 A0\n<< 90 00',
                '>> 00 B2 01 D4 00\n<< 01 02 90 00',
                '>> 00 B2 07 F4 00\n<< 06 07 90 00',
              ],
              processRecords: _process,
            ),
          ),
        ),
      ),
    );
    for (final category in [
      RawDataCategory.selection,
      RawDataCategory.file1A,
      RawDataCategory.file1E,
    ]) {
      expect(find.text(category.label), findsOneWidget);
    }
    expect(find.text(ProcessDataCategory.rail1A.label), findsOneWidget);
    expect(find.text(ProcessDataCategory.bus1A.label), findsOneWidget);
    expect(find.text(ProcessDataCategory.cycle1E.label), findsNWidgets(2));
    expect(find.text('00 00'), findsOneWidget);
  });
}

class _Coordinator extends CardReadCoordinator {
  _Coordinator() : super(MissingTestAssets());
  @override
  Future<CardReadOutcome> read(
    NfcScanResult tag, {
    required Future<List<int>> Function(List<int>) apdu,
    required Future<List<int>> Function(List<int>) felica,
    required void Function(String) onStage,
    required void Function(int) onProgress,
  }) async {
    onStage('合成TU读取');
    for (final command in [
      [0, 0xA4, 4, 0, 1, 0xA0],
      [0x80, 0x5C, 0, 2, 4],
      [0, 0xB0, 0x95, 0, 0],
      [0, 0xB2, 1, 0xD4, 0],
      [0, 0xB2, 7, 0xF4, 0],
    ]) {
      await apdu(command);
    }
    return const TransitReadOutcome(
      ParsedCard(
        parserId: CardParserIds.tunion,
        parserName: '合成交通联合卡',
        info: TUnionCardInfo(applicationSerial: '000000123456', cardKind: '01'),
        transactions: [],
        transitProcessRecords: _process,
      ),
    );
  }
}

class _Channel implements NfcChannel {
  final commands = <List<int>>[];
  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: 'UID-is-not-card-number',
    technologies: const ['IsoDep'],
    isoDepConnected: true,
    timestamp: DateTime.utc(2026),
  );
  @override
  Future<List<int>> transceive(List<int> apdu) async {
    final index = commands.length;
    commands.add(List.of(apdu));
    return [index, 0x90, 0];
  }

  @override
  Future<void> stopScan() async {}
}
