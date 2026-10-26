import '../transit_analysis/tunion_analysis_models.dart';
import '../../protocols/transit/tunion/tunion_models.dart';
import '../../protocols/transit/city_union/city_union_models.dart';

String expertValue(String? v) => v ?? '未知';

String expertDate(DateTime? d) {
  if (d == null) return '未知';
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

String expertTime(DateTime? t) {
  if (t == null) return '未知';
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '${expertDate(t)} $h:$m:$s';
}

String cuRecordSubtitle(CityUnionFileView record) => switch (record) {
  CityUnionWalletTransaction r =>
    '${r.transactionDate ?? '未知日期'} ${r.transactionTime ?? ''} · '
        '${r.transactionTypeName}',
  _ => '${record.rawHex.split(' ').length} 字节 · 未按标准解析',
};

/// City Union 字段展示值：标准解码值优先（缺失回退原始 HEX），
/// 附标准说明与字段级异常；原始字节始终保留在原始数据区。
String cuFieldValue(CjField f) {
  final base = f.decoded ?? f.rawHex;
  final notes = <String>[
    if (f.note != null) f.note!,
    if (f.error != null) f.error!,
  ];
  return notes.isEmpty ? base : '$base（${notes.join('；')}）';
}

String railRecordSubtitle(
  TUnionProcessRecord record, {
  TransitRecord? projected,
}) {
  if (record.isBlank) return '未写入（初始值）';
  final transit = projected ?? record.railTransit;
  if (transit == null) return '${record.raw.length} 字节 · 未解析';
  final (parsed, total) = railFieldProgress(transit);
  if (parsed == 0) return '${record.raw.length} 字节 · 未解析';
  if (parsed == total) return '已解析 · 进出站配对';
  return '部分解析 · $parsed/$total 字段';
}

/// 城市轨道记录已解析字段进度（非空字段数 / 字段总数）；
/// 口径与 [_railTransitFields] 展示字段一致（不含交易状态与发卡机构自定义）。
(int, int) railFieldProgress(TransitRecord rec) {
  final values = <Object?>[
    rec.entryCityCode,
    rec.exitCityCode,
    rec.entryAgencyId,
    rec.exitAgencyId,
    rec.entryStationId,
    rec.exitStationId,
    rec.entryTerminalId,
    rec.exitTerminalId,
    rec.entryTime ?? rec.entryTimeBcd,
    rec.exitTime ?? rec.exitTimeBcd,
    rec.annotateAmountFen,
    rec.entryLineCode,
    rec.exitLineCode,
    rec.entryAmountFen,
    rec.entryBalanceFen,
    rec.exitAmountFen,
  ];
  return (values.where((v) => v != null).length, values.length);
}

String busRecordSubtitle(TUnionProcessRecord record) {
  if (record.isBlank) return '未写入（初始值）';
  final bus = record.busTransit;
  if (bus == null) return '${record.raw.length} 字节 · 未解析';
  final (parsed, total) = busFieldProgress(bus);
  if (parsed == 0) return '${record.raw.length} 字节 · 未解析';
  if (parsed == total) return '已解析 · 上下车配对';
  return '部分解析 · $parsed/$total 字段';
}

/// 公共汽电车记录已解析字段进度（非空字段数 / 字段总数）；
/// 口径与 [_busTransitFields] 展示字段一致（不含交易状态与发卡机构自定义）。
(int, int) busFieldProgress(BusTransitRecord rec) {
  final values = <Object?>[
    rec.entryCityCode,
    rec.entryAgencyId,
    rec.entryOperatorCode,
    rec.entryLineCode,
    rec.entryStationCode,
    rec.entryVehicleId,
    rec.entryTerminalId,
    rec.entryTime ?? rec.entryTimeBcd,
    rec.annotateAmountFen,
    rec.directionCode,
    rec.exitCityCode,
    rec.exitAgencyId,
    rec.exitOperatorCode,
    rec.exitLineCode,
    rec.exitStationCode,
    rec.exitVehicleId,
    rec.exitTerminalId,
    rec.exitTime ?? rec.exitTimeBcd,
    rec.transactionAmountFen,
    rec.mileage,
  ];
  return (values.where((v) => v != null).length, values.length);
}

String hexByte(int v) => v.toRadixString(16).padLeft(2, '0').toLowerCase();

/// 代码 + 名称拼接（代码为卡片上报值，小写）；名称未知时仅保留"未知(0xXX)"。
String codeName(int code, String name) =>
    name.startsWith('未知') ? name : '${hexByte(code)}：$name';
String hexLower(String? v) => (v == null || v.isEmpty) ? '未知' : v.toLowerCase();

/// 1 字节值（两位小写 HEX）；缺省为"未知"。
String hexByteCell(int? v) => v == null ? '未知' : hexByte(v);

String intHexCell(int? v, {int width = 4}) {
  if (v == null) return '未知';
  final hex = v.toRadixString(16).padLeft(width, '0').toLowerCase();
  return '($hex)$v';
}

/// 时间 `yyyy/MM/dd HH:mm:ss`；DateTime 缺失时按 BCD 原始位排布
/// （如未写入的零值显示 0000/00/00 00:00:00）。
String bcdTimeCell(DateTime? t, String? bcd) {
  final digits = t != null
      ? '${t.year.toString().padLeft(4, '0')}'
            '${t.month.toString().padLeft(2, '0')}'
            '${t.day.toString().padLeft(2, '0')}'
            '${t.hour.toString().padLeft(2, '0')}'
            '${t.minute.toString().padLeft(2, '0')}'
            '${t.second.toString().padLeft(2, '0')}'
      : bcd;
  if (digits == null || digits.length != 14) return '未知';
  return '${digits.substring(0, 4)}/${digits.substring(4, 6)}/'
      '${digits.substring(6, 8)} '
      '${digits.substring(8, 10)}:${digits.substring(10, 12)}:'
      '${digits.substring(12, 14)}';
}

/// `yyyyMMddHHmmss`（0x1E 交易日期时间输出格式）。
String dateTimeDigits(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}'
    '${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}'
    '${t.hour.toString().padLeft(2, '0')}'
    '${t.minute.toString().padLeft(2, '0')}'
    '${t.second.toString().padLeft(2, '0')}';
String terminalDecodeText(TransitTrip? trip) {
  if (trip == null) return '未知';
  final loc = trip.location;
  if (loc == null) return '未匹配解码规则（终端 ${trip.terminalId}）';
  final cityCode = loc.cityCode ?? '-';
  final city = trip.cityName == null ? cityCode : '$cityCode（${trip.cityName}）';
  return '城市 $city / 线路 ${trip.lineLabel ?? loc.lineCode ?? '-'} / '
      '站点 ${trip.stationLabel ?? loc.stationCode ?? '-'}（规则 ${loc.ruleId}）';
}

String daysRemainingText(int? days) {
  if (days == null) return '未知';
  return days < 0 ? '已过期 ${-days} 天' : '$days 天';
}

String hexBytes(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// The formatter knows the captured currency and a namespace-specific lookup.
class ExpertValues {
  const ExpertValues({required this.currency, required this.cityNameOf});
  final Currency currency;
  final String? Function(String?) cityNameOf;
  String cityCell(String? code) {
    if (code == null || code.isEmpty) return '未知';
    return '(${code.toLowerCase()})'
        '${cityNameOf(code) ?? '未知城市'}';
  }

  String amountCell(int? fen) {
    if (fen == null) return '未知';
    final hex = fen.toRadixString(16).padLeft(8, '0').toLowerCase();
    return '($hex)${(fen / 100).toString()}${currency.unit}';
  }

  String processRecordSubtitle(TUnionProcessRecord r) {
    final trip = r.trip;
    if (trip != null) {
      return '${dateTimeDigits(trip.time)} · '
          '${(trip.amountFen / 100).toStringAsFixed(2)} '
          '${currency.unit}';
    }
    return '${r.raw.length} 字节 · 未解码为字段';
  }
}
