import 'dart:convert';

import '../../../shared/domain/remote_card_use.dart';
import '../../../protocols/transit/card_parser.dart' show CardParserIds;
import '../../../protocols/transit/city_union/city_union_file_parser.dart';
import '../../../protocols/transit/city_union/city_union_models.dart';
import '../../reference_data/data/city_union_lookup_rules.dart';
import '../../reference_data/domain/reference_match.dart';
import '../../reference_data/domain/station_codes.dart';
import '../../transit_analysis/cu_transaction_analysis.dart';
import 'archive_history.dart';

/// Keeps the captured CU decoding and reference results as source evidence.
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
        if (view.qingdaoMetro case final link?)
          'qingdaoMetro': {'id': link.id, 'isEntry': link.isEntry},
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

  /// Each retained capture must independently establish the CU issuing city.
  /// A TU issuing city from a dual-application card is a different namespace.
  bool isRemoteUse(
    CuTransactionView transaction,
    List<ArchiveBatchEvidence> batches,
  ) {
    final observations = sources[transaction] ?? const [];
    final byId = {for (final batch in batches) batch.id: batch};
    return observations.isNotEmpty &&
        observations.every((source) {
          final snapshot = byId[source.batchId]?.decoded.snapshot;
          if (snapshot == null) return false;
          final cities = <String>{
            for (final file in snapshot.rawEvidence)
              if (file['kind'] == 'cu_file' && file['sfi'] == '0x15')
                if (file['cityCode'] case final String city) city,
            if (snapshot.context.systemId == CardParserIds.cityUnion)
              ?snapshot.cardCityCode,
          };
          return cities.length == 1 &&
              isRemoteCardUse(cities.single, transaction.regionCode);
        });
  }

  Map<CuTransactionView, String> get sourceLabels => {
    for (final entry in sources.entries)
      entry.key: entry.value
          .map((source) => '${source.batchId}/${source.path}')
          .join(', '),
  };
}

CuArchiveProjection projectCuArchive(ArchiveHistoryResult history) {
  final records = <String, CuTransactionView>{};
  final sources = <String, List<ArchiveRecordSource>>{};
  final conflictingMetro = <String>{};
  final issues = <String>[];
  // Only identical frozen observations in the same context can share a row.
  // A changed match or unavailable reference package remains a separate view.
  for (final batch in history.batches) {
    final snapshot = batch.decoded.snapshot;
    if (snapshot == null) continue;
    final projection = snapshot.extensions['cuProjection'];
    if (projection != null &&
        (projection is! Map ||
            projection['version'] is! int ||
            projection['version'] != 1 ||
            projection['transactions'] is! List)) {
      issues.add('${batch.id}: CU 历史投影格式不支持，原始快照已保留');
      continue;
    }
    final entries = projection == null
        ? const []
        : projection['transactions'] as List;
    final restored = <String, ({CuTransactionView view, Object? original})>{};
    for (var index = 0; index < entries.length; index++) {
      final path = 'cuProjection.transactions[$index]';
      try {
        restored[path] = (
          view: _restoreView(entries[index]),
          original: entries[index],
        );
      } on FormatException {
        issues.add('${batch.id}/$path: CU 历史记录不完整，原始快照已保留');
      }
    }
    // Older readers kept 0x06/02 only as a cu_file, even when it was the
    // only wallet observation. A current capture carries both forms.
    final projectedSlots = {
      for (final observation in restored.values)
        if (observation.view.record.sfi == 0x06)
          (
            observation.view.record.recordNumber,
            observation.view.record.rawHex.replaceAll(' ', '').toUpperCase(),
          ),
    };
    for (final (index, file) in snapshot.rawEvidence.indexed) {
      if (file['kind'] != 'cu_file' || file['sfi'] != '0x06') continue;
      final credit = _capturedRecharge(
        0x06,
        file['rawHex'],
        file['recordNumber'],
      );
      if (credit == null ||
          !projectedSlots.add((
            credit.record.recordNumber,
            credit.record.rawHex.replaceAll(' ', '').toUpperCase(),
          ))) {
        continue;
      }
      final path = 'rawEvidence[$index]';
      restored[path] = (view: credit, original: file);
    }
    final completeMetro = completeQingdaoMetroLinks(
      restored.values.map((entry) => entry.view),
    );
    final chargeCounts = <(int, String), int>{};
    for (final entry in restored.entries) {
      final path = entry.key;
      final candidate = entry.value.view;
      final view = completeMetro.contains(candidate.qingdaoMetro?.id)
          ? candidate
          : candidate.withQingdaoMetro(null);
      final fields = _map(entry.value.original)..remove('qingdaoMetro');
      final context = snapshot.context;
      final recharge = view.record is CjT331WalletRecharge;
      final raw = view.record.rawHex.replaceAll(' ', '').toUpperCase();
      final key = jsonEncode(
        _canonical({
          // A legacy debit label, a raw-only capture, and an updated read
          // represent the same credit if the whole wallet row matches.
          'fields': recharge
              ? {
                  'sfi': view.record.sfi,
                  'rawHex': raw,
                  'occurrence': chargeCounts.update(
                    (view.record.sfi, raw),
                    (n) => n + 1,
                    ifAbsent: () => 1,
                  ),
                }
              : {
                  ...fields,
                  'record': _map(fields['record'])..remove('recordNumber'),
                },
          'context': {
            'systemId': recharge && context.isShanghaiTunionWallet
                ? CardParserIds.shanghaiTunion
                : context.systemId,
            'applicationId': context.applicationId,
            'currencyCode': context.currencyCode,
            'minorUnitDigits': context.minorUnitDigits,
            'timeZoneOffsetMinutes': context.timeZoneOffsetMinutes,
            'clockBasis': context.clockBasis,
          },
          'cardCityCode': snapshot.cardCityCode,
        }),
      );
      final previous = records[key];
      if (previous == null) {
        records[key] = view;
      } else if (!conflictingMetro.contains(key) && view.qingdaoMetro != null) {
        if (previous.qingdaoMetro == null) {
          records[key] = previous.withQingdaoMetro(view.qingdaoMetro);
        } else if (previous.qingdaoMetro != view.qingdaoMetro) {
          conflictingMetro.add(key);
          records[key] = previous.withQingdaoMetro(null);
        }
      }
      sources
          .putIfAbsent(key, () => [])
          .add(
            ArchiveRecordSource(
              batch.id,
              path,
              batch.storedParseVersion,
              entry.value.original,
            ),
          );
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
      for (final entry in records.entries)
        entry.value: List<ArchiveRecordSource>.unmodifiable(
          sources[entry.key]!,
        ),
    }),
    issues: List.unmodifiable(issues),
  );
}

