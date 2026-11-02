import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/expert/expert_page.dart';
import 'package:transit_card_analyzer/features/expert/expert_widgets.dart';
import 'package:transit_card_analyzer/features/expert/identity_panel.dart';
import 'package:transit_card_analyzer/features/expert/tunion_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

class _ExpertApp extends AppDependencies {
  _ExpertApp(this.card)
    : super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  final ParsedCard card;
  @override
  ParsedCard get parsedCard => card;
  @override
  CardAnalysisResult get analysis =>
      AnalysisEngine(KnowledgeBase.empty()).analyze(card);
}

ReadResult _local({bool empty = false, int type = 0x09}) => ReadResult(
  info: CardInfo()
    ..isLNT = true
    ..cardNumber = '9534635882'
    ..balance = 3840,
  records: [
    ApduRecord()..label = 'SELECT PAY.APPY',
    if (!empty)
      ApduRecord()
        ..type = 2
        ..recordNumber = 7
        ..rawBody = Uint8List.fromList([0x12, 0x34])
        ..posType = type
        ..balanceDelta = type == 0x02 ? 100 : -100
        ..timestamp = DateTime.utc(2024, 10, 27, 21, 13)
        ..terminalHex = '010203040506',
  ],
  extras: CardExtras(),
  readError: 'LNT partial read',
);

ParsedCard _card(String parserId, ReadResult local) => ParsedCard(
  parserId: parserId,
  parserName: '岭南通',
  info: const TUnionCardInfo(applicationSerial: 'TU-card', balanceFen: 10000),
  transactions: [
    TUnionTransaction(
      sequence: 99,
      overdraftLimitFen: 0,
      amountFen: 200,
      rawType: 0x06,
      terminalId: '998877665544',
      time: DateTime(2025, 5, 1, 8, 30, 45),
    ),
  ],
  localCard: local,
);

List<ExpertField> _fields(WidgetTester tester, Type panel) => tester
    .widgetList<ExpertField>(
      find.descendant(
        of: find.byType(panel),
        matching: find.byType(ExpertField),
      ),
    )
    .toList();

const _labels = ['交易记录', '最近交易', '交易金额', '交易类型', '交易序号', '终端编号'];

void main() {
  for (final id in [CardParserIds.lingnanTong, CardParserIds.lingnanTunion]) {
    for (final empty in [false, true]) {
      testWidgets('$id routes LNT transactions to transit tab (empty=$empty)', (
        tester,
      ) async {
        final app = _ExpertApp(_card(id, _local(empty: empty)));
        addTearDown(app.dispose);
        await tester.binding.setSurfaceSize(const Size(1000, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: ExpertPage(app: app)));
        final identity = _fields(tester, IdentityPanel);
        expect(
          identity.map((f) => f.label),
          containsAll(['岭南通应用', '岭南通卡号', '岭南通钱包余额', '岭南通读取异常']),
        );
        expect(identity.any((f) => f.label.contains('交易')), isFalse);

        await tester.tap(find.text('交通数据解析'));
        await tester.pumpAndSettle();
        expect(find.byType(LingnanTransactionPanel), findsOneWidget);
        final fields = _fields(tester, LingnanTransactionPanel);
        expect(fields.map((f) => f.label), _labels);
        expect(
          fields.map((f) => f.value),
          empty
              ? ['0 条', '未知', '未知', '未知', '未知', '未知']
              : [
                  '1 条',
                  '2024-10-27 21:13（年份推断，秒未知）',
                  'CNY -1.00',
                  '复合消费',
                  '4660',
                  '010203040506',
                ],
        );
        expect(fields.any((f) => f.label == '终端解码'), isFalse);
        if (id == CardParserIds.lingnanTunion) {
          final tu = _fields(tester, TunionPanel);
          String value(String label) =>
              tu.singleWhere((f) => f.label == label).value;
          expect(value('交易记录'), '1 条');
          expect(value('交易序号'), '99');
          expect(value('终端编号'), '998877665544');
          expect(value('交易类型'), '消费');
          expect(value('交易金额'), isNot('CNY -1.00'));
          expect(
            tester.getTopLeft(find.byType(TunionPanel)).dy,
            lessThan(
              tester.getTopLeft(find.byType(LingnanTransactionPanel)).dy,
            ),
          );
        } else {
          expect(find.byType(TunionPanel), findsNothing);
          expect(find.text('当前解析器暂未提供交通数据字段视图'), findsNothing);
        }
      });
    }
  }

  for (final entry in {
    0x02: '充值',
    0x06: '消费',
    0x09: '复合消费',
    0xAB: '0xAB',
  }.entries) {
    testWidgets('LNT native type ${entry.key} retains its display meaning', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LingnanTransactionPanel(result: _local(type: entry.key)),
          ),
        ),
      );
      final fields = _fields(tester, LingnanTransactionPanel);
      expect(fields.singleWhere((f) => f.label == '交易类型').value, entry.value);
      expect(
        fields.singleWhere((f) => f.label == '交易金额').value,
        entry.key == 0x02 ? 'CNY 1.00' : 'CNY -1.00',
      );
    });
  }

  testWidgets('LNT unknown date and absent sequence do not use defaults', (
    tester,
  ) async {
    final result = _local();
    result.trips.single
      ..timestamp = DateTime.fromMillisecondsSinceEpoch(0)
      ..rawBody = Uint8List.fromList([0x12])
      ..terminalHex = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LingnanTransactionPanel(result: result)),
      ),
    );
    final fields = _fields(tester, LingnanTransactionPanel);
    for (final label in ['最近交易', '交易序号', '终端编号']) {
      expect(fields.singleWhere((f) => f.label == label).value, '未知');
    }
  });
}
