import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/test_database.dart';

void main() {
  test('新1A各端城市名随捕获保存且归档不重新查询当前参考库', () async {
    final records = <TUnionProcessRecord>[
      TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 1,
        recordName: '轨道',
        raw: const [1],
        railTransit: TransitRecord(
          statusCode: 2,
          entryCityCode: '1000',
          exitCityCode: '2500',
          entryTime: DateTime(2026, 10, 27, 8),
          exitTime: DateTime(2026, 10, 27, 8, 30),
        ),
      ),
      TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 2,
        recordName: '公交',
        raw: const [2],
        busTransit: BusTransitRecord(
          statusCode: 2,
          entryCityCode: '1000',
          exitCityCode: '2500',
          entryTime: DateTime(2026, 10, 27, 9),
          exitTime: DateTime(2026, 10, 27, 9, 30),
        ),
      ),
    ];
    final json = await _capture(
      records,
      knowledge: _locationKnowledge(withCities: true),
    );
    for (final section in ['rails', 'buses']) {
      final saved = (json[section] as List).single as Map;
      final display = saved['capturedDisplay'] as Map?;
      expect((display?['entry'] as Map?)?['cityName'], '北京市');
      expect((display?['exit'] as Map?)?['cityName'], '济南市');
      expect(saved['entryCityCode'], '1000');
      expect(saved['exitCityCode'], '2500');
    }
    final events = _capturedEvents(json);
    expect(
      events
          .where((event) => event.role == JourneyEventRole.entry)
          .map((event) => event.cityLabel),
      everyElement('北京'),
    );
    expect(
      events
          .where((event) => event.role == JourneyEventRole.exit)
          .map((event) => event.cityLabel),
      everyElement('济南'),
    );
    final original = jsonEncode(json);
    expect(CardSessionSnapshot.decode(original)!.encode(), original);
  });

  test('新独立1E保存自身线路站点城市显示并在JSON往返后用于归档', () async {
    final records = [
      _source(1),
      _source(2, appType: 2, field: '0001000A000100'),
    ];
    final json = await _capture(
      records,
      knowledge: _locationKnowledge(withCities: true),
    );
    final cycles = json['cycle'] as List;
    expect((cycles[0] as Map)['capturedDisplay'], {
      'cityName': '济南市',
      'line': '1号线',
      'station': '捕获轨道进站',
    });
    expect((cycles[1] as Map)['capturedDisplay'], {
      'cityName': '济南市',
      'line': '12路',
      'station': '捕获公交上车',
    });
    expect((cycles[0] as Map)['lineStationCode'], '00010001000100');
    expect((cycles[1] as Map)['lineStationCode'], '0001000A000100');
    expect((cycles[1] as Map)['rawHex'], records[1].trip!.rawHex);
    final original = jsonEncode(json);
    final restored = CardSessionSnapshot.decode(original)!;
    expect(restored.encode(), original);
    final events = _capturedEvents(
      jsonDecode(restored.encode()) as Map<String, dynamic>,
    );
    expect(events.map((event) => event.cityLabel), everyElement('济南'));
    expect(
      events.map((event) => event.endpoint.line),
      containsAll(['1号线', '12路']),
    );
    expect(
      events.map((event) => event.endpoint.station),
      containsAll(['捕获轨道进站', '捕获公交上车']),
    );
  });

  test('新1A快照分别捕获轨道和公交两端线路站名且原始字段不变', () async {
    final rail = TransitRecord(
      statusCode: 2,
      entryCityCode: '2500',
      exitCityCode: '2500',
      entryStationId: '00000001',
      exitStationId: '00000002',
      entryLineCode: 1,
      exitLineCode: 2,
      entryTime: DateTime(2026, 10, 27, 8),
      exitTime: DateTime(2026, 10, 27, 8, 30),
    );
    final bus = BusTransitRecord(
      statusCode: 2,
      entryCityCode: '2500',
      exitCityCode: '2500',
      entryStationCode: '0A',
      exitStationCode: '11',
      entryLineCode: '0001',
      exitLineCode: '0001',
      entryOperatorCode: '0001',
      exitOperatorCode: '0001',
      entryTime: DateTime(2026, 10, 27, 9),
      exitTime: DateTime(2026, 10, 27, 9, 30),
    );
    final json = await _capture([
      TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 1,
        recordName: '轨道',
        raw: const [1],
        railTransit: rail,
      ),
      TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 2,
        recordName: '公交',
        raw: const [2],
        busTransit: bus,
      ),
    ], knowledge: _locationKnowledge());
    final savedRail = (json['rails'] as List).single as Map;
    final savedBus = (json['buses'] as List).single as Map;
    expect(savedRail['capturedDisplay'], {
      'entry': {'line': '1号线', 'station': '捕获轨道进站'},
      'exit': {'line': '2号线', 'station': '捕获轨道出站'},
    });
    expect(savedBus['capturedDisplay'], {
      'entry': {'line': '12路', 'station': '捕获公交上车'},
      'exit': {'line': '12路', 'station': '捕获公交下车'},
    });
    expect(savedRail['entryStationId'], '00000001');
    expect(savedRail['exitLineCode'], 2);
    expect(savedBus['entryStationCode'], '0A');
    expect(savedBus['exitLineCode'], '0001');
    final text = jsonEncode(json);
    expect(CardSessionSnapshot.decode(text)!.encode(), text);
  });

  test('无参考证据的新1A不把原码或单侧lineName存成两端解析名称', () async {
    final json = await _capture([
      const TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 1,
        recordName: '轨道',
        raw: [1],
        railTransit: TransitRecord(
          statusCode: 0,
          entryStationId: '00000001',
          entryLineCode: 1,
          exitLineCode: 2,
          lineName: '单侧既有线路',
        ),
      ),
    ]);
    final saved = (json['rails'] as List).single as Map;
    expect(saved['capturedDisplay'] ?? const {}, isEmpty);
    expect(saved['lineName'], '单侧既有线路');
  });

  test('新快照记录独立1E实际槽号并保留未知记录造成的断点', () async {
    final json = await _capture([
      _source(1),
      _source(2, decoded: false),
      _source(3),
    ]);
    final provenance = json['recordProvenance'] as Map;
    expect((provenance['cycle[0]'] as Map)['recordNumber'], 1);
    expect((provenance['cycle[1]'] as Map)['recordNumber'], 3);
    expect((provenance['cycle[1]'] as Map)['sfi'], 0x1E);
    expect((provenance['cycle[1]'] as Map)['recordNumberIsReliable'], isTrue);
    final snapshot = CardSessionSnapshot.decode(jsonEncode(json))!;
    expect(snapshot.processTrips, hasLength(2));
    expect(
      snapshot.rawEvidence.where(
        (record) => record['kind'] == 'tu_process_record',
      ),
      hasLength(3),
    );
  });

  test('重编号不可靠或重复的1E来源不保存可用于配对的槽号', () async {
    for (final sources in [
      [_source(1, reliable: false)],
      [_source(1), _source(1)],
    ]) {
      final json = await _capture(sources);
      final provenance = json['recordProvenance'] as Map;
      expect((provenance['cycle[0]'] as Map)['recordNumber'], isNull);
    }
  });
}

