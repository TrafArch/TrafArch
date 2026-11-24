import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/recovery/recovery_state.dart';
import 'package:transit_card_analyzer/features/scan/application/card_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/home/presentation/result_labels.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/trips/local_card_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/shared/presentation/application_evidence_panel.dart';

void main() {
  test('独立资料目录与仅选中的 DF1001 不生成钱包余额', () {
    for (final id in ['lingnan_appy', 'df1001', 'mot_bmac', 'tuCash']) {
      final app = ApplicationEvidence.confirmed(id, id);
      expect(applicationObservationText(app), isNot(contains('余额未知')));
    }
    expect(
      applicationObservationText(ApplicationEvidence.confirmed('cu', 'CU')),
      contains('余额未知'),
    );
    expect(transitTypeLabel(CardParserIds.tunionCash), '交通联合电子现金');
    expect(transitTypeLabel(CardParserIds.motBmac), 'MOT.BMAC001');
  });
  final local = ReadResult(
    info: CardInfo()
      ..isSuzhou = true
      ..isCika = true
      ..expiryDate = DateTime(2026, 11, 30)
      ..remainingTrips = 0,
    records: [
      ApduRecord()
        ..type = 2
        ..fileSelector = 0xC4
        ..recordNumber = 2
        ..response = [0x12, 0xEF],
    ],
    extras: CardExtras(),
  );
  final evidence = ApplicationEvidence.succeeded(
    'suzhou_cika',
    '苏州计次',
    records: local.records,
    recordCount: 1,
    payload: local,
  );
  final card = ParsedCard(
    parserId: CardParserIds.localCard,
    parserName: '地方卡',
    info: const TUnionCardInfo(),
    transactions: const [],
    localCard: local,
  );

  test('未读到卡号的计次应用仍在恢复现场冻结目录、流水和零次数', () {
    final outcome = TransitReadOutcome(card, applications: [evidence]);
    final capture = RecoveryCapture(
      readAt: DateTime(2026, 11, 24),
      summary: {
        ...captureCardInfo(outcome),
        'decoded': captureReadResult(outcome),
      },
      frames: const [],
    );
    final restored = RecoveryCapture.fromJson(
      jsonDecode(jsonEncode(capture.toJson())),
    ).applications(null).single;
    expect(restored.cardNumber, isNull);
    expect(restored.balanceFen, isNull);
    expect(restored.payload, isA<ReadResult>());
    final wallet = restored.payload! as ReadResult;
    expect(wallet.info.expiryDate, DateTime(2026, 11, 30));
    expect(wallet.info.remainingTrips, 0);
    expect(wallet.trips.single.response, [0x12, 0xEF]);
    expect(wallet.trips.single.fileSelector, 0xC4);
    expect(wallet.trips.single.recordNumber, 2);
    expect(
      CardIdentificationService(KnowledgeBase.empty()).identify(card),
      isNull,
    );
  });

  testWidgets('冻结后的单应用可以查看原码、零次数和有效期', (tester) async {
    final restored = ApplicationEvidence.tryParse(
      jsonDecode(jsonEncode(evidence.toJson())),
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ApplicationEvidencePanel(applications: [restored]),
          ),
        ),
      ),
    );
    expect(find.textContaining('0 次'), findsOneWidget);
    expect(find.textContaining('2026-11-30'), findsOneWidget);
    expect(find.textContaining('余额 0 分'), findsNothing);
    await tester.tap(find.textContaining('查看记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12EF'), findsOneWidget);
  });

  test('历史沪哈 TU 指纹已采用通用 TU 命名空间', () {
    final service = CardIdentificationService(KnowledgeBase.empty());
    for (final id in [
      CardParserIds.shanghaiTunion,
      CardParserIds.harbinTunion,
      CardParserIds.tunion,
    ]) {
      final found = service.identify(
        ParsedCard(
          parserId: id,
          parserName: 'TU',
          info: const TUnionCardInfo(
            applicationSerial: '0123456789',
            issuerId: '11223344',
          ),
          transactions: const [],
          selectedAidHex: 'A000000632010105',
        ),
      );
      expect(found?.fingerprint, 'tunion:11223344:123456789');
    }
  });

  test('苏薪卡保留旧原号指纹，归档展示独立卡面号', () {
    final info = CardInfo()
      ..isSuzhou = true
      ..isSuxin = true
      ..cardNumber = '00310477000000000001'
      ..displayCardNumber = '87654321';
    final service = CardIdentificationService(KnowledgeBase.empty());
    final identity = service.identify(
      ParsedCard(
        parserId: CardParserIds.localCard,
        parserName: '苏薪',
        info: const TUnionCardInfo(),
        transactions: const [],
        localCard: ReadResult(
          info: info,
          records: const [],
          extras: CardExtras(),
        ),
      ),
    );
    expect(identity?.fingerprint, 'local_card::00310477000000000001');
    expect(identity?.cardNumber, '87654321');
  });

  test('不同目录内的相同流水在历史中各保留一次，计次不计入人民币消费', () {
    final records = [
      for (final directory in ['TFT', '1002'])
        {
          'directory': directory,
          'fileSelector': 0xC4,
          'recordNumber': 2,
          'timestamp': 0,
          'type': 2,
          'rawBody': [18, 239],
          if (directory == '1002') 'tripDelta': -1 else 'balanceDelta': -1,
        },
    ];
    final snapshot = CardSessionSnapshot(
      extensions: {
        'applicationEvidence': [
          {
            'appId': 'tft',
            'displayName': '天府通',
            'confirmed': true,
            'state': 'readSucceeded',
            'payload': {
              'kind': 'read_result',
              'profiles': ['tft'],
              'records': records,
            },
          },
        ],
      },
    );
    final batch = ArchiveBatchEvidence(
      id: 'capture',
      readAt: 0,
      storedParseVersion: 1,
      origin: 'nfc',
      timeSource: 'captured',
      decoded: CardSessionSnapshot.decodeResult(snapshot.encode()),
      issues: const [],
    );
    final restored = ArchiveHistory.projectLocalCardRecords([batch, batch]);
    expect(restored, hasLength(2));
    final fields = restored
        .singleWhere((r) => r.fields['directory'] == '1002')
        .fields;
    final profile = localTripProfileOf(fields);
    final trip = describeLocalTrip(
      restoreLocalTripRecord(fields, profile: profile)!,
      profile: profile,
      currencySymbol: '¥',
    );
    expect(trip.info.amountText, isNull);
    expect(trip.info.fields, contains(('次数变化', '-1 次')));
    expect(trip.mode, TripModeFilter.other);
    expect(trip.info.sourceLabel, contains('天府通'));
  });
}
