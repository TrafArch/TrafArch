import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Exact successful 0x18 bodies and the six nonblank 1E bodies in
// transit_card_log_20261103_202948.txt (Build 2103). Only SW bytes are omitted.
// Public identity is synthetic. The 1A file is an explicit synthetic fixture
// boundary, not a claim that the source log did not contain application data.
const _transactions = [
  '0016000000000000C80941310129590120261102115930',
  '0015000000000000000941318011082120261102114859',
  '0014000000000000C80941310129573020261102112618',
  '0013000000000000000941310129589020261102111649',
  '0012000000000000C80941310129589920261101143326',
  '0011000000000000000941310129613620261101142819',
  '0010000000000000C80941310129611720261101140905',
  '000F000000000000000941310129589020261101134534',
  '000E000000000000C80941310129590220261027154101',
  '000D000000000000000941310129613620261027142646',
];
const _cycles = [
  '044131062428261B340102FF29FF000000000001900000050020261005142115261011592610FFFFFFFF000000000000',
  '034131018435481A060103FF01FF000000000000000000050020261005132818261011592610FFFFFFFF000000000000',
  '04221041310603638201000200D70003000E0100000E0600002026093017561722101217221000000000000002BC0000',
  '150000413101760747010001009F000300000000000000060E2026093017193022101217221000000000000002BC0000',
  '160000413101760738010001009F000300000001C20000060E2026093012524222101217221000000000000002BC0000',
  '15000041310183693801000200F500030000000000000007D02026093011540922101217221000000000000002BC0000',
];
const _amounts = [400, 0, 270, 0, 450, 0];
const _recordBalances = [1280, 1280, 1550, 1550, 1550, 2000];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late ScanPresentation view;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'trafarch-shenyang-journey-',
    );
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

  test('沈阳新日志读取保留15/16原类型并按逐条证据解码EP与哈尔滨金额', () {
    expect(view.parsedCard!.info.balanceFen, 280);
    expect(
      view.parsedCard!.transactions.map((record) => record.rawHex),
      _transactions,
    );
    expect(view.analysis!.trips.map((trip) => trip.sequence), [
      22,
      21,
      20,
      19,
      18,
      17,
      16,
      15,
      14,
      13,
    ]);
    expect(view.cycleProcessTrips.map((record) => record.rawHex), _cycles);
    expect(view.cycleProcessTrips.map((record) => record.typeCode), [
      0x04,
      0x03,
      0x04,
      0x15,
      0x16,
      0x15,
    ]);
    expect(view.cycleProcessTrips.map((record) => record.amountFen), _amounts);
    expect(
      view.cycleProcessTrips.map((record) => record.balanceFen),
      _recordBalances,
    );
    expect(view.cycleProcessTrips.map((record) => record.cityCode), [
      '2610',
      '2610',
      '2210',
      '2210',
      '2210',
      '2210',
    ]);
  });

  test('沈阳15进站可配EP04出站及16出站且哈尔滨标准EP保持独立', () {
    _expectReportedJourneys(_liveJourneys(view, reference));
    expect(view.cycleProcessTrips.map((record) => record.rawHex), _cycles);
  });

  test('沈阳日志经stage保存与完整JSON恢复后仍合并且保留全部证据', () async {
    final saved = await _saveAndRestore(view);
    final snapshot = CardSessionSnapshot.decode(saved.encoded)!;
    expect(snapshot.encode(), saved.encoded);
    expect(snapshot.processTrips.map((record) => record.rawHex), _cycles);
    expect(snapshot.processTrips.map((record) => record.typeCode), [
      0x04,
      0x03,
      0x04,
      0x15,
      0x16,
      0x15,
    ]);
    expect(snapshot.processTrips.map((record) => record.amountFen), _amounts);
    expect(
      snapshot.processTrips.map((record) => record.balanceFen),
      _recordBalances,
    );
    expect(snapshot.trips.map((record) => record.rawHex), _transactions);
    for (final history in [saved.history, saved.restoredHistory]) {
      final before = jsonEncode([
        for (final record in history.records) record.fields,
      ]);
      final projection = presentArchiveTrips(
        history.records,
        batches: history.batches,
        onDiagnostics: (_) {},
      );
      expect(projection.transactionCount, 10);
      _expectReportedJourneys(projection.journeys);
      expect(
        jsonEncode([for (final record in history.records) record.fields]),
        before,
      );
      expect(history.batches.single.decoded.rawJson, saved.encoded);
    }
  });

  test('模拟Build2103旧快照仅在展示时修正沈阳巨额金额而不改写捕获', () async {
    // The user supplied an APDU log, not the old archive JSON. This fixture
    // explicitly simulates the old big-endian decoder's captured values in a
    // real staged envelope; it does not claim to be the user's actual backup.
    final saved = await _saveAndRestore(view);
    final fields = jsonDecode(saved.encoded) as Map<String, dynamic>;
    fields['parseVersion'] = 8;
    fields['syntheticEvidence'] = 'Build2103 Shenyang BE money reproduction';
    final cycles = fields['cycle'] as List;
    final oldExit = cycles[2] as Map<String, dynamic>;
    oldExit['amountFen'] = 234946560;
    oldExit['balanceFen'] = 235274240;
    final provenance = fields['recordProvenance'] as Map<String, dynamic>;
    for (final value in provenance.values) {
      if (value is Map<String, dynamic> && value.containsKey('parseVersion')) {
        value['parseVersion'] = 8;
      }
    }
    final payload = '  ${jsonEncode(fields)}\n';
    final captured = CardSessionSnapshot.decode(payload)!;
    expect(captured.encode(), payload);
    expect(captured.processTrips[2].amountFen, 234946560);
    expect(captured.processTrips[2].balanceFen, 235274240);
    const card = SavedCard(
      id: 'synthetic-build2103-card',
      cardFingerprint: 'synthetic-build2103-fingerprint',
      cardType: 'china_tunion',
      identificationSource: 'synthetic-test',
      createdAt: 1,
      updatedAt: 1,
    );
    final batch = CardReadBatch(
      id: 'synthetic-build2103-batch',
      cardId: card.id,
      cardFingerprint: card.cardFingerprint,
      readAt: DateTime(2026, 11, 3, 20, 29, 40).millisecondsSinceEpoch,
      parseVersion: 8,
      payloadJson: payload,
    );
    final document = CardArchiveDocument.decode(
      CardArchiveDocument(
        card: card,
        batches: [batch],
        fieldObservationTimes: const {},
      ).encode(),
    );
    expect(document.batches.single.payloadJson, payload);
    final history = ArchiveHistory.project(
      ArchiveRows(card: document.card, batches: document.batches),
    );
    final before = jsonEncode([
      for (final record in history.records) record.fields,
    ]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    _expectReportedJourneys(projection.journeys);
    final exit = projection.entries.singleWhere(
      (entry) => _compact(entry.info.rawHex) == _cycles[2],
    );
    expect(_compact(exit.info.amountText), '-¥2.70');
    expect(
      jsonEncode([for (final record in history.records) record.fields]),
      before,
    );
    expect(history.batches.single.decoded.rawJson, payload);
    expect(document.batches.single.payloadJson, payload);
    expect(captured.encode(), payload);
    expect(captured.processTrips[2].amountFen, 234946560);
  });
}

