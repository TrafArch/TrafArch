import '../transit_analysis/tunion_analysis_models.dart';
import '../reference_data/domain/station_codes.dart';
import '../reference_data/data/tunion_bus_location.dart';
import '../transit_analysis/tunion_record_context.dart';
import 'trip_presentation_context.dart';

/// 条目的统一展示数据（卡片与详情弹层共用，避免两处口径不一致）。
class TripEntryInfo {
  final String sourceLabel;
  final String title;
  final String? line;
  final String? timeText;
  final String? amountText;
  final bool isConsume;
  final String? subText;
  final String? category;
  final List<String> badges;
  final String? related;
  final String? rawHex;
  final List<(String, String)> fields;

  /// 异地用卡时的受理城市文本「城市名（城市代码）」；非异地 / 代码缺失为 null。
  final String? remoteCityText;

  const TripEntryInfo({
    required this.sourceLabel,
    required this.title,
    required this.isConsume,
    this.line,
    this.timeText,
    this.amountText,
    this.subText,
    this.category,
    this.badges = const [],
    this.related,
    this.rawHex,
    this.fields = const [],
    this.remoteCityText,
  });

  /// 附加受理城市文本（不改其余字段，供 [describeTripEntry] 统一包装）。
  TripEntryInfo withRemoteCity(String city) => TripEntryInfo(
    sourceLabel: sourceLabel,
    title: title,
    line: line,
    timeText: timeText,
    amountText: amountText,
    isConsume: isConsume,
    subText: subText,
    category: category,
    badges: badges,
    related: related,
    rawHex: rawHex,
    fields: fields,
    remoteCityText: city,
  );
}

/// 条目发生地的城市代码（0x1A 按进 / 出侧取对应城市；异地判定与城市名
/// 解析共用同一口径）。
String? tripCityCode(TripEntry entry) => switch (entry) {
  TransactionTripEntry(:final trip) => trip.cityCode,
  ProcessTripEntry(:final record) => record.cityCode,
  RailRecordEntry(:final record, :final isEntry) =>
    isEntry ? record.entryCityCode : record.exitCityCode,
  BusRecordEntry(:final record, :final isEntry) =>
    isEntry ? record.entryCityCode : record.exitCityCode,
};

/// 行程展示数据：非异地直接返回基础视图；异地时补「城市名（城市代码）」
/// 文本（城市名按当前知识库实时解析，未收录显式「未知城市」，不猜测）。
TripEntryInfo describeTripEntry(
  TripEntry entry,
  TripPresentationContext display, {
  required bool remote,
}) {
  final info = _describeEntry(entry, display);
  if (!remote) return info;
  final code = tripCityCode(entry);
  if (code == null || code.isEmpty) return info;
  return info.withRemoteCity('${display.cityNameOf(code) ?? '未知城市'}（$code）');
}

