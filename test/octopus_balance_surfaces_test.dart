import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_name_extension.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

// 4225 is the reported parsed output. No raw balance response or exchange
// rate has been supplied. These tests prevent mislabelling; they do not claim
// to reproduce a real HKD balance read or satisfy the user's HK$50 target.
ParsedCard _card(int? amount) => ParsedCard(
  parserId: CardParserIds.tunion,
  parserName: '交通联合',
  selectedAidHex: 'A000000632010105',
  info: TUnionCardInfo(
    applicationSerial: '00310485000000000001',
    balanceFen: amount,
  ),
  transactions: const [],
);

KnowledgeBase _knowledge({String? currency}) => KnowledgeBase.fromJsonStrings(
  cardPrefixes: jsonEncode({
    'entries': [
      {
        'prefix': '31048500',
        'cardName': '八达通-全国通卡',
        'city': '香港',
        'currency': currency,
      },
    ],
  }),
);

class _App extends AppDependencies {
  _App(this.card)
    : result = AnalysisEngine(_knowledge()).analyze(card),
      super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
  final ParsedCard card;
  final CardAnalysisResult result;
  @override
  ParsedCard get parsedCard => card;
  @override
  CardAnalysisResult get analysis => result;
}

void main() {
  testWidgets(r'八达通首页不把 TU 4225 冒充账户余额或 HK$42.25', (tester) async {
    final app = _App(_card(4225));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text('港币余额未读取'), findsOneWidget);
    expect(find.text('TU侧金额'), findsOneWidget);
    expect(find.text('¥42.25'), findsOneWidget);
    expect(find.text('HK\$42.25'), findsNothing);
    expect(find.text('HK\$50.00'), findsNothing);
  });

  test('前缀 HKD 是账户元数据，不能更改 TU 观察金额单位', () {
    final result = AnalysisEngine(_knowledge(currency: 'HKD'))
        .analyze(_card(4225));
    expect(result.currency.code, 'CNY');
  });

  test('归档保留4225与未知港币余额的独立解释，部分读取不改口径', () async {
    final repository = CardRepository(testDatabase());
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    controller.stage(
      ScanPresentation(TransitReadOutcome(_card(4225)), _knowledge()),
      'octopus-read-1',
      DateTime(2026, 10, 21, 8),
      const [],
    );
    final pending = controller.pending!;
    expect(pending.balanceFen, 4225);
    expect(pending.currencyCode, 'CNY');
    final snapshot = CardSessionSnapshot.decode(pending.sessionDataJson!)!;
    final interpretation =
        snapshot.context.extensions['balanceInterpretation']
            as Map<String, dynamic>?;
    expect(interpretation, isNotNull);
    expect(interpretation!['accountCurrency'], 'HKD');
    expect(interpretation['accountBalanceMinor'], isNull);
    expect(interpretation['observedAmountMinor'], 4225);
    expect(interpretation['exchangeRate'], isNull);
    expect(await controller.accept(pending.pendingSaveId), isTrue);
    final card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 4225);
    expect(card.balanceText, '港币余额未读取');
    expect(
      (await ArchiveHistory(repository).load(card.id)).balanceText,
      '港币余额未读取',
    );

    controller.stage(
      ScanPresentation(TransitReadOutcome(_card(null)), _knowledge()),
      'octopus-read-2',
      DateTime(2026, 10, 21, 9),
      const [],
    );
    expect(await controller.accept('octopus-read-2'), isTrue);
    final history = await ArchiveHistory(repository).load(card.id);
    expect(history.card!.balanceFen, 4225);
    expect(history.balanceText, '港币余额未读取');
  });

  test('旧八达通档案不改历史原值，也不把历史CNY金额当港币账户余额', () async {
    final repository = CardRepository(testDatabase());
    const legacy = '{"v":2,"trips":[],"rails":[],"buses":[],"cycle":[]}';
    await repository.saveIdentity(
      fingerprint: 'octopus-legacy',
      identity: const CardArchiveIdentity(cardType: CardTypes.octopusTunion),
      cardNumber: '310485000000000001',
      balanceFen: 4225,
      currencyCode: 'CNY',
      sessionDataJson: legacy,
      readAt: DateTime(2026, 10, 20),
    );
    final card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 4225);
    expect(card.currencyCode, 'CNY');
    expect(card.sessionDataJson, legacy);
    expect(card.balanceText, contains('港币余额未读取'));
    final history = await ArchiveHistory(repository).load(card.id);
    expect(history.balanceText, contains('港币余额未读取'));
    expect(
      buildArchiveHistoryExport([history]),
      contains('历史金额（口径待核验）：¥ 42.25'),
    );
  });

  testWidgets('旧八达通摘要在手机宽度下可完整阅读', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = _App(_card(4225));
    addTearDown(app.dispose);
    await tester.runAsync(
      () => app.cardRepository.saveIdentity(
        fingerprint: 'octopus-phone-width',
        identity: const CardArchiveIdentity(cardType: CardTypes.octopusTunion),
        balanceFen: 4225,
        currencyCode: 'CNY',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CardsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('港币余额未读取'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
