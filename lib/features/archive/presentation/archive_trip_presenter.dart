import '../../../protocols/transit/tunion/tunion_models.dart';
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

/// Prefer valid same-mode 0x1E observations within each capture, as on the live
/// trip page. Original history/evidence remains intact. A surviving 0x1A record
/// has up to two UI events with its complete context and attribution.
List<TripCardPresentation<ArchiveRecordKind>> presentArchiveTrips(
  List<ArchiveHistoryRecord> records, {
  required void Function(ArchiveHistoryRecord) onDiagnostics,
}) {
  final cycleCaptures = <(String, int)>{};
  for (final record in records) {
    if (record.kind != ArchiveRecordKind.process) continue;
    final mode = record.fields['appTypeCode'];
    final type = record.fields['typeCode'];
    if ((mode != 1 && mode != 2) ||
        type is! int ||
        type == 0 ||
        type == 0xFF ||
        record.fields['time'] is! int) {
      continue;
    }
    for (final source in record.sources) {
      cycleCaptures.add((source.batchId, mode as int));
    }
  }
  final events = <_ArchiveEvent>[];
  for (final record in records) {
    final mode = switch (record.kind) {
      ArchiveRecordKind.rail => 1,
      ArchiveRecordKind.bus => 2,
      _ => null,
    };
    // A merged historical 1A may also belong to an older capture with no 1E.
    // Suppress it only when every attribution is superseded; never erase that
    // earlier independent observation or guess a batch for legacy records.
    if (mode != null &&
        record.sources.isNotEmpty &&
        record.sources.every(
          (s) => cycleCaptures.contains((s.batchId, mode)),
        )) {
      continue;
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
  return [
    for (final (_, event) in indexed)
      TripCardPresentation(
        info: event.info,
        source: event.record.kind,
        mode: event.mode,
        dateText: event.dateText,
        remote: event.remote,
        onDiagnostics: () => onDiagnostics(event.record),
      ),
  ];
}

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
      : TUnionTripRecord(
          typeCode: fields['typeCode'] as int,
          terminalId: fields['terminalId'] as String,
          appTypeCode: fields['appTypeCode'] as int,
          lineStationCode: fields['lineStationCode'] as String,
          amountFen: fields['amountFen'] as int,
          balanceFen: fields['balanceFen'] as int,
          time: DateTime.fromMillisecondsSinceEpoch(
            fields['time'] as int,
            isUtc: true,
          ),
        );

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

  TripEntryInfo get info {
    final cycle = process;
    final isConsume = transaction
        ? fields['consume'] == true
        : cycle != null
        ? !cycle.isEntry && cycle.amountFen > 0
        : !entry;
    final amountKey = side == null || !rail ? 'amountFen' : '${side}AmountFen';
    final balance = amount(
      transaction
          ? 'balanceAfterFen'
          : cycle != null
          ? 'balanceFen'
          : 'entryBalanceFen',
    );
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
      'balanceAfterFen': '交易后余额',
      'balanceFen': '交易后余额',
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
