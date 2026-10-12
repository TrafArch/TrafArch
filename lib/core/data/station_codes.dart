/// 站点/线路代码表：读卡识途（Trip Reader）公开数据集的查询层。
///
/// 数据来源：https://github.com/domosekai/tripreader-data（CC BY 4.0）。
/// 数据由两处提供，统一解析为 [StationDataset]：
/// - 应用内预制快照（prebuilt_station_data.dart）：默认数据源，开箱即用；
/// - 在线拉取（tripreader_sync.dart）：设置中开启开关后拉取最新数据，
///   持久化到本地（online_data_store.dart）并取代预制快照，
///   重启后继续生效，直至再次更新或关闭开关清除。
/// 用于终端编号（TAC）解码出线路/站点编码后的二次查表：命中返回线路/
/// 站点名称，未收录返回 null（保持未知，不猜测）。
///
/// 数据集字段：
/// - cityCode：交通联合城市代码（与卡片上报的城市代码同一体系）；
/// - codes：编码 → {type 类型, line 线路, station 站点}；
/// - kind：metro / brt / bus 等类别；同城市同编码冲突时按
///   地铁 > BRT > 公交 > 其它 的优先级取用。
/// prefix 模式数据集（yct 一卡通，键为 Prefix+Code 拼接）暂无城市键，
/// 不参与查询（数据保留，待后续扩展）。
class StationCodeEntry {
  /// 编码原文（codes 的键，如 "0231"）。
  final String code;

  /// 类型（如 "地铁" / "BRT" / "公交"）。
  final String? type;

  /// 线路名（如 "2号线"）。
  final String? line;

  /// 站点名（如 "苏洋"）。
  final String? station;

  /// 卡片体系：tu（交通联合）/ cu（城建）/ yct（一卡通）。
  final String? system;

  /// 数据类别：metro / brt / bus / bike 等。
  final String? kind;

  /// 来源数据集文件（相对路径，溯源用）。
  final String? datasetFile;

  const StationCodeEntry({
    required this.code,
    this.type,
    this.line,
    this.station,
    this.system,
    this.kind,
    this.datasetFile,
  });

