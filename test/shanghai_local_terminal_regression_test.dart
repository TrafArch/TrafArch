import 'dart:convert';

import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/shanghai_mirrored_records.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/city_union_region_database.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

// The 2026-10-27 and 2026-11-24 reports share these ten ledger rows.
// TU and CU 0x18 contained the same rows, while TU 1E was all zero and 1A
// contained headers only. Literal station expectations are from CU M0.B.b.
void main() {
  test('上海双应用逐应用探测后，实时和归档均呈现四段地铁行程', () async {
    final presentation = await _scanLedger(
      '03104770000000000001',
      identifiedCu: true,
    );
    final card = presentation.parsedCard!;
    expect(card.parserId, CardParserIds.tunion);
    expect(
      presentation.applications.where((a) => a.confirmed).map((a) => a.appId),
      ['tu', 'cu'],
    );
    expect(card.transactions.map((t) => t.rawHex), _sampleRows);
    expect(
      presentation.cityUnionTransactions
          .where((view) => view.record.sfi == 0x18)
          .map((view) => view.record.rawHex.replaceAll(' ', '')),
      _sampleRows,
    );
    expect(
      card.transactions.map((t) => t.recordNumber),
      List.generate(10, (i) => i + 1),
    );
    expect(
      card.transitProcessRecords.every(
        (r) => r.railTransit == null && r.busTransit == null && r.trip == null,
      ),
      isTrue,
    );
    final trips = presentation.analysis!.trips;
    final context = ArchiveContext(
      systemId: card.parserId,
      applicationId: card.selectedAidHex,
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
    expect(restored.trips.map((t) => t.rawHex), _sampleRows);
    expect(restored.trips.first.balanceAfterFen, 8900);
    expect(card.cityUnionBalanceFen, 8100);
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
      expect(
        completed.map(
          (j) => (j.start!.line, j.start!.station, j.end!.line, j.end!.station),
        ),
        [
          ('7号线', '龙华中路', '1号线', '上海火车站'),
          ('9号线', '漕河泾开发区', '7号线', '龙华中路'),
          ('1号线', '上海火车站', '12号线', '虹梅路'),
          ('2号线', '浦东1号2号航站楼', '1号线', '上海火车站'),
        ],
      );
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
  test('哈尔滨卡仅观察到相同原文、CU 身份未经独立核实时不套用上海地铁匹配', () async {
    final presentation = await _scanLedger(
      '03104970200000000001',
      identifiedCu: false,
    );
    expect(presentation.dualApplicationDetected, isTrue);
    expect(presentation.cityUnionTransactions, isEmpty);
    final trips = presentation.analysis!.trips;
    expect(trips, hasLength(10));
    expect(trips.every((trip) => trip.rideStatusSource == null), isTrue);
    expect(trips.every((trip) => trip.stationLabel == null), isTrue);
  });
  test('哈尔滨双应用折叠同笔 CU 异地地铁流水时保留站名，不推断进出站', () async {
    final view = await scanHarbinMirrorLedger();
    final card = view.parsedCard!;
    final mirrors = partitionShanghaiMirroredRecords(
      parserId: card.parserId,
      displayCardType: CardTypes.regionalTunionType(
        card.info.applicationSerial,
      ),
      tunionTransactions: card.transactions,
      cityUnionTransactions: view.cityUnionTransactions,
    );
    final cu = mirrors.mirrored.singleWhere((v) => v.record.sequence == 14);
    expect(cu.location.value?.station, '上海火车站');
    expect(cu.carrier, 2);
    expect(mirrors.independent, isEmpty);
    final trip = view.analysis!.trips.singleWhere((t) => t.sequence == 14);
    expect(trip.stationLabel, '上海火车站');
    expect(trip.lineLabel, '1号线');
    expect(trip.appTypeName, '城市轨道交通');
    expect(trip.rideStatusName, isNull);
    expect(trip.rideStatusSource, isNull);
    expect(trip.cityCode, isNull);
    expect(trip.location?.ruleNote, contains('CU 0x18 #1'));
    expect(trip.rawHex, _sampleRows.first);
    expect(trip.balanceAfterFen, 8900);
  });
  test('哈尔滨双钱包的流水仅有一字节不同时，站名仍属于 CU', () async {
    // Same sequence, fare, transaction type, terminal and clock as TU slot 1.
    // The last byte of the overdraft field is A5 in CU and A4 in TU.
    final view = await _scanLedger(
      '03104970200000000001',
      identifiedCu: true,
      cuRows: [
        '000E001FA5000001900920001101261820261024230404',
        ..._sampleRows.skip(1),
      ],
    );
    final cu = view.cityUnionTransactions.singleWhere(
      (v) => v.record.sequence == 14,
    );
    expect(cu.location.value?.station, '上海火车站');
    final trip = view.analysis!.trips.singleWhere((t) => t.sequence == 14);
    expect(trip.rawHex, _sampleRows.first);
    expect(trip.stationLabel, isNull);
    expect(trip.appTypeName, isNull);
    expect(trip.rideStatusName, isNull);
  });
  test('上海卡重读后，旧批次的复合消费并入四段地铁行程，两笔充值各保留一次', () async {
    final view = await _scanLedger('03104770000000000001', identifiedCu: true);
    final snapshot = CardSessionSnapshot(
      parseVersion: kTripParseVersion,
      context: ArchiveContext(
        systemId: view.parsedCard!.parserId,
        applicationId: view.parsedCard!.selectedAidHex,
        currencyCode: 'CNY',
        minorUnitDigits: 2,
        clockBasis: 'device-local-card-time-unverified',
        extensions: const {'displayCardType': 'shanghai_transit_union'},
      ),
      cardCityCode: '2900',
      trips: view.analysis!.trips,
    );
    final current = snapshot.encode();
    final old = jsonDecode(current) as Map<String, dynamic>;
    old['parseVersion'] = 17;
    // The old generic TU reader captured the whole ledger without identifying
    // the accepting city, terminal or direction of these composite debits.
    for (final row in (old['trips'] as List).cast<Map<String, dynamic>>()) {
      if (row['composite'] != true) continue;
      for (final key in [
        'cityCode',
        'cityName',
        'lineLabel',
        'stationLabel',
        'stationType',
        'appTypeName',
        'rideStatusName',
        'rideStatusSource',
        'stationConfidence',
      ]) {
        row[key] = null;
      }
      row.remove('capturedDisplay');
      row['isEntry'] = false;
    }
    final oldJson = jsonEncode(old);
    final batches = [
      for (final (id, version, json) in [
        ('reread', kTripParseVersion, current),
        ('original', 17, oldJson),
      ])
        ArchiveBatchEvidence(
          id: id,
          readAt: id == 'reread' ? 2 : 1,
          storedParseVersion: version,
          origin: 'nfc',
          timeSource: 'capture',
          decoded: CardSessionSnapshot.decodeResult(json),
          issues: const [],
        ),
    ];
    final journeys = presentArchiveTrips(
      ArchiveHistory.projectRecords(batches),
      batches: batches,
    ).journeys;
    expect(journeys, hasLength(6));
    expect(
      journeys.where((j) => j.state == JourneyState.completed),
      hasLength(4),
    );
    expect(
      journeys.where((j) => j.events.first.payload.info.title == '充值'),
      hasLength(2),
    );
    for (final journey in journeys) {
      expect(journey.events.expand((event) => event.sourceIds).toSet(), {
        'original',
        'reread',
      });
    }
    expect(batches.last.decoded.snapshot!.encode(), oldJson);
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

Future<ScanPresentation> scanHarbinMirrorLedger() =>
    _scanLedger('03104970200000000001', identifiedCu: true);

Future<ScanPresentation> _scanLedger(
  String serial, {
  required bool identifiedCu,
  List<String> cuRows = _sampleRows,
}) async {
  final tuPublic = '02002900FFFFFFFF0201${serial}2024010120291231AABB';
  const cuPublic =
      '869820007590FFFF82052000112233445566778820240101203012310000';
  String? selected;
  final scan = await LocalCardReader((apdu) async {
    final command = LocalHex.bytesToHex(apdu);
    if (apdu[1] == 0xA4) {
      selected = switch (command) {
        '00A4040008A00000063201010500' => 'tu',
        '00A4040009A0000000038698070100' => 'cu',
        _ => null,
      };
      if (identifiedCu && selected == 'cu') {
        return LocalHex.hexToBytes('6F0B8409A000000003869807019000');
      }
      return selected != null || command == '00A40000023F0000'
          ? [0x90, 0]
          : [0x6A, 0x82];
    }
    if (selected == null) return [0x6A, 0x82];
    final hex = switch ((selected, command)) {
      ('tu', '00B0950000') => tuPublic,
      ('cu', '00B095001E') => cuPublic,
      ('tu', '805C000204') => '000022C4',
      ('cu', '805C000204') => '00001FA4',
      _ => null,
    };
    if (hex != null) return [...LocalHex.hexToBytes(hex), 0x90, 0];
    if (apdu[1] == 0xB2) {
      final slot = apdu[2];
      final ledger = selected == 'cu' ? cuRows : _sampleRows;
      if (apdu[3] == 0xC4 && slot <= ledger.length) {
        return [...LocalHex.hexToBytes(ledger[slot - 1]), 0x90, 0];
      }
      if (selected == 'tu' && apdu[3] == 0xD4 && slot <= 2) {
        return [0x27, slot, 0x7D, ...List.filled(125, 0), 0x90, 0];
      }
      if (selected == 'tu' && apdu[3] == 0xF4 && slot <= 30) {
        return [...List.filled(48, 0), 0x90, 0];
      }
      return [0x6A, 0x83];
    }
    return [0x6A, 0x82];
  }).scan();
  final result = scan.result!;
  return ScanPresentation(
    TransitReadOutcome(result.parsedCard, applications: result.applications),
    _knowledge(),
  );
}

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
