import '../../../protocols/transit/tunion/tunion_models.dart';
import '../../transit_analysis/tunion_analysis_models.dart';
import '../../trips/trip_cards_view.dart';
import '../../trips/trip_entry_presenter.dart';
import '../../trips/trip_filters.dart';
import '../application/archive_history.dart';
import 'archive_record_presenter.dart';

const archiveTripSourceLabels = {
  ArchiveRecordKind.transaction: '0x18 交易',
  ArchiveRecordKind.process: '0x1E 过程',
  ArchiveRecordKind.rail: '0x1A 轨道',
  ArchiveRecordKind.bus: '0x1A 公交',
};

/// Saved-history projection plus the visible record counts. Linked 0x1E records
/// and the matching 0x1A rail record are merged into the 0x18 card; the
/// authoritative history and its raw evidence remain untouched.
class ArchiveTripProjection {
  const ArchiveTripProjection({
    required this.entries,
    required this.transactionCount,
    required this.processRecordCount,
    required this.mergedRecordCount,
  });

  final List<TripCardPresentation<ArchiveRecordKind>> entries;
  final int transactionCount;
  final int processRecordCount;
  final int mergedRecordCount;

  String get summaryText =>
      '交易 $transactionCount 条 · 过程及应用记录 $processRecordCount 条'
      '${mergedRecordCount == 0 ? '' : '（$mergedRecordCount 条已并入 0x18 交易）'}';
}

/// Adapt the authoritative history, without re-merging records or looking up
/// anything in a live scan/reference database. A 0x1A record has up to two UI
/// events; both retain the complete record, captured context and attribution.
ArchiveTripProjection presentArchiveTrips(
  List<ArchiveHistoryRecord> records, {
  required void Function(ArchiveHistoryRecord) onDiagnostics,
}) {
  // Association evidence is stored with the 0x18 record. A linked 0x1E is
  // represented by the 0x18 card; a rail 0x1A is hidden only when one of its
  // sides is proven to be that same process event.
  final mergedProcesses = <TUnionTripRecord>[];
  final mergedRailRecords = <ArchiveHistoryRecord>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.transaction) continue;
    final matched = record.fields['matchedProcess'];
    if (matched is! Map<String, dynamic>) continue;
    final process = _processFromFields(matched);
    if (process == null) continue;
    mergedProcesses.add(process);
    if (record.fields['consume'] != true || !process.isCityRail) continue;
    for (final rail in records) {
      if (rail.kind != ArchiveRecordKind.rail) continue;
      final railRecord = _railFromFields(rail.fields);
      if (railRecord != null && railRecordMatchesProcess(railRecord, process)) {
        mergedRailRecords.add(rail);
      }
    }
  }
  var transactionCount = 0;
  var processRecordCount = 0;
  var mergedRecordCount = 0;
  final events = <_ArchiveEvent>[];
  for (final record in records) {
    if (record.kind == ArchiveRecordKind.rail &&
        mergedRailRecords.contains(record)) {
      mergedRecordCount++;
      continue;
    }
    if (record.kind == ArchiveRecordKind.process) {
      final process = _processFromFields(record.fields);
      if (process != null &&
          mergedProcesses.any(
            (matched) => sameProcessRecord(matched, process),
          )) {
        mergedRecordCount++;
        continue;
      }
      processRecordCount++;
    } else if (record.kind == ArchiveRecordKind.transaction) {
      transactionCount++;
    } else {
      processRecordCount++;
    }
    if (record.kind == ArchiveRecordKind.rail ||
        record.kind == ArchiveRecordKind.bus) {
      final sides = [
        for (final side in ['entry', 'exit'])
          // Amount/code defaults alone do not establish an entry/exit event.
          if (record.fields['${side}Time'] is int) side,
      ];
      if (sides.isEmpty) {
        events.add(_ArchiveEvent(record));
      } else {
        events.addAll(sides.map((side) => _ArchiveEvent(record, side: side)));
      }
    } else {
      events.add(_ArchiveEvent(record));
    }
  }
  // Keep history order on ties, but place each side on its own event date.
  final indexed = events.indexed.toList()
    ..sort((a, b) {
      final time = (b.$2.epoch ?? -8640000000000000).compareTo(
        a.$2.epoch ?? -8640000000000000,
      );
      return time != 0 ? time : a.$1.compareTo(b.$1);
    });
  return ArchiveTripProjection(
    entries: [
      for (final (_, event) in indexed)
        TripCardPresentation(
          info: event.info,
          source: event.record.kind,
          mode: event.mode,
          dateText: event.dateText,
          remote: event.remote,
          onDiagnostics: () => onDiagnostics(event.record),
        ),
    ],
    transactionCount: transactionCount,
    processRecordCount: processRecordCount,
    mergedRecordCount: mergedRecordCount,
  );
}

