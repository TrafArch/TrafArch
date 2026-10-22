import 'dart:convert';

import 'station_codes.dart';

/// Offline inputs with separate namespaces for rail keys and local terminals.
/// No issuer fallback or record mutation is permitted at this boundary.
abstract interface class TuLookupDataSource {
  String? get queryIssue;
  Iterable<StationCodeEntry> railCandidates(String city);
  List<StationCodeEntry> localTerminalCandidates(
    String sourceField,
    String terminal,
  );
  List<TuLookupValue> terminalAliases(String terminal);
  List<TuLookupValue> processTerminalCandidates(String city, String terminal);
  List<TuLookupValue> railHistory(String key);
}

class TuLookupValue {
  final String sourceField;
  final String sourceKey;
  final Object? rawValue;

  const TuLookupValue(this.sourceField, this.sourceKey, this.rawValue);

  StationMatchEvidence get evidence => StationMatchEvidence(
    sourceField: sourceField,
    sourceKey: sourceKey,
    rawValueJson: jsonEncode(rawValue),
  );
}

/// Original m756j(type=3), m759m and m761o lookup semantics (Simplified Chinese).
/// City-specific cycle adapters use only their verified field/terminal slices.
/// Unknown application types never enter the rail path. Missing dates use base
/// names, not the current clock. The caller retains the original record city.
class TuLookupService {
  final TuLookupDataSource source;
  const TuLookupService(this.source);

  StationMatch get _miss => source.queryIssue == null
      ? StationMatch.unmatched
      : StationMatch.unavailable;

  StationMatch resolveRailKey({
    required String? city,
    required String key,
    DateTime? time,
  }) {
    if (!_validCity(city)) return StationMatch.unmatched;
    final normalized = key.toUpperCase();
    if (!RegExp(r'^[0-9A-F]{5,32}$').hasMatch(normalized) ||
        !normalized.startsWith(city!)) {
      return StationMatch.unmatched;
    }
    final rows = StationCodeTable.longestTuRailCandidates(
      city,
      normalized,
      source.railCandidates(city),
    );
    if (source.queryIssue != null) return StationMatch.unavailable;
    if (rows.isEmpty) return _miss;
    final evidence = <StationMatchEvidence>[];
    var candidates = rows;
    if (time != null) {
      // The history prefix is selected against the entire input, independently
      // of the base key length, as in the original nested prefix search.
      final history = source.railHistory(normalized);
      if (source.queryIssue != null) return StationMatch.unavailable;
      if (history.isNotEmpty) {
        final longest = history
            .map((e) => e.sourceKey.length)
            .reduce((a, b) => a > b ? a : b);
        for (final item in history.where(
          (e) => e.sourceKey.length == longest,
        )) {
          for (final rawRule in item.rawValue! as List) {
            final rule = rawRule as List;
            final cutoff = DateTime.parse(
              (rule[0] as Map)[r'$date_literal'] as String,
            );
            if (!time.isBefore(cutoff)) break;
            candidates = [
              for (final row in candidates)
                // User presentation overrides keep priority over dated names.
                if (row.userOverride)
                  row
                else
                  _presentation(
                    row,
                    type: rule[1] == '*' ? row.type : rule[1] as String,
                    line: rule[2] == '*' ? row.line : rule[2] as String,
                    station: rule[3] == '*' ? row.station : rule[3] as String,
                  ),
            ];
            evidence.add(item.evidence);
          }
        }
      }
    }
    return StationMatch.fromCandidates(candidates, evidence: evidence);
  }

  /// Original m762p exact key: city + 16-character process terminal in M0.S.a.
  StationMatch resolveProcess({
    required String? city,
    required String terminal,
  }) {
    if (!_validCity(city)) return StationMatch.unmatched;
    final q = terminal.toUpperCase();
    if (!RegExp(r'^[0-9A-F]{16}$').hasMatch(q)) return StationMatch.unmatched;
    final rows = source.processTerminalCandidates(city!, q);
    if (source.queryIssue != null) return StationMatch.unavailable;
    if (rows.isEmpty) return _miss;
    return StationMatch.fromCandidates(
      [for (final row in rows) _localPresentationRow(row)],
      evidence: [for (final row in rows) row.evidence],
    );
  }

  StationMatch resolveCycle({
    required String? city,
    required String field,
    String? terminalId,
    DateTime? time,
    required int? appType,
  }) {
    if (appType != 0x01 || !_validCity(city)) return StationMatch.unmatched;
    final raw = field.toUpperCase();
    // The parser retains the reserved trailing byte; original pos is 6 bytes.
    if (!RegExp(r'^(?:[0-9A-F]{12}|[0-9A-F]{14})$').hasMatch(raw)) {
      return StationMatch.unmatched;
    }
    final pos = raw.substring(0, 12);
    final q = terminalId?.toUpperCase();
    final validTerminal = q != null && RegExp(r'^[0-9A-F]{16}$').hasMatch(q);
    if (validTerminal) {
      final exact = resolveProcess(city: city, terminal: q);
      if (!exact.isUnmatched) return exact;
    }
    String? special;
    if (city == '3910' || city == '7010') {
      special = '$city${pos.substring(2, 4)}${pos.substring(6, 8)}';
    } else if (city == '4520' && validTerminal && q.startsWith('45200000')) {
      special = '$city${q.substring(8, 12)}';
    } else if (city == '3320' && pos.substring(0, 2) != '00') {
      special = '${city}00${pos.substring(0, 2)}00${pos.substring(2, 4)}';
    } else if (city == '6510') {
      special = '$city${pos.substring(4, 8)}';
    }
    if (special != null) {
      final hit = resolveRailKey(city: city, key: special, time: time);
      if (!hit.isUnmatched) return hit;
    }
    final generic = resolveRailKey(city: city, key: '$city$pos', time: time);
    if (!generic.isUnmatched) return generic;
    if (city == '7910' &&
        validTerminal &&
        q.startsWith('79100000') &&
        q.substring(8, 10) != '00' &&
        RegExp(r'^\d{2}$').hasMatch(q.substring(10, 12))) {
      final station = int.parse(q.substring(10, 12))
          .toRadixString(16)
          .toUpperCase()
          .padLeft(4, '0');
      return resolveRailKey(
        city: city,
        key: '${city}00${q.substring(8, 10)}$station',
        time: time,
      );
    }
    return _miss;
  }

