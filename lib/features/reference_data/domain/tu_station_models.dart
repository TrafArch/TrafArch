import 'station_codes.dart';

/// 地区行（`regions` 表）。
class TuRegionRow {
  final int regionId;
  final String regionCode;
  final String regionName;
  final String? province;
  final String tableName;
  final String codeSource;

  const TuRegionRow({
    required this.regionId,
    required this.regionCode,
    required this.regionName,
    this.province,
    required this.tableName,
    required this.codeSource,
  });
}

/// 站点记录（原始地区表一行）。
///
/// `sourceKey` 是站点映射键（解析器提取的编码与它对齐）；
/// `sourceField` 是映射来源字段（如 `M0.i0.a`），二者语义不同。
class TuStationRecord {
  final String regionCode;
  final String regionName;
  final int stationId;
  final String rawTransportType;

  /// 规范化交通类型：metro / brt / bus / bike / intercity_rail / other。
  final String transportType;
  final String? lineName;
  final String? stationName;
  final String? systemName;
  final String? sourceField;
  final String sourceKey;
  final String? sourceRegionCode;
  final String? sourceRegionName;
  final String? rawValueJson;
  final String? confidence;

  const TuStationRecord({
    required this.regionCode,
    required this.regionName,
    required this.stationId,
    required this.rawTransportType,
    required this.transportType,
    this.lineName,
    this.stationName,
    this.systemName,
    this.sourceField,
    required this.sourceKey,
    this.sourceRegionCode,
    this.sourceRegionName,
    this.rawValueJson,
    this.confidence,
  });

  /// 来源编码切分：(线路片段, 站点片段)。
  /// 12 位取 5-8 / 9-12，10 位取 5-6 / 7-10（北京 HEX），
  /// 8 位取 5-6 / 7-8；其余长度不切分。
  (String?, String?) get segments => tuSourceKeySegments(sourceKey);

  /// 交通类型展示名；未收录返回 null（展示层回退原始值，不猜测）。
  String? get transportLabel => switch (transportType) {
    'metro' => '地铁',
    'brt' => 'BRT',
    'bus' => '公交',
    'bike' => '自行车',
    'intercity_rail' => '城际铁路',
    _ => null,
  };

  StationCodeEntry toEntry() {
    final (lineCode, stationCode) = tuSourceKeySegments(sourceKey);
    return StationCodeEntry(
      code: sourceKey,
      type: switch (transportType) {
        'metro' => '地铁',
        'brt' => 'BRT',
        'bus' => '公交',
        'bike' => '自行车',
        'intercity_rail' => '城际铁路',
        _ => null,
      },
      line: lineName,
      station: stationName,
      system: 'tu',
      kind: transportType,
      datasetFile: 'tu:$regionCode',
      sourceField: sourceField,
      sourceKey: sourceKey,
      rawValueJson: rawValueJson,
      lineCode: lineCode,
      stationCode: stationCode,
    );
  }
}

/// `source_key` 片段切分（按字符位置，保留 A-F）：
/// - 12 位：地区 4 + 线路 4 + 站点 4；
/// - 10 位：地区 4 + 线路 2 + 站点 4（北京，如 `10005E0013`）；
/// - 8 位：地区 4 + 线路 2 + 站点 2。
/// 线路 / 站点码可能是十六进制（昌平线 5E、站点 001B），不能剥掉字母，
/// 否则 `5E` 会被误读成 5、`001B` 误读成 1。
(String?, String?) tuSourceKeySegments(String sourceKey) {
  final key = sourceKey.trim().toUpperCase().replaceAll(
    RegExp(r'[^0-9A-F]'),
    '',
  );
  switch (key.length) {
    case 12:
      return (key.substring(4, 8), key.substring(8, 12));
    case 10:
      return (key.substring(4, 6), key.substring(6, 10));
    case 8:
      return (key.substring(4, 6), key.substring(6, 8));
  }
  return (null, null);
}

/// 用户覆盖行（`tu_user_station_overrides` 表）。
class TuStationOverride {
  final String regionCode;
  final String sourceKey;
  final String sourceField;
  final String stationName;
  final String? lineName;
  final String transportType;
  final DateTime updatedAt;

  const TuStationOverride({
    required this.regionCode,
    required this.sourceKey,
    required this.sourceField,
    required this.stationName,
    this.lineName,
    required this.transportType,
    required this.updatedAt,
  });

  StationCodeEntry toEntry({StationCodeEntry? original}) {
    final (lineCode, stationCode) = tuSourceKeySegments(sourceKey);
    return StationCodeEntry(
      code: sourceKey,
      type: switch (transportType) {
        'metro' => '地铁',
        'brt' => 'BRT',
        'bus' => '公交',
        'bike' => '自行车',
        'intercity_rail' => '城际铁路',
        _ => null,
      },
      line: lineName ?? original?.line,
      station: stationName,
      system: 'tu',
      kind: transportType,
      datasetFile: 'user:tu:$regionCode',
      sourceKey: sourceKey,
      sourceField: original?.sourceField ?? sourceField,
      rawValueJson: original?.rawValueJson,
      lineCode: original?.lineCode ?? lineCode,
      stationCode: original?.stationCode ?? stationCode,
      lineKey: original?.lineKey,
      userOverride: true,
      overrideUpdatedAt: updatedAt.toIso8601String(),
    );
  }
}

/// 站点解析置信级别。
enum TuStationMatchConfidence {
  unavailable,

  /// 命中用户覆盖表。
  overridden,

  /// 唯一命中（或候选站名一致）。
  exact,

  /// 多候选且站名不一致，需结合线路 / 原始 JSON 消歧。
  ambiguous,

  /// 无匹配。
  unmatched,
}

/// 站点解析结果。
class TuStationResolution {
  final List<TuStationRecord> candidates;
  final TuStationOverride? override;
  final TuStationMatchConfidence confidence;
  final String? issue;

  const TuStationResolution({
    this.candidates = const [],
    this.issue,
    this.override,
    this.confidence = TuStationMatchConfidence.unmatched,
  });

  static const unmatched = TuStationResolution(
    confidence: TuStationMatchConfidence.unmatched,
  );

  TuStationRecord? get best => candidates.isEmpty ? null : candidates.first;

  bool get isMatched =>
      confidence == TuStationMatchConfidence.overridden ||
      confidence == TuStationMatchConfidence.exact;

  /// 仅覆盖 / 精确命中时给出站名；歧义与未匹配返回 null（不猜测）。
  String? get stationName =>
      isMatched ? (override?.stationName ?? best?.stationName) : null;

  /// 仅覆盖 / 精确命中时给出线路名。
  String? get lineName =>
      isMatched ? (override?.lineName ?? best?.lineName) : null;

  /// 仅覆盖 / 精确命中时给出交通类型。
  String? get transportType =>
      isMatched ? (override?.transportType ?? best?.transportType) : null;

  /// 仅覆盖 / 精确命中时给出可展示条目；歧义时调用方应读 [candidates]。
  StationCodeEntry? get entry =>
      isMatched ? (override?.toEntry() ?? best?.toEntry()) : null;
}
