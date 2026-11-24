import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void main() {
  test('归档快照保存逐应用证据并随解码保留', () async {
    final database = testDatabase();
    final controller = ArchiveController(
      CardRepository(database),
      const MethodChannelLogExporter(),
      (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(database.close);

    final applications = [
      ApplicationEvidence.succeeded(
        'tu',
        '交通联合电子钱包（JT/T 978.2）',
        cardNumber: '3100000000000000001',
        balanceFen: 9000,
        recordCount: 1,
      ),
      ApplicationEvidence.rejected(
        'cu',
        '城市一卡通（CJ/T 331-2016）',
        reason: 'CU 应用未确认',
      ),
    ];
    final card = ParsedCard(
      parserId: CardParserIds.tunion,
      parserName: '交通联合',
      info: const TUnionCardInfo(
        applicationSerial: '03100000000000000001',
        issuerId: '1122334455667788',
        balanceFen: 9000,
      ),
      transactions: const [],
      selectedAidHex: 'A000000632010105',
    );
    controller.stage(
      ScanPresentation(
        TransitReadOutcome(card, applications: applications),
        KnowledgeBase.empty(),
      ),
      'application-evidence-1',
      DateTime(2026, 11, 15),
      const [],
    );
    expect(controller.pending, isNotNull);

    final snapshot = CardSessionSnapshot.decode(
      controller.pending!.sessionDataJson!,
    )!;
    final rows = snapshot.extensions['applicationEvidence'] as List;
    expect(rows, hasLength(2));
    final restored = ApplicationEvidence.tryParse(rows.first)!;
    expect(restored.appId, 'tu');
    expect(restored.state, ApplicationProbeState.readSucceeded);
    expect(restored.balanceFen, 9000);
    expect(ApplicationEvidence.tryParse(rows.last)!.state,
        ApplicationProbeState.selectRejected);
  });

  test('文本导出保留交通应用，旧银行卡条目不报为损坏', () {
    final snapshot = CardSessionSnapshot(
      extensions: {
        'applicationEvidence': [
          ApplicationEvidence.succeeded(
            'tu',
            '交通联合电子钱包（JT/T 978.2）',
            cardNumber: '310477000000000001',
            balanceFen: 10000,
            recordCount: 3,
          ).toJson(),
          {'appId': 'bank', 'displayName': '银行卡', 'state': 'readSucceeded'},
        ],
      },
    );
    final history = ArchiveHistoryResult(
      card: _savedCard(),
      latestCapture: SnapshotDecodeResult(
        rawJson: snapshot.encode(),
        status: SnapshotDecodeStatus.supported,
        snapshot: snapshot,
      ),
      batches: const [],
    );
    final text = buildArchiveHistoryExport([history]);
    expect(text, contains('逐应用探测（捕获时快照）：'));
    expect(text, isNot(contains('损坏的应用探测条目')));
    expect(text, isNot(contains('银行卡')));
    expect(
      text,
      contains(
        '交通联合电子钱包（JT/T 978.2）：读取成功'
        ' · 卡号 310477000000000001'
        ' · 余额 10000 分'
        ' · 3 条记录',
      ),
    );
  });

  testWidgets('普通档案详情保留卡片信息和行程，隐藏逐应用探测', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = testDatabase();
    final repository = CardRepository(database);
    addTearDown(database.close);
    final snapshot = CardSessionSnapshot(
      extensions: {
        'applicationEvidence': [
          ApplicationEvidence.succeeded(
            'tu',
            '交通联合电子钱包（JT/T 978.2）',
            balanceFen: 9000,
          ).toJson(),
        ],
      },
    );
    await repository.saveIdentity(
      fingerprint: 'tunion:1:2',
      identity: const CardArchiveIdentity(
        cardType: CardTypes.chinaTunion,
        officialName: '测试卡',
      ),
      cardNumber: '310477000000000001',
      sessionDataJson: snapshot.encode(),
      readAt: DateTime(2026, 11, 15),
    );
    final card = (await repository.getAllCards()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: CardDetailPage(repository: repository, cardId: card.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('卡片信息'), findsOneWidget);
    expect(find.text('行程记录 · 1 个已保存批次'), findsOneWidget);
    expect(find.text('读取时的应用'), findsNothing);
    expect(find.textContaining('余额 9000 分'), findsNothing);
  });
}

SavedCard _savedCard() => SavedCard(
  id: 'card-1',
  cardFingerprint: 'tunion:1:2',
  cardType: CardTypes.chinaTunion,
  officialName: '测试卡',
  identificationSource: CardIdentificationSources.parserOnly,
  cardNumber: '310477000000000001',
  transactionCount: 3,
  createdAt: 900,
  updatedAt: 1000,
);
