import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  for (final (mode, kind) in [
    (1, ArchiveRecordKind.rail),
    (2, ArchiveRecordKind.bus),
  ]) {
    group('0x1E precedence for ${kind.name}', () {
      test('same capture uses 1E and retains the original 1A evidence', () {
        final application = _application(kind);
        final cycle = _cycle(mode);
        final records = [application, cycle];

        final entries = presentArchiveTrips(records, onDiagnostics: (_) {});

        expect(entries.map((e) => e.source), [ArchiveRecordKind.process]);
        expect(records, [application, cycle]);
        expect(application.fields['rawHex'], '27017D');
        expect(application.sources.single.batchId, 'capture');
      });

      test('another mode in the same capture does not suppress 1A', () {
        final entries = presentArchiveTrips([
          _application(kind),
          _cycle(mode == 1 ? 2 : 1),
        ], onDiagnostics: (_) {});

        expect(entries.where((e) => e.source == kind), hasLength(2));
        expect(
          entries.where((e) => e.source == ArchiveRecordKind.process),
          hasLength(1),
        );
      });

      test('1E from another capture preserves earlier 1A-only history', () {
        final entries = presentArchiveTrips([
          _application(kind, batches: ['older']),
          _cycle(mode, batches: ['newer']),
        ], onDiagnostics: (_) {});

        expect(entries.where((e) => e.source == kind), hasLength(2));
      });

      test('a deduplicated 1A retains its earlier 1A-only attribution', () {
        final application = _application(kind, batches: ['older', 'newer']);
        final entries = presentArchiveTrips([
          application,
          _cycle(mode, batches: ['newer']),
        ], onDiagnostics: (_) {});

        expect(entries.where((e) => e.source == kind), hasLength(2));
        expect(application.sources.map((s) => s.batchId), ['older', 'newer']);
      });

      test(
        'all source captures with same-mode 1E suppress deduplicated 1A',
        () {
          final entries = presentArchiveTrips([
            _application(kind, batches: ['older', 'newer']),
            _cycle(mode, batches: ['older', 'newer']),
          ], onDiagnostics: (_) {});

          expect(entries.map((e) => e.source), [ArchiveRecordKind.process]);
        },
      );

      test('no cycle or an unknown cycle mode leaves 1A available', () {
        for (final cycleMode in [null, 0xFE]) {
          final entries = presentArchiveTrips([
            _application(kind),
            if (cycleMode != null) _cycle(cycleMode),
          ], onDiagnostics: (_) {});

          expect(entries.where((e) => e.source == kind), hasLength(2));
        }
      });

      test('missing capture attribution cannot establish same-capture 1E', () {
        final entries = presentArchiveTrips([
          _application(kind, batches: []),
          _cycle(mode),
        ], onDiagnostics: (_) {});

        expect(entries.where((e) => e.source == kind), hasLength(2));
      });

      test('same-mode 1E prevents 1A entry fallback even at another time', () {
        final trip = AnalysisEngine(KnowledgeBase.empty())
            .analyze(_card(mode, cycleMode: mode))
            .trips
            .single;

        expect(trip.isEntry, isFalse);
        expect(trip.rideStatusName, isNull);
        expect(trip.stationLabel, isNull);
        expect(trip.cityCode, isNull);
        expect(trip.matchedProcessTrip, isNull);
      });

      test('absent, other-mode or unknown 1E preserves 1A entry fallback', () {
        for (final cycleMode in [null, mode == 1 ? 2 : 1, 0xFE]) {
          final trip = AnalysisEngine(KnowledgeBase.empty())
              .analyze(_card(mode, cycleMode: cycleMode))
              .trips
              .single;

          expect(trip.isEntry, isTrue, reason: 'cycle mode $cycleMode');
          expect(trip.rideStatusName, mode == 1 ? '进站' : '上车');
          expect(trip.cityCode, '3910');
          expect(trip.matchedProcessTrip, isNull);
        }
      });
    });
  }
}

final _entryTime = DateTime(2026, 10, 22, 9);
final _cycleTime = DateTime(2026, 10, 22, 10);

List<ArchiveRecordSource> _sources(List<String> batches, String path) => [
  for (final batch in batches) ArchiveRecordSource(batch, path, 1, null),
];

ArchiveHistoryRecord _application(
  ArchiveRecordKind kind, {
  List<String> batches = const ['capture'],
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: {
    'status': 2,
    'entryTime': _entryTime.millisecondsSinceEpoch,
    'exitTime': _entryTime
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
    'entryCityCode': '3910',
    'exitCityCode': '3910',
    'entryAmountFen': 0,
    'exitAmountFen': 200,
    'rawHex': '27017D',
  },
  context: const ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
  sources: _sources(
    batches,
    kind == ArchiveRecordKind.rail ? 'rails[0]' : 'buses[0]',
  ),
);

ArchiveHistoryRecord _cycle(
  int mode, {
  List<String> batches = const ['capture'],
}) => ArchiveHistoryRecord(
  kind: ArchiveRecordKind.process,
  fields: {
    'typeCode': 4,
    'terminalId': '0000000000000001',
    'appTypeCode': mode,
    'lineStationCode': '00010001000000',
    'amountFen': 200,
    'balanceFen': 1000,
    'time': _cycleTime.millisecondsSinceEpoch,
    'cityCode': '3910',
    'rawHex': '04',
  },
  context: const ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
  sources: _sources(batches, 'cycle[0]'),
);

/// Synthetic records isolate file precedence from lookup and transaction pairing.
/// The valid 1E is deliberately an hour later, so it cannot annotate the 0x18.
ParsedCard _card(int mode, {int? cycleMode}) => ParsedCard(
  parserName: 'process precedence regression',
  selectedAidHex: 'A000000632010105',
  info: const TUnionCardInfo(cityCode: '3910'),
  transactions: [
    TUnionTransaction(
      sequence: 1,
      overdraftLimitFen: 0,
      amountFen: 0,
      rawType: 0x09,
      terminalId: '999999999999',
      time: _entryTime,
    ),
  ],
  transitProcessRecords: [
    TUnionProcessRecord(
      sfi: 0x1A,
      recordNumber: mode,
      recordName: 'synthetic 1A',
      raw: const [0x27],
      railTransit: mode == 1
          ? TransitRecord(
              statusCode: 1,
              entryTime: _entryTime,
              entryCityCode: '3910',
              entryStationId: '0000000000000031',
              entryAmountFen: 0,
            )
          : null,
      busTransit: mode == 2
          ? BusTransitRecord(
              statusCode: 1,
              entryTime: _entryTime,
              entryCityCode: '3910',
              entryStationCode: '02',
            )
          : null,
    ),
    if (cycleMode != null)
      TUnionProcessRecord(
        sfi: 0x1E,
        recordNumber: 1,
        recordName: 'synthetic 1E',
        raw: const [0x04],
        trip: TUnionTripRecord(
          typeCode: 4,
          terminalId: '0000000000000001',
          appTypeCode: cycleMode,
          lineStationCode: '00010001000000',
          amountFen: 200,
          balanceFen: 1000,
          time: _cycleTime,
          cityCode: '3910',
        ),
      ),
  ],
);
