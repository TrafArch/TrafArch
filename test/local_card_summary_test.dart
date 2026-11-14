import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/expert/expert_widgets.dart';
import 'package:transit_card_analyzer/features/expert/macau_pass_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

class _App extends AppDependencies {
  _App(this.card)
    : super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  final ParsedCard card;

  @override
  ParsedCard? get parsedCard => card;

  @override
  ReadResult? get localReadResult => card.localCard;

  @override
  Currency get cardCurrency =>
      Currency.fromCode(card.localCard?.info.currencyCode);

  @override
  String? get cardCityCode => null;

  @override
  String? cityNameOf(String? code) => null;
}

ParsedCard _lingnanCard() {
  final info = CardInfo()
    ..isLNT = true
    ..isYCT = true
    ..cardNumber = '9357249770'
    ..issuerCode = '01015100'
    ..currencyCode = 'CNY'
    ..balance = 4125
    ..issueDate = DateTime(2016, 8, 15)
    ..expiryDate = DateTime(2026, 12, 31);
  final extras = CardExtras()
    ..slots['lnt.ticlConfirmed'] = true
    ..slots['lnt.tuConfirmed'] = false;
  final trip = ApduRecord()
    ..type = 2
    ..timestamp = DateTime(2026, 10, 29, 19, 24, 17);
  return ParsedCard(
    parserId: CardParserIds.lingnanTong,
    parserName: '地方交通卡 · 岭南通',
    info: const TUnionCardInfo(applicationSerial: '9357249770'),
    transactions: const [],
    localCard: ReadResult(info: info, records: [trip], extras: extras),
  );
}

ParsedCard _macauCard() {
  final info = CardInfo()
    ..isMacauPass = true
    ..cardNumber = '6132766247'
    ..currencyCode = 'MOP'
    ..balance = 165;
  final record = ApduRecord()
    ..label = '澳门通交易记录'
    ..recordNumber = 1
    ..timestamp = DateTime(2026, 7, 18, 13, 16, 28);
  return ParsedCard(
    parserId: CardParserIds.localCard,
    parserName: '地方交通卡 · 澳门通',
    info: const TUnionCardInfo(applicationSerial: '6132766247'),
    transactions: const [],
    localCard: ReadResult(info: info, records: [record], extras: CardExtras()),
  );
}

void main() {
  testWidgets('双应用仅 TU 余额可读时不把岭南通余额当作零', (tester) async {
    final localInfo = CardInfo()
      ..isLNT = true
      ..isYCT = true;
    final card = ParsedCard(
      parserId: CardParserIds.lingnanTunion,
      parserName: '岭南通（交通联合版）',
      info: const TUnionCardInfo(balanceFen: 4500),
      transactions: const [],
      localCard: ReadResult(
        info: localInfo,
        records: const [],
        extras: CardExtras(),
      ),
    );
    final app = _App(card);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('岭南通余额'), findsNothing);
    expect(find.text('¥45.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('岭南通单标卡摘要统一显示岭南通且隐藏未确认互通状态', (tester) async {
    final app = _App(_lingnanCard());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );

    expect(find.text('岭南通'), findsWidgets);
    expect(find.text('岭南通·羊城通'), findsNothing);
    expect(find.text('发卡日期'), findsNothing);
    expect(find.text('岭南通应用'), findsNothing);
    expect(find.text('岭南通钱包应用'), findsNothing);
    expect(find.text('发卡机构编码'), findsNothing);
    expect(find.text('2026-12-31'), findsOneWidget);
    expect(find.text('¥41.25'), findsOneWidget);
    expect(find.text('全国互联互通'), findsNothing);
    expect(find.text('交易记录'), findsNothing);
    expect(find.text('最近交易'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('澳门通摘要展示卡号、MOP余额、应用状态和流水时间', (tester) async {
    final app = _App(_macauCard());
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );

    expect(find.text('澳门通'), findsWidgets);
    expect(find.text('澳门'), findsOneWidget);
    expect(find.text('未识别'), findsNothing);
    expect(find.text('MOP \$165'), findsOneWidget);
    expect(find.text('澳门通钱包应用已确认'), findsOneWidget);
    expect(find.text('2026-07-18 13:16:28'), findsOneWidget);
    expect(find.text('卡种细分'), findsNothing);
    expect(find.text('有效期至'), findsNothing);
    expect(find.text('交通联合状态'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('澳门通专家面板列出可确认信息和交易原始记录', (tester) async {
    final result = _macauCard().localCard!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MacauPassPanel(result: result)),
      ),
    );

    final fields = tester
        .widgetList<ExpertField>(find.byType(ExpertField))
        .toList();
    String value(String label) =>
        fields.singleWhere((field) => field.label == label).value;
    expect(value('识别状态'), '澳门通钱包应用已确认');
    expect(value('卡号'), '6132766247');
    expect(value('余额'), 'MOP \$165');
    expect(value('有效期至'), '未读取');
    expect(find.text('记录 1：'), findsOneWidget);
    expect(find.textContaining('2026-07-18 13:16:28'), findsOneWidget);
  });
}
