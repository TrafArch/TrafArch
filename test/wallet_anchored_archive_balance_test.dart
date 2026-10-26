import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';
import 'package:transit_card_analyzer/features/archive/application/card_records_export.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_record_presenter.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  test(
    'v8 saves wallet-derived provenance even when process balance is equal',
    () {
      final snapshot = CardSessionSnapshot(
        parseVersion: 8,
        context: _context,
        trips: [
          _trip(sequence: 41, amount: 700, balance: 11850, recorded: false),
          _trip(sequence: 40, amount: 0, balance: 12550, recorded: false),
          _trip(sequence: 39, amount: 700, balance: 12550, recorded: true),
        ],
      );
      final encoded = snapshot.encode();
      final fields =
          (jsonDecode(encoded) as Map<String, dynamic>)['trips'] as List;
      expect(fields.map((row) => row['balanceAfterIsRecorded']), [
        false,
        false,
        true,
      ]);
      final restored = CardSessionSnapshot.decode(encoded)!;
      expect(restored.trips.map((trip) => trip.balanceAfterFen), [
        11850,
        12550,
        12550,
      ]);
      expect(restored.trips.map((trip) => trip.balanceAfterIsRecorded), [
        false,
        false,
        true,
      ]);
      expect(restored.trips.map((trip) => trip.balanceAfterLabel), [
        '交易后余额',
        '交易后余额',
        '记录余额',
      ]);
      expect(
        restored.trips.every(
          (trip) => trip.matchedProcessTrip!.balanceFen == 12550,
        ),
        isTrue,
      );
      expect(restored.encode(), encoded);

      final history = _history([_batch(encoded, parser: 8)]);
      final bySequence = {
        for (final record in history.records) record.fields['sequence']: record,
      };
      expect(archiveRecordBalanceFen(bySequence[41]!), 11850);
      expect(archiveRecordBalanceIsRecorded(bySequence[40]!), isFalse);
      expect(archiveRecordBalanceIsRecorded(bySequence[39]!), isTrue);
      final entries = presentArchiveTrips(
        history.records,
        onDiagnostics: (_) {},
      ).entries;
      expect(
        entries
            .singleWhere((entry) => entry.info.title.contains('序号 40'))
            .info
            .fields,
        contains(('交易后余额', '¥ 125.50')),
      );
      expect(
        entries
            .singleWhere((entry) => entry.info.title.contains('序号 40'))
            .info
            .subText,
        '交易后余额 ¥ 125.50',
      );
      expect(
        entries
            .singleWhere((entry) => entry.info.title.contains('序号 39'))
            .info
            .subText,
        '记录余额 ¥ 125.50',
      );
      final text = buildArchiveHistoryExport([history]);
      expect(text, contains('交易后余额 ¥ 118.50'));
      expect(text, contains('交易后余额 ¥ 125.50'));
      expect(text, contains('记录余额 ¥ 125.50'));
      final jsonRows = projectArchiveRecords([history]);
      expect(jsonRows.map((row) => row['balance']), [
        '118.50',
        '125.50',
        '125.50',
      ]);
    },
  );

  test(
    'v8 missing provenance never infers a recorded balance from equality',
    () {
      final payload = _payload(8, [_fields(balance: 12550)]);
      final decoded = CardSessionSnapshot.decode(payload)!;
      expect(decoded.trips.single.balanceAfterFen, 12550);
      expect(decoded.trips.single.balanceAfterIsRecorded, isFalse);
      final record = _history([_batch(payload, parser: 8)]).records.single;
      expect(archiveRecordBalanceIsRecorded(record), isFalse);
      expect(archiveRecordText(record), contains('交易后余额 ¥ 125.50'));
    },
  );

  test('v8 explicit unknown never refills from matched process evidence', () {
    final payload = _payload(8, [
      {..._fields(balance: null), 'balanceAfterIsRecorded': null},
    ]);
    final decoded = CardSessionSnapshot.decode(payload)!;
    expect(decoded.trips.single.balanceAfterFen, isNull);
    expect(decoded.trips.single.balanceAfterIsRecorded, isNull);
    expect(decoded.trips.single.matchedProcessTrip!.balanceFen, 12550);
    final history = _history([_batch(payload, parser: 8)]);
    final record = history.records.single;
    expect(archiveRecordBalanceFen(record), isNull);
    expect(archiveRecordText(record), isNot(contains('余额')));
    final info = presentArchiveTrips(
      history.records,
      onDiagnostics: (_) {},
    ).entries.single.info;
    expect(info.subText, isNull);
    expect(info.fields.where((field) => field.$1.contains('余额')), isEmpty);
    expect(projectArchiveRecords([history]).single['balance'], isNull);
    final text = buildArchiveHistoryExport([history]);
    expect(text, isNot(contains('记录余额 ¥ 125.50')));
    expect(text, isNot(contains('交易后余额 ¥ 125.50')));
    expect(text, contains(payload));
  });

  test('old captured semantics and exact payload survive full backup', () {
    for (final parser in [5, 6, 7]) {
      final payload = '  ${_payload(parser, [_fields(balance: 11850)])}\n';
      final decoded = CardSessionSnapshot.decode(payload)!;
      expect(decoded.trips.single.balanceAfterFen, parser == 5 ? 12550 : 11850);
      expect(decoded.trips.single.balanceAfterIsRecorded, parser == 5);
      expect(decoded.encode(), payload);
      final batch = _batch(payload, parser: parser);
      final archive = CardArchiveDocument(
        card: _card,
        batches: [batch],
        fieldObservationTimes: const {},
      );
      final restored = CardArchiveDocument.decode(archive.encode());
      expect(restored.batches.single.payloadJson, payload);
      expect(restored.batches.single.parseVersion, parser);
      final history = _history(restored.batches);
      expect(
        archiveRecordBalanceFen(history.records.single),
        parser == 5 ? 12550 : 11850,
      );
      expect(
        archiveRecordBalanceIsRecorded(history.records.single),
        parser == 5,
      );
    }
  });

  test(
    'history splits changed v8 provenance without splitting unrelated records',
    () {
      for (final versions in [
        [4, 5, 6, 7, 8],
        [8, 7, 6, 5, 4],
      ]) {
        final batches = [
          for (var i = 0; i < versions.length; i++)
            _batch(
              _payload(
                versions[i],
                [
                  {..._fields(balance: 12550), 'balanceAfterIsRecorded': false},
                  {
                    ..._fields(balance: null),
                    'sequence': 42,
                    'matchedProcess': null,
                  },
                ],
                cycle: [_processFields],
              ),
              parser: versions[i],
              id: 'batch-$i',
              at: i + 1,
            ),
        ];
        final history = _history(batches);
        final sameAmount = history.records
            .where(
              (record) =>
                  record.kind == ArchiveRecordKind.transaction &&
                  record.fields['sequence'] == 41,
            )
            .toList();
        expect(sameAmount, hasLength(2));
        final recorded = sameAmount.singleWhere(archiveRecordBalanceIsRecorded);
        final computed = sameAmount.singleWhere(
          (record) => !archiveRecordBalanceIsRecorded(record),
        );
        expect(recorded.sources, hasLength(4));
        expect(
          recorded.sources.every((source) => source.capturedParseVersion < 8),
          isTrue,
        );
        expect(computed.sources.single.capturedParseVersion, 8);
        expect(archiveRecordBalanceFen(recorded), 12550);
        expect(archiveRecordBalanceFen(computed), 12550);
        final unrelated = history.records.where(
          (record) =>
              record.kind == ArchiveRecordKind.process ||
              record.fields['sequence'] == 42,
        );
        expect(unrelated, hasLength(2));
        expect(unrelated.every((record) => record.sources.length == 5), isTrue);
        expect(
          history.batches.map((batch) => batch.decoded.rawJson).toSet(),
          batches.map((batch) => batch.payloadJson).toSet(),
        );
      }
    },
  );

  test(
    'invalid explicit provenance is diagnosed without discarding raw payload',
    () {
      final payload = _payload(8, [
        {..._fields(balance: 12550), 'balanceAfterIsRecorded': 'false'},
      ]);
      final decoded = CardSessionSnapshot.decodeResult(payload);
      expect(
        decoded.issues.any(
          (issue) => issue.path.endsWith('balanceAfterIsRecorded'),
        ),
        isTrue,
      );
      expect(decoded.snapshot!.trips, isEmpty);
      expect(decoded.snapshot!.encode(), payload);
      expect(_history([_batch(payload, parser: 8)]).records, isEmpty);
    },
  );

  for (final scenario in [
    (name: 'wallet-derived', balance: 11850, recorded: false),
    (name: 'process-recorded', balance: 12550, recorded: true),
    (name: 'unknown', balance: null, recorded: null),
  ]) {
    test('real v7 and v8 writers deduplicate ${scenario.name} balances', () {
      final payloads = {
        for (final parser in [7, 8])
          parser: CardSessionSnapshot(
            parseVersion: parser,
            context: _context,
            trips: [
              _trip(
                sequence: 41,
                amount: 700,
                balance: scenario.balance,
                recorded: scenario.recorded,
              ),
            ],
          ).encode(),
      };
      for (final versions in [
        [7, 8],
        [8, 7],
      ]) {
        final batches = [
          for (var i = 0; i < versions.length; i++)
            _batch(
              payloads[versions[i]]!,
              parser: versions[i],
              id: 'writer-${versions[i]}',
              at: i + 1,
            ),
        ];
        final history = _history(batches);
        expect(history.records, hasLength(1));
        final record = history.records.single;
        expect(record.sources, hasLength(2));
        expect(archiveRecordBalanceFen(record), scenario.balance);
        if (scenario.recorded != null) {
          expect(archiveRecordBalanceIsRecorded(record), scenario.recorded);
        }
        final firstPayload =
            payloads[record.sources.first.capturedParseVersion]!;
        final originalFields =
            (jsonDecode(firstPayload) as Map<String, dynamic>)['trips'] as List;
        expect(record.fields, originalFields.single);
        expect(
          history.batches.map((batch) => batch.decoded.rawJson).toSet(),
          payloads.values.toSet(),
        );
      }
    });
  }

  test(
    'real v7 and v8 writers retain genuinely different balance semantics',
    () {
      for (final versions in [
        [7, 8],
        [8, 7],
      ]) {
        final batches = [
          for (var i = 0; i < versions.length; i++)
            _batch(
              CardSessionSnapshot(
                parseVersion: versions[i],
                context: _context,
                trips: [
                  _trip(
                    sequence: 40,
                    amount: 0,
                    balance: 12550,
                    recorded: false,
                  ),
                ],
              ).encode(),
              parser: versions[i],
              id: 'writer-${versions[i]}',
              at: i + 1,
            ),
        ];
        final history = _history(batches);
        expect(history.records, hasLength(2));
        for (final record in history.records) {
          expect(record.sources, hasLength(1));
          expect(archiveRecordBalanceFen(record), 12550);
          expect(
            archiveRecordBalanceIsRecorded(record),
            record.sources.single.capturedParseVersion == 7,
          );
        }
      }
    },
  );
}

