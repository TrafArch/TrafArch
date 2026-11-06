import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';

void main() {
  late Database database;
  late TuStationRepository repository;
  late TuLookupService lookup;

  setUpAll(() {
    database = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    repository = TuStationRepository(database);
    lookup = TuLookupService(repository);
  });
  tearDownAll(() => database.close());

  test(
    'Shaoxing intercity position resolves the complete native station key',
    () {
      // 2026-11-04 1E entry: position 0121, terminal-local suffix 1A04.
      final match = lookup.resolveCycle(
        city: '3370',
        field: '01211A04000000',
        terminalId: '4131014305290000',
        appType: 0x0A,
      );

      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '绍兴城际');
      expect(match.stationName, '钱清');
      expect(match.entry?.sourceField, 'M0.W.a');
      expect(match.entry?.sourceKey, '33700121');
      expect(match.entry?.rawValueJson, '["","绍兴城际","钱清"]');
      expect(match.evidence.map((row) => row.sourceKey), contains('33700121'));
    },
  );

  test(
    'intercity exit resolves from its own native city without changing input',
    () {
      final match = lookup.resolveCycle(
        city: '3370',
        field: '11351501000000',
        terminalId: '4131018830620000',
        appType: 0x0A,
      );

      expect(match.confidence, StationMatchConfidence.exact);
      expect(match.lineName, '宁波城际');
      expect(match.stationName, '宁波');
      expect(match.entry?.sourceKey, '33201135');
    },
  );

  for (final field in [
    '01211A040000', // Missing reserved byte is not the observed layout.
    '01211A04000001', // A written reserved byte must not be discarded.
    '01211A04010000', // The remaining position bytes are not all padding.
    '01211G04000000',
  ]) {
    test('unverified Shaoxing intercity layout stays unmatched: $field', () {
      expect(
        lookup
            .resolveCycle(city: '3370', field: field, appType: 0x0A)
            .isUnmatched,
        isTrue,
      );
    });
  }

  for (final appType in [0x00, 0x02, 0x0E]) {
    test('other applications do not use the intercity adapter: $appType', () {
      expect(
        lookup
            .resolveCycle(
              city: '3370',
              field: '01211A04000000',
              appType: appType,
            )
            .isUnmatched,
        isTrue,
      );
    });
  }

  test('the existing industry-0A records of another city stay unmatched', () {
    // The 2026-11-01 capture has a different city, receiver and position map.
    for (final field in ['41111504000000', '42361A03000000']) {
      expect(
        lookup
            .resolveCycle(city: '5330', field: field, appType: 0x0A)
            .isUnmatched,
        isTrue,
      );
    }
  });

  test('short native prefixes do not establish an intercity station', () {
    final service = TuLookupService(
      _SourceOverride(
        repository,
        replaceRail: true,
        rows: [_row(key: '337001', station: '短前缀碰撞')],
      ),
    );
    expect(
      service
          .resolveCycle(city: '3370', field: '01211A04000000', appType: 0x0A)
          .isUnmatched,
      isTrue,
    );
  });

  test('a different source namespace cannot supply the intercity station', () {
    final service = TuLookupService(
      _SourceOverride(
        repository,
        replaceRail: true,
        rows: [_row(sourceField: 'M0.C.b', station: '终端命名空间碰撞')],
      ),
    );
    expect(
      service
          .resolveCycle(city: '3370', field: '01211A04000000', appType: 0x0A)
          .isUnmatched,
      isTrue,
    );
  });

  test('a stationless native row cannot complete the intercity endpoint', () {
    final service = TuLookupService(
      _SourceOverride(repository, replaceRail: true, rows: [_row(station: '')]),
    );
    expect(
      service
          .resolveCycle(city: '3370', field: '01211A04000000', appType: 0x0A)
          .isUnmatched,
      isTrue,
    );
  });

  test('conflicting complete intercity keys retain ambiguity and evidence', () {
    final service = TuLookupService(
      _SourceOverride(repository, rows: [_row(station: '同码冲突站')]),
    );
    final match = service.resolveCycle(
      city: '3370',
      field: '01211A04000000',
      appType: 0x0A,
    );

    expect(match.confidence, StationMatchConfidence.ambiguous);
    expect(match.lineName, isNull);
    expect(match.stationName, isNull);
    expect(match.candidates.map((row) => row.station).toSet(), {'钱清', '同码冲突站'});
    expect(match.evidence.map((row) => row.sourceKey).toSet(), {
      '33700121',
      '337001',
    });
  });

  test('intercity source query failures stay unavailable', () {
    final service = TuLookupService(
      _SourceOverride(repository, issue: 'synthetic read failure'),
    );
    expect(
      service
          .resolveCycle(city: '3370', field: '01211A04000000', appType: 0x0A)
          .confidence,
      StationMatchConfidence.unavailable,
    );
  });
}

StationCodeEntry _row({
  String key = '33700121',
  String sourceField = 'M0.W.a',
  required String station,
}) => StationCodeEntry(
  code: key,
  sourceKey: key,
  sourceField: sourceField,
  system: 'tu',
  kind: 'metro',
  line: '绍兴城际',
  station: station,
);

// Replace only source rows or the read-error state; the service under test is
// the production resolver, and the published SQLite asset is always read-only.
class _SourceOverride implements TuLookupDataSource, TuIntercityRailSource {
  _SourceOverride(
    this.original, {
    this.rows = const [],
    this.replaceRail = false,
    this.issue,
  });

  final TuLookupDataSource original;
  final List<StationCodeEntry> rows;
  final bool replaceRail;
  final String? issue;

  @override
  String? get queryIssue => issue ?? original.queryIssue;

  @override
  Iterable<StationCodeEntry> railCandidates(String city) sync* {
    if (!replaceRail) yield* original.railCandidates(city);
    if (city == '3370') yield* rows;
  }

  @override
  Iterable<TuIntercityRailCandidate> intercityRailCandidates(
    String city,
  ) sync* {
    if (!replaceRail && original is TuIntercityRailSource) {
      yield* (original as TuIntercityRailSource).intercityRailCandidates(city);
    }
    if (city == '3370') {
      for (final row in rows) {
        yield TuIntercityRailCandidate(
          city: '3370',
          prefix: const TuLookupValue('M0.W.a', '337001', ['', '绍兴城际', '']),
          station: row,
        );
      }
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