TUnionTripRecord? _processFromFields(Map<String, dynamic> fields) {
  final typeCode = fields['typeCode'];
  final terminalId = fields['terminalId'];
  final appTypeCode = fields['appTypeCode'];
  final lineStationCode = fields['lineStationCode'];
  final amountFen = fields['amountFen'];
  final balanceFen = fields['balanceFen'];
  final time = fields['time'];
  if (typeCode is! int ||
      terminalId is! String ||
      appTypeCode is! int ||
      lineStationCode is! String ||
      amountFen is! int ||
      balanceFen is! int ||
      time is! int) {
    return null;
  }
  return TUnionTripRecord(
    typeCode: typeCode,
    terminalId: terminalId,
    appTypeCode: appTypeCode,
    lineStationCode: lineStationCode,
    amountFen: amountFen,
    balanceFen: balanceFen,
    time: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
    cityCode: _text(fields['cityCode']),
    acquirerId: _text(fields['acquirerId']),
    rawHex: _text(fields['rawHex']),
  );
}

TransitRecord? _railFromFields(Map<String, dynamic> fields) {
  final status = fields['status'];
  if (status is! int) return null;
  return TransitRecord(
    statusCode: status,
    entryCityCode: _text(fields['entryCityCode']),
    exitCityCode: _text(fields['exitCityCode']),
    entryTerminalId: _text(fields['entryTerminalId']),
    exitTerminalId: _text(fields['exitTerminalId']),
    entryTime: _date(fields['entryTime']),
    exitTime: _date(fields['exitTime']),
    entryAmountFen: fields['entryAmountFen'] is int
        ? fields['entryAmountFen'] as int
        : null,
    exitAmountFen: fields['exitAmountFen'] is int
        ? fields['exitAmountFen'] as int
        : null,
    rawHex: _text(fields['rawHex']),
  );
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? _date(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
    : null;

class _ArchiveEvent {
  const _ArchiveEvent(this.record, {this.side});
  final ArchiveHistoryRecord record;
  final String? side;
  Map<String, dynamic> get fields => record.fields;
  bool get entry => side == 'entry';
  bool get rail => record.kind == ArchiveRecordKind.rail;
  bool get transaction => record.kind == ArchiveRecordKind.transaction;
  String get timeKey => side == null ? 'time' : '${side}Time';
  int? get epoch => fields[timeKey] as int?;

  String? text(String key) {
    final value = fields[key];
    return value == null || value == '' ? null : value.toString();
  }

  TUnionTripRecord? get process => record.kind != ArchiveRecordKind.process
      ? null
      : _processFromFields(fields);

  TripModeFilter get mode {
    if (rail) return TripModeFilter.rail;
    if (record.kind == ArchiveRecordKind.bus) return TripModeFilter.bus;
    final matched = fields['matchedProcess'];
    final appType =
        fields['appTypeCode'] ??
        (matched is Map ? matched['appTypeCode'] : null);
    return switch (fields['appTypeName'] ?? appType) {
      '城市轨道交通' || 1 => TripModeFilter.rail,
      '公共汽电车' || 2 => TripModeFilter.bus,
      _ => TripModeFilter.other,
    };
  }

  String? get city => text(side == null ? 'cityCode' : '${side}CityCode');
  bool get remote {
    final home = record.cardCityCode?.trim().toUpperCase() ?? '';
    final destination = city?.trim().toUpperCase() ?? '';
    return home.replaceAll('0', '').isNotEmpty &&
        destination.replaceAll('0', '').isNotEmpty &&
        home != destination;
  }

  String? timeText(String key) {
    final value = fields[key];
    if (value is! int) return null;
    final captured = fields['capturedTimes'];
    final representation = captured is Map ? captured[key] : null;
    final civil = representation is Map ? representation['civil'] : null;
    if (civil is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(civil)) {
      return '${civil.replaceFirst('T', ' ')}（卡内时间，时区未经核实）';
    }
    return archiveTimeText(value, record.context);
  }

  String get dateText {
    final time = timeText(timeKey);
    return time == null
        ? '日期未知'
        : RegExp(r'^\d{4}-\d{2}-\d{2}').stringMatch(time) ?? '日期未知';
  }

  String? amount(String key, {bool debit = false}) {
    final value = fields[key];
    if (value is! int) return null;
    return '${debit && value > 0 ? '-' : ''}${record.context.formatAmount(value)}';
  }

  String? get balanceAfterText {
    final matched = fields['matchedProcess'];
    final source = transaction && matched is Map<String, dynamic>
        ? _processFromFields(matched)
        : process;
    if (source != null) {
      final balance = source.balanceAfterFen;
      return balance == null ? null : record.context.formatAmount(balance);
    }
    return transaction ? amount('balanceAfterFen') : null;
  }

  TripEntryInfo get info {
    final cycle = process;
    final isConsume = transaction
        ? fields['consume'] == true
        : cycle != null
        ? cycle.isConsume && cycle.amountFen > 0
        : !entry;
    final amountKey = side == null || !rail ? 'amountFen' : '${side}AmountFen';
    final balance = transaction || cycle != null
        ? balanceAfterText
        : amount('entryBalanceFen');
    final station =
        text(side == null ? 'stationLabel' : '${side}StationName') ??
        (side == null ? null : text('${side}Station${rail ? 'Id' : 'Code'}'));
    final status = transaction
        ? text('rideStatusName') ?? text('typeName') ?? '其他'
        : cycle != null
        ? cycle.statusShortName ?? cycle.typeName
        : side != null
        ? (rail ? (entry ? '进站' : '出站') : (entry ? '上车' : '下车'))
        : rail
        ? TransitRecord(statusCode: fields['status'] as int).statusName
        : BusTransitRecord(statusCode: fields['status'] as int).statusName;
    final source = switch (record.kind) {
      ArchiveRecordKind.transaction => '0x18 交易明细',
      ArchiveRecordKind.process => '0x1E 过程记录',
      ArchiveRecordKind.rail => '0x1A 轨道记录',
      ArchiveRecordKind.bus => '0x1A 公交记录',
    };
    final batchCount = record.sources.map((s) => s.batchId).toSet().length;
    return TripEntryInfo(
      sourceLabel: source,
      title: [
        status,
        ?station,
        if (transaction) '序号 ${fields['sequence']}',
      ].join(' · '),
      line:
          text('lineLabel') ??
          text('lineName') ??
          (side == null ? null : text('${side}LineCode')),
      timeText: timeText(timeKey),
      amountText: record.kind == ArchiveRecordKind.bus && entry
          ? null
          : cycle != null && cycle.isRecharge
          ? '+${record.context.formatAmount(cycle.amountFen)}'
          : amount(amountKey, debit: isConsume),
      isConsume: isConsume,
      subText:
          record.kind == ArchiveRecordKind.bus &&
              !entry &&
              fields['mileage'] != null
          ? '里程 ${fields['mileage']} 站'
          : balance == null || (side != null && !entry)
          ? null
          : '余额 $balance',
      category:
          text('appTypeName') ??
          cycle?.appTypeLabel ??
          (mode == TripModeFilter.other ? null : tripModeLabels[mode]),
      badges: [
        if (fields['stationConfidence'] == 'ambiguous') '站名歧义',
        if (fields['stationConfidence'] == 'unmatched' ||
            fields['stationConfidence'] == 'probable')
          '未匹配',
        if (fields['stationConfidence'] == 'unavailable') '参考数据不可用',
      ],
      related:
          '已保存于 $batchCount 个批次'
          '${fields['matchedProcess'] is Map ? ' · 保存时已关联 0x1E 过程记录' : ''}',
      remoteCityText: remote ? '${text('cityName') ?? '未知城市'}（$city）' : null,
      rawHex: text('rawHex'),
      fields: detailFields(cycle),
    );
  }

  List<(String, String)> detailFields(TUnionTripRecord? cycle) => [
    if (cycle != null) ('过程类型', cycle.typeName),
    if (rail)
      ('交易状态', TransitRecord(statusCode: fields['status'] as int).statusName),
    if (record.kind == ArchiveRecordKind.bus)
      (
        '交易状态',
        BusTransitRecord(statusCode: fields['status'] as int).statusName,
      ),
    for (final field in const {
      'typeName': '交易类型',
      'sequence': '交易序号',
      'stationLabel': '站点',
      'lineLabel': '线路',
      'lineName': '线路',
      'terminalId': '终端编号',
      'cityName': '城市',
      'cityCode': '城市代码',
      'appTypeName': '应用分类',
      'entryCityCode': '进入城市',
      'exitCityCode': '离开城市',
      'entryStationName': '进入站点',
      'exitStationName': '离开站点',
      'entryStationId': '进闸站点（原始）',
      'exitStationId': '出闸站点（原始）',
      'entryStationCode': '上车站（原始）',
      'exitStationCode': '下车站（原始）',
      'entryLineCode': '进入线路（原始）',
      'exitLineCode': '离开线路（原始）',
      'entryOperatorCode': '上车运营码',
      'exitOperatorCode': '下车运营码',
      'entryTerminalId': '进入终端',
      'exitTerminalId': '离开终端',
      'lineStationCode': '线路站点字段（原始）',
      'acquirerId': '受理方标识',
    }.entries)
      if (text(field.key) case final value?) (field.value, value),
    for (final field in const {
      'time': '交易时间',
      'entryTime': '进入时间',
      'exitTime': '离开时间',
    }.entries)
      if (timeText(field.key) case final value?) (field.value, value),
    for (final field in const {
      'amountFen': '金额',
      'balanceFen': '记录余额',
      'entryBalanceFen': '进入时余额',
      'entryAmountFen': '进入时金额',
      'exitAmountFen': '离开时金额',
      'transactionAmountFen': '交易金额',
      'annotateAmountFen': '标注金额',
    }.entries)
      if (amount(
            field.key,
            debit:
                transaction &&
                fields['consume'] == true &&
                field.key == 'amountFen',
          )
          case final value?)
        (field.value, value),
    if (balanceAfterText case final balance?) ('交易后余额', balance),
    if (fields['mileage'] case final int mileage) ('里程', '$mileage 站'),
    if (fields['directionCode'] case final int direction)
      (
        '方向',
        BusTransitRecord(statusCode: 0, directionCode: direction).directionName,
      ),
    ('币种', record.context.currencyCode ?? '未知'),
    if (record.context.systemId case final system?) ('卡片系统', system),
    if (record.context.applicationId case final application?)
      ('卡片应用', application),
  ];
}
