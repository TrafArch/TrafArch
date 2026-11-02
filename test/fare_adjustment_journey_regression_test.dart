import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Captured transaction and cycle windows from
// transit_card_log_20261030_181503.txt; SW bytes are omitted. Public identity,
// holder information, and 1A files are deliberately excluded. The reader's
// identity below is synthetic; its 1500-fen wallet matches the observed balance.
// The EC07 variant is explicitly synthetic and changes only the type byte.
const _transactions = <String>[
  '2401000000000000000941310127213420261030161042',
  '2400000000000000000941310190807520261030155834',
  '23FF000000000000000941310198430220261030143450',
  '23FE000000000000000941310614777320261030132713',
  '23FD000000000000000941310623606720261030124711',
  '23FC000000000000000941310623403020261029203115',
  '23FB000000000000000941310614625820261029201547',
  '23FA000000000000000941310624810320261029200303',
  '23F9000000000000000941310614622320261029195052',
  '23F8000000000000000941310614622720261029180110',
];
const _cycles = <String>[
  '060000413101272134020020080500000000000000000005DC20261030161042337013493370FFFFFFFF000000000000', // 1E #1
  '040000413101908075010089001000000000000000000005DC20261030155834337003493370FFFFFFFF000000000000', // 1E #2
  '080000413101984302010004001400000000000000000005DC20261030143450331001663310FFFFFFFF000000000000', // 1E #3
  '040000413106147773010004001400000000000000000005DC20261030132713331001663310FFFFFFFF000000000000', // 1E #4
  '030000413106236067010003003500000000000000000005DC20261030124711331001663310FFFFFFFF000000000000', // 1E #5
  '040000413106234030010003003500000000000000000005DC20261029203115331001663310FFFFFFFF000000000000', // 1E #6
  '030000413106146258010001001300000000000000000005DC20261029201547331001663310FFFFFFFF000000000000', // 1E #7
  '040000413106248103010001001300000000000000000005DC20261029200303331001663310FFFFFFFF000000000000', // 1E #8
  '030000413106146223010001001500000000000000000005DC20261029195052331001663310FFFFFFFF000000000000', // 1E #9
  '040000413106146227010001001500000000000000000005DC20261029180110331001663310FFFFFFFF000000000000', // 1E #10
  '030000413106248129010003005800000000000000000005DC20261029172444331001663310FFFFFFFF000000000000', // 1E #11
  '040000413106248475010003005700000000000000000005DC20261029155913331001663310FFFFFFFF000000000000', // 1E #12
  '030000413106236067010003003500000000000000000005DC20261029150922331001663310FFFFFFFF000000000000', // 1E #13
  '040000413106236072010003003500000000000000000005DC20261029085108331001663310FFFFFFFF000000000000', // 1E #14
  '030000413106236067010003003500000000000000000005DC20261029070111331001663310FFFFFFFF000000000000', // 1E #15
  '040000413106236063010003003500000000000000000005DC20261028210720331001663310FFFFFFFF000000000000', // 1E #16
  '030000413106236094010003003400000000000000000005DC20261028210122331001663310FFFFFFFF000000000000', // 1E #17
  '040000413106236093010003003400000000000000000005DC20261028190416331001663310FFFFFFFF000000000000', // 1E #18
  '030000413101926089010019000200000000000000000005DC20261028181733331001663310FFFFFFFF000000000000', // 1E #19
  '040000413106248000010003001400000000000000000005DC20261028064653331001663310FFFFFFFF000000000000', // 1E #20
  '030000413106236067010003003500000000000000000005DC20261028054256331001663310FFFFFFFF000000000000', // 1E #21
  '040000413106236063010003003500000000000000000005DC20261027211448331001663310FFFFFFFF000000000000', // 1E #22
  '030000413101786066010009005400000000000000000005DC20261027202044331001663310FFFFFFFF000000000000', // 1E #23
  '040000413101785467010009005400000000000000000005DC20261027202028331001663310FFFFFFFF000000000000', // 1E #24
  '030000413106149016010001001800000000000000000005DC20261027192145331001663310FFFFFFFF000000000000', // 1E #25
  '040000413106148824010001001800000000000000000005DC20261027181855331001663310FFFFFFFF000000000000', // 1E #26
  '030000413106236067010003003500000000000000000005DC20261027174604331001663310FFFFFFFF000000000000', // 1E #27
  '040000413106236068010003003500000000000000000005DC20261026205240331001663310FFFFFFFF000000000000', // 1E #28
  '030000413106146688010001001000000000000000000005DC20261026202018331001663310FFFFFFFF000000000000', // 1E #29
  '040000413106147806010004001400000000000000000005DC20261026180130331001663310FFFFFFFF000000000000', // 1E #30
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'trafarch-fare-adjustment-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    expect(reference.knowledge!.loadIssues, isEmpty);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('实测10笔交易及30条1E将杭州补票与绍兴出站组成行程且保留补票身份', () async {
    final view = await _view(reference);
    expect(view.parsedCard!.transactions, hasLength(10));
    expect(view.cycleProcessTrips, hasLength(30));
    expect(view.parsedCard!.transactions.map((t) => t.sequence), [
      9217,
      9216,
      9215,
      9214,
      9213,
      9212,
      9211,
      9210,
      9209,
      9208,
    ]);
    final events = _liveEvents(view, reference);
    final adjustment = events.singleWhere((event) => event.sequence == 9215);
    final exit = events.singleWhere((event) => event.sequence == 9216);
    expect(adjustment.role, JourneyEventRole.fareAdjustment);
    expect(exit.role, JourneyEventRole.exit);
    expect(adjustment.processPositions, {'live': 3});
    expect(exit.processPositions, {'live': 2});
    expect(adjustment.cityCode, '3310');
    expect(exit.cityCode, '3370');
    expect(adjustment.confirmedBalanceFen, 1500);
    expect(exit.confirmedBalanceFen, 1500);
    final journeys = projectJourneys(events);
    _expectReportedJourney(_target(journeys));
    // The preceding ordinary trip must continue pairing independently.
    final ordinary = journeys.singleWhere(
      (journey) => journey.events.any((event) => event.sequence == 9213),
    );
    expect(ordinary.state, JourneyState.completed);
    expect(ordinary.events.map((event) => event.sequence).toSet(), {
      9213,
      9214,
    });
    expect(ordinary.startsWithFareAdjustment, isFalse);
    expect(ordinary.duration, const Duration(minutes: 40, seconds: 2));
    expect(
      view.parsedCard!.transactions.map((t) => _clean(t.rawHex)),
      _transactions,
    );
    expect(view.cycleProcessTrips.map((t) => _clean(t.rawHex)), _cycles);
  });

  test('实测补票行程经正式stage和JSON恢复后仍匹配且不改写原始证据', () async {
    final view = await _view(reference);
    final saved = await _archiveProjection(view);
    expect(saved.projection.transactionCount, 10);
    _expectReportedJourney(
      _target(
        projectJourneys([
          for (final entry in saved.projection.entries) entry.journeyEvent!,
        ]),
      ),
      // The existing archive formatter omits the debit sign for zero amounts.
      zeroAmountText: '¥0.00',
    );
    final restored = CardSessionSnapshot.decode(saved.encoded)!;
    expect(restored.encode(), saved.encoded);
    expect(restored.trips.map((trip) => _clean(trip.rawHex)), _transactions);
    expect(restored.processTrips.map((trip) => _clean(trip.rawHex)), _cycles);
    expect(
      restored.trips
          .singleWhere((trip) => trip.sequence == 9215)
          .rideStatusName,
      '补票',
    );
    expect(restored.processTrips[2].typeCode, 8);
    expect(restored.processTrips[2].isEntry, isFalse);
    final before = jsonEncode([
      for (final record in saved.records) record.fields,
    ]);
    presentArchiveTrips(saved.records, onDiagnostics: (_) {});
    expect(
      jsonEncode([for (final record in saved.records) record.fields]),
      before,
    );
  });

  testWidgets('历史卡片明确显示补票并保留两笔详情且不虚构完整乘车时长', (tester) async {
    final view = await _view(reference);
    final saved = await _archiveProjection(view);
    final entries = saved.projection.entries
        .where(
          (entry) => const {9215, 9216}.contains(entry.journeyEvent?.sequence),
        )
        .toList();
    expect(entries, hasLength(2));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCardsView(
              entries: entries,
              sourceLabels: archiveTripSourceLabels,
              summaryText: saved.projection.summaryText,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('轨道交通'), findsOneWidget);
    expect(find.text('杭州轨道交通'), findsNothing);
    expect(find.text('绍兴轨道交通'), findsNothing);
    expect(find.text('景芳'), findsOneWidget);
    expect(find.text('中国轻纺城'), findsOneWidget);
    expect(find.textContaining('补票'), findsWidgets);
    expect(find.textContaining('1小时23分钟'), findsNothing);
    expect(find.textContaining('83分钟'), findsNothing);
    expect(find.textContaining('行程后余额'), findsOneWidget);
    expect(find.byKey(const ValueKey('journey-arrow')), findsOneWidget);
    await tester.tap(find.byTooltip('查看行程记录'));
    await tester.pumpAndSettle();
    expect(find.textContaining('9215'), findsOneWidget);
    expect(find.textContaining('9216'), findsOneWidget);
    expect(find.textContaining('补票'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('SIMULATED EC07补票类型走同一实时配对路径而不被改为普通进站', () async {
    final view = await _view(reference, ecAdjustment: true);
    final events = _liveEvents(view, reference);
    expect(view.cycleProcessTrips[2].typeCode, 7);
    expect(
      events.singleWhere((event) => event.sequence == 9215).role,
      JourneyEventRole.fareAdjustment,
    );
    _expectReportedJourney(_target(projectJourneys(events)));
  });
}

void _expectReportedJourney<T>(
  JourneyPresentation<T> journey, {
  String zeroAmountText = '-¥0.00',
}) {
  expect(journey.state, JourneyState.completed);
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.startsWithFareAdjustment, isTrue);
  expect(journey.isCrossCity, isTrue);
  expect(journey.cityLabel, isNull);
  expect(journey.start?.line, '4号线');
  expect(journey.start?.station, '景芳');
  expect(journey.start?.time?.hour, 14);
  expect(journey.start?.time?.minute, 34);
  expect(journey.start?.time?.second, 50);
  expect(journey.end?.line, '1号线');
  expect(journey.end?.station, '中国轻纺城');
  expect(journey.end?.time?.hour, 15);
  expect(journey.end?.time?.minute, 58);
  expect(journey.end?.time?.second, 34);
  expect(journey.duration, isNull);
  expect(journey.events.map((event) => event.sequence).toSet(), {9215, 9216});
  expect(journey.events.map((event) => event.role).toSet(), {
    JourneyEventRole.fareAdjustment,
    JourneyEventRole.exit,
  });
  expect(_clean(journey.amountText), zeroAmountText);
  expect(_clean(journey.fareAdjustmentAmountText), zeroAmountText);
  expect(_clean(journey.balanceAfterText), '¥15.00');
}

JourneyPresentation<TripEntryInfo> _target(
  List<JourneyPresentation<TripEntryInfo>> journeys,
) => journeys.singleWhere(
  (journey) => journey.events.any((event) => event.sequence == 9215),
);

Future<ScanPresentation> _view(
  ReferenceDataController reference, {
  bool ecAdjustment = false,
}) async {
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, [0, 0, 0x33, 0x70, 0, 0, 0, 0])
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, [
      0x31,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      1,
    ])
    ..setRange(20, 28, [0x20, 0x26, 1, 1, 0x20, 0x99, 0x12, 0x31]);
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x33, 0x70]);
  final cycles = [..._cycles];
  if (ecAdjustment) cycles[2] = '07${cycles[2].substring(2)}';
  final responses = <String, List<int>>{
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [0, 0, 0x05, 0xDC, 0x90, 0],
    '00B201C500': [..._hex(_transactions.join()), 0x90, 0],
    for (final (index, raw) in _transactions.indexed)
      '00B2${_byte(index + 1)}C400': [..._hex(raw), 0x90, 0],
    for (final (index, raw) in cycles.indexed)
      '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
  };
  // Missing source files/APDUs return a fixture boundary, not an observed SW.
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async =>
          responses[command.map(_byte).join()] ?? const [0x6A, 0x83],
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  final card = await unit.read(info, records);
  expect(card, isNotNull);
  expect(card!.info.balanceFen, 1500);
  return ScanPresentation(TransitReadOutcome(card), reference.knowledge!);
}

