import 'dart:convert';

import '../../../protocols/transit/city_union/city_union_models.dart';
import '../../reference_data/domain/reference_match.dart';
import '../../reference_data/domain/station_codes.dart';
import '../../transit_analysis/cu_transaction_analysis.dart';
import 'archive_history.dart';

/// This extension freezes the captured CU decoding and reference result. History
/// never reparses raw card bytes or queries the current reference database.
Map<String, dynamic> captureCuProjection(
  List<CuTransactionView> transactions,
) => {
  'version': 1,
  'transactions': [
    for (final view in transactions)
      {
        'record': view.record.toJson(),
        'sfi': view.record.sfi,
        'timeUtcMillis': view.transactionTime?.millisecondsSinceEpoch,
        'regionCode': view.regionCode,
        'carrier': view.carrier,
        'location': {
          'status': view.location.status.name,
          'issue': view.location.issue,
          'candidates': [
            for (final entry in view.location.candidates)
              _captureStation(entry),
          ],
        },
      },
  ],
};

class CuArchiveProjection {
  const CuArchiveProjection({
    required this.transactions,
    required this.sources,
    required this.issues,
  });
  final List<CuTransactionView> transactions;
  final Map<CuTransactionView, List<ArchiveRecordSource>> sources;
  final List<String> issues;

  Map<CuTransactionView, String> get sourceLabels => {
    for (final entry in sources.entries)
      entry.key: entry.value
          .map((source) => '${source.batchId}/${source.path}')
          .join(', '),
  };
}

CuArchiveProjection projectCuArchive(ArchiveHistoryResult history) {
  final records = <String, CuTransactionView>{};
  final sources = <CuTransactionView, List<ArchiveRecordSource>>{};
  final issues = <String>[];
  // Only identical frozen observations in the same context can share a row.
  // A changed match or unavailable reference package remains a separate view.
  for (final batch in history.batches) {
    final projection = batch.decoded.snapshot?.extensions['cuProjection'];
    if (projection == null) continue;
    if (projection is! Map ||
        projection['version'] is! int ||
        projection['version'] != 1 ||
        projection['transactions'] is! List) {
      issues.add('${batch.id}: CU 历史投影格式不支持，原始快照已保留');
      continue;
    }
    final entries = projection['transactions'] as List;
    for (var index = 0; index < entries.length; index++) {
      final path = 'cuProjection.transactions[$index]';
      try {
        final view = _restoreView(entries[index]);
        final fields = _map(entries[index]);
        final recordFields = _map(fields['record'])..remove('recordNumber');
        final snapshot = batch.decoded.snapshot!;
        final context = snapshot.context;
        final key = jsonEncode(
          _canonical({
            'fields': {...fields, 'record': recordFields},
            'context': {
              'systemId': context.systemId,
              'applicationId': context.applicationId,
              'currencyCode': context.currencyCode,
              'minorUnitDigits': context.minorUnitDigits,
              'timeZoneOffsetMinutes': context.timeZoneOffsetMinutes,
              'clockBasis': context.clockBasis,
            },
            'cardCityCode': snapshot.cardCityCode,
          }),
        );
        final kept = records.putIfAbsent(key, () => view);
        sources
            .putIfAbsent(kept, () => [])
            .add(
              ArchiveRecordSource(
                batch.id,
                path,
                batch.storedParseVersion,
                entries[index],
              ),
            );
      } on FormatException {
        issues.add('${batch.id}/$path: CU 历史记录不完整，原始快照已保留');
      }
    }
  }
  final indexed = records.values.indexed.toList();
  indexed.sort((a, b) {
    final first = a.$2.transactionTime;
    final second = b.$2.transactionTime;
    if (first == null || second == null) {
      if (first == null && second == null) return a.$1.compareTo(b.$1);
      return first == null ? 1 : -1;
    }
    final timeOrder = second.compareTo(first);
    return timeOrder == 0 ? a.$1.compareTo(b.$1) : timeOrder;
  });
  return CuArchiveProjection(
    transactions: List.unmodifiable(indexed.map((entry) => entry.$2)),
    sources: Map.unmodifiable({
      for (final entry in sources.entries)
        entry.key: List<ArchiveRecordSource>.unmodifiable(entry.value),
    }),
    issues: List.unmodifiable(issues),
  );
}

