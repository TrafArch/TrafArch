import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

// User's complete, unchanged 48-byte 0x1E record. Spaces are only separators.
const _reportedHex =
    '06000041 31800007 56020016 000000D5 00000000 6400003A '
    'CA202609 24182929 16101297 1610FFFF FFFF0000 00000000';

void main() {
  test('1E display preserves raw balance for all types', () {
    for (final type in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 255]) {
      for (final amount in [0, 100]) {
        final record = TUnionTripRecord(
          typeCode: type,
          terminalId: '0000000000000000',
          appTypeCode: 2,
          lineStationCode: '00000000000000',
          amountFen: amount,
          balanceFen: 100,
          time: DateTime(2026),
          rawHex: 'ABCD',
        );
        final info = describeTripEntry(
          ProcessTripEntry(record),
          _display,
          remote: false,
        );
        expect(info.subText, '记录余额 ¥1.00', reason: '$type/$amount');
        expect(info.fields, contains(('记录余额', '¥1.00')));
        expect(record.balanceFen, 100);
        expect(record.rawHex, 'ABCD');
      }
    }
  });
  test('1A displays only recorded entry balance without deducting fares', () {
    for (final balance in [2500, 0, null]) {
      final rail = TransitRecord(
        statusCode: 2,
        entryBalanceFen: balance,
        entryAmountFen: 100,
        exitAmountFen: 300,
      );
      final entry = describeTripEntry(
        RailRecordEntry(rail, isEntry: true),
        _display,
        remote: false,
      );
      final exit = describeTripEntry(
        RailRecordEntry(rail, isEntry: false),
        _display,
        remote: false,
      );
      expect(
        entry.subText,
        balance == null ? null : '余额 ¥${(balance / 100).toStringAsFixed(2)}',
      );
      expect(exit.subText, isNull);
      expect(exit.fields.where((f) => f.$1.contains('余额')), isEmpty);
    }
  });
  late Database db;
  late StationCodeTable stations;
  late KnowledgeBase knowledge;
  setUp(() {
    db = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    stations = StationCodeTable.empty.withLiveSources([
      TuRegionLiveSource(TuStationRepository(db)),
    ]);
    String document(String name) =>
        db.select('SELECT json FROM reference_documents WHERE name = ?', [
              name,
            ]).single['json']
            as String;
    knowledge = KnowledgeBase.fromJsonStrings(
      stationCodes: stations,
      cardPrefixes: document('card_prefixes'),
      issuerFingerprints: document('issuers'),
      terminalRules: document('terminal_rules'),
    );
  });
  tearDown(() => db.close());

  test(
    'reported HEX preserves 1E bus fields without BCD or offset corruption',
    () {
      final bytes = _bytes(_reportedHex);
      final record = const TUnionProcessParser().parseCycleTrip(bytes)!;
      expect(bytes, hasLength(48));
      expect(record.typeCode, 0x06);
      expect(record.typeName, 'EP 单次消费');
      expect(record.isBus, isTrue);
      expect(record.terminalId, '0000413180000756');
      expect(record.lineStationCode, '0016000000D500');
      expect(record.lineCode, '0016');
      expect(record.stationCode, '0000');
      expect(record.operatorCode, '00D5');
      expect(record.amountFen, 100);
      expect(record.balanceFen, 15050);
      expect(record.time, DateTime(2026, 9, 24, 18, 29, 29));
      expect(record.cityCode, '1610');
      expect(record.acquirerId, '12971610FFFFFFFF');
      expect(record.rawHex, _reportedHex.replaceAll(' ', ''));
    },
  );

  test('reported 1E resolves route without a station or terminal SQL hit', () {
    final record = const TUnionProcessParser().parseCycleTrip(
      _bytes(_reportedHex),
    )!;
    // These are terminal-keyed M0.n0.a records, not the m764r bus route table.
    expect(TuStationRepository(db).findByKey('1610', '413180000756'), isEmpty);
    final location = resolveTunionBusLocation(
      stations: stations,
      cityCode: record.cityCode,
      field: record.lineStationCode,
    );
    expect(location.lineLabel, '864');
    expect(location.stationLabel, isNull);
    expect(location.match.confidence, StationMatchConfidence.unmatched);
  });

  test('paired out-of-city trip displays 864 and keeps original evidence', () {
    final result = _analyze(knowledge);
    final trip = result.trips.single;
    expect(result.identity.cityCode, '3910');
    expect(trip.cityCode, '1610');
    expect(trip.cityName, '太原');
    expect(trip.lineLabel, '864');
    expect(trip.matchedProcessTrip!.lineCode, '0016');
    expect(trip.matchedProcessTrip!.rawHex, _reportedHex.replaceAll(' ', ''));
    expect(trip.balanceAfterFen, 15050);
    expect(trip.stationConfidence, isNot(StationMatchConfidence.exact));
    expect(trip.stationLabel, '0000');
  });

  for (final match in [
    {'cityCode': '3910'},
    {'terminalPrefix': '3910'},
  ]) {
    test('record city wins over conflicting terminal rule $match', () {
      // Synthetic 0x18 context: the reported 0x1E bytes remain unchanged.
      final withRule = KnowledgeBase(
        cities: knowledge.cities,
        issuers: knowledge.issuers,
        stationCodes: stations,
        terminalRules: TerminalRuleSet.fromJson({
          'rules': [
            {
              'id': 'conflicting-test-rule',
              'match': match,
              'layout': {
                'cityCode': [0, 4],
                'lineCode': [4, 6],
                'stationCode': [8, 10],
              },
            },
          ],
        }),
      );
      final trip = _analyze(withRule, terminal: '391002003100').trips.single;
      expect(trip.cityCode, '1610');
      expect(trip.cityName, '太原');
      expect(trip.location, isNull);
      expect(trip.stationLabel, '0000');
      expect(trip.lineLabel, '864');
    });
  }

  // Independently checked cases from TripReader 1.7.17-cn m764r's entire
  // Taiyuan branch (JADX 6559-7259; original Smali 36119-39408).
  // Include A-F keys, shared jump targets, named routes and suffixes.
  for (final example in const {
    '0012': '13',
    '001B': '1',
    '0022': '57',
    '002A': '16',
    '0042': '12支',
    '0062': '3',
    '008A': '2',
    '008E': '821支',
    '008F': '821支',
    '0097': '安广专线',
    '009C': '6',
    '00BB': '865',
    '013C': '天龙山景区摆渡',
    '013F': 'Z005',
    '014C': '839支',
    '0150': 'G1',
    '015E': '86',
  }.entries) {
    test('Taiyuan source rule ${example.key} resolves ${example.value}', () {
      final location = resolveTunionBusLocation(
        stations: stations,
        cityCode: '1610',
        field: '${example.key}000000D500',
      );
      expect(location.lineLabel, example.value);
      expect(location.stationLabel, isNull);
    });
  }

  test(
    'unknown Taiyuan line retains its raw code rather than guessing a route',
    () {
      final bytes = _bytes(_reportedHex)..setRange(10, 12, [0xFE, 0xFE]);
      final trip = _analyze(knowledge, bytes: bytes).trips.single;
      expect(trip.lineLabel, 'FEFE');
      expect(trip.matchedProcessTrip!.lineCode, 'FEFE');
      expect(trip.stationConfidence, isNot(StationMatchConfidence.exact));
    },
  );

  test('Taiyuan route rules never leak into another city or rail records', () {
    for (final city in [null, '', '0000', 'FFFF', '3910', '1000']) {
      final location = resolveTunionBusLocation(
        stations: stations,
        cityCode: city,
        field: '0016000000D500',
      );
      expect(location.lineLabel, isNot('864'), reason: 'city=$city');
    }
    final railBytes = _bytes(_reportedHex)..[9] = 0x01;
    expect(
      _analyze(knowledge, bytes: railBytes).trips.single.lineLabel,
      isNot('864'),
    );
  });

  test('incomplete or malformed fields cannot activate the route rules', () {
    for (final field in [
      null,
      '',
      '0016',
      '0016000000D5',
      '0016000000D50000',
      '0016000000ZZ00',
      '0000000000D500',
      'FFFF000000D500',
    ]) {
      expect(
        resolveTunionBusLocation(
          stations: stations,
          cityCode: '1610',
          field: field,
        ).lineLabel,
        isNull,
        reason: 'field=$field',
      );
    }
  });

  test('1A bus location uses the same source rules with no invented stop', () {
    final location = resolveTunionBusLocation(
      stations: stations,
      cityCode: '1610',
      field: busRecordLocationField('0016', '00', '00D5'),
    );
    expect(location.lineLabel, '864');
    expect(location.stationLabel, isNull);
  });
}