void _expectReportedJourneys<T>(Iterable<JourneyPresentation<T>> journeys) {
  JourneyPresentation<T> startingAt(DateTime time) => journeys.singleWhere(
    (journey) => _civil(journey.start?.time) == _civil(time),
  );
  final mixed = startingAt(DateTime(2026, 9, 30, 17, 19, 30));
  expect(mixed.state, JourneyState.completed);
  expect(mixed.mode, TripModeFilter.rail);
  expect(mixed.start?.station, '东中街');
  expect(mixed.end?.station, '沈阳北站');
  expect(_civil(mixed.end?.time), _civil(DateTime(2026, 9, 30, 17, 56, 17)));
  expect(mixed.duration, const Duration(minutes: 36, seconds: 47));
  expect(_compact(mixed.amountText), '-¥2.70');
  expect(mixed.events.map((event) => event.role).toSet(), {
    JourneyEventRole.entry,
    JourneyEventRole.exit,
  });
  expect(mixed.events.map((event) => event.cityCode).toSet(), {'2210'});
  final native = startingAt(DateTime(2026, 9, 30, 11, 54, 9));
  expect(native.state, JourneyState.completed);
  expect(native.mode, TripModeFilter.rail);
  expect(_civil(native.end?.time), _civil(DateTime(2026, 9, 30, 12, 52, 42)));
  expect(native.duration, const Duration(minutes: 58, seconds: 33));
  expect(_compact(native.amountText), '-¥4.50');
  expect(native.events.map((event) => event.role).toSet(), {
    JourneyEventRole.entry,
    JourneyEventRole.exit,
  });
  expect(native.events.map((event) => event.cityCode).toSet(), {'2210'});
  final harbin = startingAt(DateTime(2026, 10, 5, 13, 28, 18));
  expect(harbin.state, JourneyState.completed);
  expect(harbin.mode, TripModeFilter.rail);
  expect(_civil(harbin.end?.time), _civil(DateTime(2026, 10, 5, 14, 21, 15)));
  expect(harbin.duration, const Duration(minutes: 52, seconds: 57));
  expect(_compact(harbin.amountText), '-¥4.00');
  expect(harbin.events.map((event) => event.cityCode).toSet(), {'2610'});
  // The process fields alone do not prove that 1280/1550 is a post-trip
  // wallet balance. This regression deliberately makes no balance assertion.
}

