import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/cu_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CU uses its carrier, civil date and Trip Reader amount without inventing endpoints', () {
    final before = _view(sequence: 10, amount: 0);
    final after = _view(sequence: 11);
    final bytesBefore = before.record.toJson();
    final entries = [describeCuTrip(after), describeCuTrip(before)];
    final journeys = projectJourneys([
      for (final entry in entries) entry.journeyEvent!,
    ]);
    expect(journeys, hasLength(2));
    for (final journey in journeys) {
      expect(journey.mode, TripModeFilter.rail);
      expect(journey.state, JourneyState.incomplete);
      expect(journey.start, isNull);
      expect(journey.end, isNull);
      expect(journey.duration, isNull);
      expect(journey.balanceAfterText, isNull);
    }
    expect(
      journeys.map((journey) => journey.amountText),
      orderedEquals(['-¥3.00', '-¥0.00']),
    );
    final endpoint = entries.first.journeyEvent!.endpoint;
    expect(endpoint.time, DateTime.utc(2026, 11, 7, 0, 5));
    expect(endpoint.timeText, '2026-11-07 00:05:00');
    expect(endpoint.line, '2号线');
    expect(endpoint.station, '演示站');
    expect(before.record.toJson(), bytesBefore);
  });

  test('CU preserves ambiguity and cannot turn recharge or unknown types into rides', () {
    final candidates = const [
      StationCodeEntry(
        code: '001',
        line: '错误线路甲',
        station: '错误站甲',
        kind: 'metro',
      ),
      StationCodeEntry(
        code: '002',
        line: '错误线路乙',
        station: '错误站乙',
        kind: 'metro',
      ),
    ];
    final ambiguous = describeCuTrip(
      _view(
        location: ReferenceMatch(ReferenceMatchStatus.ambiguous, candidates),
      ),
    );
    expect(ambiguous.mode, TripModeFilter.rail);
    expect(ambiguous.journeyEvent!.endpoint.line, isNull);
    expect(ambiguous.journeyEvent!.endpoint.station, '地点存在歧义');
    expect(ambiguous.info.badges, ['站名歧义']);
    final unknown = describeCuTrip(
      _view(
        carrier: null,
        location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
      ),
    );
    expect(unknown.mode, TripModeFilter.other);
    final recharge = describeCuTrip(
      _view(sfi: 0x10, kind: CityUnionTransactionKind.recharge),
    );
    expect(recharge.mode, TripModeFilter.other);
    expect(recharge.source, CuTripSourceFilter.recharge);
    expect(recharge.info.isConsume, isFalse);
    expect(recharge.info.amountText, '+¥3.00');
    expect(recharge.info.title, '充值');
    expect(describeCuTrip(_view(sfi: 0x1A)).source, CuTripSourceFilter.foreign);
    expect(
      describeCuTrip(_view(sfi: 0x06)).source,
      CuTripSourceFilter.shanghaiForeign,
    );
    final bus = describeCuTrip(_view(carrier: 1, line: '345'));
    expect(bus.mode, TripModeFilter.bus);
    expect(bus.journeyEvent!.endpoint.line, '345路');
    expect(describeCuTrip(_view(carrier: 1, line: '00345')).info.line, '00345');
    final unknownType = describeCuTrip(_view(transactionType: 0x0A));
    expect(unknownType.info.amountText, '-¥3.00');
    expect(unknownType.info.fields, contains(('交易金额', '-¥3.00')));
  });

  test(
    'CU keeps the four-byte field while interpreting its low three bytes',
    () {
      final transaction = _view(amountField: const [0x12, 0x34, 0x56, 0x78]);
      expect(transaction.record.amountRaw, 0x12345678);
      expect(transaction.record.amountHex, '12345678');
      expect(transaction.record.interpretedAmountFen, -0x345678);
      expect(transaction.interpretedAmountFen, -0x345678);
      expect(transaction.amountText(), '-¥34300.08');
    },
  );

  test(
    'CU archived tickets consume frozen locations and preserve every source',
    () {
      final capture = captureCuProjection([_view()]);
      final batches = [_batch('a', capture), _batch('b', capture)];
      final projection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: batches),
      );
      expect(projection.transactions, hasLength(1));
      final transaction = projection.transactions.single;
      final entry = describeCuTrip(
        transaction,
        savedSource: projection.sourceLabels[transaction],
      );
      expect(entry.journeyEvent!.endpoint.line, '2号线');
      expect(entry.journeyEvent!.endpoint.station, '演示站');
      expect(entry.info.amountText, '-¥3.00');
      expect(
        entry.info.fields,
        contains((
          '保存来源',
          'a/cuProjection.transactions[0], b/cuProjection.transactions[0]',
        )),
      );
      expect(projection.isRemoteUse(transaction, batches), isTrue);
      for (final batch in batches) {
        expect(batch.decoded.snapshot!.encode(), batch.decoded.rawJson);
      }
      final tuOnly = [
        _batch('tu', capture, systemId: CardParserIds.shanghaiTunion),
      ];
      final tuProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: tuOnly),
      );
      expect(
        tuProjection.isRemoteUse(tuProjection.transactions.single, tuOnly),
        isFalse,
      );
      final dual = [
        _batch(
          'dual',
          capture,
          systemId: CardParserIds.shanghaiTunion,
          cuCity: '2000',
        ),
      ];
      final dualProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: dual),
      );
      expect(
        dualProjection.isRemoteUse(dualProjection.transactions.single, dual),
        isFalse,
      );
      final partial = [...batches, _batch('unknown', capture, cuCity: '0000')];
      final partialProjection = projectCuArchive(
        ArchiveHistoryResult(card: null, batches: partial),
      );
      expect(
        partialProjection.isRemoteUse(
          partialProjection.transactions.single,
          partial,
        ),
        isFalse,
      );
    },
  );
}