CuTransactionView _restoreView(Object? value) {
  final data = _map(value);
  final recordData = _map(data['record']);
  final sfi = _integer(data['sfi'], 1, 31);
  final raw = _string(recordData['rawHex']);
  if (!RegExp(r'^[0-9a-fA-F]{46}$').hasMatch(raw.replaceAll(' ', ''))) {
    throw const FormatException('CU raw record length');
  }
  final kindName = _string(recordData['recordKind']);
  final kind = CityUnionTransactionKind.values
      .where((value) => value.name == kindName)
      .firstOrNull;
  if (kind == null) throw const FormatException('CU record role');
  final recordNumber = recordData['recordNumber'];
  if (recordNumber != null) _integer(recordNumber, 1, 255);
  _integer(recordData['sequence'], 0, 65535);
  _integer(recordData['amountRaw'], 0, 0xFFFFFFFF);
  final transactionType = _string(recordData['transactionType']);
  if (!RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(transactionType)) {
    throw const FormatException('CU transaction type');
  }
  _string(recordData['amountHex']);
  _string(recordData['fileLabel']);
  _string(recordData['transactionTypeName']);
  for (final field in [
    'terminalNumber',
    'transactionDate',
    'transactionTime',
  ]) {
    _optionalString(recordData[field]);
  }
  final errors = recordData['errors'];
  if (errors is! List || errors.any((error) => error is! String)) {
    throw const FormatException('CU record diagnostics');
  }
  final location = _map(data['location']);
  final statusName = _string(location['status']);
  final status = ReferenceMatchStatus.values
      .where((value) => value.name == statusName)
      .firstOrNull;
  if (status == null || location['candidates'] is! List) {
    throw const FormatException('CU captured location');
  }
  final candidates = (location['candidates'] as List)
      .map(_restoreStation)
      .toList();
  if (status == ReferenceMatchStatus.matched && candidates.isEmpty) {
    throw const FormatException('CU captured match cardinality');
  }
  final millis = data['timeUtcMillis'];
  if (millis != null) _integer(millis, -8640000000000000, 8640000000000000);
  final carrier = data['carrier'];
  if (carrier != null) _integer(carrier, 0, 65535);
  return CuTransactionView(
    record: _CapturedCuRecord(Map.unmodifiable(recordData), sfi, kind),
    transactionTime: millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis as int, isUtc: true),
    regionCode: _optionalString(data['regionCode']),
    carrier: carrier as int?,
    location: ReferenceMatch(
      status,
      candidates,
      issue: _optionalString(location['issue']),
    ),
  );
}

Map<String, dynamic> _captureStation(StationCodeEntry entry) => {
  'code': entry.code,
  'type': entry.type,
  'line': entry.line,
  'station': entry.station,
  'system': entry.system,
  'kind': entry.kind,
  'datasetFile': entry.datasetFile,
  'lineCode': entry.lineCode,
  'stationCode': entry.stationCode,
  'sourceField': entry.sourceField,
  'sourceKey': entry.sourceKey,
  'rawValueJson': entry.rawValueJson,
  'lineKey': entry.lineKey,
  'userOverride': entry.userOverride,
  'overrideUpdatedAt': entry.overrideUpdatedAt,
};

StationCodeEntry _restoreStation(Object? value) {
  final data = _map(value);
  final override = data['userOverride'];
  if (override is! bool) throw const FormatException('CU station override');
  return StationCodeEntry(
    code: _string(data['code']),
    type: _optionalString(data['type']),
    line: _optionalString(data['line']),
    station: _optionalString(data['station']),
    system: _optionalString(data['system']),
    kind: _optionalString(data['kind']),
    datasetFile: _optionalString(data['datasetFile']),
    lineCode: _optionalString(data['lineCode']),
    stationCode: _optionalString(data['stationCode']),
    sourceField: _optionalString(data['sourceField']),
    sourceKey: _optionalString(data['sourceKey']),
    rawValueJson: _optionalString(data['rawValueJson']),
    lineKey: _optionalString(data['lineKey']),
    userOverride: override,
    overrideUpdatedAt: _optionalString(data['overrideUpdatedAt']),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('CU projection object');
  }
  return Map<String, dynamic>.from(value);
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('CU projection integer');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('CU projection string');
  return value;
}

String? _optionalString(Object? value) => value == null ? null : _string(value);

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// Saved decoding is displayed verbatim; raw bytes remain available separately.
class _CapturedCuRecord implements CityUnionWalletTransaction {
  const _CapturedCuRecord(this.data, this.sfi, this.kind);
  final Map<String, dynamic> data;
  @override
  final int sfi;
  @override
  final CityUnionTransactionKind kind;
  @override
  String get rawHex => data['rawHex'] as String;
  @override
  String get fileLabel => data['fileLabel'] as String;
  @override
  int get sequence => data['sequence'] as int;
  @override
  int get amountRaw => data['amountRaw'] as int;
  @override
  String get amountHex => data['amountHex'] as String;
  @override
  int get transactionType =>
      int.parse(data['transactionType'] as String, radix: 16);
  @override
  String get transactionTypeName => data['transactionTypeName'] as String;
  @override
  String? get terminalNumber => data['terminalNumber'] as String?;
  @override
  String? get transactionDate => data['transactionDate'] as String?;
  @override
  String? get transactionTime => data['transactionTime'] as String?;
  @override
  int? get recordNumber => data['recordNumber'] as int?;
  @override
  List<CjField> get fields => const [];
  @override
  List<String> get errors => List<String>.unmodifiable(data['errors'] as List);
  @override
  Map<String, dynamic> toJson() => data;
}