CuTransactionView? _capturedRecharge(int sfi, Object? raw, Object? slot) {
  if (raw is! String || slot is! int || slot < 1 || slot > 255) return null;
  final hex = raw.replaceAll(' ', '');
  if (!RegExp(r'^[0-9a-fA-F]{46}$').hasMatch(hex)) return null;
  final bytes = [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  final kind = CityUnionFileParser.walletRecordKind(sfi, bytes);
  if (kind != CityUnionTransactionKind.recharge) return null;
  final record = CityUnionFileParser.parseWalletRecord(
    sfi,
    bytes,
    kind: CityUnionTransactionKind.recharge,
    recordNumber: slot,
  );
  if (!CityUnionFileParser.hasVerifiableWalletFields(record)) return null;
  final identity = CityUnionLookupRules.identifyTerminal(record.terminalHex);
  return CuTransactionView(
    record: record,
    transactionTime: CityUnionLookupRules.transactionTime(
      record.transactionDate,
      record.transactionTime,
    ),
    regionCode: identity?.regionCode,
    carrier: identity?.carrier,
    location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
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
  if ((sfi == 0x06 || sfi == 0x18) && transactionType == '02') {
    final credit = _capturedRecharge(sfi, raw, recordNumber);
    if (credit != null &&
        credit.record.sequence == recordData['sequence'] &&
        credit.record.amountRaw == recordData['amountRaw'] &&
        credit.record.terminalNumber == recordData['terminalNumber'] &&
        credit.record.transactionDate == recordData['transactionDate'] &&
        credit.record.transactionTime == recordData['transactionTime'] &&
        (millis == null ||
            millis == credit.transactionTime?.millisecondsSinceEpoch)) {
      return credit;
    }
  }
  final capturedMetro = data['qingdaoMetro'];
  QingdaoMetroLink? metro;
  if (sfi == 0x18 &&
      kind == CityUnionTransactionKind.consumption &&
      capturedMetro is Map) {
    final id = capturedMetro['id'];
    final isEntry = capturedMetro['isEntry'];
    if (id is String &&
        isEntry is bool &&
        RegExp(r'^[0-9A-F]{46}/[0-9A-F]{46}$').hasMatch(id)) {
      final side = isEntry ? id.substring(0, 46) : id.substring(47);
      if (side == raw.replaceAll(' ', '').toUpperCase()) {
        metro = (id: id, isEntry: isEntry);
      }
    }
  }
  return CuTransactionView(
    record: _CapturedCuRecord(Map.unmodifiable(recordData), sfi, kind),
    transactionTime: millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis as int, isUtc: true),
    regionCode: _optionalString(data['regionCode']),
    carrier: carrier as int?,
    qingdaoMetro: metro,
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
