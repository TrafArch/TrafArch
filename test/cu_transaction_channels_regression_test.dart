import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/city_union_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/cu_transaction_list.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/cj_t331_wallet_local_consumption_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

// TripReader 1.7.17 L0/d.smali (case-safe d.1.smali): 28161 P2=84;
// 28203/28211 compare CU city 2000/2153, then 28228 D4 or 28257 34.
void main() {
  for (final sample in [
    (0x20, 0x00, 0x06),
    (0x21, 0x53, 0x06),
    (0x31, 0x00, 0x1A),
  ]) {
    test(
      'CU ${sample.$1.toRadixString(16)}${sample.$2.toRadixString(16)} reads recharge and foreign channels by profile',
      () async {
        final commands = <String>[];
        final info = CardInfo();
        final records = <ApduRecord>[];
        final cu = CommonUnitCu(
          ApduExchange(
            transceive: (command) async {
              commands.add(_hex(command));
              if (command[1] == 0xA4) return [0x90, 0];
              if (command[1] == 0xB0) {
                return [
                  0,
                  0,
                  sample.$1,
                  sample.$2,
                  ...List.filled(26, 0),
                  0x90,
                  0,
                ];
              }
              if (command[1] == 0xB2 && command[2] == 1) {
                final sfi = command[3] >> 3;
                if ([0x18, 0x10, sample.$3].contains(sfi)) {
                  return [
                    ..._record('200011023400', type: sfi == 0x10 ? 2 : 6),
                    0x90,
                    0,
                  ];
                }
              }
              return [0x6A, 0x83];
            },
          ),
        );
        expect(await cu.select(info, records), isTrue);
        final card = (await cu.read(info, records))!;
        expect(commands, contains('00B2018417'));
        expect(
          commands,
          contains(
            '00B201${((sample.$3 << 3) | 4).toRadixString(16).toUpperCase().padLeft(2, '0')}17',
          ),
        );
        expect(
          card.cityUnionFiles.whereType<CjT331WalletRecharge>().single.sfi,
          0x10,
        );
        expect(
          card.cityUnionFiles
              .whereType<CjT331WalletOfflineTransaction>()
              .single
              .sfi,
          sample.$3,
        );
        expect(records.map((record) => record.fileSelector), [
          0x18,
          0x10,
          sample.$3,
        ]);
      },
    );
  }

  testWidgets(
    'CU terminal lookup preserves raw HEX even when standard BCD field is invalid',
    (tester) async {
      String? receivedTerminal;
      final record = CjT331WalletLocalConsumptionParser.parseRecord(
        _record('2000110A0100'),
      );
      expect(record.terminalNumber, isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CityUnionPanel(
                files: [record],
                resolveStationName:
                    (
                      terminal, {
                      cityCode,
                      decodedCarrierType,
                      transactionTime,
                      busLookupEnabled = false,
                    }) {
                      receivedTerminal = terminal;
                      return null;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('电子钱包本地消费交易明细（0x18）'));
      await tester.pumpAndSettle();
      expect(receivedTerminal, '2000110A0100');
    },
  );

  test('CU scan projection retains source file, raw identifiers and unknown classifications', () {
    final files = [
      CityUnionFileParser.parseWalletRecord(
        0x18,
        _record('2000110A0100'),
        kind: CityUnionTransactionKind.consumption,
        recordNumber: 3,
      ),
      CityUnionFileParser.parseWalletRecord(
        0x06,
        _record('310099999999'),
        kind: CityUnionTransactionKind.foreignConsumption,
        recordNumber: 1,
      ),
      CityUnionFileParser.parseWalletRecord(
        0x10,
        _record('000000000001', type: 2),
        kind: CityUnionTransactionKind.recharge,
        recordNumber: 2,
      ),
    ];
    final view = ScanPresentation(
      TransitReadOutcome(
        ParsedCard(
          parserId: CardParserIds.cityUnion,
          parserName: 'CU',
          info: const TUnionCardInfo(),
          transactions: const [],
          cityUnionFiles: files,
        ),
      ),
      KnowledgeBase.empty(),
    );
    expect(view.analysis, isNull);
    expect(view.cityUnionTransactions, hasLength(3));
    expect(view.cityUnionTransactions[0].sourceLabel, 'CU 0x18 #3');
    expect(view.cityUnionTransactions[0].record.terminalHex, '2000110A0100');
    expect(view.cityUnionTransactions[0].regionCode, '2000');
    expect(view.cityUnionTransactions[0].carrier, 2);
    expect(view.cityUnionTransactions[1].regionCode, isNull);
    expect(view.cityUnionTransactions[1].carrier, isNull);
    expect(view.cityUnionTransactions[2].record.terminalHex, '000000000001');
    expect(view.cityUnionTransactions[2].kindLabel, '充值');
  });

  testWidgets(
    'CU transaction list displays partial records independently of TU analysis',
    (tester) async {
      final transaction = CityUnionFileParser.parseWalletRecord(
        0x06,
        _record('518020000001'),
        kind: CityUnionTransactionKind.foreignConsumption,
        recordNumber: 5,
      );
      final views = analyzeCuTransactions([transaction], KnowledgeBase.empty());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CuTransactionList(transactions: views),
            ),
          ),
        ),
      );
      expect(find.text('城市一卡通 · 1 条记录'), findsOneWidget);
      expect(find.text('异地消费 · 地点未匹配'), findsOneWidget);
      await tester.tap(find.text('异地消费 · 地点未匹配'));
      await tester.pumpAndSettle();
      expect(find.text('终端原始编码：518020000001'), findsOneWidget);
      expect(find.text('金额原始值：1（单位未确认）'), findsOneWidget);
      expect(find.textContaining('CU 0x06 #5'), findsOneWidget);
    },
  );
}

List<int> _record(String terminal, {int type = 6}) => [
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  1,
  type,
  for (var index = 0; index < terminal.length; index += 2)
    int.parse(terminal.substring(index, index + 2), radix: 16),
  0x20,
  0x24,
  0x09,
  0x20,
  0x12,
  0,
  0,
];

String _hex(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();