List<JourneyEvent<TripEntryInfo>> _liveEvents(
  ScanPresentation view,
  ReferenceDataController reference,
) {
  final rails = [for (final r in view.transitProcessRecords) ?r.railTransit];
  final buses = [for (final r in view.transitProcessRecords) ?r.busTransit];
  final stream = buildTripStream(
    trips: view.analysis!.trips,
    rails: rails,
    buses: buses,
    processTrips: view.cycleProcessTrips,
  );
  final evidence = buildLiveJourneyEvidence(
    stream: stream,
    processRecords: view.transitProcessRecords,
    rails: rails,
    buses: buses,
  );
  final display = TripPresentationContext(
    currency: view.cardCurrency,
    cityNameOf: reference.cityNameOf,
    resolveStationMatch: reference.resolveStationMatch,
    resolveCycleStationMatch: reference.resolveCycleStationMatch,
    resolveLineName: reference.resolveLineName,
    resolveBusLocation: reference.resolveBusLocation,
  );
  return [
    for (final entry in stream)
      describeJourneyEvent(
        entry,
        display,
        describeTripEntry(entry, display, remote: false),
        applicationRecordId: evidence[entry]?.applicationRecordId,
        processPositions: evidence[entry]?.processPositions ?? const {},
      ),
  ];
}

