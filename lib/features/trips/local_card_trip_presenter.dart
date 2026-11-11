import 'dart:typed_data';

import '../../protocols/transit/local/local_card_models.dart';
import 'journey_presentation.dart';
import 'trip_cards_view.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

/// 地方交通卡行程记录来源：按行程流水所在文件区分（与 [TripFile] 的
/// 文件选择子对应）。未识别文件回退 [LocalTripSourceFilter.other]。
enum LocalTripSourceFilter {
  metro,
  bus,
  ferry,
  suxinTx,
  lingnan,
  shenzhen,
  other,
}

/// A local wallet can coexist with TU. Its SFI 0x18 alone does not prove
/// rail travel; only the local parser's explicit mode flag can do that.
enum LocalTripProfile { general, lingnan, shenzhen }

const localTripSourceLabels = <LocalTripSourceFilter, String>{
  LocalTripSourceFilter.metro: '地铁流水',
  LocalTripSourceFilter.bus: '公交流水',
  LocalTripSourceFilter.ferry: '轮渡流水',
  LocalTripSourceFilter.suxinTx: '通行流水',
  LocalTripSourceFilter.lingnan: '岭南通流水',
  LocalTripSourceFilter.shenzhen: '深圳通流水',
  LocalTripSourceFilter.other: '其他文件',
};

/// 按行程记录标志 / 文件选择子映射来源；空白记录回退 [other]。
LocalTripSourceFilter localTripSourceOf(
  ApduRecord record, {
  LocalTripProfile profile = LocalTripProfile.general,
}) {
  if (profile == LocalTripProfile.lingnan) {
    return record.isMetro
        ? LocalTripSourceFilter.metro
        : LocalTripSourceFilter.lingnan;
  }
  if (profile == LocalTripProfile.shenzhen) {
    return LocalTripSourceFilter.shenzhen;
  }
  if (record.isMetro) return LocalTripSourceFilter.metro;
  if (record.isBus) return LocalTripSourceFilter.bus;
  if (record.isFerry) return LocalTripSourceFilter.ferry;
  if (record.isOtherA) return LocalTripSourceFilter.suxinTx;
  if (record.isOtherB) return LocalTripSourceFilter.other;
  if (record.fileSelector == TripFile.metro.p2) {
    return LocalTripSourceFilter.metro;
  }
  if (record.fileSelector == TripFile.bus.p2) {
    return LocalTripSourceFilter.bus;
  }
  if (record.fileSelector == TripFile.ferry.p2) {
    return LocalTripSourceFilter.ferry;
  }
  if (record.fileSelector == TripFile.suxinTx.p2) {
    return LocalTripSourceFilter.suxinTx;
  }
  return LocalTripSourceFilter.other;
}

/// 地方交通卡行程按钮展示文案：消费（balanceDelta<0）/ 充值（>0）/
/// 未知金额变化（0）——不按卡型猜测类型名。
String localTripKindLabel(ApduRecord record) {
  if (record.balanceDelta < 0) return '消费';
  if (record.balanceDelta > 0) return '充值';
  return '交易';
}

