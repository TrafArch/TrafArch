import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/expert/expert_page.dart';
import 'package:transit_card_analyzer/features/expert/expert_widgets.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

ParsedCard _card(
  int? balance, {
  int? cuBalance,
  String parserId = CardParserIds.shanghaiTunion,
  String selectedAidHex = 'A000000632010105',
  String? cuCity,
}) => ParsedCard(
  parserId: parserId,
  parserName: '上海交通卡（交通联合版）',
  selectedAidHex: selectedAidHex,
  info: TUnionCardInfo(
    applicationSerial: '00310477000000000001',
    issuerId: '0200290000000000',
    cityCode: '2900',
    balanceFen: balance,
  ),
  transactions: const [],
  dualApplication: cuBalance != null,
  cityUnionBalanceFen: cuBalance,
  cityUnionFiles: [
    if (cuCity != null)
      CjT331PublicInfo(cityCode: cuCity, fields: const [], rawHex: '00'),
  ],
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
  @override
  CjT331PublicInfo? get cityUnionPublicInfo =>
      current.cityUnionFiles.whereType<CjT331PublicInfo>().firstOrNull;
}

void main() {
  testWidgets('上海TU含额度89元和CU实余额81元，关闭显示81/81且CU切换不变', (tester) async {
    final app = _SummaryApp(_card(8900, cuBalance: 8100));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: app,
            builder: (_, _) => TransitSummaryPanel(app: app),
          ),
        ),
      ),
    );
    expect(find.text('¥81.00'), findsOneWidget);
    expect(find.text('81.00 元'), findsOneWidget);
    expect(find.text('73.00 元'), findsNothing);
    await app.setIncludeShanghaiOverdraft(true);
    await tester.pump();
    expect(find.text('¥89.00'), findsOneWidget);
    expect(find.text('81.00 元'), findsOneWidget);
    await app.setIncludeShanghaiOverdraft(false);
    await tester.pump();
    expect(find.text('¥81.00'), findsOneWidget);
    expect(find.text('81.00 元'), findsOneWidget);
    expect(app.parsedCard.info.balanceFen, 8900);
    expect(app.parsedCard.cityUnionBalanceFen, 8100);
  });

  testWidgets('普通TU不会因上海城市信息而扣除额度', (tester) async {
    final app = _SummaryApp(_card(10000, parserId: CardParserIds.tunion));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('¥92.00'), findsNothing);
  });

  testWidgets('上海城市一卡通单标卡实余额不再次扣除额度', (tester) async {
    final app = _SummaryApp(
      _card(10000, parserId: CardParserIds.cityUnion, cuCity: '2000'),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥100.00'), findsOneWidget);
  });

  testWidgets('首页余额使用本次解析值，不使用旧的分析摘要', (tester) async {
    final app = _SummaryApp(_card(10000), analyzedBalance: 10800);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥92.00'), findsOneWidget);
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
    expect(find.text('¥92.00'), findsOneWidget);
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
    expect(find.text('¥-8.00'), findsOneWidget);
    expect(find.text('¥108.00'), findsNothing);
  });

  testWidgets('上海TU钱包不可读时CU余额保持81元', (tester) async {
    final app = _SummaryApp(_card(null, cuBalance: 8100));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('81.00 元'), findsOneWidget);
    expect(find.text('73.00 元'), findsNothing);
  });

  testWidgets('上海仅CU应用可用时统一卡信息中的CU余额也不扣8元', (tester) async {
    final app = _SummaryApp(
      _card(8100, selectedAidHex: 'A00000000386980701', cuCity: '2000'),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('¥81.00'), findsOneWidget);
    expect(find.text('¥73.00'), findsNothing);
  });

  testWidgets('专家页面双应用CU钱包保持81元，TU余额仍由开关控制', (tester) async {
    final app = _SummaryApp(
      _card(8900, cuBalance: 8100, cuCity: '2000'),
      analyzedBalance: 8900,
    );
    addTearDown(app.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ExpertPage(app: app)));
    await tester.tap(find.text('交通数据解析'));
    await tester.pumpAndSettle();
    final cu = find.byWidgetPredicate(
      (widget) => widget is ExpertField && widget.label == '城市一卡通钱包余额',
    );
    expect(tester.widget<ExpertField>(cu).value, '81.00 元');
    expect(find.text('¥81.00'), findsOneWidget);
    await app.setIncludeShanghaiOverdraft(true);
    await tester.pumpAndSettle();
    expect(tester.widget<ExpertField>(cu).value, '81.00 元');
    expect(find.text('¥89.00'), findsOneWidget);
  });
}
