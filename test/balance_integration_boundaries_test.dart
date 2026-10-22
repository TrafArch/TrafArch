import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_name_extension.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/domain/pending_card_save.dart';
import 'package:transit_card_analyzer/features/expert/expert_formatters.dart';
import 'package:transit_card_analyzer/features/expert/tunion_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/transit_summary_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/balance_interpretation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

ParsedCard _card(int? amount, {String serial = '00310485000000000001'}) =>
    ParsedCard(
      parserId: CardParserIds.tunion,
      parserName: '交通联合',
      selectedAidHex: 'A000000632010105',
      info: TUnionCardInfo(applicationSerial: serial, balanceFen: amount),
      transactions: const [],
    );

KnowledgeBase _knowledge() => KnowledgeBase.fromJsonStrings(
  cardPrefixes: jsonEncode({
    'entries': [
      {'prefix': '31048500', 'cardName': '八达通-全国通卡', 'currency': 'HKD'},
      {'prefix': '31049900', 'cardName': '其他外币卡', 'currency': 'HKD'},
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
  // 与生产一致：ScanPresentation.cardCurrency 取自同一份分析结果。
  @override
  Currency get cardCurrency => result.currency;
}

ArchiveController _controller(CardRepository repository) {
  final controller = ArchiveController(
    repository,
    const MethodChannelLogExporter(),
    (_) {},
  );
  addTearDown(controller.dispose);
  return controller;
}

PendingCardSave _stage(ArchiveController controller, ParsedCard card, int at) {
  controller.stage(
    ScanPresentation(TransitReadOutcome(card), _knowledge()),
    'read-$at',
    DateTime.fromMillisecondsSinceEpoch(at),
    const [],
  );
  return controller.pending!;
}

Future<void> _save(
  CardRepository repository,
  PendingCardSave item,
  int at, {
  String? payload,
}) => repository.saveIdentity(
  fingerprint: item.fingerprint,
  identity: item.identity,
  cardNumber: item.cardNumber,
  balanceFen: item.balanceFen,
  currencyCode: item.currencyCode,
  transactionCount: item.transactionCount,
  sessionDataJson: payload ?? item.sessionDataJson,
  parseVersion: kTripParseVersion,
  readAt: DateTime.fromMillisecondsSinceEpoch(at),
);

// A different interpretation of the SAME TU integer, supplied as explicit
// independent evidence only in this fixture. No reader infers HKD 5000.
String _verifiedPayload(PendingCardSave item) {
  final json = jsonDecode(item.sessionDataJson!) as Map<String, dynamic>;
  (json['context'] as Map<String, dynamic>)['balanceInterpretation'] =
      BalanceInterpretation.fromParsedCard(
        _card(4225),
        verifiedAccountBalance: VerifiedAccountBalance(
          amountMinor: 5000,
          currency: 'HKD',
          evidenceSource: 'independent-test-observation-B',
        ),
      ).toJson();
  return jsonEncode(json);
}

void main() {
  testWidgets('截断八达通身份在首页和专家页保持 unknown，不受 HKD 元数据影响', (tester) async {
    final card = _card(4225, serial: '003104850000000000');
    final app = _App(card);
    addTearDown(app.dispose);
    for (final panel in <Widget>[
      TransitSummaryPanel(app: app),
      TunionPanel(
        parsed: card,
        analysis: app.result,
        processRecords: const [],
        fallbackRail: null,
        values: ExpertValues(currency: Currency.hkd, cityNameOf: (_) => null),
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: panel)),
        ),
      );
      expect(find.text('余额未读取'), findsOneWidget);
      expect(find.text('4225 原始单位（币种未知）'), findsOneWidget);
      expect(find.text(r'HK$42.25'), findsNothing);
      expect(find.text('¥42.25'), findsNothing);
    }
  });

  testWidgets('普通非八达通 TU 保留首页和专家页既有外币展示', (tester) async {
    final card = _card(4225, serial: '00310499000000000001');
    final app = _App(card);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TransitSummaryPanel(app: app)),
      ),
    );
    expect(find.text(r'HK$42.25'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TunionPanel(
              parsed: card,
              analysis: app.result,
              processRecords: const [],
              fallbackRail: null,
              values: ExpertValues(
                currency: Currency.hkd,
                cityNameOf: (_) => null,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text(r'HK$42.25'), findsOneWidget);
  });

  test('普通非八达通 TU 保留既有外币归档策略', () async {
    final card = _card(4225, serial: '00310499000000000001');
    final repository = CardRepository(testDatabase());
    final controller = _controller(repository);
    final pending = _stage(controller, card, 100);
    expect(pending.currencyCode, 'HKD');
    expect(await controller.accept(pending.pendingSaveId), isTrue);
    final saved = (await repository.getAllCards()).single;
    expect(saved.balanceText, r'HK$ 42.25');
    expect(
      (await ArchiveHistory(repository).load(saved.id)).balanceText,
      r'HK$ 42.25',
    );
  });

  for (final currency in ['HKD', 'CNY']) {
    test('旧非八达通 $currency 档案及部分读取不迁移整数或币种', () async {
      final repository = CardRepository(testDatabase());
      const legacy = '{"v":2,"trips":[],"rails":[],"buses":[],"cycle":[]}';
      await repository.saveIdentity(
        fingerprint: 'legacy-$currency',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        cardNumber: '310499000000000001',
        balanceFen: 4225,
        currencyCode: currency,
        sessionDataJson: legacy,
        readAt: DateTime.fromMillisecondsSinceEpoch(100),
      );
      await repository.saveIdentity(
        fingerprint: 'legacy-$currency',
        identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
        readAt: DateTime.fromMillisecondsSinceEpoch(200),
      );
      final saved = (await repository.getAllCards()).single;
      final history = await ArchiveHistory(repository).load(saved.id);
      expect(saved.balanceFen, 4225);
      expect(saved.currencyCode, currency);
      expect(saved.balanceText, currency == 'HKD' ? r'HK$ 42.25' : '¥ 42.25');
      expect(history.balanceText, saved.balanceText);
      expect(
        history.batches.any((batch) => batch.decoded.rawJson == legacy),
        isTrue,
      );
    });
  }

  for (final amount in <int?>[4225, 0, null]) {
    test('截断身份归档保留原整数 $amount 与 unknown 语义', () async {
      final repository = CardRepository(testDatabase());
      final controller = _controller(repository);
      final item = _stage(
        controller,
        _card(amount, serial: '003104850000000000'),
        100,
      );
      expect(item.balanceFen, amount);
      expect(item.currencyCode, isNull);
      final snapshot = CardSessionSnapshot.decode(item.sessionDataJson!)!;
      final interpretation =
          snapshot.context.extensions['balanceInterpretation'] as Map;
      expect(interpretation['semantics'], 'unknown');
      expect(interpretation['observedAmountMinor'], amount);
      expect(await controller.accept(item.pendingSaveId), isTrue);
      final saved = (await repository.getAllCards()).single;
      expect(saved.balanceFen, amount);
      expect(saved.balanceText, '余额未读取');
      final history = await ArchiveHistory(repository).load(saved.id);
      expect(history.balanceText, '余额未读取');
      expect(
        history.balanceObservationText,
        amount == null ? null : '$amount 原始单位（币种未知）',
      );
    });
  }

  test('A B A 去重重放按最新明确观察的 payload 解释，不按同金额选 B', () async {
    final repository = CardRepository(testDatabase());
    final controller = _controller(repository);
    final a = _stage(controller, _card(4225), 100);
    await _save(repository, a, 100);
    await _save(repository, a, 200, payload: _verifiedPayload(a));
    await _save(repository, a, 300);
    final saved = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(saved.id);
    expect(history.batches, hasLength(2));
    expect(saved.balanceText, '港币余额未读取');
    expect(history.balanceText, '港币余额未读取');
    expect(history.balanceObservationText, '¥42.25');
    expect(history.balanceSource!.observedAt, 300);
    expect(history.balanceSource!.payloadJson, saved.sessionDataJson);
    expect(buildArchiveHistoryExport([history]), isNot(contains(r'HK$50.00')));
  });

  test('A B A 后部分读取保留 A 的来源和观察时间，旧解释不能复活', () async {
    final repository = CardRepository(testDatabase());
    final controller = _controller(repository);
    final a = _stage(controller, _card(4225), 100);
    await _save(repository, a, 100);
    await _save(repository, a, 200, payload: _verifiedPayload(a));
    await _save(repository, a, 300);
    final originalA = (await repository.getAllCards()).single.sessionDataJson;
    for (final time in [400, 500]) {
      final partial = _stage(controller, _card(null), time);
      expect(await controller.accept(partial.pendingSaveId), isTrue);
      final saved = (await repository.getAllCards()).single;
      final history = await ArchiveHistory(repository).load(saved.id);
      expect(saved.balanceFen, 4225);
      expect(saved.balanceText, '港币余额未读取');
      expect(history.balanceText, saved.balanceText);
      expect(history.balanceSource!.observedAt, 300);
      expect(history.balanceSource!.payloadJson, originalA);
      expect(history.latestObservedFields['balanceFen'], isFalse);
      expect(
        buildArchiveHistoryExport([history]),
        isNot(contains(r'HK$50.00')),
      );
    }
  });

  test('旧去重记录缺来源链接时保留整数，不能借同金额 B 伪造港币余额', () async {
    final repository = CardRepository(testDatabase());
    final controller = _controller(repository);
    final a = _stage(controller, _card(4225), 100);
    await _save(repository, a, 100);
    await _save(repository, a, 200, payload: _verifiedPayload(a));
    await _save(repository, a, 300);
    // Emulate an older writer that did not carry a source into partial reads.
    final partial = _stage(controller, _card(null), 400);
    await _save(repository, partial, 400);
    final saved = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(saved.id);
    expect(saved.balanceFen, 4225);
    expect(history.balanceSource, isNull);
    expect(history.balanceInterpretation, isNull);
    expect(history.balanceText, contains('口径待核验'));
    expect(history.balanceObservationText, '¥ 42.25');
    expect(history.batches, hasLength(3));
  });

  test('晚到的同金额观察可更新部分读取的来源，但不能借用旧 verified 解释', () async {
    final repository = CardRepository(testDatabase());
    final controller = _controller(repository);
    final a = _stage(controller, _card(4225), 100);
    await _save(repository, a, 100, payload: _verifiedPayload(a));
    final partial = _stage(controller, _card(null), 300);
    expect(await controller.accept(partial.pendingSaveId), isTrue);
    var saved = (await repository.getAllCards()).single;
    expect(saved.balanceText, r'HK$50.00');
    final late = _stage(controller, _card(4225), 200);
    expect(await controller.accept(late.pendingSaveId), isTrue);
    saved = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(saved.id);
    expect(saved.lastReadAt, 300);
    expect(saved.balanceText, '港币余额未读取');
    expect(history.balanceText, saved.balanceText);
    expect(history.balanceSource!.observedAt, 200);
  });
}
