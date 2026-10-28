import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/features/trips/trip_stream_view.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Exact transaction/process payloads from the final Beijing read in the
// 2026-10-27 12:50:19 report. Card identity files are deliberately omitted;
// the reader receives a synthetic public file instead. Rail station names
// come from the shipped TU database; bus ordinals use the existing city decoder.
void main() {
  late sqlite.Database referenceDatabase;
  late StationCodeTable stations;
  late KnowledgeBase knowledge;

  setUp(() {
    referenceDatabase = sqlite.sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: sqlite.OpenMode.readOnly,
    );
    stations = StationCodeTable.empty.withLiveSources([
      TuRegionLiveSource(TuStationRepository(referenceDatabase)),
    ]);
    knowledge = KnowledgeBase.fromJsonStrings(stationCodes: stations);
  });
  tearDown(() => referenceDatabase.close());

  testWidgets('北京十笔交易窗口边界的独立1E进站与交易出站合成完整行程', (tester) async {
    final replay = await _pumpReplay(tester, stations, knowledge);
    final related = replay.journeys
        .where(
          (journey) => journey.events.any(
            (event) =>
                event.endpoint.time == DateTime(2026, 10, 18, 10, 27, 39) ||
                event.endpoint.time == DateTime(2026, 10, 18, 10, 36, 56),
          ),
        )
        .toList();

    expect(related, hasLength(1));
    final journey = related.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.start?.line, '15号线');
    expect(journey.start?.station, '北沙滩');
    expect(journey.end?.line, '8号线');
    expect(journey.end?.station, '奥林匹克公园');
    expect(journey.duration, const Duration(minutes: 9, seconds: 17));
    expect(journey.amountText, '-¥3.00');
    expect(journey.balanceAfterText, '¥138.50');
    expect(journey.events, hasLength(2));
    expect(
      journey.events.map((event) => event.payload.sourceLabel),
      unorderedEquals(['0x1E 过程记录', '0x18 交易明细']),
    );
    expect(
      journey.events.map((event) => event.payload.rawHex),
      unorderedEquals([_cycles[9], _transactions[9]]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('北京345路重复1A和1E两侧仅显示一段且四份原始详情全部保留', (tester) async {
    final replay = await _pumpReplay(tester, stations, knowledge);
    final related = replay.journeys
        .where(
          (journey) => journey.events.any(
            (event) =>
                event.endpoint.time == DateTime(2026, 10, 18, 9, 19, 57) ||
                event.endpoint.time == DateTime(2026, 10, 18, 10, 23, 52),
          ),
        )
        .toList();

    expect(related, hasLength(1));
    final journey = related.single;
    expect(journey.state, JourneyState.completed);
    expect(journey.start?.line, '345路');
    expect(journey.start?.station, '站点19');
    expect(journey.end?.line, '345路');
    expect(journey.end?.station, '站点5');
    expect(journey.duration, const Duration(hours: 1, minutes: 3, seconds: 55));
    expect(journey.amountText, '-¥2.00');
    expect(journey.balanceAfterText, '¥141.50');
    expect(journey.events, hasLength(4));
    expect(
      journey.events.map((event) => event.payload.sourceLabel),
      unorderedEquals(['0x1A 公交记录', '0x1A 公交记录', '0x1E 过程记录', '0x1E 过程记录']),
    );
    expect(
      journey.events.map((event) => event.payload.rawHex),
      unorderedEquals([
        replay.card.transitProcessRecords
            .singleWhere((record) => record.busTransit != null)
            .busTransit!
            .rawHex,
        replay.card.transitProcessRecords
            .singleWhere((record) => record.busTransit != null)
            .busTransit!
            .rawHex,
        _cycles[10],
        _cycles[11],
      ]),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('北京十笔交易窗口之外完整公交和地铁行程按局部证据恢复后余额', (tester) async {
    final replay = await _pumpReplay(tester, stations, knowledge);
    // Hand-checked against the original 1E payloads. Rail records retain
    // pre-fare balances; bus records here already contain post-fare balances.
    for (final (time, expected) in [
      (DateTime(2026, 10, 18, 10, 23, 52), '¥141.50'),
      (DateTime(2026, 10, 18, 9, 0, 7), '¥143.50'),
      (DateTime(2026, 10, 7, 12, 4, 19), '¥144.50'),
      (DateTime(2026, 10, 7, 11, 45, 45), '¥145.50'),
      (DateTime(2026, 9, 24, 12, 26, 49), '¥151.50'),
      (DateTime(2026, 9, 24, 11, 27, 49), '¥152.50'),
      (DateTime(2026, 9, 24, 11, 17, 29), '¥153.50'),
      (DateTime(2026, 9, 20, 17, 22, 51), '¥159.50'),
      (DateTime(2026, 9, 20, 13, 19, 30), '¥165.50'),
    ]) {
      final journey = replay.journeys.singleWhere((j) => j.end?.time == time);
      expect(journey.state, JourneyState.completed);
      expect(journey.balanceAfterText, expected, reason: '$time');
    }
    // The original raw balances are evidence, never overwritten by projection.
    final raw = replay.card.transitProcessRecords
        .singleWhere((r) => r.sfi == 0x1E && r.recordNumber == 17)
        .trip!;
    expect(raw.balanceFen, 15050);
    expect(raw.amountFen, 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('太原单次公交在北京零金额进站前的相邻1E证明后余额15050', (tester) async {
    final replay = await _pumpReplay(tester, stations, knowledge);
    final journey = replay.journeys.singleWhere(
      (j) => j.events.any(
        (e) => e.endpoint.time == DateTime(2026, 9, 24, 18, 29, 29),
      ),
    );
    expect(journey.state, JourneyState.single);
    expect(journey.events.single.cityCode, '1610');
    expect(journey.amountText, '-¥1.00');
    expect(journey.balanceAfterText, '¥150.50');
    final original = replay.card.transitProcessRecords
        .singleWhere((r) => r.sfi == 0x1E && r.recordNumber == 19)
        .trip!;
    expect(original.balanceFen, 15050);
    expect(original.amountFen, 100);
    expect(tester.takeException(), isNull);
  });
}

Future<({ParsedCard card, List<JourneyPresentation<TripEntryInfo>> journeys})>
_pumpReplay(
  WidgetTester tester,
  StationCodeTable stations,
  KnowledgeBase knowledge,
) async {
  final card = await _readSample();
  final analysis = AnalysisEngine(knowledge).analyze(card);
  final database = AppDatabase(NativeDatabase.memory());
  final app = _ReplayApp(card, database);
  addTearDown(() async {
    app.dispose();
    await database.close();
  });
  final stream = buildTripStream(
    trips: analysis.trips,
    rails: [?app.railTransitRecord],
    buses: [?app.busTransitRecord],
    processTrips: app.cycleProcessTrips,
  );
  expect(card.transactions, hasLength(10));
  expect(app.cycleProcessTrips, hasLength(30));
  expect(card.transactions.last.sequence, 0x21);
  expect(
    app.transitProcessRecords
        .where((record) => record.sfi == 0x1E)
        .map((record) => record.recordNumber),
    List.generate(30, (index) => index + 1),
  );
  expect(analysis.trips.last.balanceAfterFen, 13850);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripStreamView(
            stream: stream,
            app: app,
            isRemote: (_) => false,
            presentationContext: _display(stations),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    card: card,
    journeys: [
      for (final widget in tester.widgetList<TripEntryCard>(
        find.byType(TripEntryCard),
      ))
        if (widget.journey != null) widget.journey!,
    ],
  );
}

// Supplies the real read result through the existing presentation facade while
// avoiding asynchronous application initialization in a widget fake clock.
// No analysis, decoder, stream, or journey implementation is replaced here.
class _ReplayApp extends AppDependencies {
  _ReplayApp(this.card, AppDatabase database) : super(database: database);
  final ParsedCard card;

  @override
  ParsedCard get parsedCard => card;
  @override
  List<TUnionProcessRecord> get transitProcessRecords =>
      card.transitProcessRecords;
  @override
  List<TUnionTripRecord> get cycleProcessTrips => [
    for (final record in card.transitProcessRecords)
      if (record.trip != null) record.trip!,
  ];
  @override
  TransitRecord? get railTransitRecord => card.transitProcessRecords
      .singleWhere((record) => record.railTransit != null)
      .railTransit;
  @override
  BusTransitRecord? get busTransitRecord => card.transitProcessRecords
      .singleWhere((record) => record.busTransit != null)
      .busTransit;
}

TripPresentationContext _display(StationCodeTable stations) =>
    TripPresentationContext(
      currency: Currency.cny,
      cityNameOf: (city) => city == '1000'
          ? '北京'
          : city == '1610'
          ? '太原'
          : null,
      resolveStationMatch: (city, code, {lineValue}) =>
          stations.matchTuStationByCardId(
            rawStationId: code ?? '',
            cityCode: city,
            lineValue: lineValue,
          ),
      resolveCycleStationMatch: (city, field, {terminalId, time, appType}) =>
          stations.matchLineStationField(field: field ?? '', cityCode: city),
      resolveLineName: (city, line) =>
          stations.lookupLineName(rawLineCode: line ?? '', cityCode: city),
      resolveBusLocation:
          (city, field, {context = const TunionBusDecodeContext()}) =>
              resolveTunionBusLocation(
                stations: stations,
                cityCode: city,
                field: field,
                context: context,
              ),
    );

Future<ParsedCard> _readSample() async {
  final public = List.filled(30, 0)
    ..setRange(10, 20, [0x03, 0x10, 0, 0, 0, 0, 0, 0, 0, 1]);
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async {
        if (command[1] == 0xA4) return [0x90, 0];
        if (command[1] == 0xB0 && command[2] == 0x95) {
          return [...public, 0x90, 0];
        }
        if (command[1] == 0x5C) return [0, 0, 0x2E, 0x4A, 0x90, 0];
        if (command[1] == 0xB2) {
          final rows = switch (command[3]) {
            0xC4 => _transactions,
            0xD4 => _applications,
            0xF4 => _cycles,
            _ => const <String>[],
          };
          final number = command[2];
          if (number > 0 && number <= rows.length) {
            return [..._hex(rows[number - 1]), 0x90, 0];
          }
        }
        return [0x6A, 0x83];
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  return (await unit.read(info, records))!;
}

List<int> _hex(String value) => [
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];

const _transactions = [
  '0029000000000002BC0930094900021020261026113749',
  '0028000000000000000930002900052720261026101942',
  '0027000000000013880930088900000420261023152220',
  '0026000000000000000930088900010820261023145616',
  '0025000000000002BC0930019900011820261023145535',
  '0024000000000000000930094900022720261023123730',
  '0003000000000013880211023080001720261021001833',
  '0023000000000002580930094900019620261018171630',
  '0022000000000000000930008900032320261018155418',
  '00210000000000012C0930008900034420261018103656',
];

const _applications = [
  '27017D0101000000000000154295021000100001011000FFFFFFFF01011000FFFFFFFF10007513090002101000751309009433100075131F021018100075131F943349202610261019422026102611374900000320025E0000000000003106000002BC0201000000000000000000000000000000000000000000000000000000',
  '27027D010100000000000000000002100011011000FFFFFFFF00010159133030303332313331000000100900156320261018091957000001F4AB100011011000FFFFFFFF00010159053030303332313331000000100900154820261018102352000000C806400000000000000000000000000000000000000000000000006D59',
];

const _cycles = [
  '040000300949000210015E0021004A0000000002BC0000310620261026113749100001011000FFFFFFFF000000000000',
  '0300003000290005270102000A002A0000000000000000310620261026101942100001011000FFFFFFFF000000000000',
  '0400003008890000040158001B00440000000013880000448E20261023152220100001011000FFFFFFFF000000000000',
  '0300003008890001080158001700440000000000000000448E20261023145616100001011000FFFFFFFF000000000000',
  '04000030019900011801130023003B0000000002BC0000474A20261023145535100001011000FFFFFFFF000000000000',
  '030000300949000227015E0021004A0000000000000000474A20261023123730100001011000FFFFFFFF000000000000',
  '040000300949000196015E0021004A0000000002580000361A20261018171630100001011000FFFFFFFF000000000000',
  '0300003000890003230108001900300000000000000000361A20261018155418100001011000FFFFFFFF000000000000',
  '04000030008900034401080019003000000000012C0000374620261018103656100001011000FFFFFFFF000000000000',
  '030000300159000072010F001D00370000000000000000374620261018102739100001011000FFFFFFFF000000000000',
  '0400000010090015480201590005000100000000C80000374620261018102352100011011000FFFFFFFF000000000000',
  '0300000010090015630201590013000100000000000000380E20261018091957100011011000FFFFFFFF000000000000',
  '040000000109007652025E06000F000100000000640000380E20261018090007100011011000FFFFFFFF000000000000',
  '030000001009008926025E060009000100000000000000387220261018084416100011011000FFFFFFFF000000000000',
  '0400000001090186630203B1002D000100000000640000387220261007120419100011011000FFFFFFFF000000000000',
  '0300000001090186520203B1002F00010000000000000038D620261007115938100011011000FFFFFFFF000000000000',
  '040000300949000212015E0021004A0000000001F400003ACA20261007114545100001011000FFFFFFFF000000000000',
  '030000300139000496010D001E003500000000000000003ACA20261007112200100001011000FFFFFFFF000000000000',
  '060000413180000756020016000000D5000000006400003ACA20260924182929161012971610FFFFFFFF000000000000',
  '04000000010900726802014C00130001000000006400003B2E20260924122649100011011000FFFFFFFF000000000000',
  '03000000010903977602014C00120001000000000000003B9220260924122306100011011000FFFFFFFF000000000000',
  '04000000010901358102001A00170001000000006400003B9220260924112749100011011000FFFFFFFF000000000000',
  '03000000010904839202001A00160001000000000000003BF620260924112616100011011000FFFFFFFF000000000000',
  '040000300139000036010D0015003500000000025800003E4E20260924111729100001011000FFFFFFFF000000000000',
  '030000300949000217015E0021004A00000000000000003E4E20260924102747100001011000FFFFFFFF000000000000',
  '040000300949000222015E0021004A000000000258000040A620260920172251100001011000FFFFFFFF000000000000',
  '030000300089000318010800190030000000000000000040A620260920164216100001011000FFFFFFFF000000000000',
  '040000300089000344010800190030000000000258000042FE20260920131930100001011000FFFFFFFF000000000000',
  '030000300949000227015E0021004A000000000000000042FE20260920123400100001011000FFFFFFFF000000000000',
  '040000300949000226015E0021004A0000000002580000455620260919171640100001011000FFFFFFFF000000000000',
];
