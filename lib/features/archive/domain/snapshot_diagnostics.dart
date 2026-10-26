enum SnapshotDecodeStatus { supported, legacy, partial, unsupported, malformed }

class SnapshotIssue {
  final String path;
  final String message;
  const SnapshotIssue(this.path, this.message);

  @override
  String toString() => '$path: $message';
}

/// Validation is intentionally separate from projection defaults. A bad record
/// remains in the original payload and is reported, never rendered as zero.
bool validateSnapshotRecord(
  Map<String, dynamic> record,
  String kind,
  String path,
  List<SnapshotIssue> issues,
) {
  final before = issues.length;
  final requiredFields = switch (kind) {
    'trips' => const {
      'time',
      'amountFen',
      'sequence',
      'terminalId',
      'consume',
      'typeName',
    },
    'cycle' => const {
      'time',
      'typeCode',
      'terminalId',
      'appTypeCode',
      'lineStationCode',
      'amountFen',
      'balanceFen',
    },
    'rails' || 'buses' => const {'status'},
    'location' => const {'ruleId'},
    _ => const <String>{},
  };
  for (final field in requiredFields) {
    if (record[field] == null) {
      issues.add(SnapshotIssue('$path.$field', '缺少必要字段，原始条目已保留'));
    }
  }
  const integerFields = {
    'time',
    'amountFen',
    'overdraftFen',
    'sequence',
    'balanceAfterFen',
    'status',
    'entryTime',
    'exitTime',
    'entryBalanceFen',
    'entryAmountFen',
    'exitAmountFen',
    'annotateAmountFen',
    'transactionAmountFen',
    'mileage',
    'directionCode',
    'typeCode',
    'appTypeCode',
    'balanceFen',
  };
  const boolFields = {
    'consume',
    'composite',
    'isEntry',
    'hasRecordHeader',
    'balanceAfterIsRecorded',
  };
  const stringFields = {
    'typeName',
    'terminalId',
    'cityName',
    'cityCode',
    'lineLabel',
    'stationLabel',
    'stationType',
    'appTypeName',
    'rideStatusName',
    'currency',
    'rawHex',
    'stationConfidence',
    'entryCityCode',
    'exitCityCode',
    'entryStationId',
    'exitStationId',
    'entryTerminalId',
    'exitTerminalId',
    'entryStationCode',
    'exitStationCode',
    'entryAgencyId',
    'exitAgencyId',
    'issuerCustom',
    'issuerCustomHex',
    'entryOperatorCode',
    'exitOperatorCode',
    'entryVehicleId',
    'exitVehicleId',
    'entryTimeBcd',
    'exitTimeBcd',
    'entryStationName',
    'exitStationName',
    'lineName',
    'lineStationCode',
    'acquirerId',
    'ruleId',
    'ruleNote',
    'operatorCode',
    'lineCode',
    'stationCode',
  };
  for (final entry in record.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value == null) continue;
    final line = key == 'entryLineCode' || key == 'exitLineCode';
    final valid = integerFields.contains(key) || (line && kind == 'rails')
        ? value is int
        : boolFields.contains(key)
        ? value is bool
        : stringFields.contains(key) || line
        ? value is String
        : true;
    if (!valid) issues.add(SnapshotIssue('$path.$key', '字段类型不符，未强制转换'));
    if ((key == 'time' || key == 'entryTime' || key == 'exitTime') &&
        value is int &&
        (value < -8640000000000000 || value > 8640000000000000)) {
      issues.add(SnapshotIssue('$path.$key', '时间超出可表示范围'));
    }
  }
  for (final nested in const {
    'matchedProcess': 'cycle',
    'location': 'location',
  }.entries) {
    final value = record[nested.key];
    if (value == null) continue;
    if (value is! Map<String, dynamic>) {
      issues.add(SnapshotIssue('$path.${nested.key}', '应为对象'));
    } else {
      validateSnapshotRecord(
        value,
        nested.value,
        '$path.${nested.key}',
        issues,
      );
    }
  }
  final confidence = record['stationConfidence'];
  if (confidence != null &&
      !const {
        'exact',
        'ambiguous',
        'unmatched',
        'unavailable',
        'probable',
      }.contains(confidence)) {
    issues.add(SnapshotIssue('$path.stationConfidence', '未知匹配置信度'));
  }
  return before == issues.length;
}

bool validateArchiveContext(
  Map<String, dynamic> value,
  List<SnapshotIssue> issues,
) {
  final before = issues.length;
  for (final key in const [
    'systemId',
    'applicationId',
    'currencyCode',
    'clockBasis',
  ]) {
    if (value[key] != null && value[key] is! String) {
      issues.add(SnapshotIssue('context.$key', '应为字符串或 null'));
    }
  }
  for (final key in const ['minorUnitDigits', 'timeZoneOffsetMinutes']) {
    if (value[key] != null && value[key] is! int) {
      issues.add(SnapshotIssue('context.$key', '应为整数或 null'));
    }
  }
  final offset = value['timeZoneOffsetMinutes'];
  if (offset is int && (offset < -840 || offset > 840)) {
    issues.add(
      const SnapshotIssue('context.timeZoneOffsetMinutes', '时区偏移超出支持范围'),
    );
  }
  final digits = value['minorUnitDigits'];
  if (digits is int && (digits < 0 || digits > 9)) {
    issues.add(const SnapshotIssue('context.minorUnitDigits', '精度超出支持范围'));
  }
  for (final key in const ['referencePackages', 'observedFields']) {
    final field = value[key];
    if (field != null && field is! Map<String, dynamic>) {
      issues.add(SnapshotIssue('context.$key', '应为对象'));
    }
  }
  final observed = value['observedFields'];
  if (observed is Map<String, dynamic> &&
      observed.values.any((v) => v is! bool)) {
    issues.add(
      const SnapshotIssue('context.observedFields', '字段是否观察到必须是 bool'),
    );
  }
  return before == issues.length;
}
