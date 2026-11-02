import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Exact transaction/process bodies from transit_card_log_20261031_213004.txt.
// Card serial, FCI and holder information are deliberately synthetic/omitted.
const _transactions = [
  '0003000000000000780941310180873820260820165722',
  '0002000000000000780941310605440520260820143845',
  '0001000000000000780941310005705720260819174244',
  '0001000000000003E80240000000000120260814173553',
];
const _cycles = [
  '064131018087389000020003011037120000000078000002F820260820165722305001423050FFFFFFFF000000000000',
  '0641310605440590000200020410320600000000780000037020260820143845305001423050FFFFFFFF000000000000',
  '064131000570579000020000081030210000000078000003E820260819174244305001423050FFFFFFFF000000000000',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late ScanPresentation view;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-suzhou-bus-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    expect(reference.knowledge!.loadIssues, isEmpty);
    view = await _read(reference);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('苏州日志4笔交易和3条公交过程记录经真实读卡器保留原始字段', () {
    final card = view.parsedCard!;
    expect(card.info.balanceFen, 640);
    expect(card.info.applicationSerial, '03104830000000000001');
    expect(card.transactions.map((t) => t.rawHex), _transactions);
    expect(card.transactions.map((t) => t.sequence), [3, 2, 1, 1]);
    final cycles = view.cycleProcessTrips;
    expect(cycles, hasLength(3));
    expect(cycles.map((p) => p.rawHex), _cycles);
    expect(cycles.map((p) => p.typeCode), [6, 6, 6]);
    expect(cycles.map((p) => p.appTypeCode), [2, 2, 2]);
    expect(cycles.map((p) => p.cityCode), ['3050', '3050', '3050']);
    expect(cycles.map((p) => p.lineStationCode), [
      '00030110371200',
      '00020410320600',
      '00000810302100',
    ]);
    expect(cycles.map((p) => p.balanceFen), [760, 880, 1000]);
    expect(view.railTransitRecord, isNull);
    expect(view.busTransitRecord, isNull);
    final applications = card.transitProcessRecords.where((p) => p.sfi == 0x1A);
    expect(applications.map((p) => p.recordNumber), [
      for (var i = 1; i <= 18; i++) i,
    ]);
    expect(applications.map((p) => _compact(p.rawHex)), [
      for (var i = 1; i <= 18; i++) _blankApplication(i).map(_byte).join(),
    ]);
    expect(
      applications.every((p) => p.railTransit == null && p.busTransit == null),
      isTrue,
    );
  });

  test('苏州公交过程关联0x18后仍保留301、204、8路分类与交易后余额', () {
    final trips = view.analysis!.trips;
    expect(trips, hasLength(4));
    expect(trips.take(3).map((trip) => trip.appTypeName), [
      '公共汽电车',
      '公共汽电车',
      '公共汽电车',
    ]);
    expect(trips.take(3).map((trip) => trip.resolvedBusLineLabel), [
      '301',
      '204',
      '8',
    ]);
    expect(trips.take(3).map((trip) => trip.balanceAfterFen), [640, 760, 880]);
    expect(
      trips.take(3).every((trip) => trip.displayProcessKey != null),
      isTrue,
    );
    expect(
      trips.take(3).every((trip) => trip.matchedProcessTrip != null),
      isTrue,
    );
    expect(trips.last.typeName, '充值');
    expect(trips.last.appTypeName, isNull);

    _expectBusJourneys(_journeys(view, reference));
  });

  test('苏州公交经数据库保存与档案JSON编解码后的历史投影保留分类、线路及原文', () async {
    final saved = await _saveAndRestore(view);
    final snapshot = CardSessionSnapshot.decode(saved.encoded)!;
    expect(snapshot.encode(), saved.encoded);
    expect(snapshot.trips.map((trip) => trip.rawHex), _transactions);
    expect(snapshot.processTrips.map((trip) => trip.rawHex), _cycles);
    expect(snapshot.trips.take(3).map((trip) => trip.resolvedBusLineLabel), [
      '301',
      '204',
      '8',
    ]);
    expect(snapshot.trips.take(3).map((trip) => trip.appTypeName), [
      '公共汽电车',
      '公共汽电车',
      '公共汽电车',
    ]);
    expect(snapshot.trips.take(3).map((trip) => trip.balanceAfterFen), [
      640,
      760,
      880,
    ]);
    final rawApplications = snapshot.rawEvidence.where(
      (record) =>
          record['kind'] == 'tu_process_record' && record['sfi'] == 0x1A,
    );
    expect(
      rawApplications.map((record) => _compact(record['rawHex'] as String?)),
      [for (var i = 1; i <= 18; i++) _blankApplication(i).map(_byte).join()],
    );
    for (final history in [saved.history, saved.restoredHistory]) {
      final originalFields = jsonEncode([
        for (final record in history.records) record.fields,
      ]);
      final projection = presentArchiveTrips(
        history.records,
        batches: history.batches,
        onDiagnostics: (_) {},
      );
      expect(projection.transactionCount, 4);
      expect(projection.entries, hasLength(4));
      _expectBusJourneys(projection.journeys);
      expect(history.batches.single.decoded.rawJson, saved.encoded);
      expect(
        jsonEncode([for (final record in history.records) record.fields]),
        originalFields,
      );
    }
  });

  testWidgets('苏州日志经完整扫描入口在行程页显示3条公交和1条其他记录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = _memoryDatabase();
    addTearDown(database.close);
    final channel = _LogNfcChannel(_responses());
    final app = AppDependencies(
      channel: channel,
      bundle: rootBundle,
      settingsStore: MemorySettingsStore(),
      database: database,
    );
    addTearDown(app.dispose);
    await tester.runAsync(() async {
      await app.init();
      await app.scanOnce();
    });
    expect(app.scan.error, isNull);
    expect(app.scan.outcome, isA<TransitReadOutcome>());
    expect(app.parsedCard!.info.balanceFen, 640);
    expect(
      app.analysis!.trips.take(3).map((trip) => trip.resolvedBusLineLabel),
      ['301', '204', '8'],
    );
    expect(app.cycleProcessTrips.map((trip) => trip.rawHex), _cycles);
    expect(app.railTransitRecord, isNull);
    expect(app.busTransitRecord, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TripsPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    _expectBusCards();
    expect(find.text('记录 4 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('苏州恢复历史投影的行程卡片组件显示3条公交和1条其他记录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = (await tester.runAsync(() => _saveAndRestore(view)))!;
    final projection = presentArchiveTrips(
      saved.restoredHistory.records,
      batches: saved.restoredHistory.batches,
      onDiagnostics: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCardsView(
              entries: projection.entries,
              projectedJourneys: projection.journeys,
              sourceLabels: archiveTripSourceLabels,
              summaryText: projection.summaryText,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectBusCards();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('缺少过程信息时不能因苏州发卡地或1.20元金额猜测公交线路', () async {
    final basicOnly = await _read(reference, cycleBodies: const []);
    expect(basicOnly.cycleProcessTrips, isEmpty);
    final trips = basicOnly.analysis!.trips;
    expect(trips.every((trip) => trip.appTypeName == null), isTrue);
    expect(trips.every((trip) => trip.resolvedBusLineLabel == null), isTrue);
    expect(
      _journeys(
        basicOnly,
        reference,
      ).every((journey) => journey.mode == TripModeFilter.other),
      isTrue,
    );
  });
}

void _expectBusJourneys<T>(Iterable<JourneyPresentation<T>> journeys) {
  final bus = journeys.where((journey) => journey.mode == TripModeFilter.bus);
  expect(bus, hasLength(3));
  expect(bus.map((journey) => journey.state), [
    JourneyState.single,
    JourneyState.single,
    JourneyState.single,
  ]);
  expect(bus.map((journey) => journey.events.single.endpoint.line), [
    '301路',
    '204路',
    '8路',
  ]);
  expect(bus.map((journey) => _compact(journey.balanceAfterText)), [
    '¥6.40',
    '¥7.60',
    '¥8.80',
  ]);
  expect(
    journeys.where((journey) => journey.mode == TripModeFilter.other),
    hasLength(1),
  );
}

void _expectBusCards() {
  expect(find.text('历史行程 3'), findsOneWidget);
  expect(find.text('其他记录 1'), findsOneWidget);
  expect(find.byType(TripEntryCard), findsNWidgets(4));
  for (final line in ['301路', '204路', '8路']) {
    expect(find.text(line), findsOneWidget);
  }
  final bus = find
      .byType(TripEntryCard)
      .evaluate()
      .map((element) => element.widget as TripEntryCard)
      .where((card) => card.journey?.mode == TripModeFilter.bus);
  expect(bus, hasLength(3));
  expect(bus.map((card) => _compact(card.journey!.balanceAfterText)), [
    '¥6.40',
    '¥7.60',
    '¥8.80',
  ]);
}

List<JourneyPresentation<TripEntryInfo>> _journeys(
  ScanPresentation view,
  ReferenceDataController reference,
) {
  final stream = buildTripStream(
    trips: view.analysis!.trips,
    processTrips: view.cycleProcessTrips,
  );
  // All three process observations are represented by their linked 0x18.
  expect(stream, hasLength(4));
  final evidence = buildLiveJourneyEvidence(
    stream: stream,
    processRecords: view.transitProcessRecords,
    rails: const [],
    buses: const [],
  );
  final display = TripPresentationContext(
    currency: view.cardCurrency,
    cityNameOf: reference.cityNameOf,
    resolveStationMatch: reference.resolveStationMatch,
    resolveCycleStationMatch: reference.resolveCycleStationMatch,
    resolveLineName: reference.resolveLineName,
    resolveBusLocation: reference.resolveBusLocation,
  );
  return projectJourneys([
    for (final entry in stream)
      describeJourneyEvent(
        entry,
        display,
        describeTripEntry(entry, display, remote: false),
        applicationRecordId: evidence[entry]?.applicationRecordId,
        processPositions: evidence[entry]?.processPositions ?? const {},
      ),
  ]);
}

Future<ScanPresentation> _read(
  ReferenceDataController reference, {
  List<String> cycleBodies = _cycles,
}) async {
  final responses = _responses(cycleBodies: cycleBodies);
  final unit = CommonUnitTu(
    ApduExchange(transceive: (command) async => _response(responses, command)),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  final card = await unit.read(info, records);
  expect(card, isNotNull);
  return ScanPresentation(TransitReadOutcome(card!), reference.knowledge!);
}

Map<String, List<int>> _responses({List<String> cycleBodies = _cycles}) {
  // Synthetic serial retains only the public Suzhou IIN, never the user's card.
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, [1, 0x42, 0x30, 0x50, 0xFF, 0xFF, 0xFF, 0xFF])
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, _hex('03104830000000000001'))
    ..setRange(20, 28, _hex('2026010120991231'));
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x30, 0x50]);
  return <String, List<int>>{
    '00A40000023F0000': [0x6A, 0x82],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0960000': [...List<int>.filled(56, 0), 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [0, 0, 2, 0x80, 0x90, 0],
    '00B201C500': [0x6A, 0x86],
    for (final (index, raw) in _transactions.indexed)
      '00B2${_byte(index + 1)}C400': [..._hex(raw), 0x90, 0],
    for (var number = 5; number <= 10; number++)
      '00B2${_byte(number)}C400': [...List<int>.filled(23, 0), 0x90, 0],
    for (var number = 1; number <= 18; number++)
      '00B2${_byte(number)}D400': [..._blankApplication(number), 0x90, 0],
    '00B201F500': [0x6A, 0x86],
    for (final (index, raw) in cycleBodies.indexed)
      '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
    for (var number = cycleBodies.length + 1; number <= 30; number++)
      '00B2${_byte(number)}F400': [...List<int>.filled(48, 0), 0x90, 0],
    '00B21FF400': [0x6A, 0x83],
  };
}

// The log's 18 initialized 1A records have a public record header and an empty
// body. Slot 7 is 112 bytes, slot 13 is 30 bytes, and all others are 128 bytes.
List<int> _blankApplication(int number) {
  final length = switch (number) {
    7 => 112,
    13 => 30,
    _ => 128,
  };
  return [0x27, number, length - 3, 1, 1, ...List<int>.filled(length - 5, 0)];
}

List<int> _response(Map<String, List<int>> responses, List<int> command) =>
    responses[command.map(_byte).join()] ??
    (command.length > 1 && command[1] == 0xA4
        ? const [0x6A, 0x82]
        : const [0x6A, 0x83]);

class _LogNfcChannel implements NfcChannel {
  _LogNfcChannel(this.responses);
  final Map<String, List<int>> responses;

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: '01020304',
    technologies: const ['IsoDep'],
    isoDepConnected: true,
    timestamp: DateTime(2026, 10, 31, 21, 29, 58),
  );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> apdu) async =>
      _response(responses, apdu);
}

AppDatabase _memoryDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

Future<
  ({
    String encoded,
    ArchiveHistoryResult history,
    ArchiveHistoryResult restoredHistory,
  })
>
_saveAndRestore(ScanPresentation view) async {
  final database = _memoryDatabase();
  final repository = CardRepository(database);
  final controller = ArchiveController(
    repository,
    const MethodChannelLogExporter(),
    (_) {},
  );
  const attempt = 'synthetic-suzhou-capture';
  try {
    controller.stage(
      view,
      attempt,
      DateTime(2026, 10, 31, 21, 29, 58),
      const [],
    );
    expect(controller.pending, isNotNull);
    final staged = CardSessionSnapshot.decode(
      controller.pending!.sessionDataJson!,
    )!;
    expect(staged.trips.take(3).map((trip) => trip.balanceAfterFen), [
      640,
      760,
      880,
    ]);
    expect(await controller.accept(attempt), isTrue);
    final card = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(card.id);
    final encoded = history.batches.single.decoded.rawJson;
    final rows = await repository.getArchiveRows(card.id);
    final restored = CardArchiveDocument.decode(
      CardArchiveDocument(
        card: rows.card!,
        batches: rows.batches,
        fieldObservationTimes: const {},
      ).encode(),
    );
    expect(restored.batches.single.payloadJson, encoded);
    final restoredHistory = ArchiveHistory.project(
      ArchiveRows(card: restored.card, batches: restored.batches),
    );
    return (
      encoded: encoded,
      history: history,
      restoredHistory: restoredHistory,
    );
  } finally {
    controller.dispose();
    await database.close();
  }
}

String? _compact(String? value) => value?.replaceAll(RegExp(r'\s+'), '');
String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
