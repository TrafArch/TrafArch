import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/expert/compliance_panel.dart';
import 'package:transit_card_analyzer/features/expert/expert_formatters.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/settings/presentation/settings_page.dart';
import 'package:transit_card_analyzer/features/transit_analysis/shanghai_balance_display.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('读卡与数据中的新开关默认关闭，点击后持久化', (tester) async {
    final store = MemorySettingsStore();
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: store,
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: SettingsPage(app: app)));
    final tile = find.widgetWithText(SwitchListTile, '上海交通卡可透支余额');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(store.values[SettingsKeys.includeShanghaiOverdraft], 'true');
  });

  testWidgets('专家符合性余额采用同一展示口径且分析原值保留', (tester) async {
    final analysis = AnalysisEngine(KnowledgeBase.empty()).analyze(
      ParsedCard(
        parserId: CardParserIds.shanghaiTunion,
        parserName: '上海交通卡',
        info: TUnionCardInfo(balanceFen: 10800),
        transactions: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompliancePanel(
              analysis: analysis,
              balanceDisplay: const ShanghaiBalanceDisplay(offsetFen: -800),
            ),
          ),
        ),
      ),
    );
    expect(find.text('余额 100.00 元'), findsOneWidget);
    expect(analysis.wallet.balanceFen, 10800);
    expect(
      analysis.compliance.items
          .singleWhere((item) => item.id == 'balance')
          .detail,
      '余额 108.00 元',
    );
  });

  test('专家记录余额扣除额度，金额与十六进制观察保持原值', () {
    final values = ExpertValues(
      currency: Currency.cny,
      cityNameOf: (_) => null,
      balanceDisplay: const ShanghaiBalanceDisplay(offsetFen: -800),
    );
    expect(values.balanceCell(800), '(00000320)0.0元');
    expect(values.balanceCell(500), '(000001f4)-3.0元');
    expect(values.amountCell(800), '(00000320)8.0元');
    expect(values.balanceCell(null), '未知');
  });
}
