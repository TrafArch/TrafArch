/// 站点/线路代码表：交通联合 / 城市一卡通站点数据的查询层。
///
/// 数据来源：应用内本地数据，统一解析为 [StationDataset]：
/// - 交通联合外部 SQLite 数据库（tunion_region_database.dart）：按站点后
///   四位登记线路 / 站点；
/// - 城市一卡通外部 SQLite 数据库（city_union_region_database.dart）：经
///   terminal_index 匹配卡面终端码后按「完整键 + 后四位」登记。
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

  /// 交通联合站点：源自 source_field 的「线路号片段」——12 位编码取 5-8
  /// 位、8 位编码取 5-6 位。非 TU 数据集或未切出片段时为 null。
  final String? lineCode;

  /// 交通联合站点：源自 source_field 的「站点号片段」——12 位编码取 9-12
  /// 位、8 位编码取 7-8 位。非 TU 数据集或未切出片段时为 null。
  final String? stationCode;

  const StationCodeEntry({
    required this.code,
    this.type,
    this.line,
    this.station,
    this.system,
    this.kind,
    this.datasetFile,
    this.lineCode,
    this.stationCode,
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

  /// "规范化城市代码|线路号数字" → 线路名（line_name）。
  final Map<String, String> _lineNames;

  /// "city|lineNum|stationNum" → TU source_field 片段候选（1E / 1A 线路+站点组合）。
  final Map<String, List<StationCodeEntry>> _tuByLineStation;

  /// "city|stationNum" → TU source_field 站点片段候选（1A 站点单独匹配）。
  final Map<String, List<StationCodeEntry>> _tuByStation;

  /// "city|lineNum" → TU source_field 线路片段候选（1A 线路单独匹配）。
  final Map<String, List<StationCodeEntry>> _tuByLine;

  /// 已索引数据集数量（prefix 模式数据集不计入）。
  final int datasetCount;

  const StationCodeTable._(
    this._entries,
    this._lineNames,
    this._tuByLineStation,
    this._tuByStation,
    this._tuByLine,
    this.datasetCount,
  );

  /// 空表（无站点数据时的降级值）。
  static const empty =
      StationCodeTable._({}, {}, {}, {}, {}, 0);

  /// 只读行视图："规范化城市代码|编码" → 条目（供上层与外部数据源合并）。
  Map<String, StationCodeEntry> get rows => Map.unmodifiable(_entries);

  /// 可查询编码条目数。
  int get entryCount => _entries.length;

  /// 由数据集列表构建查询表：无城市键的数据集跳过、不计入 datasetCount；
  /// 同城市同编码冲突时保留类别优先级更高的条目
  /// （地铁 > BRT > 公交 > 自行车 > 其它）。
  factory StationCodeTable.fromDatasets(Iterable<StationDataset> datasets) {
    final entries = <String, StationCodeEntry>{};
    final lineNames = <String, String>{};
    final byLineStation = <String, List<StationCodeEntry>>{};
    final byStation = <String, List<StationCodeEntry>>{};
    final byLine = <String, List<StationCodeEntry>>{};
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
        // 线路号索引：从 line_name 提取数字（"1号线"/"S1线" → "1"），
        // 与卡片上报线路号对齐；同键保留首个（不覆盖）。
        final lineDigits = _lineNameDigits(entry.line);
        if (lineDigits != null) {
          lineNames.putIfAbsent('$cityKey|$lineDigits', () => entry.line!);
        }
        // TU source_field 数字片段索引（1E / 1A 匹配主通道）：
        // 卡片线路 / 站点为单字节 2 位有效值，而库片段可能是 2 位（8 位码）
        // 或 4 位（12 位码，含左 / 右补零）。按「完整值 / 前两位 / 后两位」
        // 多口径登记数字键，使两侧无论补零方向都能对齐；命中时再择优。
        if (entry.system == 'tu') {
          final lineKeys = _tuFragmentKeys(entry.lineCode);
          final stationKeys = _tuFragmentKeys(entry.stationCode);
          for (final stationKey in stationKeys) {
            (byStation['$cityKey|$stationKey'] ??= []).add(entry);
          }
          for (final lineKey in lineKeys) {
            (byLine['$cityKey|$lineKey'] ??= []).add(entry);
            for (final stationKey in stationKeys) {
              (byLineStation['$cityKey|$lineKey|$stationKey'] ??= [])
                  .add(entry);
            }
          }
        }
      });
    }
    return StationCodeTable._(
      entries,
      lineNames,
      byLineStation,
      byStation,
      byLine,
      datasetCount,
    );
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

  /// 线路名中的数字（首个连续数字段）：如 "1号线"→"1"、"S1线"→"1"、
  /// "机场线"→null；去前导零（"01"→"1"）。
  static String? _lineNameDigits(String? line) {
    if (line == null) return null;
    final m = RegExp(r'(\d+)').firstMatch(line);
    if (m == null) return null;
    final trimmed = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  /// 编码末四位（仅数字）：取字符串末尾连续数字的最后 4 位；不足 4 位
  /// 返回 null。与数据库「后四位」站点键口径一致。
  static String? tailFourDigits(String rawCode) {
    final m = RegExp(r'(\d+)$').firstMatch(rawCode);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
  }

  /// 站点编码的「后四位」候选键（含进制转译，按优先级）：
  /// 1) 直接取末尾连续数字的后四位（BCD / 十进制形态，与库同口径即命中）；
  /// 2) 整串按十六进制解析为十进制后再取末四位（卡片以 HEX 读取、库以
  ///    十进制登记时的转译对齐）。均不命中时不产出（保持未知，不猜测）。
  static List<String> tailMatchKeys(String rawCode) {
    final out = <String>[];
    final dec = tailFourDigits(rawCode);
    if (dec != null) out.add(dec);
    if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(rawCode)) {
      try {
        final asDec = BigInt.parse(rawCode, radix: 16).toString();
        final t = tailFourDigits(asDec);
        if (t != null && !out.contains(t)) out.add(t);
      } catch (_) {
        // 超长 / 非法十六进制：跳过转译候选
      }
    }
    return out;
  }

  /// 按城市 + 编码查询；未收录返回 null。
  StationCodeEntry? lookup({required String code, String? cityCode}) {
    if (code.isEmpty || cityCode == null || cityCode.isEmpty) return null;
    return _entries['${_normalizeCity(cityCode)}|$code'];
  }

  /// 站点查询（兼容卡片侧多种编码形态）：先按完整编码精确命中，未命中
  /// 再依次按「后四位」候选键（含 HEX→十进制转译）命中（数据库站点即以
  /// 末四位登记）；均未命中返回 null（保持未知，不猜测）。
  StationCodeEntry? lookupStation({
    required String rawCode,
    String? cityCode,
  }) {
    if (rawCode.isEmpty) return null;
    final full = lookup(code: rawCode, cityCode: cityCode);
    if (full != null) return full;
    for (final key in tailMatchKeys(rawCode)) {
      final hit = lookup(code: key, cityCode: cityCode);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 线路号 → 线路名：卡片线路号数字与 line_name 提取的数字精确匹配
  /// （如线路号 1 → "1号线"）；未命中返回 null（不猜测）。
  String? lookupLineName({required String rawLineCode, String? cityCode}) {
    if (cityCode == null || cityCode.isEmpty) return null;
    final digits = _lineNameDigits(rawLineCode);
    if (digits == null) return null;
    return _lineNames['${_normalizeCity(cityCode)}|$digits'];
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

  /// 0x1E「线路和站点代码」字段查询（TU 规则）：卡片 BCD 前 2 位线路 +
  /// 第 5-6 位站点（或福州分段布局：第 3-4 位线路 + 第 7-8 位站点）经数字
  /// 归一化后，与库中 source_field 5-8/5-6 位线路片段、9-12/7-8 位站点
  /// 片段做数字精确匹配。站点段 "00"（未写入）跳过；两种布局均未命中时
  /// 回退旧的 line_name + 站点末两位匹配（兼容 CSV 数据集与测试）；仍未
  /// 命中返回 null（保持未知，不猜测）。
  StationCodeEntry? lookupLineStationField({
    required String field,
    String? cityCode,
  }) {
    if (field.length < 8) return null;
    if (cityCode == null || cityCode.isEmpty) return null;
    const layouts = <(int, int)>[(0, 4), (2, 6)];
    final cityKey = _normalizeCity(cityCode);
    for (final layout in layouts) {
      final lineRaw = field.substring(layout.$1, layout.$1 + 2);
      final stationRaw = field.substring(layout.$2, layout.$2 + 2);
      if (stationRaw == '00') continue; // 站点段未写入（补齐零）跳过
      final lineNum = _normalizeNumericSegment(lineRaw);
      final stationNum = _normalizeNumericSegment(stationRaw);
      if (lineNum == null || stationNum == null) continue;
      final hit = _pickBestTu(_tuByLineStation['$cityKey|$lineNum|$stationNum']);
      if (hit != null) return hit;
    }
    // 回退：CSV / 老口径数据集无 source_field 片段时沿用 line_name + 站点末两位。
    for (final layout in layouts) {
      final line = field.substring(layout.$1, layout.$1 + 2);
      final station = field.substring(layout.$2, layout.$2 + 2);
      if (station == '00') continue;
      final hit = lookupByLineAndStation(
        lineCode: line,
        stationCode: station,
        cityCode: cityCode,
      );
      if (hit != null) return hit;
    }
    return null;
  }

  /// 0x1A 站点匹配（TU 规则）：卡片进/出闸站点（8 字节编码字符串）先取
  /// 末尾数字段，按「末 4 位」（对齐 12 位 source_field 的 9-12 位）
  /// 「末 2 位」（对齐 8 位 source_field 的 7-8 位）两档依次做数字归一化
  /// 精确匹配；命中优先返回；均未命中返回 null（不猜测）。
  StationCodeEntry? lookupTuStationByCardId({
    required String rawStationId,
    String? cityCode,
  }) {
    if (cityCode == null || cityCode.isEmpty) return null;
    final digits = RegExp(r'(\d+)$').firstMatch(rawStationId)?.group(1);
    if (digits == null || digits.length < 2) return null;
    final cityKey = _normalizeCity(cityCode);
    for (final n in const [4, 2]) {
      if (digits.length < n) continue;
      final tail = digits.substring(digits.length - n);
      final num = _normalizeNumericSegment(tail);
      if (num == null) continue;
      final hit = _pickBestTu(_tuByStation['$cityKey|$num']);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 0x1A 线路匹配（TU 规则）：卡片入/出站线路号（1 字节，展示为整数
  /// 字符串或 HEX）数字归一化后，与库中 source_field 5-8/5-6 位线路片段
  /// 数字精确匹配；候选多者按「有站点名 → 类别优先级」择优；未命中返回
  /// null（不猜测）。
  StationCodeEntry? lookupTuLineByCardValue({
    required String rawLineCode,
    String? cityCode,
  }) {
    if (cityCode == null || cityCode.isEmpty) return null;
    final num = _normalizeNumericSegment(rawLineCode);
    if (num == null) return null;
    return _pickBestTu(_tuByLine['${_normalizeCity(cityCode)}|$num']);
  }

  /// 线路号 + 站点尾码组合查询（CSV / 无 source_field 片段数据集的兜底通
  /// 道）：卡片 [lineCode] 的数字与库 line_name 抽出的数字（`_lineNameDigits`）
  /// 精确相等，且库编码键末两位与 [stationCode] 末两位相等即命中；多个候
  /// 选按「有站点名 → 类别优先级（地铁 > BRT > 公交 …）」择优。城市缺失 /
  /// 线路无效 / 站点不足两位 / 无匹配均返回 null（不猜测）。
  StationCodeEntry? lookupByLineAndStation({
    required String lineCode,
    required String stationCode,
    String? cityCode,
  }) {
    if (cityCode == null || cityCode.isEmpty) return null;
    final lineDigits = _lineNameDigits(lineCode);
    final stationTail = _tailDigits(stationCode, 2);
    if (lineDigits == null || stationTail == null) return null;
    final prefix = '${_normalizeCity(cityCode)}|';
    StationCodeEntry? best;
    var bestScore = _stationMatchScore(null);
    for (final row in _entries.entries) {
      if (!row.key.startsWith(prefix)) continue;
      final entry = row.value;
      if (_lineNameDigits(entry.line) != lineDigits) continue;
      if (_tailDigits(entry.code, 2) != stationTail) continue;
      final score = _stationMatchScore(entry);
      if (best == null || score < bestScore) {
        best = entry;
        bestScore = score;
      }
    }
    return best;
  }

  /// 数字段归一化：去非数字、去前导零；空或全零视为未写入（返回 null）。
  static String? _normalizeNumericSegment(String? s) {
    if (s == null) return null;
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final stripped = digits.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? null : stripped;
  }

  /// source_field 线路 / 站点片段的「多口径数字键」：卡片侧该字段是单字节
  /// 2 位有效值（如 "08"），而库侧片段位数不固定——8 位码 2 位、12 位码 4 位，
  /// 且不同地区存在左补零（"0031"）与右补零（"3100"）两种约定。这里把片段
  /// 同时归一到「完整数值 / 前两位 / 后两位」三种去前导零形态并去重（全零、
  /// 空值丢弃），使卡片 2 位值无论对齐哪种补零方向都能命中；由建索引侧调用。
  static Set<String> _tuFragmentKeys(String? fragment) {
    if (fragment == null) return const {};
    final digits = fragment.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const {};
    final keys = <String>{};
    void add(String part) {
      final stripped = part.replaceFirst(RegExp(r'^0+'), '');
      if (stripped.isNotEmpty) keys.add(stripped);
    }
    add(digits);
    if (digits.length > 2) {
      add(digits.substring(0, 2));
      add(digits.substring(digits.length - 2));
    }
    return keys;
  }

  /// TU 候选集择优：有站点名优先，其次类别优先级（地铁 > BRT > 公交 …）。
  static StationCodeEntry? _pickBestTu(List<StationCodeEntry>? rows) {
    if (rows == null || rows.isEmpty) return null;
    StationCodeEntry? best;
    var bestScore = _stationMatchScore(null);
    for (final e in rows) {
      final score = _stationMatchScore(e);
      if (best == null || score < bestScore) {
        best = e;
        bestScore = score;
      }
    }
    return best;
  }

  /// 组合命中择优分值：有站点名优先，其次类别优先级（地铁 > BRT > 公交 …）；
  /// 分值越小越优；[entry] 为 null（无候选）返回极大值。
  static int _stationMatchScore(StationCodeEntry? entry) {
    if (entry == null) return 1 << 30;
    final hasStation = entry.station != null && entry.station!.isNotEmpty;
    return (hasStation ? 0 : 100) + _kindPriority(entry.kind);
  }

  /// 取编码末尾连续数字的最后 [n] 位；不足 [n] 位返回 null。
  static String? _tailDigits(String code, int n) {
    final m = RegExp(r'(\d+)$').firstMatch(code);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length >= n ? digits.substring(digits.length - n) : null;
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