final _display = TripPresentationContext(
  currency: Currency.cny,
  cityNameOf: (_) => null,
  resolveStationMatch: (_, _, {lineValue}) => StationMatch.unmatched,
  resolveCycleStationMatch: (_, _, {terminalId, time, appType}) =>
      StationMatch.unmatched,
  resolveLineName: (_, _) => null,
  resolveBusLocation:
      (city, field, {context = const TunionBusDecodeContext()}) =>
          resolveTunionBusLocation(
            stations: StationCodeTable.empty,
            cityCode: city,
            field: field,
            context: context,
          ),
);

List<int> _bytes(String hex) {
  final compact = hex.replaceAll(RegExp(r'\s+'), '');
  return [
    for (var i = 0; i < compact.length; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ];
}

CardAnalysisResult _analyze(
  KnowledgeBase knowledge, {
  List<int>? bytes,
  String terminal = '413180000756',
}) {
  final raw = bytes ?? _bytes(_reportedHex);
  final record = const TUnionProcessParser().parseCycleTrip(raw)!;
  // Only 0x1E was supplied. This 0x18 transaction is an explicit pairing
  // fixture, not a claim about the user's card or its issuing city.
  return AnalysisEngine(knowledge).analyze(
    ParsedCard(
      parserName: 'Taiyuan regression',
      selectedAidHex: 'A000000632010105',
      info: const TUnionCardInfo(cityCode: '3910'),
      transactions: [
        TUnionTransaction(
          sequence: 1,
          overdraftLimitFen: 0,
          amountFen: 100,
          rawType: 9,
          terminalId: terminal,
          time: DateTime(2026, 9, 24, 18, 29, 29),
        ),
      ],
      transitProcessRecords: [
        TUnionProcessRecord(
          sfi: 0x1E,
          recordNumber: 1,
          recordName: '循环记录 1',
          raw: raw,
          trip: record,
        ),
      ],
    ),
    now: DateTime(2026, 10, 21),
  );
}
