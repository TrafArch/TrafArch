import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/cj_t331_public_info_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void main() {
  testWidgets(
    'CU archive keeps captured records readable after save and reopen',
    (tester) async {
      final repository = CardRepository(testDatabase());
      final controller = ArchiveController(
        repository,
        const MethodChannelLogExporter(),
        (_) {},
      );
      addTearDown(controller.dispose);
      final record = CityUnionFileParser.parseWalletRecord(
        0x06,
        [
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          6,
          0x20,
          0x00,
          0x11,
          0x0A,
          0x01,
          0,
          0x20,
          0x24,
          0x09,
          0x20,
          0x12,
          0,
          0,
        ],
        kind: CityUnionTransactionKind.foreignConsumption,
        recordNumber: 5,
      );
      final public = CjT331PublicInfoParser.parse([
        0,
        0,
        0x20,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0x20,
        0x20,
        1,
        1,
        0x20,
        0x30,
        1,
        1,
        0,
        0,
      ]);
      final card = ParsedCard(
        parserId: CardParserIds.cityUnion,
        parserName: 'CU',
        info: const TUnionCardInfo(),
        transactions: const [],
        cityUnionFiles: [public, record],
      );
      controller.stage(
        ScanPresentation(TransitReadOutcome(card), KnowledgeBase.empty()),
        'cu-capture',
        DateTime.utc(2026, 10, 26),
        const [],
      );
      final pending = controller.pending!;
      expect(pending.transactionCount, 1);
      final captured = pending.sessionDataJson!;
      expect((jsonDecode(captured) as Map)['cuProjection'], isA<Map>());
      expect(CardSessionSnapshot.decode(captured)!.encode(), captured);
      expect(await controller.accept(pending.pendingSaveId), isTrue);
      final saved = (await repository.getAllCards()).single;
      final exported = buildArchiveHistoryExport([
        await ArchiveHistory(repository).load(saved.id),
      ]);
      expect(exported, contains('城市一卡通记录（1 条）'));
      expect(exported, contains('终端原始编码：2000110A0100'));
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: repository, cardId: saved.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('城市一卡通 · 1 条记录'), findsOneWidget);
      await tester.tap(find.text('异地消费 · 地点未匹配'));
      await tester.pumpAndSettle();
      expect(find.text('终端原始编码：2000110A0100'), findsOneWidget);
      expect(find.textContaining('CU 0x06 #5'), findsOneWidget);
      expect(find.text('金额原始值：1（单位未确认）'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test('CU archive freezes matching labels and raw reference identifiers', () {
    final captured = captureCuProjection([_capturedView()]);
    final batch = _batch('saved', captured);
    final projected = projectCuArchive(
      ArchiveHistoryResult(card: null, batches: [batch]),
    );
    final view = projected.transactions.single;
    expect(view.locationLabel, '地铁 · 保存时线路 · 保存时站名');
    expect(view.location.value!.code, '000A');
    expect(view.location.value!.lineCode, '0010');
    expect(view.location.value!.stationCode, '0002');
    expect(view.location.value!.sourceKey, '000A:0010:0002');
    expect(view.location.value!.userOverride, isTrue);
    expect(view.record.rawHex, _capturedView().record.rawHex);
    expect(view.record.errors, isNotEmpty);
    expect(view.transactionTime, DateTime.utc(2024, 9, 20, 4));
    expect(projected.sources[view]!.single.batchId, 'saved');
    expect(batch.decoded.snapshot!.encode(), batch.decoded.rawJson);
    expect(projected.issues, isEmpty);
  });

  test(
    'CU matched duplicate-identity candidates survive archive projection',
    () {
      final view = _capturedView();
      final captured = captureCuProjection([
        CuTransactionView(
          record: view.record,
          location: ReferenceMatch(ReferenceMatchStatus.matched, [
            view.location.value!,
            view.location.value!,
          ]),
        ),
      ]);
      final projected = projectCuArchive(
        ArchiveHistoryResult(
          card: null,
          batches: [_batch('matched', captured)],
        ),
      );
      expect(projected.transactions, hasLength(1));
      expect(projected.transactions.single.location.candidates, hasLength(2));
      expect(projected.transactions.single.locationLabel, view.locationLabel);
      expect(projected.issues, isEmpty);
    },
  );

  test('CU repeat reads merge source attribution while different SFIs stay separate', () {
    final recent = captureCuProjection([
      _capturedView(recordNumber: 1),
      _capturedView(sfi: 0x1A),
    ]);
    final older = captureCuProjection([_capturedView(recordNumber: 5)]);
    final projected = projectCuArchive(
      ArchiveHistoryResult(
        card: null,
        batches: [_batch('recent', recent), _batch('older', older)],
      ),
    );
    expect(projected.transactions, hasLength(2));
    final originalFile = projected.transactions.singleWhere(
      (view) => view.record.sfi == 0x06,
    );
    expect(originalFile.record.recordNumber, 1);
    expect(projected.sources[originalFile]!.map((source) => source.batchId), [
      'recent',
      'older',
    ]);
  });

  test(
    'CU same raw bytes retain distinct captured locations and availability',
    () {
      final matched = _capturedView();
      final unavailable = CuTransactionView(
        record: matched.record,
        transactionTime: matched.transactionTime,
        regionCode: matched.regionCode,
        carrier: matched.carrier,
        location: ReferenceMatch(
          ReferenceMatchStatus.unavailable,
          const [],
          issue: '历史读取时参考库不可用',
        ),
      );
      final renamed = CuTransactionView(
        record: matched.record,
        transactionTime: matched.transactionTime,
        regionCode: matched.regionCode,
        carrier: matched.carrier,
        location: ReferenceMatch(ReferenceMatchStatus.matched, const [
          StationCodeEntry(code: '000A', station: '另一份冻结站名'),
        ]),
      );
      final projected = projectCuArchive(
        ArchiveHistoryResult(
          card: null,
          batches: [
            _batch('unavailable', captureCuProjection([unavailable])),
            _batch('renamed', captureCuProjection([renamed])),
            _batch('original', captureCuProjection([matched])),
          ],
        ),
      );
      expect(projected.transactions, hasLength(3));
      expect(
        projected.transactions.map((view) => view.locationLabel),
        containsAll(['参考数据不可用', '另一份冻结站名', matched.locationLabel]),
      );
      expect(
        projected.sources.values.every((sources) => sources.length == 1),
        isTrue,
      );
    },
  );

  test(
    'CU identical captures from distinct application contexts stay separate',
    () {
      final captured = captureCuProjection([_capturedView()]);
      final projected = projectCuArchive(
        ArchiveHistoryResult(
          card: null,
          batches: [
            _batch(
              'first-app',
              captured,
              context: const ArchiveContext(
                systemId: 'city_union',
                applicationId: 'A000000632',
              ),
            ),
            _batch(
              'other-app',
              captured,
              context: const ArchiveContext(
                systemId: 'city_union',
                applicationId: 'D156000136',
              ),
            ),
          ],
        ),
      );
      expect(projected.transactions, hasLength(2));
    },
  );

  test('CU malformed and future projections preserve snapshot evidence and report diagnostics', () {
    final malformed = captureCuProjection([_capturedView()]);
    ((malformed['transactions'] as List).single as Map)['record']['rawHex'] =
        '00';
    final batch = _batch('malformed', malformed);
    final future = _batch('future', {'version': 2, 'transactions': []});
    final projected = projectCuArchive(
      ArchiveHistoryResult(card: null, batches: [batch, future]),
    );
    expect(projected.transactions, isEmpty);
    expect(projected.issues, hasLength(2));
    expect(batch.decoded.snapshot!.encode(), batch.decoded.rawJson);
    expect(future.decoded.snapshot!.encode(), future.decoded.rawJson);
  });
}

CuTransactionView _capturedView({int recordNumber = 5, int sfi = 0x06}) =>
    CuTransactionView(
      record: CityUnionFileParser.parseWalletRecord(
        sfi,
        [
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          6,
          0x20,
          0,
          0x11,
          0x0A,
          1,
          0,
          0x20,
          0x24,
          9,
          0x20,
          0x12,
          0,
          0,
        ],
        kind: CityUnionTransactionKind.foreignConsumption,
        recordNumber: recordNumber,
      ),
      transactionTime: DateTime.utc(2024, 9, 20, 4),
      regionCode: '2000',
      carrier: 2,
      location: ReferenceMatch(ReferenceMatchStatus.matched, const [
        StationCodeEntry(
          code: '000A',
          type: '地铁',
          line: '保存时线路',
          station: '保存时站名',
          system: 'cu',
          kind: 'metro',
          datasetFile: 'captured.csv',
          lineCode: '0010',
          stationCode: '0002',
          sourceField: 'terminal',
          sourceKey: '000A:0010:0002',
          rawValueJson: '{"station":"保存时站名"}',
          lineKey: 'line:0010',
          userOverride: true,
          overrideUpdatedAt: '2024-09-20',
        ),
      ]),
    );

ArchiveBatchEvidence _batch(
  String id,
  Map<String, dynamic> projection, {
  ArchiveContext context = const ArchiveContext(),
}) => ArchiveBatchEvidence(
  id: id,
  readAt: 1,
  storedParseVersion: 1,
  origin: 'test',
  timeSource: 'test',
  decoded: CardSessionSnapshot.decodeResult(
    CardSessionSnapshot(
      context: context,
      extensions: {'cuProjection': projection},
    ).encode(),
  ),
  issues: const [],
);