TripEntryInfo _describeEntry(TripEntry entry, TripPresentationContext display) {
  switch (entry) {
    case TransactionTripEntry(:final trip):
      final badges = <String>[
        switch (trip.stationConfidence) {
          StationMatchConfidence.ambiguous => '站名歧义',
          StationMatchConfidence.unmatched => '未匹配',
          StationMatchConfidence.unavailable => '参考数据不可用',
          _ => '',
        },
      ].where((b) => b.isNotEmpty).toList();
      return TripEntryInfo(
        sourceLabel: '0x18 交易明细',
        title: <String>[
          trip.rideStatusName ?? trip.typeName,
          if (trip.stationLabel != null) trip.stationLabel!,
          '序号 ${trip.sequence}',
        ].join(' · '),
        line: trip.lineLabel,
        timeText: trip.timeText,
        amountText: trip.amountText,
        isConsume: trip.isConsume,
        subText: trip.balanceAfterText == null
            ? null
            : '${trip.balanceAfterLabel} ${trip.balanceAfterText}',
        category: trip.appTypeName,
        badges: badges,
        related: trip.matchedProcessTrip != null
            ? '已与 0x1E 过程记录唯一关联（时间 + 金额 + 终端互证）'
            : '无过程记录关联（独立保留）',
        rawHex: trip.rawHex,
        fields: [
          ('交易类型', trip.typeName),
          ('交易序号', '${trip.sequence}'),
          ('交易时间', trip.timeText),
          ('金额', trip.amountText),
          if (trip.balanceAfterText != null)
            (trip.balanceAfterLabel!, trip.balanceAfterText!),
          ('终端编号', trip.terminalId),
          if (trip.cityCode != null) ('城市代码', trip.cityCode!),
          if (trip.cityName != null) ('城市', trip.cityName!),
          if (trip.location?.lineCode != null)
            ('线路原始编码', trip.location!.lineCode!),
          if (trip.location?.stationCode != null)
            ('站点原始编码', trip.location!.stationCode!),
          if (trip.stationConfidence != null)
            ('站点匹配置信', _stationConfidenceLabel(trip.stationConfidence!)),
          if (trip.appTypeName != null) ('应用分类', trip.appTypeName!),
        ],
      );
    case RailRecordEntry(:final record, :final isEntry):
      final cityCode = isEntry ? record.entryCityCode : record.exitCityCode;
      final rawStation = isEntry ? record.entryStationId : record.exitStationId;
      final rawLineValue = isEntry ? record.entryLineCode : record.exitLineCode;
      final rawLine = rawLineValue?.toString();
      final match = display.resolveStationMatch(
        cityCode,
        rawStation,
        lineValue: rawLineValue,
      );
      final station = match.stationName ?? rawStation;
      final line =
          match.lineName ??
          (rawLineValue == null
              ? display.resolveLineName(cityCode, rawLine)
              : (display.resolveLineName(
                      cityCode,
                      rawLineValue.toRadixString(16).toUpperCase(),
                    ) ??
                    display.resolveLineName(
                      cityCode,
                      rawLineValue.toString(),
                    ) ??
                    rawLine));
      final symbol = display.currency.symbol;
      final amountFen = isEntry ? record.entryAmountFen : record.exitAmountFen;
      final balanceFen = isEntry ? record.entryBalanceFen : null;
      final time = isEntry ? record.entryTime : record.exitTime;
      return TripEntryInfo(
        sourceLabel: '0x1A 轨道记录',
        title: <String>[isEntry ? '进站' : '出站', ?station].join(' · '),
        line: line,
        timeText: time == null ? null : _fmtTime(time),
        amountText: amountFen == null || amountFen <= 0
            ? null
            : '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
        isConsume: (amountFen ?? 0) > 0,
        subText: balanceFen == null
            ? null
            : '余额 $symbol${(balanceFen / 100).toStringAsFixed(2)}',
        category: '城市轨道交通',
        badges: _confidenceBadges(
          match,
          hasRawCode: rawStation != null && rawStation.isNotEmpty,
        ),
        related: '过程记录（未与交易确认重复，独立保留）',
        rawHex: record.rawHex,
        fields: [
          ('交易状态', record.statusName),
          ('进站时间', _fmtOpt(record.entryTime)),
          ('出站时间', _fmtOpt(record.exitTime)),
          ('进闸城市', _fmtOptText(record.entryCityCode)),
          ('出闸城市', _fmtOptText(record.exitCityCode)),
          ('进闸站点（原始）', _fmtOptText(record.entryStationId)),
          ('出闸站点（原始）', _fmtOptText(record.exitStationId)),
          ('进闸终端', _fmtOptText(record.entryTerminalId)),
          ('出闸终端', _fmtOptText(record.exitTerminalId)),
          if (balanceFen != null)
            ('进站时余额', '$symbol${(balanceFen / 100).toStringAsFixed(2)}'),
          if (amountFen != null && amountFen > 0)
            ('本侧金额', '-$symbol${(amountFen / 100).toStringAsFixed(2)}'),
        ],
      );
    case BusRecordEntry(:final record, :final isEntry):
      // 公交独立查完整编码和城市规则，原始字段在详情中保持不变。
      final rawStation = isEntry
          ? record.entryStationCode
          : record.exitStationCode;
      final rawLine = isEntry ? record.entryLineCode : record.exitLineCode;
      final location = display.resolveBusLocation(
        isEntry ? record.entryCityCode : record.exitCityCode,
        busRecordLocationField(
          rawLine,
          rawStation,
          isEntry ? record.entryOperatorCode : record.exitOperatorCode,
        ),
        context: TunionBusDecodeContext(
          transactionTime: isEntry ? record.entryTime : record.exitTime,
          amountFen: isEntry || record.transactionAmountFen == null
              ? null
              : -record.transactionAmountFen!,
        ),
      );
      final station = location.stationLabel ?? rawStation;
      final symbol = display.currency.symbol;
      final amountFen = isEntry ? null : record.transactionAmountFen;
      final mileage = isEntry ? null : record.mileage;
      final time = isEntry ? record.entryTime : record.exitTime;
      return TripEntryInfo(
        sourceLabel: '0x1A 公交记录',
        title: <String>[isEntry ? '上车' : '下车', ?station].join(' · '),
        line: location.lineLabel ?? rawLine,
        timeText: time == null ? null : _fmtTime(time),
        amountText: amountFen == null || amountFen <= 0
            ? null
            : '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
        isConsume: (amountFen ?? 0) > 0,
        subText: mileage == null ? null : '里程 $mileage 站',
        category: '公共汽电车',
        badges: const [],
        related: '过程记录（未与交易确认重复，独立保留）',
        rawHex: record.rawHex,
        fields: [
          ('交易状态', record.statusName),
          ('上车时间', _fmtOpt(record.entryTime)),
          ('下车时间', _fmtOpt(record.exitTime)),
          ('上车城市', _fmtOptText(record.entryCityCode)),
          ('下车城市', _fmtOptText(record.exitCityCode)),
          ('上车站（原始）', _fmtOptText(record.entryStationCode)),
          ('下车站（原始）', _fmtOptText(record.exitStationCode)),
          ('上车线路（原始）', _fmtOptText(record.entryLineCode)),
          ('下车线路（原始）', _fmtOptText(record.exitLineCode)),
          ('上车终端', _fmtOptText(record.entryTerminalId)),
          ('下车终端', _fmtOptText(record.exitTerminalId)),
          ('方向', record.directionName),
        ],
      );
    case ProcessTripEntry(:final record):
      final isBus = isTunionBusCycle(record);
      final busLocation = isBus
          ? display.resolveBusLocation(
              record.cityCode,
              record.lineStationCode,
              context: busContextForCycle(record),
            )
          : null;
      final match = isBus
          ? busLocation!.match
          : display.resolveCycleStationMatch(
              normalizeTunionAcquirerCity(
                record.cityCode,
                rawCity36: cycleCityPair(record, 36),
              ),
              record.lineStationCode,
              terminalId: record.terminalId,
              time: record.time,
              appType: record.appTypeCode,
            );
      final station =
          busLocation?.stationLabel ??
          match.stationName ??
          (isBus ? record.stationCode : null);
      final symbol = display.currency.symbol;
      return TripEntryInfo(
        sourceLabel: '0x1E 过程记录',
        title: <String>[
          record.statusShortName ?? record.typeName,
          ?station,
        ].join(' · '),
        line:
            busLocation?.lineLabel ??
            match.lineName ??
            (isBus ? record.lineCode : null),
        timeText: _fmtTime(record.time),
        amountText: record.amountFen <= 0
            ? null
            : '${record.isRecharge
                  ? '+'
                  : record.isConsume
                  ? '-'
                  : ''}$symbol${(record.amountFen / 100).toStringAsFixed(2)}',
        isConsume: record.isConsume && record.amountFen > 0,
        subText: '记录余额 $symbol${(record.balanceFen / 100).toStringAsFixed(2)}',
        category: record.appTypeLabel,
        badges: isBus ? const [] : _confidenceBadges(match),
        related: '未与 0x18 交易关联，作为独立过程事件保留',
        rawHex: record.rawHex,
        fields: [
          ('过程类型', record.typeName),
          ('应用分类', record.appTypeName),
          ('终端编号', record.terminalId),
          ('线路站点字段（原始）', record.lineStationCode),
          ('金额', '$symbol${(record.amountFen / 100).toStringAsFixed(2)}'),
          ('记录余额', '$symbol${(record.balanceFen / 100).toStringAsFixed(2)}'),
          ('城市代码', _fmtOptText(record.cityCode)),
          ('受理方标识', _fmtOptText(record.acquirerId)),
        ],
      );
  }
}

