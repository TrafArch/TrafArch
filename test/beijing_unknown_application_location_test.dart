import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_cycle_station_resolver.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

import 'support/test_database.dart';

// Exact 1E slots 17/18 in transit_card_log_20261027_165021.txt, excluding
// status words and all card identity files. Expected labels were independently
// checked against TripReader M0.i0.a:1000040041 and the supplied screenshot.
const _debitHex =
    '06000030004910001400040041002C0000000007D00000000020240428171215'
    '100001011000FFFFFFFF000000000000';
const _rechargeHex =
    '0A0000300939100015015D001700490000000007D0000007D020240427170703'
    '100001011000FFFFFFFF000000000000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late KnowledgeBase knowledge;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('trafarch-beijing-app00-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    knowledge = reference.knowledge!;
    expect(knowledge.loadIssues, isEmpty);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test(
    'source-backed Beijing app00 resolves the original rail location key',
    () {
      final record = _parse(_debitHex);
      final match = knowledge.tuLookup!.resolveCycle(
        city: record.cityCode,
        field: record.lineStationCode,
        terminalId: record.terminalId,
        time: record.time,
        appType: record.appTypeCode,
      );
      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '4号线');
      expect(match.stationName, '角门西');
      expect(match.entry?.sourceField, 'M0.i0.a');
      expect(match.entry?.sourceKey, '1000040041');
    },
  );

  test('live app00 location does not turn the event into a ride or refund', () {
    final record = _parse(_debitHex);
    final entry = ProcessTripEntry(record);
    final display = _display(reference);
    final info = describeTripEntry(entry, display, remote: false);
    expect(info.title, '单次消费 · 角门西');
    expect(info.line, '4号线');
    expect(info.amountText, '-¥20.00');
    expect(info.category, isNull);
    expect(info.badges, isEmpty);
    expect(info.fields, contains(('应用分类', '未知(0x00)')));
    expect(info.fields, contains(('过程类型', 'EP 单次消费')));
    final event = describeJourneyEvent(entry, display, info);
    expect(event.endpoint.station, '角门西');
    expect(event.mode, TripModeFilter.other);
    expect(event.role, JourneyEventRole.unknown);
    expect(event.balanceAfterText, isNull);
    final recharge = ProcessTripEntry(_parse(_rechargeHex));
    final rechargeInfo = describeTripEntry(recharge, display, remote: false);
    final journeys = projectJourneys([
      event,
      describeJourneyEvent(recharge, display, rechargeInfo),
    ]);
    expect(journeys, hasLength(2));
    expect(journeys.every((journey) => journey.events.length == 1), isTrue);
    expect(record.typeCode, 6);
    expect(record.appTypeCode, 0);
    expect(record.amountFen, 2000);
    expect(record.balanceFen, 0);
    expect(record.time, DateTime(2024, 4, 28, 17, 12, 15));
    expect(record.rawHex, _debitHex);
  });

  test('a linked transaction gains location without gaining rail mode', () {
    // Synthetic 18 counterpart, not a transaction captured in the report.
    final record = _parse(_debitHex);
    final trip = AnalysisEngine(knowledge)
        .analyze(_card(withTransaction: true))
        .trips
        .single;
    expect(trip.matchedProcessTrip?.rawHex, record.rawHex);
    expect(trip.lineLabel, '4号线');
    expect(trip.stationLabel, '角门西');
    expect(trip.stationConfidence, StationMatchConfidence.exact);
    expect(trip.stationType, isNull);
    expect(trip.appTypeName, isNull);
    expect(trip.typeName, '消费');
    expect(trip.isEntry, isFalse);
    final entry = TransactionTripEntry(trip);
    final display = _display(reference);
    final info = describeTripEntry(entry, display, remote: false);
    final event = describeJourneyEvent(entry, display, info);
    expect(event.mode, TripModeFilter.other);
    expect(event.role, JourneyEventRole.unknown);
    expect(event.endpoint.station, '角门西');
    expect(trip.matchedProcessTrip?.appTypeCode, 0);
  });

  test(
    'a missing process city cannot borrow Beijing from the issuing card',
    () {
      // Synthetic truncated variant: all fields through time remain, but the
      // record has no acquirer city. The unrelated card's city is still 1000.
      final truncated = _debitHex.substring(0, 64);
      final trip = AnalysisEngine(knowledge)
          .analyze(_card(withTransaction: true, debitHex: truncated))
          .trips
          .single;
      expect(trip.matchedProcessTrip?.cityCode, isNull);
      expect(trip.lineLabel, isNot('4号线'));
      expect(trip.stationLabel, isNot('角门西'));
    },
  );

  test(
    'new capture and JSON restore keep app00 location and raw evidence',
    () async {
      final database = testDatabase();
      final repository = CardRepository(database);
      final archive = ArchiveController(
        repository,
        const MethodChannelLogExporter(),
        (_) {},
      );
      addTearDown(() async {
        archive.dispose();
        await database.close();
      });
      archive.stage(
        ScanPresentation(TransitReadOutcome(_card()), knowledge),
        'beijing-app00-location',
        DateTime(2026, 10, 27, 17),
        const [],
      );
      final json =
          jsonDecode(archive.pending!.sessionDataJson!) as Map<String, dynamic>;
      final cycle = (json['cycle'] as List).first as Map<String, dynamic>;
      expect(cycle['capturedDisplay'], containsPair('station', '角门西'));
      expect(cycle['capturedDisplay'], containsPair('line', '4号线'));
      expect(cycle['appTypeCode'], 0);
      expect(cycle['typeCode'], 6);
      expect(cycle['amountFen'], 2000);
      expect(cycle['balanceFen'], 0);
      expect(cycle['rawHex'], _debitHex);
      expect(cycle['stationType'], isNull);
      final original = jsonEncode(json);
      final restored = CardSessionSnapshot.decode(original)!;
      expect(restored.encode(), original);
      final fields =
          (jsonDecode(restored.encode())['cycle'] as List).first
              as Map<String, dynamic>;
      final saved = presentArchiveTrips([
        _history(fields),
      ], onDiagnostics: (_) {}).entries.single;
      expect(saved.info.title, '单次消费 · 角门西');
      expect(saved.info.line, '4号线');
      expect(saved.info.fields, contains(('应用分类', '未知(0x00)')));
      expect(saved.mode, TripModeFilter.other);
      expect(saved.journeyEvent!.role, JourneyEventRole.unknown);
      expect(saved.journeyEvent!.balanceAfterText, isNull);
      expect(saved.info.rawHex, _debitHex);
      expect(await archive.accept(archive.pending!.pendingSaveId), isTrue);
      final card = await database.select(database.savedCards).getSingle();
      final history = await ArchiveHistory(repository).load(card.id);
      final persisted = presentArchiveTrips(
        history.records,
        onDiagnostics: (_) {},
      );
      final debit = persisted.entries.singleWhere(
        (entry) => entry.info.rawHex == _debitHex,
      );
      expect(debit.info.title, '单次消费 · 角门西');
      expect(debit.info.line, '4号线');
      expect(debit.mode, TripModeFilter.other);
      expect(debit.journeyEvent!.role, JourneyEventRole.unknown);
      expect(persisted.processRecordCount, 2);
    },
  );

  testWidgets('saved app00 ordinary card visibly uses its captured location', (
    tester,
  ) async {
    final projection = presentArchiveTrips([
      _history({
        ..._savedCycle,
        'capturedDisplay': {'line': '4号线', 'station': '角门西'},
      }),
    ], onDiagnostics: (_) {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCardsView(
              entries: projection.entries,
              sourceLabels: archiveTripSourceLabels,
              summaryText: projection.summaryText,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('单次消费 · 角门西'), findsOneWidget);
    expect(find.text('4号线'), findsOneWidget);
    expect(find.textContaining('退资'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('legacy app00 archive stays unchanged without captured location', () {
    final fields = Map<String, dynamic>.from(_savedCycle);
    final original = jsonEncode(fields);
    final saved = presentArchiveTrips([
      _history(fields),
    ], onDiagnostics: (_) {}).entries.single;
    expect(saved.info.title, '单次消费');
    expect(saved.info.line, isNull);
    expect(saved.mode, TripModeFilter.other);
    expect(jsonEncode(fields), original);
  });

  for (final (city, terminal, field, appType) in [
    ('1000', null, '040041002C0000', 0),
    ('1000', '0000000000000001', '040041002C0000', 0),
    ('1000', '0000300799100014', '040041002C0000', 0),
    ('1000', 'FFFF300049100014', '040041002C0000', 0),
    ('1000', '000030004910001Z', '040041002C0000', 0),
    ('1000', '0000300049100014', '040041002C0000', 2),
    ('1000', '0000300049100014', '040041002C0000', null),
    ('1000', '0000300049100014', 'FFFF41002C0000', 0),
    ('1000', '0000300049100014', '040041002C00ZZ', 0),
    ('6900', '0000300049100014', '18000100000000', 0),
  ]) {
    test(
      'unknown location rejects unsupported context $city/$terminal/$field/$appType',
      () {
        final match = reference.resolveCycleStationMatch(
          city,
          field,
          terminalId: terminal,
          appType: appType,
        );
        expect(match.isUnmatched, isTrue);
      },
    );
  }

  test('app00 never falls back to station fragments without source lookup', () {
    final match = resolveTuCycleStation(
      stations: knowledge.stationCodes,
      lookup: null,
      cityCode: '1000',
      field: '040041002C0000',
      terminalId: '0000300049100014',
      appType: 0,
    );
    expect(match.isUnmatched, isTrue);
  });

  for (final (issue, conflict, confidence) in [
    (
      'synthetic reference read failure',
      false,
      StationMatchConfidence.unavailable,
    ),
    (null, true, StationMatchConfidence.ambiguous),
  ]) {
    test('app00 retains reference $confidence without fragment fallback', () {
      final lookup = TuLookupService(
        _ReferenceOverride(
          knowledge.tuLookup!.source,
          issue: issue,
          conflict: conflict,
        ),
      );
      final match = resolveTuCycleStation(
        stations: knowledge.stationCodes,
        lookup: lookup,
        cityCode: '1000',
        field: '040041002C0000',
        terminalId: '0000300049100014',
        appType: 0,
      );
      expect(match.confidence, confidence);
      expect(match.stationName, isNull);
      if (conflict) expect(match.candidates, hasLength(2));
    });
  }
}

TUnionTripRecord _parse(String hex) =>
    const TUnionProcessParser().parseCycleTrip([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ])!;

ParsedCard _card({bool withTransaction = false, String debitHex = _debitHex}) =>
    ParsedCard(
      parserId: CardParserIds.tunion,
      parserName: '交通联合',
      selectedAidHex: 'A000000632010105',
      info: const TUnionCardInfo(
        applicationSerial: '03100000000000000001',
        issuerId: '1122334455667788',
        cityCode: '1000',
      ),
      transactions: [
        if (withTransaction)
          TUnionTransaction(
            sequence: 1,
            overdraftLimitFen: 0,
            amountFen: 2000,
            rawType: 6,
            terminalId: '300049100014',
            time: DateTime(2024, 4, 28, 17, 12, 15),
          ),
      ],
      transitProcessRecords: [
        for (final (slot, hex) in [(17, debitHex), (18, _rechargeHex)])
          TUnionProcessRecord(
            sfi: 0x1E,
            recordNumber: slot,
            recordName: '循环记录$slot',
            raw: [
              for (var i = 0; i < hex.length; i += 2)
                int.parse(hex.substring(i, i + 2), radix: 16),
            ],
            trip: _parse(hex),
          ),
      ],
    );

TripPresentationContext _display(ReferenceDataController reference) =>
    TripPresentationContext(
      currency: Currency.cny,
      cityNameOf: reference.cityNameOf,
      resolveStationMatch: reference.resolveStationMatch,
      resolveCycleStationMatch: reference.resolveCycleStationMatch,
      resolveLineName: reference.resolveLineName,
      resolveBusLocation: reference.resolveBusLocation,
    );

final _savedCycle = <String, dynamic>{
  'typeCode': 6,
  'appTypeCode': 0,
  'terminalId': '0000300049100014',
  'lineStationCode': '040041002C0000',
  'amountFen': 2000,
  'balanceFen': 0,
  'cityCode': '1000',
  'time': DateTime(2024, 4, 28, 17, 12, 15).millisecondsSinceEpoch,
  'rawHex': _debitHex,
};

ArchiveHistoryRecord _history(Map<String, dynamic> fields) =>
    ArchiveHistoryRecord(
      kind: ArchiveRecordKind.process,
      fields: fields,
      context: const ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
      sources: const [ArchiveRecordSource('captured', 'cycle[0]', 10, null)],
    );

// Inject only competing source evidence / an I/O issue, retaining the published
// database and production lookup behavior. The override never edits assets.
class _ReferenceOverride implements TuLookupDataSource {
  _ReferenceOverride(this.original, {this.issue, this.conflict = false});
  final TuLookupDataSource original;
  final String? issue;
  final bool conflict;

  @override
  String? get queryIssue => issue ?? original.queryIssue;

  @override
  Iterable<StationCodeEntry> railCandidates(String city) sync* {
    yield* original.railCandidates(city);
    if (conflict && city == '1000') {
      yield const StationCodeEntry(
        code: '1000040041',
        sourceKey: '1000040041',
        sourceField: 'M0.i0.a',
        system: 'tu',
        kind: 'metro',
        line: '4号线',
        station: '合成冲突站点',
      );
    }
  }

  @override
  List<StationCodeEntry> localTerminalCandidates(
    String field,
    String terminal,
  ) => original.localTerminalCandidates(field, terminal);
  @override
  List<TuLookupValue> terminalAliases(String terminal) =>
      original.terminalAliases(terminal);
  @override
  List<TuLookupValue> processTerminalCandidates(String city, String terminal) =>
      original.processTerminalCandidates(city, terminal);
  @override
  List<TuLookupValue> railHistory(String key) => original.railHistory(key);
}