/// 地方交通卡行程展示数据：时间 / 金额沿卡内字段口径（分），时钟按
/// 卡片解析时的本地呈现；交易后余额在缺少钱包连续账本证据时不展示
/// （与 CU 行程展示一致，避免把未重建的 0 余额当作真实余额）。
TripCardPresentation<LocalTripSourceFilter> describeLocalTrip(
  ApduRecord record, {
  required String currencySymbol,
  LocalTripProfile profile = LocalTripProfile.general,
  String? cityName,
  bool remote = false,
  String? titlePrefix,
}) {
  final source = localTripSourceOf(record, profile: profile);
  final mode = switch (source) {
    LocalTripSourceFilter.metro => TripModeFilter.rail,
    LocalTripSourceFilter.bus => TripModeFilter.bus,
    LocalTripSourceFilter.ferry ||
    LocalTripSourceFilter.suxinTx ||
    LocalTripSourceFilter.lingnan ||
    LocalTripSourceFilter.shenzhen ||
    LocalTripSourceFilter.other => TripModeFilter.other,
  };
  final amountFen = record.balanceDelta;
  final amountText = amountFen == 0
      ? null
      : '${amountFen < 0 ? '-' : '+'}$currencySymbol'
            '${(amountFen.abs() / 100).toStringAsFixed(2)}';
  final time = _recordTime(
    record.timestamp,
    secondsKnown: profile != LocalTripProfile.lingnan,
  );
  // The LNT year is inferred; its minute must remain a display observation,
  // not a verified instant used to join two independent wallet events.
  final timeLabel = time == null || profile != LocalTripProfile.lingnan
      ? time
      : '$time（年份推断，秒未知）';
  final rawHex = _recordRaw(record);
  final info = TripEntryInfo(
    sourceLabel: localTripSourceLabels[source]!,
    title: [
      if (titlePrefix != null && titlePrefix.isNotEmpty) titlePrefix,
      localTripKindLabel(record),
      '序号 ${record.recordNumber}',
    ].join(' · '),
    timeText: timeLabel,
    amountText: amountText,
    isConsume: amountFen < 0,
    subText: null,
    category: switch (mode) {
      TripModeFilter.rail => '轨道交通',
      TripModeFilter.bus => '公共汽电车',
      TripModeFilter.other => null,
    },
    rawHex: rawHex,
    fields: [
      ('记录类型', localTripKindLabel(record)),
      ('交易序号', '${record.recordNumber}'),
      ('交易时间', timeLabel ?? '未知'),
      if (profile == LocalTripProfile.lingnan) ('时间精度', '年份推断，秒未知'),
      if (amountText != null) ('金额变化', amountText),
      (
        '状态字节',
        '0x${record.statusCode.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      ),
      if (record.terminalHex != null && record.terminalHex!.isNotEmpty)
        ('终端 HEX', record.terminalHex!),
      if (record.cityCode > 0) ('城市代码', record.cityCode.toString()),
      ('来源文件', record.label ?? localTripSourceLabels[source]!),
      if (cityName != null && cityName.isNotEmpty) ('城市', cityName),
    ],
  );
  return TripCardPresentation(
    info: info,
    source: source,
    mode: mode,
    dateText: time == null ? '日期未知' : (time.split(' ').first),
    remote: remote,
    journeyEvent: JourneyEvent(
      payload: info,
      mode: mode,
      role: JourneyEventRole.unknown,
      endpoint: JourneyEndpoint(
        time:
            profile == LocalTripProfile.lingnan ||
                record.timestamp.millisecondsSinceEpoch == 0
            ? null
            : record.timestamp,
        timeText: timeLabel,
      ),
      amountText: amountText,
    ),
  );
}

String? _recordTime(DateTime timestamp, {bool secondsKnown = true}) {
  if (timestamp.millisecondsSinceEpoch == 0) return null;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${timestamp.year}-${two(timestamp.month)}-${two(timestamp.day)} '
      '${two(timestamp.hour)}:${two(timestamp.minute)}'
      '${secondsKnown ? ':${two(timestamp.second)}' : ''}';
}

String? _recordRaw(ApduRecord record) {
  final bytes = record.response ?? record.rawBody;
  if (bytes == null || bytes.isEmpty) return null;
  return bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
}

/// 归档字段 → [ApduRecord]：卡片详情 / 恢复现场用捕获时保存的字段还原
/// 地方卡行程，复用同一票据式展示；无法还原（缺关键字段）返回 null。
ApduRecord? restoreLocalTripRecord(
  Map<String, dynamic> fields, {
  LocalTripProfile profile = LocalTripProfile.general,
}) {
  final recordNumber = fields['recordNumber'];
  final timestamp = fields['timestamp'];
  if (recordNumber is! int || timestamp is! int) return null;
  final raw = fields['rawBody'] ?? fields['response'];
  final record = ApduRecord()
    ..recordNumber = recordNumber
    ..fileSelector = fields['fileSelector'] is int
        ? fields['fileSelector'] as int
        : 0
    ..statusCode = fields['statusCode'] is int ? fields['statusCode'] as int : 0
    ..posType = fields['posType'] is int
        ? fields['posType'] as int
        : fields['subtype'] is int
        ? fields['subtype'] as int
        : 0
    ..balanceDelta = fields['balanceDelta'] is int
        ? fields['balanceDelta'] as int
        : fields['amountDelta'] is int
        ? fields['amountDelta'] as int
        : 0
    ..cityCode = fields['cityCode'] is int ? fields['cityCode'] as int : 0
    ..isMetro = fields['isMetro'] == true
    ..isBus = fields['isBus'] == true
    ..isFerry = fields['isFerry'] == true
    ..isOtherA = fields['isOtherA'] == true
    ..isOtherB = fields['isOtherB'] == true
    ..terminalHex = fields['terminalHex'] is String
        ? fields['terminalHex'] as String
        : null
    ..label = fields['label'] is String ? fields['label'] as String : null;
  record.timestamp = DateTime.fromMillisecondsSinceEpoch(
    timestamp,
    isUtc:
        profile == LocalTripProfile.lingnan || fields['yearInferred'] == true,
  );
  if (raw is List) {
    record.rawBody = Uint8List.fromList(
      raw.map((value) => value is int ? value : 0).toList(),
    );
  }
  return record;
}

LocalTripProfile localTripProfileOf(
  Map<String, dynamic> fields, {
  String? cardType,
}) => switch (fields['profile'] ?? cardType) {
  'lingnan' || 'lingnanTong' => LocalTripProfile.lingnan,
  'shenzhen' || 'shenzhenTong' => LocalTripProfile.shenzhen,
  _ => LocalTripProfile.general,
};
