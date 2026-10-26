import 'dart:convert';

import '../../../protocols/transit/city_union/city_union_models.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../../protocols/transit/tunion/tunion_trip_matcher.dart';
import '../data/app_database.dart';
import '../domain/archive_context.dart';
import '../domain/archive_export_options.dart';
import '../domain/card_name_extension.dart';
import '../presentation/archive_record_presenter.dart';
import 'archive_history.dart';
import 'cu_archive_projection.dart';

/// A field-limited document contains no hidden restore payload or identifiers.
class ArchiveRecordsDocument {
  ArchiveRecordsDocument({
    required Set<ArchiveExportField> fields,
    required List<Map<String, dynamic>> records,
    required this.exportedAt,
  }) : fields = Set.unmodifiable(fields),
       records = List.unmodifiable(
         records.map(Map<String, dynamic>.unmodifiable),
       );

  static const format = 'trafarch.records';
  static const version = 1;
  static const maximumBytes = 32 * 1024 * 1024;
  final Set<ArchiveExportField> fields;
  final List<Map<String, dynamic>> records;
  final DateTime exportedAt;
}

String encodeArchiveRecords(
  List<Map<String, dynamic>> records, {
  required Set<ArchiveExportField> fields,
  DateTime? exportedAt,
}) {
  if (fields.isEmpty) throw ArgumentError('请至少选择一个导出字段');
  final ordered = ArchiveExportField.values.where(fields.contains).toList();
  final selected = [
    for (final record in records)
      {for (final field in ordered) field.key: record[field.key]},
  ];
  // Validate field types before encoding; no fallback stringifies an object
  // that could carry private evidence through a selected, seemingly scalar key.
  _validateRows(selected, ordered.map((f) => f.key).toSet());
  final content = const JsonEncoder.withIndent('  ').convert({
    'format': ArchiveRecordsDocument.format,
    'version': ArchiveRecordsDocument.version,
    'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'fields': [for (final field in ordered) field.key],
    'records': selected,
  });
  if (utf8.encode(content).length > ArchiveRecordsDocument.maximumBytes) {
    throw const FormatException('JSON 文件超过 32 MiB，请减少导出的卡片或字段');
  }
  return content;
}

ArchiveRecordsDocument decodeArchiveRecords(String content) {
  if (utf8.encode(content).length > ArchiveRecordsDocument.maximumBytes) {
    throw const FormatException('JSON 文件超过 32 MiB');
  }
  final decoded = jsonDecode(
    content.startsWith('\uFEFF') ? content.substring(1) : content,
  );
  if (decoded is! Map<String, dynamic> ||
      decoded['format'] != ArchiveRecordsDocument.format ||
      decoded['version'] != ArchiveRecordsDocument.version) {
    throw const FormatException('不支持的记录 JSON 格式或版本');
  }
  const keys = {'format', 'version', 'exportedAt', 'fields', 'records'};
  if (decoded.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('记录 JSON 含有未声明的顶层字段');
  }
  final exportedAt = decoded['exportedAt'];
  final time = exportedAt is String ? DateTime.tryParse(exportedAt) : null;
  if (time == null ||
      !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(exportedAt as String)) {
    throw const FormatException('导出时间应为带时区的 ISO 8601 时间');
  }
  final fields = decoded['fields'];
  if (fields is! List || fields.isEmpty) {
    throw const FormatException('记录 JSON 必须声明至少一个字段');
  }
  final selected = <ArchiveExportField>{};
  for (final value in fields) {
    final field = value is String ? ArchiveExportField.fromKey(value) : null;
    if (field == null || !selected.add(field)) {
      throw const FormatException('记录 JSON 含有未知或重复字段');
    }
  }
  final rows = decoded['records'];
  if (rows is! List) throw const FormatException('records 必须是记录数组');
  final names = selected.map((field) => field.key).toSet();
  final checked = _validateRows(rows, names);
  return ArchiveRecordsDocument(
    fields: selected,
    records: checked,
    exportedAt: time,
  );
}

List<Map<String, dynamic>> _validateRows(
  List<dynamic> rows,
  Set<String> fields,
) {
  final checked = <Map<String, dynamic>>[];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    if (row is! Map<String, dynamic> ||
        row.keys.any((key) => !fields.contains(key))) {
      throw FormatException('records[$index] 含有未声明的字段或不是对象');
    }
    if (row.values.any((value) => value != null && value is! String)) {
      throw FormatException('records[$index] 的字段必须为文本或 null；编码和金额不应转换为浮点数');
    }
    checked.add(Map<String, dynamic>.of(row));
  }
  return checked;
}

