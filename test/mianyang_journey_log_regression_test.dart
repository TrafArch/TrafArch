import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_cards_view.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Synthetic replay of the capture shape: nine new 0x18 debits, including two
// pairs in the same minute, then an older debit corroborated by 0x1E.
const _times = [
  '20261113183325',
  '20261113175605',
  '20261113172036',
  '20261113164927',
  '20261113161543',
  '20261113143536',
  '20261113143522',
  '20261113081856',
  '20261113081801',
  '20261112083020',
];
const _busSequence = 91;

void main() {
  for (final archive in [false, true]) {
    testWidgets(
      '${archive ? 'archived' : 'live'} TU history keeps all newer unmatched debits',
      (tester) async {
        final card = await _readCard();
        final analysis = AnalysisEngine(KnowledgeBase.empty()).analyze(card);
        final cycles = card.transitProcessRecords
            .map((record) => record.trip!)
            .toList();
        expect(card.transactions, hasLength(10));
        expect(cycles, hasLength(2));
        expect(
          analysis.trips
              .take(9)
              .every(
                (trip) => trip.isConsume && trip.matchedProcessTrip == null,
              ),
          isTrue,
        );
        expect(analysis.trips.last.matchedProcessTrip, same(cycles.first));

        if (archive) {
          final encoded = CardSessionSnapshot(
            parseVersion: kTripParseVersion,
            context: const ArchiveContext(
              systemId: CardParserIds.tunion,
              currencyCode: 'CNY',
              minorUnitDigits: 2,
            ),
            trips: analysis.trips,
            processTrips: cycles,
          ).encode();
          final decoded = CardSessionSnapshot.decodeResult(encoded);
          final batches = [
            ArchiveBatchEvidence(
              id: 'synthetic-mianyang-capture',
              readAt: DateTime(2026, 11, 14).millisecondsSinceEpoch,
              storedParseVersion: kTripParseVersion,
              origin: 'local',
              timeSource: 'device',
              decoded: decoded,
              issues: const [],
            ),
          ];
          final projection = presentArchiveTrips(
            ArchiveHistory.projectRecords(batches),
            onDiagnostics: (_) {},
            batches: batches,
          );
          expect(decoded.snapshot!.encode(), encoded);
          expect(projection.transactionCount, 10);
          expect(projection.mergedRecordCount, 1);
          await _expectHistory(
            tester,
            projection.entries,
            archiveTripSourceLabels,
            ArchiveRecordKind.transaction,
            projectedJourneys: projection.journeys,
          );
        } else {
          final stream = buildTripStream(
            trips: analysis.trips,
            processTrips: cycles,
          );
          final evidence = buildLiveJourneyEvidence(
            stream: stream,
            processRecords: card.transitProcessRecords,
            rails: const [],
            buses: const [],
          );
          final display = TripPresentationContext(
            currency: Currency.cny,
            cityNameOf: (_) => null,
            resolveStationMatch: (_, _, {lineValue}) => StationMatch.unmatched,
            resolveCycleStationMatch: (_, _, {terminalId, time, appType}) =>
                StationMatch.unmatched,
            resolveLineName: (_, _) => null,
            resolveBusLocation: (
              _,
              _, {
              context = const TunionBusDecodeContext(),
            }) => TunionBusLocation.unknown,
          );
          final entries = [
            for (final source in stream)
              _liveEntry(source, display, evidence[source]!),
          ];
          expect(stream.whereType<TransactionTripEntry>(), hasLength(10));
          expect(stream.whereType<ProcessTripEntry>(), hasLength(1));
          await _expectHistory(
            tester,
            entries,
            tripSourceLabels,
            TripSourceFilter.transaction,
          );
        }
      },
    );
  }
}