  StationMatch resolveBasic({
    required String? city,
    required String terminal,
    DateTime? time,
  }) {
    if (!_validCity(city)) return StationMatch.unmatched;
    final key = terminal.toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(key)) return StationMatch.unmatched;
    String? field;
    if (city == '1610') {
      field = 'M0.n0.a';
    } else if (city == '3010') {
      field = 'M0.E.a';
    } else if (city == '6510') {
      field = 'M0.b.a';
    } else if (const ['3310', '3350', '3370'].contains(city)) {
      final aliases = source.terminalAliases(key);
      if (source.queryIssue != null) return StationMatch.unavailable;
      // m761o tries s, t, u in order. An unresolved alias must not turn into
      // an unrelated local-terminal fallback, even if C.b contains this key.
      for (final aliasField in const ['M0.s.a', 'M0.t.a', 'M0.u.a']) {
        final hits = aliases.where((e) => e.sourceField == aliasField).toList();
        if (hits.isEmpty) continue;
        final targets = hits.map((e) => e.rawValue).toSet();
        if (targets.length != 1) {
          return StationMatch(
            null,
            StationMatchConfidence.ambiguous,
            evidence: hits.map((e) => e.evidence).toList(),
          );
        }
        final hit = resolveRailKey(
          city: city,
          key: '$city${targets.single}',
          time: time,
        );
        return StationMatch(
          hit.entry,
          hit.confidence,
          candidates: hit.candidates,
          evidence: [...hits.map((e) => e.evidence), ...hit.evidence],
        );
      }
      field = 'M0.C.b';
    }
    if (field == null) return StationMatch.unmatched;
    final rows = source.localTerminalCandidates(field, key);
    if (source.queryIssue != null) return StationMatch.unavailable;
    if (rows.isEmpty) return _miss;
    return StationMatch.fromCandidates([
      for (final row in rows) _localPresentation(row, field),
    ]);
  }

  static bool _validCity(String? city) =>
      city != null &&
      RegExp(r'^\d{4}$').hasMatch(city) &&
      city != '0000' &&
      city != '9999';

  static StationCodeEntry _localPresentationRow(TuLookupValue row) {
    final raw = row.rawValue;
    final list = raw is List ? raw : const [];
    return _localPresentation(
      StationCodeEntry(
        code: row.sourceKey,
        sourceKey: row.sourceKey,
        sourceField: row.sourceField,
        type: list.isNotEmpty ? '${list[0]}' : '',
        line: list.length > 1 ? '${list[1]}' : '',
        station: list.isNotEmpty ? '${list.last}' : '',
        system: 'tu',
        kind: 'metro',
        datasetFile: 'tu:lookup',
        rawValueJson: jsonEncode(raw),
      ),
      row.sourceField,
    );
  }

  static StationCodeEntry _localPresentation(
    StationCodeEntry row,
    String field,
  ) {
    if (row.userOverride) return row;
    final raw = row.rawValueJson == null ? null : jsonDecode(row.rawValueJson!);
    if (raw is! List || (raw.length != 2 && raw.length != 3)) return row;
    if (field == 'M0.n0.a' || field == 'M0.C.b') {
      final line = raw[0] as String;
      return _presentation(
        row,
        type: '',
        line: RegExp(r'^\d+$').hasMatch(line) ? '$line号线' : line,
        station: raw[1] as String,
        kind: field == 'M0.n0.a' ? 'metro' : 'intercity_rail',
      );
    }
    return _presentation(
      row,
      type: raw[0] as String,
      line: raw[1] as String,
      station: raw[2] as String,
    );
  }

  static StationCodeEntry _presentation(
    StationCodeEntry row, {
    String? type,
    String? line,
    String? station,
    String? kind,
  }) => StationCodeEntry(
    code: row.code,
    type: type,
    line: line,
    station: station,
    system: row.system,
    kind: kind ?? row.kind,
    datasetFile: row.datasetFile,
    lineCode: row.lineCode,
    stationCode: row.stationCode,
    sourceField: row.sourceField,
    sourceKey: row.sourceKey,
    rawValueJson: row.rawValueJson,
    lineKey: row.lineKey,
    userOverride: row.userOverride,
    overrideUpdatedAt: row.overrideUpdatedAt,
  );
}
