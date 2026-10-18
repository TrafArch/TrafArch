// 新建文件：lib/features/card_archive/models/card_session_snapshot.dart
import 'dart:convert';

import '../../../core/analysis/tunion_analysis_models.dart';
import '../../../core/data/station_codes.dart';
import '../../../core/transit/tunion/tunion_models.dart';

/// 卡片读取行程记录快照（随卡片档案与读取批次持久化，v2）。
///
/// v2 升级（历史存储）：
/// - 完整保存 0x1E 过程记录集合与 0x1A 记录集合（含原始 HEX），
///   不再只保存最近一次单条展示快照；批次经 [mergeHistories] 按记录
///   身份累积去重，新读取追加批次、不覆盖旧数据；
/// - 交易条目随快照保存原始 HEX、站点匹配置信与配对的 0x1E 记录
///   （关联证据入档，历史展示仍可"逐条关联、确认重复才合并"）；
/// - [parseVersion] 记录产出批次的解析口径版本（[kTripParseVersion]），
///   站点 / 线路名称在展示时始终按当前知识库实时重解。
class CardSessionSnapshot {
  static const currentFormatVersion = 2;

  final int formatVersion;

  /// 产出本快照的解析口径版本（重解析依据）。
  final int parseVersion;

  /// 读取时刻的卡片城市代码（发卡地识别优先，回退管理信息城市代码）。
  final String? cardCityCode;

  /// 本次读取解析出的交易行程（0x18 明细 + 0x1E / 0x1A 配对结果）。
  final List<TransitTrip> trips;

  /// 本次读取解析出的 0x1A 记录 1（城市轨道进出站记录）集合。
  final List<TransitRecord> rails;

  /// 本次读取解析出的 0x1A 记录 2（公共汽电车上下车记录）集合。
  final List<BusTransitRecord> buses;

  /// 本次读取解析出的 0x1E 循环过程记录集合（含未关联的独立事件）。
  final List<TUnionTripRecord> processTrips;

  const CardSessionSnapshot({
    this.formatVersion = currentFormatVersion,
    this.parseVersion = 1,
    this.cardCityCode,
    this.trips = const [],
    this.rails = const [],
    this.buses = const [],
    this.processTrips = const [],
  });

  /// 兼容旧调用点（导出等）：最近一条 0x1A 记录 1 / 记录 2。
  TransitRecord? get railRecord => rails.isEmpty ? null : rails.first;
  BusTransitRecord? get busRecord => buses.isEmpty ? null : buses.first;

  /// 是否不含任何记录数据（无需写入档案，也不会覆盖既有快照 / 批次）。
  bool get isEmpty =>
      trips.isEmpty && rails.isEmpty && buses.isEmpty && processTrips.isEmpty;

  /// [code] 是否与卡片城市不同（异地用卡判定，不可判定时不判定）。
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

  /// 序列化为 JSON 字符串（v2：原始 HEX + 关联证据 + 解析版本）。
  String encode() => jsonEncode({
        'v': formatVersion,
        'parseVersion': parseVersion,
        'cityCode': cardCityCode,
        'trips': [for (final t in trips) _tripToJson(t)],
        'rails': [for (final r in rails) _railToJson(r)],
        'buses': [for (final b in buses) _busToJson(b)],
        'cycle': [for (final p in processTrips) _cycleToJson(p)],
      });

