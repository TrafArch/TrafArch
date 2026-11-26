import 'dart:convert';

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
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/octopus/octopus_balance.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

// 4225 is the reported parsed output. These display tests use synthetic HKD
// results; the real-card frames and balance formula live in
// octopus_balance_reader_test.dart. They prevent mislabelling and do not
// replace validation on TrafArch's own device path.
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
  _App(this.card, {this.balanceRead})
    : result = AnalysisEngine(_knowledge()).analyze(card),
      super(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
  final ParsedCard card;
  final OctopusBalanceResult? balanceRead;
  final CardAnalysisResult result;
  @override
  OctopusBalanceResult? get currentOctopusResult => balanceRead;
  @override
  ParsedCard get parsedCard => card;
  @override
  CardAnalysisResult get analysis => result;
}

void main() {
  test('组合余额保留零和负数，未读 TU 不补零或按汇率推算', () {
    for (final (tu, hkd, expected) in [
      (0, 0, r'HK$0.00 (￥0.00)'),
      (0, -1, r'HK$-0.01 (￥0.00)'),
      (null, 5000, r'HK$50.00'),
      (null, 651850, r'HK$6518.50'),
    ]) {
      final app = _App(
        _card(tu),
        balanceRead: OctopusBalanceResult(
          balanceMinor: hkd,
          idmHex: '0102030405060708',
          readAt: DateTime.utc(2026, 11, 17),
        ),
      );
      addTearDown(app.dispose);
      expect(app.octopusBalanceText, expected);
    }
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

  test('已保存档案在余额读取后显示港币，TU 原值与币种不变', () async {
    final repository = CardRepository(testDatabase());
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    final readAt = DateTime(2026, 11, 17, 12, 21);
    controller.stage(
      ScanPresentation(TransitReadOutcome(_card(4225)), _knowledge()),
      'octopus-read-balance',
      readAt,
      const [],
    );
    final pending = controller.pending!;
    expect(await controller.accept(pending.pendingSaveId), isTrue);
    final card = (await repository.getAllCards()).single;
    expect(
      (await ArchiveHistory(repository).load(card.id)).balanceText,
      contains('港币余额未读取'),
    );

    await controller.attachVerifiedAccountBalance(
      fingerprint: pending.fingerprint,
      readAt: readAt,
      balanceMinor: 5000,
      evidenceSource: 'test:octopus:01011301E2223F08',
    );

    final updated = (await repository.getAllCards()).single;
    expect(updated.balanceFen, 4225);
    expect(updated.currencyCode, 'CNY');
    expect(updated.balanceText, r'HK$50.00');
    final history = await ArchiveHistory(repository).load(updated.id);
    expect(history.balanceText, r'HK$50.00');
    expect(history.balanceObservationText, '¥42.25');
    final snapshot = CardSessionSnapshot.decode(updated.sessionDataJson!)!;
    final interpretation =
        snapshot.context.extensions['balanceInterpretation']
            as Map<String, dynamic>;
    expect(interpretation['observedAmountMinor'], 4225);
    expect(interpretation['accountCurrency'], 'HKD');
    expect(interpretation['accountBalanceMinor'], 5000);
    expect(
      (interpretation['verifiedAccountBalance'] as Map)['verification'],
      'verified',
    );
  });

  test('尚未保存时读取港币，确认保存后档案直接显示港币', () async {
    final repository = CardRepository(testDatabase());
    final controller = ArchiveController(
      repository,
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    final readAt = DateTime(2026, 11, 17, 12, 30);
    controller.stage(
      ScanPresentation(TransitReadOutcome(_card(4225)), _knowledge()),
      'octopus-pending-balance',
      readAt,
      const [],
    );
    final pending = controller.pending!;
    await controller.attachVerifiedAccountBalance(
      fingerprint: pending.fingerprint,
      readAt: readAt,
      balanceMinor: 5000,
      evidenceSource: 'test:octopus:pending',
    );
    expect(controller.pending, isNotNull);
    expect(await controller.accept('octopus-pending-balance'), isTrue);
    final card = (await repository.getAllCards()).single;
    expect(card.balanceFen, 4225);
    expect(card.balanceText, r'HK$50.00');
    expect(
      (await ArchiveHistory(repository).load(card.id)).balanceText,
      r'HK$50.00',
    );
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
}
