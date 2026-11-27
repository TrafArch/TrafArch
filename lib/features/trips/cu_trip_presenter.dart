import '../../protocols/transit/city_union/city_union_models.dart';
import '../reference_data/data/city_union_lookup_rules.dart';
import '../reference_data/domain/reference_match.dart';
import '../transit_analysis/cu_transaction_analysis.dart';
import 'journey_presentation.dart';
import 'trip_card_presentation.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

enum CuTripSourceFilter {
  transaction,
  recharge,
  shanghaiForeign,
  foreign,
  other,
}

const cuTripSourceLabels = {
  CuTripSourceFilter.transaction: '0x18 交易',
  CuTripSourceFilter.recharge: '0x10 充值',
  CuTripSourceFilter.shanghaiForeign: '0x06 交易',
  CuTripSourceFilter.foreign: '0x1A 交易',
  CuTripSourceFilter.other: '其他文件',
};

List<TripCardPresentation<CuTripSourceFilter>> describeCuTrips(
  List<CuTransactionView> transactions, {
  String? Function(String?)? cityNameOf,
  bool Function(CuTransactionView)? isRemote,
  Map<CuTransactionView, String> sourceLabels = const {},
  String currencySymbol = '¥',
}) {
  final links = completeQingdaoMetroLinks(transactions);
  return [
    for (final transaction in transactions)
      describeCuTrip(
        transaction,
        cityName: cityNameOf?.call(transaction.regionCode),
        remote: isRemote?.call(transaction) ?? false,
        savedSource: sourceLabels[transaction],
        currencySymbol: currencySymbol,
        showQingdaoMetroLink: links.contains(transaction.qingdaoMetro?.id),
      ),
  ];
}

/// Adapts CU's own captured observations to the shared trip UI. A terminal's
/// carrier establishes the mode, never entry/exit direction or a fare unit.
TripCardPresentation<CuTripSourceFilter> describeCuTrip(
  CuTransactionView transaction, {
  String? cityName,
  bool remote = false,
  String? savedSource,
  String currencySymbol = '¥',
  bool showQingdaoMetroLink = true,
}) {
  final record = transaction.record;
  final isRecharge = record.kind == CityUnionTransactionKind.recharge;
  final metro = showQingdaoMetroLink && !isRecharge
      ? transaction.qingdaoMetro
      : null;
  final location = metro == null ? transaction.location.value : null;
  final kind =
      CityUnionLookupRules.presentation(transaction.carrier)?.$1 ??
      location?.kind;
  final mode = metro != null
      ? TripModeFilter.rail
      : isRecharge
      ? TripModeFilter.other
      : switch (kind) {
          'bus' || 'custom_bus' || 'brt' => TripModeFilter.bus,
          'metro' || 'rail' || 'maglev' || 'tram' => TripModeFilter.rail,
          _ => TripModeFilter.other,
        };
  final line = isRecharge
      ? null
      : mode == TripModeFilter.bus
      ? formatJourneyBusLine(location?.line)
      : location?.line;
  final city =
      cityName ??
      (transaction.regionCode == null ? null : '地区 ${transaction.regionCode}');
  final amountText = transaction.amountText(symbol: currencySymbol);
  final info = TripEntryInfo(
    sourceLabel: transaction.sourceLabel,
    title: isRecharge
        ? '充值'
        : '${metro == null ? transaction.kindLabel : (metro.isEntry ? '进站' : '出站')} · '
              '${metro == null ? transaction.locationLabel : '站点未记录'} · '
              '序号 ${record.sequence}',
    line: line,
    timeText: transaction.timeLabel,
    amountText: amountText ?? '金额未知',
    isConsume: !isRecharge,
    isRecharge: isRecharge,
    category: metro == null && !isRecharge
        ? CityUnionLookupRules.presentation(transaction.carrier)?.$2
        : null,
    badges: metro != null
        ? const []
        : switch (transaction.location.status) {
            ReferenceMatchStatus.ambiguous => const ['站名歧义'],
            ReferenceMatchStatus.unavailable => const ['参考数据不可用'],
            ReferenceMatchStatus.unknown => const ['未匹配'],
            ReferenceMatchStatus.matched => const [],
          },
    remoteCityText: metro == null && remote
        ? '${cityName ?? '未知城市'}（${transaction.regionCode}）'
        : null,
    rawHex: record.rawHex,
    fields: [
      if (savedSource != null) ('保存来源', savedSource),
      ('记录类型', transaction.kindLabel),
      ('交易序号', '${record.sequence}'),
      ('交易时间', transaction.timeLabel),
      if (metro != null) ('地铁时刻依据', '琴岛通 0x19 第 ${metro.isEntry ? 3 : 7} 槽'),
      ('地点', metro == null ? transaction.locationLabel : '站点未记录'),
      ('终端原始编码', record.terminalHex ?? '未知'),
      if (metro == null && transaction.regionCode != null)
        ('受理地区代码', transaction.regionCode!),
      if (location?.lineCode case final code?) ('线路原始编码', code),
      if (location?.stationCode case final code?) ('站点原始编码', code),
      (
        '交易类型',
        '0x${record.transactionType.toRadixString(16).toUpperCase().padLeft(2, '0')}'
            ' · ${record.transactionTypeName}',
      ),
      ('交易金额', amountText ?? '未知'),
      ('金额原始字段', record.amountHex),
      ('金额四字节原始值', '${record.amountRaw}'),
      if (metro == null && transaction.location.issue != null)
        ('地点诊断', transaction.location.issue!),
      for (final error in record.errors) ('解析诊断', error),
    ],
  );
  return TripCardPresentation(
    info: info,
    source: switch (record.sfi) {
      0x18 => CuTripSourceFilter.transaction,
      0x10 => CuTripSourceFilter.recharge,
      0x06 => CuTripSourceFilter.shanghaiForeign,
      0x1A => CuTripSourceFilter.foreign,
      _ => CuTripSourceFilter.other,
    },
    mode: mode,
    dateText: record.transactionDate ?? '日期未知',
    remote: metro == null && remote,
    journeyEvent: JourneyEvent(
      payload: info,
      mode: mode,
      role: metro == null
          ? JourneyEventRole.unknown
          : metro.isEntry
          ? JourneyEventRole.entry
          : JourneyEventRole.exit,
      cityCode: metro == null ? transaction.regionCode : '4520',
      cityLabel: metro == null ? city : '青岛',
      scopeKey: metro?.id,
      sourceIds: metro == null ? const {} : {metro.id},
      applicationRecordId: metro?.id,
      endpoint: JourneyEndpoint(
        line: line,
        station: metro != null
            ? null
            : location?.station ??
                  (location == null ? transaction.locationLabel : null),
        // CU stores a UTC instant separately from its original civil clock.
        // Use the captured clock for tickets, independent of the phone zone.
        time: transaction.transactionTime
            ?.add(const Duration(hours: 8))
            .toUtc(),
        timeText: transaction.timeLabel,
      ),
      amountText: amountText,
    ),
  );
}