Future<Map<String, dynamic>> _capture(
  List<TUnionProcessRecord> records, {
  KnowledgeBase? knowledge,
}) async {
  final database = testDatabase();
  final controller = ArchiveController(
    CardRepository(database),
    const MethodChannelLogExporter(),
    (_) {},
  );
  final card = ParsedCard(
    parserId: CardParserIds.tunion,
    parserName: '交通联合',
    selectedAidHex: 'A000000632010105',
    transactions: const [],
    info: const TUnionCardInfo(
      applicationSerial: '03100000000000000001',
      issuerId: '1122334455667788',
      balanceFen: 9000,
    ),
    transitProcessRecords: records,
  );
  controller.stage(
    ScanPresentation(
      TransitReadOutcome(card),
      knowledge ?? KnowledgeBase.empty(),
    ),
    'capture-process-slots',
    DateTime(2026, 10, 27),
    const [],
  );
  expect(controller.pending, isNotNull);
  final json =
      jsonDecode(controller.pending!.sessionDataJson!) as Map<String, dynamic>;
  controller.dispose();
  await database.close();
  return json;
}

List<JourneyEvent<TripEntryInfo>> _capturedEvents(Map<String, dynamic> json) {
  final snapshot = CardSessionSnapshot.decode(jsonEncode(json))!;
  final records = <ArchiveHistoryRecord>[
    for (final section in const {
      'rails': ArchiveRecordKind.rail,
      'buses': ArchiveRecordKind.bus,
      'cycle': ArchiveRecordKind.process,
    }.entries)
      for (final fields in json[section.key] as List)
        ArchiveHistoryRecord(
          kind: section.value,
          fields: fields as Map<String, dynamic>,
          context: snapshot.context,
          sources: const [ArchiveRecordSource('captured', 'record', 8, null)],
        ),
  ];
  return presentArchiveTrips(
    records,
    onDiagnostics: (_) {},
  ).entries.map((entry) => entry.journeyEvent!).toList();
}