TripCardPresentation<TripSourceFilter> _liveEntry(
  TripEntry source,
  TripPresentationContext display,
  LiveJourneyEvidence evidence,
) {
  final info = describeTripEntry(source, display, remote: false);
  final event = describeJourneyEvent(
    source,
    display,
    info,
    applicationRecordId: evidence.applicationRecordId,
    processPositions: evidence.processPositions,
  );
  return TripCardPresentation(
    info: info,
    source: tripSourceOf(source),
    mode: event.mode,
    dateText: '',
    remote: false,
    journeyEvent: event,
  );
}

Future<void> _expectHistory<S extends Enum>(
  WidgetTester tester,
  List<TripCardPresentation<S>> entries,
  Map<S, String> labels,
  S transaction, {
  List<JourneyPresentation<TripCardPresentation<S>>>? projectedJourneys,
}) async {
  final debits = entries
      .where(
        (entry) =>
            entry.source == transaction && entry.mode == TripModeFilter.other,
      )
      .toList();
  expect(debits, hasLength(9));
  for (final debit in debits) {
    expect(debit.info.isConsume, isTrue);
    expect(debit.info.rawHex, isNotNull);
    expect(debit.journeyEvent!.role, JourneyEventRole.unknown);
    expect(
      debit.journeyEvent!.evidenceSource,
      JourneyEvidenceSource.transaction,
    );
    expect(debit.journeyEvent!.cityCode, isNull);
    expect(debit.journeyEvent!.endpoint.line, isNull);
    expect(debit.journeyEvent!.endpoint.station, isNull);
  }

  Future<void> show([TripModeFilter? mode]) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripCardsView(
            key: ValueKey(mode),
            entries: entries,
            sourceLabels: labels,
            summaryText: '',
            projectedJourneys: projectedJourneys,
            initialFilters: mode == null ? null : ['mode:${mode.name}'],
          ),
        ),
      ),
    ),
  );
  List<TripEntryCard> cards() => tester
      .widgetList<TripEntryCard>(
        find.byType(TripEntryCard, skipOffstage: false),
      )
      .toList();
  await show();
  expect(find.text('历史行程 10'), findsOneWidget);
  expect(find.text('其他记录 1'), findsOneWidget);
  expect(
    cards().take(9).map((card) => card.info.rawHex),
    debits.map((entry) => entry.info.rawHex),
  );
  expect(cards().take(9).every((card) => card.journey == null), isTrue);
  expect(cards()[9].journey?.events.single.sequence, _busSequence);
  expect(cards()[9].journey?.mode, TripModeFilter.bus);

  await show(TripModeFilter.bus);
  expect(cards().single.journey?.events.single.sequence, _busSequence);
  await show(TripModeFilter.other);
  expect(
    cards().take(9).map((card) => card.info.rawHex),
    debits.map((entry) => entry.info.rawHex),
  );
  expect(cards(), hasLength(10));
}

Future<ParsedCard> _readCard() async {
  final public = List<int>.filled(30, 0)
    ..setRange(10, 20, _hex('31999999999999999901'));
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x10, 0]);
  final responses = <String, List<int>>{
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [0, 0, 0x11, 0x30, 0x90, 0],
    for (final (index, time) in _times.indexed)
      '00B2${_byte(index + 1)}C400': [
        ..._hex('00${_byte(100 - index)}0000000000006409413100000001$time'),
        0x90,
        0,
      ],
    '00B201F400': [
      ..._hex(
        '0600004131000000010200000000000000000000640000100020261112083020690011656900FFFFFFFF000000000000',
      ),
      0x90,
      0,
    ],
    '00B202F400': [
      ..._hex(
        '0600000000000000020000000000000000000000640000106420261111083020690011656900FFFFFFFF000000000000',
      ),
      0x90,
      0,
    ],
  };
  final reader = CommonUnitTu(
    ApduExchange(
      transceive: (command) async =>
          responses[command.map(_byte).join()] ?? const [0x6A, 0x83],
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await reader.select(info, records), isTrue);
  return (await reader.read(info, records))!;
}

String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
