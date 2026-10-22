import 'dart:convert';

import '../../transit_analysis/tunion_analysis_models.dart';
import '../../reference_data/domain/station_codes.dart';
import '../../reference_data/domain/tunion_terminal_decoder.dart';
import '../../../protocols/transit/tunion/tunion_models.dart';
import 'archive_context.dart';
import 'snapshot_diagnostics.dart';

export 'archive_context.dart';
export 'snapshot_diagnostics.dart';

class SnapshotDecodeResult {
  final String rawJson;
  final int? formatVersion;
  final SnapshotDecodeStatus status;
  final CardSessionSnapshot? snapshot;
  final List<SnapshotIssue> issues;
  const SnapshotDecodeResult({
    required this.rawJson,
    required this.status,
    this.formatVersion,
    this.snapshot,
    this.issues = const [],
  });
}

/// 卡片读取行程记录快照：v3 保存上下文与完整已知字段，v1/v2 独立兼容。
///
/// v2 升级（历史存储）：
/// - 完整保存 0x1E 过程记录集合与 0x1A 记录集合（含原始 HEX），
///   不再只保存最近一次单条展示快照；批次经 [mergeHistories] 按记录
///   身份累积去重，新读取追加批次、不覆盖旧数据；
/// - 交易条目随快照保存原始 HEX、站点匹配置信与配对的 0x1E 记录
///   （关联证据入档，历史展示仍可"逐条关联、确认重复才合并"）；
/// - [parseVersion] 记录产出批次的解析口径版本（[kTripParseVersion]），
///   历史显示使用捕获时的解析结果；重解析不得覆盖原始证据。
class CardSessionSnapshot {
  static const currentFormatVersion = 3;

  final int formatVersion;

  /// 产出本快照的解析口径版本（重解析依据）。
  final int parseVersion;

  final ArchiveContext context;

  /// Protocol-owned evidence (file/block/record coordinates, original bytes,
  /// parse/match source and diagnostics). The archive does not reinterpret it.
  final List<Map<String, dynamic>> rawEvidence;
  final Map<String, dynamic> recordProvenance;
  final Map<String, dynamic> extensions;