KnowledgeBase _locationKnowledge({bool withCities = false}) =>
    KnowledgeBase.fromJsonStrings(
      cardPrefixes: !withCities ? null : '{"entries":[{"issuer":"00001000","city":"北京市"},{"issuer":"00002500","city":"济南市"}]}',
      stationCodes: StationCodeTable.fromDatasets(const [
        StationDataset(
          file: 'test/rail',
          cityCode: '2500',
          system: 'tu',
          kind: 'metro',
          codes: {
            '25000101': StationCodeEntry(
              code: '25000101',
              system: 'tu',
              kind: 'metro',
              type: '地铁',
              line: '1号线',
              station: '捕获轨道进站',
            ),
            '25000202': StationCodeEntry(
              code: '25000202',
              system: 'tu',
              kind: 'metro',
              type: '地铁',
              line: '2号线',
              station: '捕获轨道出站',
            ),
          },
        ),
        StationDataset(
          file: 'test/bus',
          cityCode: '2500',
          system: 'tu',
          kind: 'bus',
          codes: {
            '25000001000A': StationCodeEntry(
              code: '25000001000A',
              system: 'tu',
              kind: 'bus',
              type: '公交',
              line: '12路',
              station: '捕获公交上车',
            ),
            '250000010011': StationCodeEntry(
              code: '250000010011',
              system: 'tu',
              kind: 'bus',
              type: '公交',
              line: '12路',
              station: '捕获公交下车',
            ),
          },
        ),
      ]),
    );

TUnionProcessRecord _source(
  int number, {
  bool decoded = true,
  bool reliable = true,
  int appType = 1,
  String field = '00010001000100',
}) {
  final raw = [3, number, ...List.filled(46, 1)];
  return TUnionProcessRecord(
    sfi: 0x1E,
    recordNumber: number,
    recordNumberIsReliable: reliable,
    recordName: '循环记录$number',
    raw: raw,
    trip: !decoded
        ? null
        : TUnionTripRecord(
            typeCode: 3,
            terminalId: '0000000000000001',
            appTypeCode: appType,
            lineStationCode: field,
            amountFen: 0,
            balanceFen: 9000,
            time: DateTime(2026, 10, 27, 8, number),
            cityCode: '2500',
            rawHex: raw
                .map((value) => value.toRadixString(16).padLeft(2, '0'))
                .join(' '),
          ),
  );
}
