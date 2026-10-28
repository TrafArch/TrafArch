import 'dart:convert';

import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/city_union_region_database.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

// Transaction fields from the 2026-10-27 Shanghai report; no card identifier.
// TU and CU 0x18 contained the same rows, while TU 1E was all zero and 1A
// contained headers only. Literal station expectations are from CU M0.B.b.
void main() {
  test('上海样本原始APDU经读取分析及JSON往返仍呈现四段行程与独立余额', () async {
    final rows = _sampleRows.map(_hex).toList();
    final public = List.filled(30, 0)
      ..setRange(10, 20, [
        0x03,
        0x10,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
      ]); // Synthetic identity.
    final unit = CommonUnitTu(
      ApduExchange(
        transceive: (command) async {
          if (command[1] == 0xA4) return [0x90, 0];
          if (command[1] == 0xB0 && command[2] == 0x95) {
            return [...public, 0x90, 0];
          }
          if (command[1] == 0x5C) return [0, 0, 0x22, 0xC4, 0x90, 0];
          if (command[1] == 0xB2 &&
              command[3] == 0xC4 &&
              command[2] <= rows.length) {
            return [...rows[command[2] - 1], 0x90, 0];
          }
          if (command[1] == 0xB2 && command[3] == 0xD4 && command[2] <= 2) {
            return [0x27, command[2], 0x7D, ...List.filled(125, 0), 0x90, 0];
          }
          if (command[1] == 0xB2 && command[3] == 0xF5) {
            return [...List.filled(48 * 30, 0), 0x90, 0];
          }
          return [0x6A, 0x83];
        },
      ),
    );
    final info = CardInfo();
    final apdus = <ApduRecord>[];
    expect(await unit.select(info, apdus), isTrue);
    final read = (await unit.read(info, apdus))!;
    expect(read.transactions, hasLength(10));
    expect(
      read.transactions.map((t) => t.recordNumber),
      List.generate(10, (i) => i + 1),
    );
    expect(
      read.transitProcessRecords.every(
        (r) => r.railTransit == null && r.busTransit == null && r.trip == null,
      ),
      isTrue,
    );
    final dual = ParsedCard(
      parserId: CardParserIds.shanghaiTunion,
      parserName: 'Shanghai dual sample',
      info: read.info,
      transactions: read.transactions,
      transitProcessRecords: read.transitProcessRecords,
      cityUnionBalanceFen: 8100,
    );
    final trips = AnalysisEngine(_knowledge()).analyze(dual).trips;
    const context = ArchiveContext(
      systemId: CardParserIds.shanghaiTunion,
      applicationId: 'A000000632010105',
      currencyCode: 'CNY',
      minorUnitDigits: 2,
      clockBasis: 'device-local-card-time-unverified',
    );
    final snapshot = CardSessionSnapshot(
      parseVersion: kTripParseVersion,
      context: context,
      trips: trips,
      cardCityCode: '2900',
    );
    final encoded = snapshot.encode();
    final restored = CardSessionSnapshot.decode(encoded)!;
    expect(
      restored.trips.map((t) => t.rawHex),
      read.transactions.map((t) => t.rawHex),
    );
    expect(restored.trips.first.balanceAfterFen, 8900);
    expect(dual.cityUnionBalanceFen, 8100);
    final display = TripPresentationContext(
      currency: Currency.cny,
      cityNameOf: (_) => '上海',
      resolveStationMatch: (c, s, {lineValue}) => StationMatch.unmatched,
      resolveCycleStationMatch: (c, s, {terminalId, time, appType}) =>
          StationMatch.unmatched,
      resolveLineName: (_, _) => null,
      resolveBusLocation: (c, s, {context = const TunionBusDecodeContext()}) =>
          const TunionBusLocation(),
    );
    final live = projectJourneys(
      buildTripStream(trips: trips).map(
        (entry) => describeJourneyEvent(
          entry,
          display,
          describeTripEntry(entry, display, remote: false),
        ),
      ),
    );
    final raw = jsonDecode(encoded) as Map<String, dynamic>;
    final archived = presentArchiveTrips([
      for (final fields in raw['trips'])
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.transaction,
          fields: Map<String, dynamic>.from(fields),
          context: context,
          sources: const [ArchiveRecordSource('sample', 'trips', 9, null)],
        ),
    ], onDiagnostics: (_) {});
    final saved = projectJourneys(archived.entries.map((e) => e.journeyEvent!));
    for (final journeys in [live, saved]) {
      final completed = journeys
          .where((j) => j.state == JourneyState.completed)
          .toList();
      expect(completed, hasLength(4));
      expect(journeys.expand((j) => j.events), hasLength(10));
      expect(completed.first.start!.station, '龙华中路');
      expect(completed.first.end!.station, '上海火车站');
      expect(
        completed.first.duration,
        const Duration(minutes: 27, seconds: 18),
      );
      expect(
        completed.last.duration,
        const Duration(hours: 2, minutes: 8, seconds: 41),
      );
      expect(completed.map((j) => j.amountText?.replaceAll(' ', '')), [
        '-¥4.00',
        '-¥4.00',
        '-¥4.00',
        '-¥7.00',
      ]);
    }
    expect(restored.encode(), encoded);
  });
  test('Shanghai CU metro direction follows the source ledger state rule', () {
    final trips = AnalysisEngine(_knowledge()).analyze(_card()).trips;
    expect(trips.take(8).map((t) => t.rideStatusName), [
      '出站',
      '进站',
      '出站',
      '进站',
      '出站',
      '进站',
      '出站',
      '进站',
    ]);
    expect(trips.take(8).map((t) => t.isEntry), [
      false,
      true,
      false,
      true,
      false,
      true,
      false,
      true,
    ]);
    expect(
      trips
          .take(8)
          .every((t) => t.rideStatusSource == 'shanghai-cu-ledger-inference'),
      isTrue,
    );
    expect(trips.skip(8).every((t) => t.rideStatusName == null), isTrue);
  });

  for (final gap in [
    'unknown-terminal',
    'sequence',
    'slot',
    'time-order',
    'previous-slot-null',
    'next-slot-null',
  ]) {
    test('Shanghai metro inference resets across $gap gaps', () {
      final txns = <TUnionTransaction>[
        TUnionTransaction(
          sequence: 4,
          recordNumber: gap == 'previous-slot-null' ? null : 1,
          overdraftLimitFen: 0,
          amountFen: 0,
          rawType: 9,
          terminalId: '200011012618',
          time: DateTime(2026, 10, 24, 23),
        ),
        if (gap == 'unknown-terminal')
          TUnionTransaction(
            sequence: 3,
            recordNumber: 2,
            overdraftLimitFen: 0,
            amountFen: 0,
            rawType: 9,
            terminalId: '999999999999',
            time: DateTime(2026, 10, 24, 22),
          ),
        TUnionTransaction(
          sequence: gap == 'sequence' || gap == 'unknown-terminal' ? 2 : 3,
          recordNumber: gap == 'next-slot-null'
              ? null
              : gap == 'slot' || gap == 'unknown-terminal'
              ? 3
              : 2,
          overdraftLimitFen: 0,
          amountFen: 0,
          rawType: 9,
          terminalId: '200011012618',
          time: DateTime(2026, 10, 24, gap == 'time-order' ? 23 : 21),
        ),
      ];
      final trips = AnalysisEngine(_knowledge())
          .analyze(
            ParsedCard(
              parserId: CardParserIds.shanghaiTunion,
              parserName: 'source gap regression',
              info: const TUnionCardInfo(cityCode: '2900', balanceFen: 8900),
              transactions: txns,
            ),
          )
          .trips;
      expect(
        trips
            .where((t) => t.terminalId != '999999999999')
            .map((t) => t.rideStatusName),
        ['进站', '进站'],
      );
      if (gap == 'unknown-terminal') {
        expect(
          trips.singleWhere((t) => t.sequence == 3).rideStatusSource,
          isNull,
        );
      }
    });
  }

  test('consecutive zero-fare metro records are not all labelled entry', () {
    final card = ParsedCard(
      parserId: CardParserIds.shanghaiTunion,
      parserName: 'source state regression',
      info: const TUnionCardInfo(cityCode: '2900', balanceFen: 8900),
      transactions: [
        for (final (sequence, time) in const [
          (3, '2026-10-24T23:00:00'),
          (2, '2026-10-24T22:00:00'),
          (1, '2026-10-24T21:00:00'),
        ])
          TUnionTransaction(
            sequence: sequence,
            overdraftLimitFen: 0,
            amountFen: 0,
            rawType: 9,
            terminalId: '200011012618',
            time: DateTime.parse(time),
          ),
      ],
    );
    final trips = AnalysisEngine(_knowledge()).analyze(card).trips;
    expect(trips.map((t) => t.rideStatusName), ['进站', '出站', '进站']);
  });

  test('Shanghai local CU terminals enrich the TU ledger without changing its wallet', () {
    final card = _card();
    final trips = AnalysisEngine(_knowledge()).analyze(card).trips;
    expect(trips.map((t) => t.stationLabel).take(8), [
      '上海火车站',
      '龙华中路',
      '龙华中路',
      '漕河泾开发区',
      '虹梅路',
      '上海火车站',
      '上海火车站',
      '浦东1号2号航站楼',
    ]);
    expect(trips.map((t) => t.lineLabel).take(8), [
      '1号线',
      '7号线',
      '7号线',
      '9号线',
      '12号线',
      '1号线',
      '1号线',
      '2号线',
    ]);
    expect(trips.take(8).every((t) => t.cityCode == '2900'), isTrue);
    expect(trips.take(8).every((t) => t.appTypeName == '城市轨道交通'), isTrue);
    expect(trips.map((t) => t.balanceAfterFen), [
      8900,
      9300,
      9300,
      9700,
      9700,
      10100,
      10100,
      10800,
      10800,
      8800,
    ]);
    expect(trips.first.terminalId, '200011012618');
    expect(trips.first.typeName, '复合消费');
    expect(trips.first.amountFen, 400);
    expect(trips.first.matchedProcessTrip, isNull);
    expect(trips.last.isConsume, isFalse);
    expect(card.cityUnionBalanceFen, 8100);
  });

  test(
    'ordinary TU and unrecognized Shanghai terminals do not enter CU lookup',
    () {
      final ordinary = AnalysisEngine(_knowledge())
          .analyze(_card(parserId: CardParserIds.tunion));
      expect(ordinary.trips.every((t) => t.stationLabel == null), isTrue);
      final unknown = AnalysisEngine(_knowledge())
          .analyze(_card(terminal: '290099999999'));
      expect(unknown.trips.first.stationLabel, isNull);
      expect(unknown.trips.first.appTypeName, isNull);
      expect(unknown.trips.first.rideStatusName, isNull);
    },
  );

  test('CU raw-code ambiguity is not collapsed by identical display names', () {
    final trip = AnalysisEngine(_knowledge(ambiguous: true))
        .analyze(_card())
        .trips
        .first;
    expect(trip.stationConfidence, StationMatchConfidence.ambiguous);
    expect(trip.stationLabel, isNull);
    expect(trip.lineLabel, isNull);
  });

  test(
    'explicit local metro entry advances the continuous inference state',
    () {
      final time = DateTime(2026, 10, 24, 23);
      final trips = AnalysisEngine(_knowledge())
          .analyze(
            ParsedCard(
              parserId: CardParserIds.shanghaiTunion,
              parserName: 'explicit local direction regression',
              info: const TUnionCardInfo(cityCode: '2900', balanceFen: 8900),
              transactions: [
                for (final sequence in [2, 1])
                  TUnionTransaction(
                    sequence: sequence,
                    overdraftLimitFen: 0,
                    amountFen: 0,
                    rawType: 9,
                    terminalId: sequence == 2 ? '200011012618' : '200011074356',
                    time: sequence == 2
                        ? time
                        : time.subtract(const Duration(hours: 1)),
                  ),
              ],
              transitProcessRecords: [
                TUnionProcessRecord(
                  sfi: 0x1E,
                  recordNumber: 1,
                  recordName: 'synthetic local explicit entry',
                  raw: const [],
                  trip: TUnionTripRecord(
                    typeCode: 1,
                    terminalId: '0000200011012618',
                    appTypeCode: 1,
                    lineStationCode: '00010026000000',
                    amountFen: 0,
                    balanceFen: 8900,
                    time: time,
                    cityCode: '2900',
                  ),
                ),
              ],
            ),
          )
          .trips;
      expect(trips.map((t) => t.rideStatusName), ['进站', '出站']);
      expect(trips.first.rideStatusSource, isNull);
      expect(trips.last.rideStatusSource, 'shanghai-cu-ledger-inference');
    },
  );

  test(
    'Shanghai local terminal fallback does not override a linked TU process',
    () {
      final time = _transactions().first.time;
      final process = TUnionTripRecord(
        typeCode: 6,
        terminalId: '0000200011012618',
        appTypeCode: 1,
        lineStationCode: '08010000000000',
        amountFen: 400,
        balanceFen: 99999,
        time: time,
        cityCode: '2220',
      );
      final trip = AnalysisEngine(_knowledge())
          .analyze(
            _card(
              processes: [
                TUnionProcessRecord(
                  sfi: 0x1E,
                  recordNumber: 1,
                  recordName: 'synthetic conflicting acquirer evidence',
                  raw: const [],
                  trip: process,
                ),
              ],
            ),
          )
          .trips
          .first;
      expect(trip.cityCode, '2220');
      expect(trip.stationLabel, '河口');
      expect(trip.lineLabel, '12号线');
      expect(trip.balanceAfterFen, 8900);
      expect(trip.rideStatusSource, isNull);
    },
  );
}