Future<
  ({
    ArchiveTripProjection projection,
    String encoded,
    List<ArchiveHistoryRecord> records,
  })
>
_archiveProjection(ScanPresentation view) async {
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final controller = ArchiveController(
    CardRepository(database),
    const MethodChannelLogExporter(),
    (_) {},
  );
  try {
    controller.stage(
      view,
      'fare-adjustment-capture',
      DateTime(2026, 10, 30, 18, 15, 3),
      const [],
    );
    expect(controller.pending, isNotNull);
    final encoded = controller.pending!.sessionDataJson!;
    final restored = CardSessionSnapshot.decode(encoded)!;
    expect(restored.encode(), encoded);
    final json = jsonDecode(restored.encode()) as Map<String, dynamic>;
    final provenance = json['recordProvenance'] as Map;
    final records = <ArchiveHistoryRecord>[
      for (final section in const {
        'trips': ArchiveRecordKind.transaction,
        'rails': ArchiveRecordKind.rail,
        'buses': ArchiveRecordKind.bus,
        'cycle': ArchiveRecordKind.process,
      }.entries)
        for (final (index, fields) in (json[section.key] as List).indexed)
          ArchiveHistoryRecord(
            kind: section.value,
            fields: fields as Map<String, dynamic>,
            context: restored.context,
            cardCityCode: restored.cardCityCode,
            sources: [
              ArchiveRecordSource(
                'fare-adjustment-capture',
                '${section.key}[$index]',
                restored.parseVersion,
                provenance['${section.key}[$index]'],
              ),
            ],
          ),
    ];
    return (
      projection: presentArchiveTrips(records, onDiagnostics: (_) {}),
      encoded: encoded,
      records: records,
    );
  } finally {
    controller.dispose();
    await database.close();
  }
}

String? _clean(String? value) => value?.replaceAll(RegExp(r'\s+'), '');
String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