CuTransactionView _view({
  int sequence = 11,
  int amount = 300,
  int minute = 5,
  int sfi = 0x18,
  int? carrier = 2,
  String line = '2号线',
  CityUnionTransactionKind kind = CityUnionTransactionKind.consumption,
  ReferenceMatch<StationCodeEntry>? location,
  int? transactionType,
  List<int>? amountField,
}) => CuTransactionView(
  record: CityUnionFileParser.parseWalletRecord(
    sfi,
    [
      sequence >> 8,
      sequence & 0xff,
      0,
      0,
      0,
      ...(amountField ??
          [0, (amount >> 16) & 0xff, (amount >> 8) & 0xff, amount & 0xff]),
      transactionType ??
          (kind == CityUnionTransactionKind.recharge ? 0x02 : 0x09),
      0x20,
      0x00,
      0x11,
      0x02,
      0x34,
      0x00,
      0x20,
      0x26,
      0x11,
      0x07,
      0x00,
      minute,
      0x00,
    ],
    kind: kind,
    recordNumber: 1,
  ),
  transactionTime: DateTime.utc(2026, 11, 6, 16, minute),
  carrier: carrier,
  regionCode: '2000',
  location:
      location ??
      ReferenceMatch(ReferenceMatchStatus.matched, [
        StationCodeEntry(
          code: '2000110234',
          line: line,
          station: '演示站',
          kind: 'metro',
          system: 'cu',
          lineCode: '02',
          stationCode: '34',
        ),
      ]),
);

ArchiveBatchEvidence _batch(
  String id,
  Map<String, dynamic> projection, {
  String systemId = CardParserIds.cityUnion,
  String? cardCity = '1000',
  String? cuCity,
}) => ArchiveBatchEvidence(
  id: id,
  readAt: 1,
  storedParseVersion: 15,
  origin: 'test',
  timeSource: 'test',
  issues: const [],
  decoded: CardSessionSnapshot.decodeResult(
    CardSessionSnapshot(
      cardCityCode: cardCity,
      context: ArchiveContext(systemId: systemId),
      extensions: {'cuProjection': projection},
      rawEvidence: [
        if (cuCity != null)
          {'kind': 'cu_file', 'sfi': '0x15', 'cityCode': cuCity},
      ],
    ).encode(),
  ),
);