/// Uses only frozen history. Does not query a current reference package or
/// match new journeys from similar timestamps/POS values.
List<Map<String, dynamic>> projectArchiveRecords(
  List<ArchiveHistoryResult> histories,
) {
  final result = <Map<String, dynamic>>[];
  for (final history in histories) {
    final card = history.card;
    if (card == null) continue;
    final transactions = <ArchiveHistoryRecord, _TransactionRow>{};
    for (final record in history.records) {
      if (record.kind == ArchiveRecordKind.transaction) {
        transactions[record] = _TransactionRow(record, _tuRow(card, record));
      }
    }
    final links = _SavedLinks(transactions.values);
    for (final record in history.records) {
      if (record.kind == ArchiveRecordKind.transaction) {
        result.add(transactions[record]!.row);
        continue;
      }
      if (record.kind == ArchiveRecordKind.process) {
        final process = _process(record.fields);
        final recipients = process == null
            ? null
            : links.consume(record, cycleDisplayKey(process));
        if (recipients != null) {
          for (final recipient in recipients) {
            recipient.addSource('0x1E');
            _copyMissing(recipient.row, _tuRow(card, record), const [
              'entry_time',
              'exit_time',
              'entry_station',
              'exit_station',
              'entry_station_code',
              'exit_station_code',
              'entry_line',
              'exit_line',
              'entry_line_code',
              'exit_line_code',
            ]);
          }
          continue;
        }
        result.add(_tuRow(card, record));
        continue;
      }
      final sides = <String>[
        for (final side in ['entry', 'exit'])
          if (record.fields['${side}Time'] is int) side,
      ];
      final remaining = sides.toSet();
      final original = _tuRow(card, record);
      for (final side in sides) {
        final key = tunionDisplayKey(
          '1A-${record.kind == ArchiveRecordKind.rail ? 'rail' : 'bus'}-${side == 'entry'}',
          DateTime.fromMillisecondsSinceEpoch(
            record.fields['${side}Time'] as int,
            isUtc: true,
          ),
          _text(record.fields['${side}TerminalId']),
          _text(record.fields['rawHex']),
        );
        final recipients = links.consume(record, key);
        if (recipients == null) continue;
        remaining.remove(side);
        for (final recipient in recipients) {
          recipient.addSource('0x1A');
          _copyMissing(recipient.row, original, [
            '${side}_time',
            '${side}_station',
            '${side}_station_code',
            '${side}_line',
            '${side}_line_code',
          ]);
        }
      }
      if (sides.isNotEmpty && remaining.isEmpty) continue;
      for (final side in sides.where((side) => !remaining.contains(side))) {
        for (final field in [
          'time',
          'station',
          'station_code',
          'line',
          'line_code',
        ]) {
          original['${side}_$field'] = null;
        }
      }
      if (sides.contains('exit') && !remaining.contains('exit')) {
        // The linked exit already belongs to a transaction row. Its completed
        // fare must not also appear on the remaining independent entry event.
        original['amount'] = null;
        original['amount_raw'] = null;
      }
      result.add(original);
    }
    final cu = projectCuArchive(history);
    for (final view in cu.transactions) {
      final record = view.record;
      final location = view.location.value;
      final utc = view.transactionTime?.toUtc();
      // The CU projection explicitly interpreted its card civil time at UTC+08.
      final civil = utc?.add(const Duration(hours: 8));
      result.add({
        ..._base(card),
        'record_type': view.kindLabel,
        'source':
            'CU 0x${record.sfi.toRadixString(16).toUpperCase().padLeft(2, '0')}',
        'time': civil == null ? null : '${_civilText(civil)}+08:00',
        'time_basis': utc == null ? 'unknown' : 'UTC+08:00',
        'station': location?.station,
        'station_code': location?.stationCode,
        'line': location?.line,
        'line_code': location?.lineCode,
        'amount_raw': record.amountRaw.toString(),
        'amount_unit': 'unknown',
        'city': view.regionCode,
        'terminal': record.terminalHex,
      });
    }
    // Imported fields remain exactly as captured; a current card label or
    // observation must not silently fill a field omitted by the export owner.
    for (final row in history.importedRecords) {
      result.add({
        for (final field in ArchiveExportField.values)
          if (row.containsKey(field.key)) field.key: row[field.key],
      });
    }
  }
  return result;
}

Map<String, dynamic> _base(SavedCard card) => {
  for (final field in ArchiveExportField.values) field.key: null,
  'card_name': card.displayName,
  'card_number': card.cardNumber,
};