const _context = ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2);

const _card = SavedCard(
  id: 'wallet-card',
  cardFingerprint: 'wallet-fingerprint',
  cardType: 'china_tunion',
  identificationSource: 'test',
  cardNumber: '00004041',
  createdAt: 1,
  updatedAt: 1,
);

const _processFields = <String, dynamic>{
  'time': 1792972800000,
  'typeCode': 4,
  'terminalId': '000000004100',
  'appTypeCode': 2,
  'lineStationCode': '00000000000001',
  'amountFen': 700,
  'balanceFen': 12550,
  'cityCode': '2000',
  'rawHex': '0000000000003106',
};

TransitTrip _trip({
  required int sequence,
  required int amount,
  required int? balance,
  required bool? recorded,
}) => TransitTrip(
  time: DateTime.fromMillisecondsSinceEpoch(1792972800000 + sequence * 60000),
  amountFen: amount,
  overdraftLimitFen: 0,
  isConsume: true,
  typeName: '复合消费',
  isCompositeConsume: true,
  sequence: sequence,
  terminalId: '000000004100',
  balanceAfterFen: balance,
  balanceAfterIsRecorded: recorded,
  matchedProcessTrip: TUnionTripRecord(
    typeCode: amount == 0 ? 3 : 4,
    terminalId: '000000004100',
    appTypeCode: 2,
    lineStationCode: '00000000000001',
    amountFen: amount,
    balanceFen: 12550,
    time: DateTime.fromMillisecondsSinceEpoch(1792972800000 + sequence * 60000),
    cityCode: '2000',
  ),
);

Map<String, dynamic> _fields({required int? balance}) => {
  'time': 1792972800000,
  'amountFen': 700,
  'consume': true,
  'typeName': '复合消费',
  'sequence': 41,
  'terminalId': '000000004100',
  'balanceAfterFen': balance,
  'currency': 'CNY',
  'matchedProcess': _processFields,
};

String _payload(
  int parser,
  List<Map<String, dynamic>> trips, {
  List<Map<String, dynamic>> cycle = const [],
}) => jsonEncode({
  'v': 3,
  'parseVersion': parser,
  'context': _context.toJson(),
  'trips': trips,
  'rails': [],
  'buses': [],
  'cycle': cycle,
  'rawEvidence': [],
  'recordProvenance': {},
  'unknownEvidence': '000012550',
});

CardReadBatch _batch(
  String payload, {
  required int parser,
  String id = 'batch',
  int at = 1,
}) => CardReadBatch(
  id: id,
  cardId: _card.id,
  cardFingerprint: _card.cardFingerprint,
  readAt: at,
  parseVersion: parser,
  payloadJson: payload,
);

ArchiveHistoryResult _history(List<CardReadBatch> batches) =>
    ArchiveHistory.project(ArchiveRows(card: _card, batches: batches));
