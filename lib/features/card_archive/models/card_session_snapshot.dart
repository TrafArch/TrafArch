// 新建文件：lib/features/card_archive/models/card_session_snapshot.dart
import 'dart:convert';

import '../../../core/analysis/tunion_analysis_models.dart';
import '../../../core/transit/tunion/tunion_models.dart';

/// 卡片最近一次读取的行程记录快照（随卡片档案持久化）。
///
/// 卡片详情页在当前会话读取的正是该卡片时直接消费 AppState 的实时解析
/// 结果；读取其他卡片后改为消费本快照（保存该卡片时写入），保证已读取过
/// 的行程记录不会因读取新卡片而消失。
class CardSessionSnapshot {
  /// 读取时刻的卡片城市代码（发卡地识别优先，回退卡片管理信息城市代码）；
  /// 用于异地用卡判定，无法判定时为 null。
  final String? cardCityCode;

  /// 本次读取解析出的交易行程（0x18 明细 + 0x1E / 0x1A 配对结果）。
  final List<TransitTrip> trips;

  /// 本次读取解析出的 0x1A 记录 1（城市轨道进出站记录）。
  final TransitRecord? railRecord;

  /// 本次读取解析出的 0x1A 记录 2（公共汽电车上下车记录）。
  final BusTransitRecord? busRecord;

  const CardSessionSnapshot({
    this.cardCityCode,
    this.trips = const [],
    this.railRecord,
    this.busRecord,
  });

  /// 是否不含任何记录数据（无需写入档案，也不会覆盖既有快照）。
  bool get isEmpty => trips.isEmpty && railRecord == null && busRecord == null;

  /// [code] 是否与卡片城市不同（异地用卡判定，与 AppState.isRemoteUse
  /// 同一口径：城市不可判定或未写入（空 / 全 0）时不判定，返回 false）。
  bool isRemoteUse(String? code) {
    final local = cardCityCode;
    if (local == null || code == null) return false;
    final a = local.trim().toUpperCase();
    final b = code.trim().toUpperCase();
    if (_isUnsetCityCode(a) || _isUnsetCityCode(b)) return false;
    return a != b;
  }

  static bool _isUnsetCityCode(String code) =>
      code.isEmpty || code.replaceAll('0', '').isEmpty;

  /// 序列化为 JSON 字符串（字段保持展示所需最小集合，不存原始字节）。
  String encode() => jsonEncode({
        'cityCode': cardCityCode,
        'trips': [for (final t in trips) _tripToJson(t)],
        'rail': railRecord == null ? null : _railToJson(railRecord!),
        'bus': busRecord == null ? null : _busToJson(busRecord!),
      });

  /// 解码快照；JSON 损坏或结构不符时返回 null（详情页回退不展示记录）。
  static CardSessionSnapshot? decode(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final trips = data['trips'];
      final rail = data['rail'];
      final bus = data['bus'];
      return CardSessionSnapshot(
        cardCityCode: _str(data['cityCode']),
        trips: [
          if (trips is List)
            for (final item in trips)
              if (item is Map<String, dynamic>) _tripFromJson(item),
        ],
        railRecord: rail is Map<String, dynamic> ? _railFromJson(rail) : null,
        busRecord: bus is Map<String, dynamic> ? _busFromJson(bus) : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _tripToJson(TransitTrip t) => {
        'time': t.time.millisecondsSinceEpoch,
        'amountFen': t.amountFen,
        'overdraftFen': t.overdraftLimitFen,
        'consume': t.isConsume,
        'typeName': t.typeName,
        'sequence': t.sequence,
        'terminalId': t.terminalId,
        'cityName': t.cityName,
        'cityCode': t.cityCode,
        'lineLabel': t.lineLabel,
        'stationLabel': t.stationLabel,
        'stationType': t.stationType,
        'appTypeName': t.appTypeName,
        'balanceAfterFen': t.balanceAfterFen,
        'rideStatusName': t.rideStatusName,
        'isEntry': t.isEntry,
        'currency': t.currency.code,
      };

  static TransitTrip _tripFromJson(Map<String, dynamic> m) => TransitTrip(
        time: DateTime.fromMillisecondsSinceEpoch(_int(m['time']) ?? 0),
        amountFen: _int(m['amountFen']) ?? 0,
        overdraftLimitFen: _int(m['overdraftFen']) ?? 0,
        isConsume: m['consume'] == true,
        typeName: _str(m['typeName']) ?? '其他',
        sequence: _int(m['sequence']) ?? 0,
        terminalId: _str(m['terminalId']) ?? '',
        cityName: _str(m['cityName']),
        cityCode: _str(m['cityCode']),
        lineLabel: _str(m['lineLabel']),
        stationLabel: _str(m['stationLabel']),
        stationType: _str(m['stationType']),
        appTypeName: _str(m['appTypeName']),
        balanceAfterFen: _int(m['balanceAfterFen']),
        rideStatusName: _str(m['rideStatusName']),
        isEntry: m['isEntry'] == true,
        currency: Currency.fromCode(_str(m['currency'])),
      );

  static Map<String, dynamic> _railToJson(TransitRecord r) => {
        'status': r.statusCode,
        'entryCityCode': r.entryCityCode,
        'exitCityCode': r.exitCityCode,
        'entryStationId': r.entryStationId,
        'exitStationId': r.exitStationId,
        'entryTime': r.entryTime?.millisecondsSinceEpoch,
        'exitTime': r.exitTime?.millisecondsSinceEpoch,
        'entryBalanceFen': r.entryBalanceFen,
        'exitAmountFen': r.exitAmountFen,
      };

  static TransitRecord _railFromJson(Map<String, dynamic> m) => TransitRecord(
        statusCode: _int(m['status']) ?? 0,
        entryCityCode: _str(m['entryCityCode']),
        exitCityCode: _str(m['exitCityCode']),
        entryStationId: _str(m['entryStationId']),
        exitStationId: _str(m['exitStationId']),
        entryTime: _date(m['entryTime']),
        exitTime: _date(m['exitTime']),
        entryBalanceFen: _int(m['entryBalanceFen']),
        exitAmountFen: _int(m['exitAmountFen']),
      );

  static Map<String, dynamic> _busToJson(BusTransitRecord r) => {
        'status': r.statusCode,
        'entryCityCode': r.entryCityCode,
        'exitCityCode': r.exitCityCode,
        'entryStationCode': r.entryStationCode,
        'exitStationCode': r.exitStationCode,
        'entryTime': r.entryTime?.millisecondsSinceEpoch,
        'exitTime': r.exitTime?.millisecondsSinceEpoch,
        'amountFen': r.transactionAmountFen,
        'mileage': r.mileage,
        'directionCode': r.directionCode,
      };

  static BusTransitRecord _busFromJson(Map<String, dynamic> m) =>
      BusTransitRecord(
        statusCode: _int(m['status']) ?? 0,
        entryCityCode: _str(m['entryCityCode']),
        exitCityCode: _str(m['exitCityCode']),
        entryStationCode: _str(m['entryStationCode']),
        exitStationCode: _str(m['exitStationCode']),
        entryTime: _date(m['entryTime']),
        exitTime: _date(m['exitTime']),
        transactionAmountFen: _int(m['amountFen']),
        mileage: _int(m['mileage']),
        directionCode: _int(m['directionCode']),
      );

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  static DateTime? _date(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
}