// 0x18 record bodies from the report; card identity/other private files excluded.
const _sampleRows = [
  '000E001FA4000001900920001101261820261024230404',
  '000D002134000000000920001107435620261024223646',
  '000C002134000001900920001107430220261024185822',
  '000B0022C4000000000920001109311320261024181233',
  '000A0022C4000001900920001112246420261024130115',
  '0009002454000000000920001101266520261024121909',
  '0008002454000002BC0920001101261720261024001541',
  '0007002710000000000920001102636720261023220700',
  '0006002710000007D00220009507000120261015120628',
  '0005001F40000013880220009507000120261014211824',
];
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

ParsedCard _card({
  String parserId = CardParserIds.shanghaiTunion,
  String? terminal,
  List<TUnionProcessRecord> processes = const [],
}) => ParsedCard(
  parserId: parserId,
  parserName: 'Shanghai local terminal regression',
  info: const TUnionCardInfo(cityCode: '2900', balanceFen: 8900),
  transactions: _transactions(terminal: terminal),
  transactionFileObserved: true,
  transitProcessRecords: processes,
  cityUnionBalanceFen: 8100,
);

List<TUnionTransaction> _transactions({String? terminal}) => [
  for (final (sequence, amount, pos, time) in const [
    (14, 400, '200011012618', '2026-10-24T23:04:04'),
    (13, 0, '200011074356', '2026-10-24T22:36:46'),
    (12, 400, '200011074302', '2026-10-24T18:58:22'),
    (11, 0, '200011093113', '2026-10-24T18:12:33'),
    (10, 400, '200011122464', '2026-10-24T13:01:15'),
    (9, 0, '200011012665', '2026-10-24T12:19:09'),
    (8, 700, '200011012617', '2026-10-24T00:15:41'),
    (7, 0, '200011026367', '2026-10-23T22:07:00'),
    (6, 2000, '200095070001', '2026-10-15T12:06:28'),
    (5, 5000, '200095070001', '2026-10-14T21:18:24'),
  ])
    TUnionTransaction(
      sequence: sequence,
      overdraftLimitFen: 0,
      amountFen: amount,
      rawType: sequence > 6 ? 9 : 2,
      terminalId: terminal ?? pos,
      time: DateTime.parse(time),
    ),
];