List<JourneyPresentation<TripEntryInfo>> _liveJourneys(
  ScanPresentation view,
  ReferenceDataController reference,
) {
  final stream = buildTripStream(
    trips: view.analysis!.trips,
    processTrips: view.cycleProcessTrips,
  );
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

Future<ScanPresentation> _read(ReferenceDataController reference) async {
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, _hex('01011000FFFFFFFF'))
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, _hex('03100000000000000001'))
    ..setRange(20, 28, _hex('2026010120991231'));
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x10, 0]);
  final responses = <String, List<int>>{
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0960000': [...List<int>.filled(56, 0), 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [0, 0, 1, 0x18, 0x90, 0],
    '00B201C500': [0x6A, 0x86],
    for (final (index, raw) in _transactions.indexed)
      '00B2${_byte(index + 1)}C400': [..._hex(raw), 0x90, 0],
    '00B201F500': [0x6A, 0x86],
    for (final (index, raw) in _cycles.indexed)
      '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
    for (var number = 7; number <= 30; number++)
      '00B2${_byte(number)}F400': [...List<int>.filled(48, 0), 0x90, 0],
    '00B21FF400': [0x6A, 0x83],
  };
  final commands = <String>[];
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async {
        final key = command.map(_byte).join();
        commands.add(key);
        // The missing 1A route and any unobserved request are fixture boundaries.
        return responses[key] ?? const [0x6A, 0x83];
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  final card = await unit.read(info, records);
  expect(card, isNotNull);
  expect(commands, contains('00B21EF400'));
  return ScanPresentation(TransitReadOutcome(card!), reference.knowledge!);
}

Future<
  ({
    String encoded,
    ArchiveHistoryResult history,
    ArchiveHistoryResult restoredHistory,
  })
>
_saveAndRestore(ScanPresentation view) async {
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final repository = CardRepository(database);
  final controller = ArchiveController(
    repository,
    const MethodChannelLogExporter(),
    (_) {},
  );
  const attempt = 'synthetic-shenyang-journey-capture';
  try {
    controller.stage(
      view,
      attempt,
      DateTime(2026, 11, 3, 20, 29, 40),
      const [],
    );
    expect(controller.pending, isNotNull);
    final staged = CardSessionSnapshot.decode(
      controller.pending!.sessionDataJson!,
    )!;
    expect(staged.processTrips.map((record) => record.rawHex), _cycles);
    expect(staged.processTrips.map((record) => record.typeCode), [
      0x04,
      0x03,
      0x04,
      0x15,
      0x16,
      0x15,
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
String? _civil(DateTime? value) => value == null
    ? null
    : '${value.year}/${value.month}/${value.day} ${value.hour}:${value.minute}:${value.second}';
String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var offset = 0; offset < value.length; offset += 2)
    int.parse(value.substring(offset, offset + 2), radix: 16),
];