  /// Decoded snapshots re-emit the exact captured text, including unknown fields
  /// and malformed entries. A display projection must never replace evidence.
  final String? originalJson;
  final bool isProjection;

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
    this.context = const ArchiveContext(),
    this.rawEvidence = const [],
    this.recordProvenance = const {},
    this.extensions = const {},
    this.originalJson,
    this.isProjection = false,
    this.cardCityCode,
    this.trips = const [],
    this.rails = const [],
    this.buses = const [],
    this.processTrips = const [],
  });

  /// 兼容旧调用点（导出等）：最近一条 0x1A 记录 1 / 记录 2。
  TransitRecord? get railRecord => rails.isEmpty ? null : rails.first;
  BusTransitRecord? get busRecord => buses.isEmpty ? null : buses.first;

  /// 是否不含记录/原始证据；读取上下文仍可有意义，不能用此值丢弃部分读取。
  bool get isEmpty =>
      trips.isEmpty &&
      rails.isEmpty &&
      buses.isEmpty &&
      processTrips.isEmpty &&
      rawEvidence.isEmpty;

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

  /// New captures use v3. Decoded captures retain their original version/text.
  String encode() {
    if (isProjection) {
      throw StateError('A history projection is not a captured snapshot');
    }
    if (originalJson != null) return originalJson!;
    if (!const {1, 2, 3}.contains(formatVersion)) {
      throw StateError('Unsupported snapshot writer version: $formatVersion');
    }
    return jsonEncode({
      ...extensions,
      'v': formatVersion,
      'parseVersion': parseVersion,
      'cityCode': cardCityCode,
      'trips': [for (final t in trips) _tripToJson(t)],
      if (formatVersion == 1) ...{
        'rail': railRecord == null ? null : _railToJson(railRecord!),
        'bus': busRecord == null ? null : _busToJson(busRecord!),
      } else ...{
        'rails': [for (final r in rails) _railToJson(r)],
        'buses': [for (final b in buses) _busToJson(b)],
        'cycle': [for (final p in processTrips) _cycleToJson(p)],
      },
      if (formatVersion == 3) ...{
        'context': context.toJson(),
        'rawEvidence': rawEvidence,
        'recordProvenance': recordProvenance,
      },
    });
  }

  /// Compatibility projection only; history/detail/export use decodeResult so
  /// unsupported/corrupt data cannot masquerade as an empty successful read.
  static CardSessionSnapshot? decode(String json) =>
      decodeResult(json).snapshot;

  static SnapshotDecodeResult decodeResult(String json) {
    int? version;
    final issues = <SnapshotIssue>[];
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('快照顶层必须是对象');
      }
      final value = data.containsKey('v') ? data['v'] : 1;
      if (value is! int) throw const FormatException('v 必须是整数');
      version = value;
      if (!const {1, 2, 3}.contains(version)) {
        return SnapshotDecodeResult(
          rawJson: json,
          formatVersion: version,
          status: SnapshotDecodeStatus.unsupported,
          issues: [SnapshotIssue('v', '不支持的快照版本 $version；原文已保留')],
        );
      }
      if (data['trips'] is! List) {
        throw const FormatException('trips 必须是数组');
      }
      final parser = data['parseVersion'];
      if (version == 3 && parser == null) {
        throw const FormatException('v3 缺少 parseVersion');
      }
      if (parser != null && (parser is! int || parser < 1)) {
        throw const FormatException('parseVersion 必须是正整数');
      }
      if (data['cityCode'] != null && data['cityCode'] is! String) {
        throw const FormatException('cityCode 必须是字符串或 null');
      }
      var context = const ArchiveContext();
      if (version == 3) {
        final rawContext = data['context'];
        if (rawContext is! Map<String, dynamic>) {
          throw const FormatException('v3 缺少 context 对象');
        }
        if (validateArchiveContext(rawContext, issues)) {
          context = ArchiveContext.fromJson(rawContext);
        }
      }
      List<T> records<T>(
        String key,
        T? Function(Map<String, dynamic>) convert, {
        String? singleton,
      }) {
        final raw = singleton == null ? data[key] : data[singleton];
        if (raw == null && version == 1) return [];
        if (raw == null && singleton != null) return [];
        final items = singleton == null ? raw : [raw];
        if (items is! List) {
          issues.add(SnapshotIssue(key, '应为记录数组，原始内容已保留'));
          return [];
        }
        final result = <T>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          final path = singleton ?? '$key[$i]';
          if (item is! Map<String, dynamic>) {
            issues.add(SnapshotIssue(path, '应为记录对象'));
          } else if (validateSnapshotRecord(item, key, path, issues)) {
            T? converted;
            try {
              converted = convert(item);
            } on RangeError {
              issues.add(SnapshotIssue(path, '数值超出范围，原文已保留'));
            } on FormatException {
              issues.add(SnapshotIssue(path, '记录格式错误，原文已保留'));
            }
            if (converted != null) {
              result.add(converted);
            } else {
              issues.add(SnapshotIssue(path, '记录无法解码，原文已保留'));
            }
          }
        }
        return List.unmodifiable(result);
      }

      Map<String, dynamic> object(String key) {
        final value = data[key];
        if (value == null) return const {};
        if (value is Map<String, dynamic>) return Map.unmodifiable(value);
        issues.add(SnapshotIssue(key, '应为对象，原文已保留'));
        return const {};
      }

      final evidence = <Map<String, dynamic>>[];
      if (version == 3) {
        final raw = data['rawEvidence'];
        if (raw is List) {
          for (var i = 0; i < raw.length; i++) {
            final entry = raw[i];
            if (entry is Map<String, dynamic>) {
              evidence.add(Map.unmodifiable(entry));
            } else {
              issues.add(SnapshotIssue('rawEvidence[$i]', '应为证据对象'));
            }
          }
        } else {
          issues.add(const SnapshotIssue('rawEvidence', 'v3 缺少原始证据数组'));
        }
      }
      final snapshot = CardSessionSnapshot(
        formatVersion: version,
        parseVersion: _int(data['parseVersion']) ?? 1,
        cardCityCode: _str(data['cityCode']),
        context: context,
        rawEvidence: List.unmodifiable(evidence),
        recordProvenance: object('recordProvenance'),
        extensions: Map.unmodifiable(data),
        originalJson: json,
        trips: records('trips', _tripFromJson),
        rails: records(
          'rails',
          _railFromJson,
          singleton: version == 1 ? 'rail' : null,
        ),
        buses: records(
          'buses',
          _busFromJson,
          singleton: version == 1 ? 'bus' : null,
        ),
        processTrips: version == 1
            ? const []
            : records('cycle', _cycleFromJson),
      );
      return SnapshotDecodeResult(
        rawJson: json,
        formatVersion: version,
        snapshot: snapshot,
        issues: List.unmodifiable(issues),
        status: issues.isNotEmpty
            ? SnapshotDecodeStatus.partial
            : version < 3
            ? SnapshotDecodeStatus.legacy
            : SnapshotDecodeStatus.supported,
      );
    } on FormatException catch (error) {
      return SnapshotDecodeResult(
        rawJson: json,
        formatVersion: version,
        status: SnapshotDecodeStatus.malformed,
        issues: [SnapshotIssue(r'$', error.message)],
      );
    }
  }

  /// 历史批次合并：多份快照按记录身份累积去重（交易按 序号+时间+金额+
  /// 终端，0x1A 按 时间+站点+终端，0x1E 按 原始 HEX / 四要素），
  /// 先入池的批次（较新读取）优先保留，供详情页历史累积展示。
  static CardSessionSnapshot mergeHistories(
    List<CardSessionSnapshot> histories,
  ) {
    final tripsById = <String, TransitTrip>{};
    final railsById = <String, TransitRecord>{};
    final busesById = <String, BusTransitRecord>{};
    final cyclesById = <String, TUnionTripRecord>{};
    String? cityCode;
    // Compatibility projection only. Zero explicitly denotes mixed versions;
    // ArchiveHistory retains the actual version on every source record.
    final versions = histories.map((h) => h.parseVersion).toSet();
    for (final h in histories) {
      cityCode ??= h.cardCityCode;
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
      parseVersion: versions.length == 1 ? versions.single : 0,
      isProjection: true,
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

  static Map<String, dynamic> _tripToJson(TransitTrip t) => {
    'time': t.time.millisecondsSinceEpoch,
    'capturedTimes': {'time': _civil(t.time)},
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
    'location': t.location == null
        ? null
        : {
            'ruleId': t.location!.ruleId,
            'ruleNote': t.location!.ruleNote,
            'cityCode': t.location!.cityCode,
            'operatorCode': t.location!.operatorCode,
            'lineCode': t.location!.lineCode,
            'stationCode': t.location!.stationCode,
          },
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
    final location = m['location'];
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
      location: location is Map<String, dynamic>
          ? TerminalLocation(
              ruleId: location['ruleId'] as String,
              ruleNote: _str(location['ruleNote']),
              cityCode: _str(location['cityCode']),
              operatorCode: _str(location['operatorCode']),
              lineCode: _str(location['lineCode']),
              stationCode: _str(location['stationCode']),
            )
          : null,
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
      currency: _archivedCurrency(_str(m['currency'])),
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
    'capturedTimes': {
      if (r.entryTime != null) 'entryTime': _civil(r.entryTime!),
      if (r.exitTime != null) 'exitTime': _civil(r.exitTime!),
    },
    'entryTime': r.entryTime?.millisecondsSinceEpoch,
    'exitTime': r.exitTime?.millisecondsSinceEpoch,
    'entryBalanceFen': r.entryBalanceFen,
    'entryAmountFen': r.entryAmountFen,
    'exitAmountFen': r.exitAmountFen,
    'annotateAmountFen': r.annotateAmountFen,
    'entryLineCode': r.entryLineCode,
    'exitLineCode': r.exitLineCode,
    'rawHex': r.rawHex,
    'issuerCustom': r.issuerCustom,
    'entryAgencyId': r.entryAgencyId,
    'exitAgencyId': r.exitAgencyId,
    'entryTimeBcd': r.entryTimeBcd,
    'exitTimeBcd': r.exitTimeBcd,
    'entryStationName': r.entryStationName,
    'exitStationName': r.exitStationName,
    'lineName': r.lineName,
    'transactionAmountFen': r.transactionAmountFen,
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
    issuerCustom: _str(m['issuerCustom']),
    entryAgencyId: _str(m['entryAgencyId']),
    exitAgencyId: _str(m['exitAgencyId']),
    entryTimeBcd: _str(m['entryTimeBcd']),
    exitTimeBcd: _str(m['exitTimeBcd']),
    entryStationName: _str(m['entryStationName']),
    exitStationName: _str(m['exitStationName']),
    lineName: _str(m['lineName']),
    transactionAmountFen: _int(m['transactionAmountFen']),
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
    'capturedTimes': {
      if (r.entryTime != null) 'entryTime': _civil(r.entryTime!),
      if (r.exitTime != null) 'exitTime': _civil(r.exitTime!),
    },
    'entryTime': r.entryTime?.millisecondsSinceEpoch,
    'exitTime': r.exitTime?.millisecondsSinceEpoch,
    'amountFen': r.transactionAmountFen,
    'mileage': r.mileage,
    'directionCode': r.directionCode,
    'rawHex': r.rawHex,
    'issuerCustomHex': r.issuerCustomHex,
    'entryAgencyId': r.entryAgencyId,
    'exitAgencyId': r.exitAgencyId,
    'entryOperatorCode': r.entryOperatorCode,
    'exitOperatorCode': r.exitOperatorCode,
    'entryVehicleId': r.entryVehicleId,
    'exitVehicleId': r.exitVehicleId,
    'entryTimeBcd': r.entryTimeBcd,
    'exitTimeBcd': r.exitTimeBcd,
    'annotateAmountFen': r.annotateAmountFen,
    'hasRecordHeader': r.hasRecordHeader,
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
        issuerCustomHex: _str(m['issuerCustomHex']),
        entryAgencyId: _str(m['entryAgencyId']),
        exitAgencyId: _str(m['exitAgencyId']),
        entryOperatorCode: _str(m['entryOperatorCode']),
        exitOperatorCode: _str(m['exitOperatorCode']),
        entryVehicleId: _str(m['entryVehicleId']),
        exitVehicleId: _str(m['exitVehicleId']),
        entryTimeBcd: _str(m['entryTimeBcd']),
        exitTimeBcd: _str(m['exitTimeBcd']),
        annotateAmountFen: _int(m['annotateAmountFen']),
        hasRecordHeader: m['hasRecordHeader'] == true,
      );

  static Map<String, dynamic> _cycleToJson(TUnionTripRecord r) => {
    'typeCode': r.typeCode,
    'terminalId': r.terminalId,
    'appTypeCode': r.appTypeCode,
    'lineStationCode': r.lineStationCode,
    'amountFen': r.amountFen,
    'balanceFen': r.balanceFen,
    'time': r.time.millisecondsSinceEpoch,
    'capturedTimes': {'time': _civil(r.time)},
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

  static Currency _archivedCurrency(String? code) => switch (code) {
    'CNY' => Currency.cny,
    'HKD' => Currency.hkd,
    _ => Currency(code: code ?? '', symbol: code ?? '币种未知', unit: code ?? '未知'),
  };

  static StationMatchConfidence? _conf(Object? v) {
    final name = _str(v);
    if (name == null) return null;
    // 旧版快照可能存有已取消的 probable（站名推测），按未匹配兼容。
    if (name == 'probable') return StationMatchConfidence.unmatched;
    for (final value in StationMatchConfidence.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static int? _int(Object? v) => v is int ? v : null;

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  static Map<String, dynamic> _civil(DateTime time) => {
    'civil': time.toIso8601String(),
    'conversionOffsetMinutes': time.timeZoneOffset.inMinutes,
    'basis': time.isUtc ? 'utc' : 'parser-local-unverified',
  };

  static DateTime? _date(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
}