Map<String, dynamic> _tuRow(SavedCard card, ArchiveHistoryRecord record) {
  final fields = record.fields;
  final location = fields['location'];
  final process = record.kind == ArchiveRecordKind.process
      ? _process(fields)
      : _process(fields['matchedProcess']);
  // The saved standard cycle field is seven bytes. Preserve its documented
  // code segments without treating shorter or unfamiliar layouts as codes.
  final codedProcess =
      process != null &&
          RegExp(r'^[0-9A-Fa-f]{14}$').hasMatch(process.lineStationCode)
      ? process
      : null;
  final currency = _text(record.context.currencyCode);
  final scale = record.context.minorUnitDigits;
  final knownMoney =
      currency != null &&
      currency != 'XXX' &&
      currency != 'UNKNOWN' &&
      scale != null &&
      scale >= 0 &&
      scale <= 9;
  final rawAmount =
      fields['amountFen'] ??
      fields['transactionAmountFen'] ??
      fields['exitAmountFen'];
  // TU18 snapshots retain the type label rather than rawType. Only its exact
  // captured recharge label confirms credit; consume:false alone does not.
  final bool? debit = switch (record.kind) {
    ArchiveRecordKind.transaction =>
      fields['consume'] == true
          ? true
          : fields['typeName'] == '充值'
          ? false
          : null,
    ArchiveRecordKind.process =>
      process?.isConsume == true
          ? true
          : process?.isRecharge == true
          ? false
          : null,
    ArchiveRecordKind.rail || ArchiveRecordKind.bus => true,
  };
  final amount = rawAmount is int && debit != null
      ? (debit && rawAmount > 0 ? -rawAmount : rawAmount)
      : null;
  final knownSide = _knownSide(record, process);
  final time = _time(fields, 'time', record.context);
  final row = <String, dynamic>{
    ..._base(card),
    'record_type':
        _text(fields['rideStatusName']) ??
        _text(fields['typeName']) ??
        process?.statusShortName ??
        switch (record.kind) {
          ArchiveRecordKind.transaction => '交易',
          ArchiveRecordKind.process => '过程记录',
          ArchiveRecordKind.rail => '轨道进出站',
          ArchiveRecordKind.bus => '公交上下车',
        },
    'source': record.kind == ArchiveRecordKind.transaction
        ? 'TU 0x18'
        : record.kind == ArchiveRecordKind.process
        ? 'TU 0x1E'
        : 'TU 0x1A',
    'time': time,
    'entry_time': _time(fields, 'entryTime', record.context),
    'exit_time': _time(fields, 'exitTime', record.context),
    'time_basis': _timeBasis(fields, record.context),
    'entry_station': _text(fields['entryStationName']),
    'exit_station': _text(fields['exitStationName']),
    'entry_station_code': _identifier(
      fields['entryStationId'] ?? fields['entryStationCode'],
    ),
    'exit_station_code': _identifier(
      fields['exitStationId'] ?? fields['exitStationCode'],
    ),
    'entry_line': _text(fields['entryLineName']),
    'exit_line': _text(fields['exitLineName']),
    'entry_line_code': _identifier(fields['entryLineCode']),
    'exit_line_code': _identifier(fields['exitLineCode']),
    'station': _text(fields['stationLabel']),
    'station_code':
        (location is Map ? _identifier(location['stationCode']) : null) ??
        codedProcess?.stationCode,
    'line': _text(fields['lineLabel']) ?? _text(fields['lineName']),
    'line_code':
        (location is Map ? _identifier(location['lineCode']) : null) ??
        codedProcess?.lineCode,
    'amount': knownMoney && amount != null && process?.isEntry != true
        ? _decimal(amount, scale)
        : null,
    'amount_raw': rawAmount is int ? rawAmount.toString() : null,
    'amount_unit': knownMoney ? '10^-${scale.toString()} $currency' : 'unknown',
    'currency': currency,
    'balance': knownMoney && archiveRecordBalanceFen(record) != null
        ? _decimal(archiveRecordBalanceFen(record)!, scale)
        : null,
    'city': _text(fields['cityName']) ?? _text(fields['cityCode']),
    'terminal': _text(fields['terminalId']),
  };
  if (knownSide != null) {
    row['${knownSide}_time'] ??= time;
    row['${knownSide}_station'] ??= row['station'];
    row['${knownSide}_station_code'] ??= row['station_code'];
    row['${knownSide}_line'] ??= row['line'];
    row['${knownSide}_line_code'] ??= row['line_code'];
  }
  return row;
}

String? _knownSide(ArchiveHistoryRecord record, TUnionTripRecord? process) {
  final code = process?.typeCode;
  if (code == 1 || code == 3) return 'entry';
  if (code == 2 || code == 4) return 'exit';
  if (record.kind != ArchiveRecordKind.transaction) return null;
  if (record.fields['isEntry'] == true) return 'entry';
  return switch (record.fields['rideStatusName']) {
    '进站' || '上车' || '进场' => 'entry',
    '出站' || '下车' || '出场' => 'exit',
    _ => null,
  };
}

