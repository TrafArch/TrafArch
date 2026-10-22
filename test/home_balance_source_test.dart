import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

ParsedCard _card(int? balance, {int? cuBalance}) => ParsedCard(
  parserId: CardParserIds.shanghaiTunion,
  parserName: '上海交通卡（交通联合版）',
  selectedAidHex: 'A000000632010105',
  info: TUnionCardInfo(
    applicationSerial: '00310477000000000001',
    issuerId: '0200290000000000',
    cityCode: '2900',
    balanceFen: balance,
  ),
  transactions: const [],
  dualApplication: cuBalance != null,
  cityUnionBalanceFen: cuBalance,
);

/// Isolate the display contract from analysis timing. A deliberately stale
/// analysis snapshot is a guard case, not a reproduction of the phone's +8.
class _SummaryApp extends AppDependencies {
  _SummaryApp(this.current, {int? analyzedBalance})
    : cachedAnalysis = AnalysisEngine(KnowledgeBase.empty())
          .analyze(_card(analyzedBalance)),
      super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );

  final ParsedCard current;
  final CardAnalysisResult cachedAnalysis;
  @override
  ParsedCard get parsedCard => current;
  @override
  CardAnalysisResult get analysis => cachedAnalysis;
  @override
  int? get cityUnionBalanceFen => current.cityUnionBalanceFen;
}

void main() {
  testWidgets('首页余额使用本次解析值，不使用旧的分析摘要', (tester) async {
    final app = _SummaryApp(_card(10000), analyzedBalance: 10800);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('¥108.00'), findsNothing);
  });

  testWidgets('本次没有余额时不把旧摘要显示为当前余额', (tester) async {
    final app = _SummaryApp(_card(null), analyzedBalance: 10800);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥108.00'), findsNothing);
  });

  testWidgets('上海双应用的两个余额分行显示，不覆盖也不相加', (tester) async {
    final app = _SummaryApp(
      _card(10000, cuBalance: 800),
      analyzedBalance: 10800,
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('城市一卡通余额'), findsOneWidget);
    expect(find.text('8.00 元'), findsOneWidget);
    expect(find.text('¥108.00'), findsNothing);
  });

  testWidgets('成功读取零余额时不使用旧摘要的非零余额', (tester) async {
    final app = _SummaryApp(_card(0), analyzedBalance: 10800);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('¥108.00'), findsNothing);
  });
}