  /// 解码快照；JSON 损坏或结构不符时返回 null（页面回退不展示记录）。
  /// 兼容 v1（仅单条 rail/bus、无 1E 集合与原始 HEX 的旧档案）。
  static CardSessionSnapshot? decode(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final version = _int(data['v']) ?? 1;
      if (version < 2) {
        final rail = data['rail'];
        final bus = data['bus'];
        return CardSessionSnapshot(
          formatVersion: currentFormatVersion,
          parseVersion: 1,
          cardCityCode: _str(data['cityCode']),
          trips: _list(data['trips'], _tripFromJson),
          rails: rail is Map<String, dynamic>
              ? _list([rail], _railFromJson)
              : const [],
          buses:
              bus is Map<String, dynamic> ? _list([bus], _busFromJson) : const [],
        );
      }
      return CardSessionSnapshot(
        formatVersion: currentFormatVersion,
        parseVersion: _int(data['parseVersion']) ?? 1,
        cardCityCode: _str(data['cityCode']),
        trips: _list(data['trips'], _tripFromJson),
        rails: _list(data['rails'], _railFromJson),
        buses: _list(data['buses'], _busFromJson),
        processTrips: _list(data['cycle'], _cycleFromJson),
      );
    } catch (_) {
      return null;
    }
  }

  /// 历史批次合并：多份快照按记录身份累积去重（交易按 序号+时间+金额+
  /// 终端，0x1A 按 时间+站点+终端，0x1E 按 原始 HEX / 四要素），
  /// 先入池的批次（较新读取）优先保留，供详情页历史累积展示。
  static CardSessionSnapshot mergeHistories(List<CardSessionSnapshot> histories) {
    final tripsById = <String, TransitTrip>{};
    final railsById = <String, TransitRecord>{};
    final busesById = <String, BusTransitRecord>{};
    final cyclesById = <String, TUnionTripRecord>{};
    String? cityCode;
    var maxParseVersion = 1;
    for (final h in histories) {
      cityCode ??= h.cardCityCode;
      if (h.parseVersion > maxParseVersion) maxParseVersion = h.parseVersion;
      for (final t in h.trips) {
        tripsById.putIfAbsent(_tripKey(t), () => t);
      }
      for (final r in h.rails) {
        railsById.putIfAbsent(_railKey(r), () => r);
      }
      for (final b in h.buses) {
        busesById.putIfAbsent(_busKey(b), () => b);
      }
      for (final p in h.processTrips) {
        cyclesById.putIfAbsent(_cycleKey(p), () => p);
      }
    }
    final trips = tripsById.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    final rails = railsById.values.toList()
      ..sort((a, b) => (_railTime(b)).compareTo(_railTime(a)));
    final buses = busesById.values.toList()
      ..sort((a, b) => (_busTime(b)).compareTo(_busTime(a)));
    final cycles = cyclesById.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return CardSessionSnapshot(
      cardCityCode: cityCode,
      parseVersion: maxParseVersion,
      trips: trips,
      rails: rails,
      buses: buses,
      processTrips: cycles,
    );
  }

  static DateTime _railTime(TransitRecord r) =>
      r.exitTime ?? r.entryTime ?? DateTime(0);

  static DateTime _busTime(BusTransitRecord r) =>
      r.exitTime ?? r.entryTime ?? DateTime(0);

  static String _tripKey(TransitTrip t) =>
      '${t.sequence}|${t.time.millisecondsSinceEpoch}|${t.amountFen}|${t.terminalId}';

  static String _railKey(TransitRecord r) =>
      '${r.entryTime?.millisecondsSinceEpoch}|${r.exitTime?.millisecondsSinceEpoch}|${r.entryStationId}|${r.exitStationId}|${r.entryTerminalId}';

  static String _busKey(BusTransitRecord r) =>
      '${r.entryTime?.millisecondsSinceEpoch}|${r.exitTime?.millisecondsSinceEpoch}|${r.entryStationCode}|${r.exitStationCode}|${r.entryTerminalId}';

  static String _cycleKey(TUnionTripRecord p) =>
      p.rawHex ??
      '${p.typeCode}|${p.time.millisecondsSinceEpoch}|${p.amountFen}|${p.terminalId}';

  static List<T> _list<T>(
    Object? src,
    T? Function(Map<String, dynamic>) conv,
  ) {
    if (src is! List) return const [];
    final out = <T>[];
    for (final item in src) {
      if (item is Map<String, dynamic>) {
        final value = conv(item);
        if (value != null) out.add(value);
      }
    }
    return out;
  }

  static Map<String, dynamic> _tripToJson(TransitTrip t) => {
        'time': t.time.millisecondsSinceEpoch,
        'amountFen': t.amountFen,
        'overdraftFen': t.overdraftLimitFen,
        'consume': t.isConsume,
        'typeName': t.typeName,
        'composite': t.isCompositeConsume,
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
        'rawHex': t.rawHex,
        'stationConfidence': t.stationConfidence?.name,
        'matchedProcess': t.matchedProcessTrip == null
            ? null
            : _cycleToJson(t.matchedProcessTrip!),
      };

  static TransitTrip? _tripFromJson(Map<String, dynamic> m) {
    final time = _date(m['time']);
    if (time == null) return null;
    final matched = m['matchedProcess'];
    return TransitTrip(
      time: time,
      amountFen: _int(m['amountFen']) ?? 0,
      overdraftLimitFen: _int(m['overdraftFen']) ?? 0,
      isConsume: m['consume'] == true,
      typeName: _str(m['typeName']) ?? '其他',
      isCompositeConsume:
          m['composite'] == true || _str(m['typeName']) == '复合消费',
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
      matchedProcessTrip: matched is Map<String, dynamic>
          ? _cycleFromJson(matched)
          : null,
      stationConfidence: _conf(m['stationConfidence']),
      rawHex: _str(m['rawHex']),
      currency: Currency.fromCode(_str(m['currency'])),
    );
  }

  static Map<String, dynamic> _railToJson(TransitRecord r) => {
        'status': r.statusCode,
        'entryCityCode': r.entryCityCode,
        'exitCityCode': r.exitCityCode,
        'entryStationId': r.entryStationId,
        'exitStationId': r.exitStationId,
        'entryTerminalId': r.entryTerminalId,
        'exitTerminalId': r.exitTerminalId,
        'entryTime': r.entryTime?.millisecondsSinceEpoch,
        'exitTime': r.exitTime?.millisecondsSinceEpoch,
        'entryBalanceFen': r.entryBalanceFen,
        'entryAmountFen': r.entryAmountFen,
        'exitAmountFen': r.exitAmountFen,
        'annotateAmountFen': r.annotateAmountFen,
        'entryLineCode': r.entryLineCode,
        'exitLineCode': r.exitLineCode,
        'rawHex': r.rawHex,
      };

  static TransitRecord? _railFromJson(Map<String, dynamic> m) => TransitRecord(
        statusCode: _int(m['status']) ?? 0,
        entryCityCode: _str(m['entryCityCode']),
        exitCityCode: _str(m['exitCityCode']),
        entryStationId: _str(m['entryStationId']),
        exitStationId: _str(m['exitStationId']),
        entryTerminalId: _str(m['entryTerminalId']),
        exitTerminalId: _str(m['exitTerminalId']),
        entryTime: _date(m['entryTime']),
        exitTime: _date(m['exitTime']),
        entryBalanceFen: _int(m['entryBalanceFen']),
        entryAmountFen: _int(m['entryAmountFen']),
        exitAmountFen: _int(m['exitAmountFen']),
        annotateAmountFen: _int(m['annotateAmountFen']),
        entryLineCode: _int(m['entryLineCode']),
        exitLineCode: _int(m['exitLineCode']),
        rawHex: _str(m['rawHex']),
      );

  static Map<String, dynamic> _busToJson(BusTransitRecord r) => {
        'status': r.statusCode,
        'entryCityCode': r.entryCityCode,
        'exitCityCode': r.exitCityCode,
        'entryStationCode': r.entryStationCode,
        'exitStationCode': r.exitStationCode,
        'entryLineCode': r.entryLineCode,
        'exitLineCode': r.exitLineCode,
        'entryTerminalId': r.entryTerminalId,
        'exitTerminalId': r.exitTerminalId,
        'entryTime': r.entryTime?.millisecondsSinceEpoch,
        'exitTime': r.exitTime?.millisecondsSinceEpoch,
        'amountFen': r.transactionAmountFen,
        'mileage': r.mileage,
        'directionCode': r.directionCode,
        'rawHex': r.rawHex,
      };

  static BusTransitRecord? _busFromJson(Map<String, dynamic> m) =>
      BusTransitRecord(
        statusCode: _int(m['status']) ?? 0,
        entryCityCode: _str(m['entryCityCode']),
        exitCityCode: _str(m['exitCityCode']),
        entryStationCode: _str(m['entryStationCode']),
        exitStationCode: _str(m['exitStationCode']),
        entryLineCode: _str(m['entryLineCode']),
        exitLineCode: _str(m['exitLineCode']),
        entryTerminalId: _str(m['entryTerminalId']),
        exitTerminalId: _str(m['exitTerminalId']),
        entryTime: _date(m['entryTime']),
        exitTime: _date(m['exitTime']),
        transactionAmountFen: _int(m['amountFen']),
        mileage: _int(m['mileage']),
        directionCode: _int(m['directionCode']),
        rawHex: _str(m['rawHex']),
      );

  static Map<String, dynamic> _cycleToJson(TUnionTripRecord r) => {
        'typeCode': r.typeCode,
        'terminalId': r.terminalId,
        'appTypeCode': r.appTypeCode,
        'lineStationCode': r.lineStationCode,
        'amountFen': r.amountFen,
        'balanceFen': r.balanceFen,
        'time': r.time.millisecondsSinceEpoch,
        'cityCode': r.cityCode,
        'acquirerId': r.acquirerId,
        'rawHex': r.rawHex,
      };

  static TUnionTripRecord? _cycleFromJson(Map<String, dynamic> m) {
    final time = _date(m['time']);
    if (time == null) return null;
    return TUnionTripRecord(
      typeCode: _int(m['typeCode']) ?? 0,
      terminalId: _str(m['terminalId']) ?? '',
      appTypeCode: _int(m['appTypeCode']) ?? 0,
      lineStationCode: _str(m['lineStationCode']) ?? '',
      amountFen: _int(m['amountFen']) ?? 0,
      balanceFen: _int(m['balanceFen']) ?? 0,
      time: time,
      cityCode: _str(m['cityCode']),
      acquirerId: _str(m['acquirerId']),
      rawHex: _str(m['rawHex']),
    );
  }

  static StationMatchConfidence? _conf(Object? v) {
    final name = _str(v);
    if (name == null) return null;
    for (final value in StationMatchConfidence.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  static DateTime? _date(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
}