String? _time(Map<String, dynamic> fields, String key, ArchiveContext context) {
  final captured = fields['capturedTimes'];
  final representation = captured is Map ? captured[key] : null;
  final civil = representation is Map ? representation['civil'] : null;
  if (civil is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?$')
          .hasMatch(civil)) {
    return civil;
  }
  final epoch = fields[key];
  if (epoch is! int || epoch < -8640000000000000 || epoch > 8640000000000000) {
    return null;
  }
  final utc = DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
  final offset = context.timeZoneOffsetMinutes;
  if (offset == null) return utc.toIso8601String();
  if (offset < -1440 || offset > 1440) return null;
  final shifted = epoch + offset * 60000;
  if (shifted < -8640000000000000 || shifted > 8640000000000000) return null;
  final local = DateTime.fromMillisecondsSinceEpoch(shifted, isUtc: true);
  return '${_civilText(local)}${_offset(offset)}';
}

String _timeBasis(Map<String, dynamic> fields, ArchiveContext context) {
  final captured = fields['capturedTimes'];
  if (captured is Map &&
      captured.values.any((v) => v is Map && v['civil'] is String)) {
    return 'card_local_unverified';
  }
  if (!['time', 'entryTime', 'exitTime'].any((key) => fields[key] is int)) {
    return 'unknown';
  }
  final offset = context.timeZoneOffsetMinutes;
  return offset == null ? 'stored_epoch_unverified' : 'UTC${_offset(offset)}';
}

String _decimal(int value, int digits) {
  final text = value.toString();
  final magnitude = text.replaceFirst('-', '').padLeft(digits + 1, '0');
  return '${value < 0 ? '-' : ''}${digits == 0 ? magnitude : '${magnitude.substring(0, magnitude.length - digits)}.${magnitude.substring(magnitude.length - digits)}'}';
}

String _civilText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${_two(value.month)}-${_two(value.day)}T${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
String _two(int value) => value.toString().padLeft(2, '0');
String _offset(int minutes) =>
    '${minutes < 0 ? '-' : '+'}${_two(minutes.abs() ~/ 60)}:${_two(minutes.abs() % 60)}';
String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
String? _identifier(Object? value) => value is String
    ? value
    : value is int
    ? value.toString()
    : null;

TUnionTripRecord? _process(Object? raw) {
  if (raw is! Map<String, dynamic> ||
      ![
        'typeCode',
        'appTypeCode',
        'amountFen',
        'balanceFen',
        'time',
      ].every((key) => raw[key] is int) ||
      !['terminalId', 'lineStationCode'].every((key) => raw[key] is String)) {
    return null;
  }
  final epoch = raw['time'] as int;
  if (epoch < -8640000000000000 || epoch > 8640000000000000) return null;
  return TUnionTripRecord(
    typeCode: raw['typeCode'],
    terminalId: raw['terminalId'],
    appTypeCode: raw['appTypeCode'],
    lineStationCode: raw['lineStationCode'],
    amountFen: raw['amountFen'],
    balanceFen: raw['balanceFen'],
    time: DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true),
    rawHex: _text(raw['rawHex']),
  );
}

void _copyMissing(
  Map<String, dynamic> destination,
  Map<String, dynamic> source,
  List<String> keys,
) {
  for (final key in keys) {
    destination[key] ??= source[key];
  }
}

class _TransactionRow {
  _TransactionRow(this.record, this.row);
  final ArchiveHistoryRecord record;
  final Map<String, dynamic> row;
  final linked = <String>{};
  void addSource(String file) {
    linked.add(file);
    row['source'] = 'TU 0x18${linked.map((source) => ' + $source').join()}';
  }
}

class _SavedLinks {
  _SavedLinks(Iterable<_TransactionRow> transactions) {
    for (final transaction in transactions) {
      final fields = transaction.record.fields;
      final keys = <String>[
        if (fields['displayProcessKey'] is String)
          fields['displayProcessKey'] as String,
        if (fields['displayApplicationKey'] is String)
          fields['displayApplicationKey'] as String,
      ];
      final matched = _process(fields['matchedProcess']);
      if (fields['displayProcessKey'] == null && matched != null) {
        keys.add(cycleDisplayKey(matched));
      }
      for (final batch
          in transaction.record.sources
              .map((source) => source.batchId)
              .toSet()) {
        for (final key in keys) {
          (_byBatch.putIfAbsent(batch, () => {}).putIfAbsent(key, () => []))
              .add(transaction);
        }
      }
    }
  }
  final _byBatch = <String, Map<String, List<_TransactionRow>>>{};

  Set<_TransactionRow>? consume(ArchiveHistoryRecord record, String key) {
    final batches = record.sources.map((source) => source.batchId).toSet();
    if (batches.isEmpty ||
        !batches.every((batch) => _byBatch[batch]?[key]?.isNotEmpty == true)) {
      return null;
    }
    return {for (final batch in batches) _byBatch[batch]![key]!.removeAt(0)};
  }
}