  /// 展示标签（如 "地铁 · 2号线 · 苏洋"）；各字段全空时返回 null。
  String? get displayLabel {
    final parts = <String>[
      if (type != null && type!.isNotEmpty) type!,
      if (line != null && line!.isNotEmpty) line!,
      if (station != null && station!.isNotEmpty) station!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 站点/线路代码数据集（读卡识途数据源的一份数据文件）。
class StationDataset {
  /// 数据集相对路径（如 Fujian/Fuzhou/metro-tu.csv，溯源用）。
  final String file;

  /// 交通联合城市代码；prefix 模式数据集为 null（不参与查询）。
  final String? cityCode;

  /// 城市名（可选，溯源用）。
  final String? cityName;

  /// 省份（可选，溯源用）。
  final String? province;

  /// 卡片体系：tu（交通联合）/ cu（城建）/ yct（一卡通）。
  final String system;

  /// 数据类别：metro / brt / bus / mixed 等。
  final String kind;

  /// 编码 → 条目。
  final Map<String, StationCodeEntry> codes;

  const StationDataset({
    required this.file,
    this.cityCode,
    this.cityName,
    this.province,
    this.system = 'tu',
    this.kind = 'mixed',
    this.codes = const {},
  });
}

/// 解析读卡识途数据文件（CSV：City/Prefix,Code,Type,Line,Station）。
///
/// 表头首列为 PREFIX 时按 prefix 模式处理（codes 键为 Prefix+Code 拼接，
/// cityCode 为 null）；表头不识别或无有效编码行时返回 null（跳过）。
StationDataset? parseTripreaderDatasetCsv({
  required String file,
  required String csvText,
  String? cityName,
  String? province,
  String system = 'tu',
  String kind = 'mixed',
}) {
  final rows = _parseCsv(csvText);
  if (rows.length < 2) return null;
  final header = rows.first.map((h) => h.trim().toUpperCase()).toList();
  if (header.length < 5) return null;
  final prefixMode = header.first == 'PREFIX';

  final codes = <String, StationCodeEntry>{};
  final cellCityCodes = <String>{};
  for (final row in rows.skip(1)) {
    if (row.length < 5) continue;
    final cellCity = row[0].trim();
    final code = row[1].trim();
    if (code.isEmpty) continue;
    cellCityCodes.add(cellCity);
    final key = prefixMode ? '$cellCity$code' : code;
    final type = row[2].trim();
    final line = row[3].trim();
    final station = row[4].trim();
    codes[key] = StationCodeEntry(
      code: key,
      type: type.isEmpty ? null : type,
      line: line.isEmpty ? null : line,
      station: station.isEmpty ? null : station,
      system: system,
      kind: kind,
      datasetFile: file,
    );
  }
  if (codes.isEmpty) return null;
  return StationDataset(
    file: file,
    cityCode: prefixMode || cellCityCodes.isEmpty ? null : cellCityCodes.first,
    cityName: cityName,
    province: province,
    system: system,
    kind: kind,
    codes: codes,
  );
}

/// 站点/线路代码表：按 (城市代码, 编码) 精确查询线路/站点名称。
/// 未收录的编码返回 null（不做模糊或跨城匹配，保持未知）。
class StationCodeTable {
  /// "规范化城市代码|编码" → 条目。
  final Map<String, StationCodeEntry> _entries;

  /// 已索引数据集数量（prefix 模式数据集不计入）。
  final int datasetCount;

  const StationCodeTable._(this._entries, this.datasetCount);

  /// 空表（无站点数据时的降级值）。
  static const empty = StationCodeTable._({}, 0);

  /// 可查询编码条目数。
  int get entryCount => _entries.length;

  /// 由数据集列表构建查询表：无城市键的数据集跳过、不计入 datasetCount；
  /// 同城市同编码冲突时保留类别优先级更高的条目
  /// （地铁 > BRT > 公交 > 自行车 > 其它）。
  factory StationCodeTable.fromDatasets(Iterable<StationDataset> datasets) {
    final entries = <String, StationCodeEntry>{};
    var datasetCount = 0;
    for (final dataset in datasets) {
      final cityCode = dataset.cityCode;
      if (cityCode == null || cityCode.isEmpty) continue;
      datasetCount++;
      final cityKey = _normalizeCity(cityCode);
      dataset.codes.forEach((code, entry) {
        final indexKey = '$cityKey|$code';
        final existing = entries[indexKey];
        if (existing == null ||
            _kindPriority(entry.kind) < _kindPriority(existing.kind)) {
          entries[indexKey] = entry;
        }
      });
    }
    return StationCodeTable._(entries, datasetCount);
  }

  /// 类别优先级（数值越小越优先）：地铁 > BRT > 公交 > 自行车 > 其它。
  static int _kindPriority(String? kind) => switch (kind) {
        'metro' => 0,
        'brt' => 1,
        'bus' => 2,
        'bike' => 3,
        _ => 4,
      };

  static String _normalizeCity(String cityCode) =>
      cityCode.replaceAll(' ', '').toUpperCase();

  /// 按城市 + 编码查询；未收录返回 null。
  StationCodeEntry? lookup({required String code, String? cityCode}) {
    if (code.isEmpty || cityCode == null || cityCode.isEmpty) return null;
    return _entries['${_normalizeCity(cityCode)}|$code'];
  }

  /// 组合查询：候选编码按"最具体优先"依次精确匹配
  /// （线路+站点拼接 → 站点 → 线路）；全部未收录返回 null（不猜测）。
  StationCodeEntry? lookupLineStation({
    String? lineCode,
    String? stationCode,
    String? cityCode,
  }) {
    final line = lineCode ?? '';
    final station = stationCode ?? '';
    final candidates = <String>[
      if (line.isNotEmpty && station.isNotEmpty) '$line$station',
      if (station.isNotEmpty) station,
      if (line.isNotEmpty) line,
    ];
    for (final candidate in candidates) {
      final entry = lookup(code: candidate, cityCode: cityCode);
      if (entry != null) return entry;
    }
    return null;
  }

  /// 0x1E「线路和站点代码」字段（BCD 14 位）查询：依次尝试两种实测布局：
  /// - 通用布局：第 1-4 位线路 + 第 5-8 位站点（社区开源实现归纳的
  ///   T-Union 标准排布，与 TUnionTripRecord.lineCode/stationCode 一致）；
  /// - 分段布局：第 3-4 位线路 + 第 7-8 位站点（如福州地铁 README 记录的
  ///   "线路和站点 3-4 位 + 7-8 位"识别方式）。
  /// 采用"最具体优先"组合查询；未命中返回 null（不猜测）。
  StationCodeEntry? lookupLineStationField({
    required String field,
    String? cityCode,
  }) {
    if (field.length < 8) return null;
    final generic = lookupLineStation(
      lineCode: field.substring(0, 4),
      stationCode: field.substring(4, 8),
      cityCode: cityCode,
    );
    if (generic != null) return generic;
    final segLine = field.substring(2, 4);
    if (segLine == '00') return null; // 线路切片全零视为无效，避免误命中
    return lookupLineStation(
      lineCode: segLine,
      stationCode: field.substring(6, 8),
      cityCode: cityCode,
    );
  }
}

/// 简易 CSV 解析（支持引号包裹与转义，容忍 CRLF 与 BOM）。
List<List<String>> _parseCsv(String text) {
  var source = text;
  if (source.startsWith('\uFEFF')) source = source.substring(1);
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (ch == '\n') {
      row.add(field.toString());
      field = StringBuffer();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}