KnowledgeBase _knowledge({bool ambiguous = false}) {
  final empty = KnowledgeBase.empty();
  return KnowledgeBase(
    cities: empty.cities,
    issuers: empty.issuers,
    terminalRules: empty.terminalRules,
    stationCodes: StationCodeTable.fromDatasets([
      const StationDataset(
        file: 'TU precedence fixture',
        cityCode: '2220',
        kind: 'metro',
        codes: {
          '22200801': StationCodeEntry(
            code: '22200801',
            sourceKey: '22200801',
            sourceField: 'M0.i0.a',
            line: '12号线',
            station: '河口',
          ),
        },
      ),
    ]),
    cuTerminals: CityUnionTerminalMatcher([
      if (ambiguous)
        const CuTerminalRule(
          regionCode: '2000',
          matchKey: '2000110126',
          isPrefix: true,
          requiredTxnType: -1,
          priority: 30,
          entry: StationCodeEntry(
            code: 'conflicting-source-key',
            system: 'cu',
            kind: 'metro',
            line: '1号线',
            station: '上海火车站',
            stationCode: 'different-raw-station',
          ),
        ),
      for (final (key, line, station) in const [
        ('2000110126', '1号线', '上海火车站'),
        ('2000110743', '7号线', '龙华中路'),
        ('2000110931', '9号线', '漕河泾开发区'),
        ('2000111224', '12号线', '虹梅路'),
        ('2000110263', '2号线', '浦东1号2号航站楼'),
      ])
        CuTerminalRule(
          regionCode: '2000',
          matchKey: key,
          isPrefix: true,
          requiredTxnType: -1,
          priority: 30,
          entry: StationCodeEntry(
            code: key,
            sourceKey: key,
            sourceField: 'M0.B.b',
            system: 'cu',
            kind: 'metro',
            line: line,
            station: station,
          ),
        ),
    ]),
  );
}
