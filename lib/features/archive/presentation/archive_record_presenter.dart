import '../domain/archive_context.dart';
import '../application/archive_history.dart';
import '../domain/captured_transaction_balance.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';

/// Shared detail/export text. No resolver may replace captured identifiers or
/// consult the currency of a different active card.
String archiveRecordTitle(ArchiveHistoryRecord record) => switch (record.kind) {
  ArchiveRecordKind.transaction =>
    '0x18 交易 · ${record.fields['rideStatusName'] ?? record.fields['typeName'] ?? '未知'}'
        '${record.fields['stationLabel'] == null ? '' : ' · ${record.fields['stationLabel']}'}'
        '${record.fields['sequence'] == null ? '' : ' · 序号 ${record.fields['sequence']}'}',
  ArchiveRecordKind.rail =>
    '0x1A 轨道 · 状态 ${TransitRecord(statusCode: record.fields['status'] as int).statusName}',
  ArchiveRecordKind.bus =>
    '0x1A 公交 · 状态 ${BusTransitRecord(statusCode: record.fields['status'] as int).statusName}',
  ArchiveRecordKind.process => '0x1E 过程 · 类型 ${record.fields['typeCode']}',
};

/// 按捕获版本展示保存的余额与来源；独立 1E 始终保留原始记录余额。
int? archiveRecordBalanceFen(ArchiveHistoryRecord record) {
  final fields = record.fields;
  if (record.kind == ArchiveRecordKind.process) {
    return fields['balanceFen'] is int ? fields['balanceFen'] as int : null;
  }
  if (record.kind != ArchiveRecordKind.transaction) return null;
  return capturedTransactionBalance(fields, _parseVersion(record)).fen;
}

/// 交易余额是否为过程记录原值；v8 起以捕获时显式保存的来源为准。
bool archiveRecordBalanceIsRecorded(ArchiveHistoryRecord record) {
  if (record.kind != ArchiveRecordKind.transaction) return true;
  return capturedTransactionBalance(
    record.fields,
    _parseVersion(record),
  ).isRecorded;
}

int _parseVersion(ArchiveHistoryRecord record) {
  final sources = record.sources;
  return sources.isEmpty ? 1 : sources.first.capturedParseVersion;
}

String archiveRecordText(ArchiveHistoryRecord record) {
  final fields = record.fields;
  final parts = <String>[];
  final context = record.context;
  void value(String key, String label) {
    if (fields[key] case final value?) {
      final local = record.cardCityCode?.trim().toUpperCase();
      final city = (fields['cityCode'] as String?)?.trim().toUpperCase();
      final remote =
          key == 'cityName' &&
          local != null &&
          city != null &&
          local.replaceAll('0', '').isNotEmpty &&
          city.replaceAll('0', '').isNotEmpty &&
          local != city;
      parts.add('$label $value${remote ? '（异地用卡）' : ''}');
    }
  }

  void amount(String key, String label) {
    if (fields[key] case final int value) {
      final debit =
          key == 'amountFen' && fields['consume'] == true && value > 0;
      parts.add('$label ${debit ? '-' : ''}${context.formatAmount(value)}');
    }
  }

  for (final pair in const {
    'time': '时间',
    'entryTime': '进入',
    'exitTime': '离开',
  }.entries) {
    if (fields[pair.key] case final int time) {
      final captured = fields['capturedTimes'];
      final representation = captured is Map ? captured[pair.key] : null;
      final civil = representation is Map ? representation['civil'] : null;
      final text = civil is String
          ? '${civil.replaceFirst("T", " ")}（捕获的卡内时间，时区未经核实）'
          : archiveTimeText(time, context);
      parts.add('${pair.value} $text');
    }
  }
  value('sequence', '序号');
  amount('amountFen', '金额');
  if (archiveRecordBalanceFen(record) case final balance?) {
    final label = archiveRecordBalanceIsRecorded(record) ? '记录余额' : '交易后余额';
    parts.add('$label ${context.formatAmount(balance)}');
  }
  amount('entryBalanceFen', '进站时余额');
  amount('entryAmountFen', '进入时金额');
  amount('exitAmountFen', '离开时金额');
  amount('transactionAmountFen', '交易金额');
  amount('annotateAmountFen', '标注金额');
  if (fields['mileage'] case final int mileage) parts.add('里程 $mileage 站');
  if (fields['directionCode'] case final int direction) {
    parts.add(
      '方向 ${BusTransitRecord(statusCode: 0, directionCode: direction).directionName}（原码 $direction）',
    );
  }
  for (final pair in const {
    'cityName': '城市',
    'cityCode': '城市码',
    'lineLabel': '线路',
    'stationLabel': '站点',
    'entryCityCode': '进入城市',
    'exitCityCode': '离开城市',
    'entryStationName': '进入站点',
    'exitStationName': '离开站点',
    'entryStationId': '进入站点码',
    'exitStationId': '离开站点码',
    'entryStationCode': '上车站点码',
    'exitStationCode': '下车站点码',
    'entryLineCode': '进入线路码',
    'exitLineCode': '离开线路码',
    'entryOperatorCode': '上车运营码',
    'exitOperatorCode': '下车运营码',
    'lineStationCode': '线路站点原码',
    'terminalId': '终端',
    'entryTerminalId': '进入终端',
    'exitTerminalId': '离开终端',
  }.entries) {
    value(pair.key, pair.value);
  }
  final location = fields['location'];
  if (location is Map<String, dynamic>) {
    for (final key in const [
      'ruleId',
      'cityCode',
      'operatorCode',
      'lineCode',
      'stationCode',
    ]) {
      if (location[key] case final value?) parts.add('$key $value');
    }
  }
  if (fields['stationConfidence'] == 'probable') {
    parts.add('匹配置信度 unmatched（旧值 probable，原文保留）');
  } else {
    value('stationConfidence', '匹配置信度');
  }
  return parts.join(' | ');
}

String archiveTimeText(int epoch, ArchiveContext context) {
  final offset = context.timeZoneOffsetMinutes;
  final DateTime time;
  try {
    time = offset == null
        ? DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(
            epoch,
            isUtc: true,
          ).add(Duration(minutes: offset));
  } on RangeError {
    return '$epoch 毫秒（时区换算超出显示范围，原值保留）';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final text =
      '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  return offset == null
      ? '$text UTC（旧记录仅存时间戳，原始卡内时区未知）'
      : '$text UTC${offset < 0 ? '-' : '+'}${two(offset.abs() ~/ 60)}:${two(offset.abs() % 60)}';
}