List<String> _confidenceBadges(StationMatch match, {bool hasRawCode = true}) =>
    [
      if (hasRawCode)
        switch (match.confidence) {
          StationMatchConfidence.ambiguous => '站名歧义',
          StationMatchConfidence.unmatched => '未匹配',
          StationMatchConfidence.unavailable => '参考数据不可用',
          _ => '',
        },
    ].where((b) => b.isNotEmpty).toList();

String _stationConfidenceLabel(StationMatchConfidence c) => switch (c) {
  StationMatchConfidence.exact => '精确匹配',
  StationMatchConfidence.ambiguous => '歧义',
  StationMatchConfidence.unmatched => '未匹配',
  StationMatchConfidence.unavailable => '参考数据不可用',
};
String _fmtTime(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}

String _fmtOpt(DateTime? t) => t == null ? '未写入' : _fmtTime(t);

String _fmtOptText(String? v) => v == null || v.isEmpty ? '未写入' : v;

/// 原始 HEX 按 4 字节分组（逐字节核对用）。
String groupTripHex(String hex) {
  final compact = hex.replaceAll(RegExp(r'\s'), '');
  final parts = <String>[];
  for (var i = 0; i < compact.length; i += 8) {
    parts.add(compact.substring(i, (i + 8).clamp(0, compact.length)));
  }
  return parts.join('  ');
}
