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

  /// 交通联合站点：源自 source_key 的「线路号片段」——12 位编码取 5-8
  /// 位、10 位编码取 5-6 位、8 位编码取 5-6 位。非 TU 数据集或未切出
  /// 片段时为 null。
  final String? lineCode;

  /// 交通联合站点：源自 source_key 的「站点号片段」——12 位编码取 9-12
  /// 位、10 位编码取 7-10 位、8 位编码取 7-8 位。非 TU 数据集或未切出
  /// 片段时为 null。
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

/// 运行期点查数据源契约：[StationCodeTable] 的 live 模式经此接口委派到持久化
/// 库。定义在本库以避免 `station_codes.dart` 与 `region_db_store.dart` 循环
/// import（实现类 `RegionKnowledgeDb` 位于 region_db_store.dart）。
abstract class LiveStationSource {
  /// 所属体系：tu（交通联合）/ cu（城市一卡通）。
  String get system;

  StationCodeEntry? lookupEntry(String cityKey, String key);
  String? lookupLineNameDigits(String cityKey, String digits);
  List<StationCodeEntry> fragLineStation(
    String cityKey,
    String lineNum,
    String stationNum,
  );
  List<StationCodeEntry> fragStation(String cityKey, String stationNum);
  List<StationCodeEntry> fragLine(String cityKey, String lineNum);
  Iterable<StationCodeEntry> lineNameEntryCandidates(String cityKey);

  /// 线路号数字 + 编码末两位直查（避免整城扫描）；默认按候选流过滤。
  List<StationCodeEntry> lookupLineStationTail(
    String cityKey,
    String lineDigits,
    String stationTail,
  ) {
    final out = <StationCodeEntry>[];
    for (final e in lineNameEntryCandidates(cityKey)) {
      if (StationCodeTable.lineNameDigitsOf(e.line) != lineDigits) continue;
      if (StationCodeTable.tailDigitsOf(e.code, 2) != stationTail) continue;
      out.add(e);
    }
    return out;
  }

  /// 知识库页惰性地区数据集；默认无。
  List<StationDataset> lazyDatasets() => const [];

  int get totalEntryCount;
  int get datasetCount;
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

  /// 数据集条目数覆盖（惰性数据集用构建期计数代替空 codes Map）。
  int get entryCountOverride => codes.length;

  /// 数据集线路数覆盖（惰性数据集用构建期概况计数；物化数据集缺省 0）。
  int get lineCountOverride => 0;

  /// 惰性条目（知识库页按需查询）；物化数据集直接返回内存条目。
  Future<List<StationCodeEntry>> lazyEntries() async => codes.values.toList();

  /// 是否按需点查的惰性数据集（知识库页据此选择瓦片形态）。
  bool get isLazy => false;

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

  /// 持久化知识库点查源列表（内存索引未命中时按顺序回落到持久化库）。
  final List<LiveStationSource> _liveSources;

  const StationCodeTable._(
    this._entries,
    this._lineNames,
    this._tuByLineStation,
    this._tuByStation,
    this._tuByLine,
    this.datasetCount,
    this._liveSources,
  );

  /// 空表（无站点数据时的降级值）。
  static const empty = StationCodeTable._({}, {}, {}, {}, {}, 0, const []);

  /// 首个 live 源（兼容旧字段语义）。
  LiveStationSource? get live =>
      _liveSources.isEmpty ? null : _liveSources.first;

  /// 以一组 live 点查源包装（替换原有 live 源）。
  StationCodeTable withLiveSources(Iterable<LiveStationSource> sources) {
    final next = <LiveStationSource>[];
    for (final s in sources) {
      if (next.any((e) => identical(e, s))) continue;
      next.add(s);
    }
    if (next.length == _liveSources.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (!identical(next[i], _liveSources[i])) {
          same = false;
          break;
        }
      }
      if (same) return this;
    }
    return StationCodeTable._(
      _entries,
      _lineNames,
      _tuByLineStation,
      _tuByStation,
      _tuByLine,
      datasetCount,
      List<LiveStationSource>.unmodifiable(next),
    );
  }

  /// 以单个 live 点查源包装（兼容旧调用）。
  StationCodeTable withLive(LiveStationSource? source) =>
      withLiveSources([if (source != null) source]);

  LiveStationSource? _sourceOf(String system) {
    for (final s in _liveSources) {
      if (s.system == system) return s;
    }
    return null;
  }

  /// 只读行视图："规范化城市代码|编码" → 条目（供上层与外部数据源合并）。
  Map<String, StationCodeEntry> get rows => Map.unmodifiable(_entries);

  /// 可查询编码条目数（live 模式 = 内存条目 + 各持久化库构建期计数）。
  int get entryCount =>
      _entries.length +
      _liveSources.fold(0, (sum, s) => sum + s.totalEntryCount);

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
      dataset.codes.forEach((code, source) {
        // Dataset metadata applies when a row does not override it.
        final entry = StationCodeEntry(
          code: source.code,
          type: source.type,
          line: source.line,
          station: source.station,
          system: source.system ?? dataset.system,
          kind: source.kind ?? dataset.kind,
          datasetFile: source.datasetFile ?? dataset.file,
          lineCode: source.lineCode,
          stationCode: source.stationCode,
        );
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
        // TU source_field 十六进制片段索引（1E / 1A 匹配主通道）：
        // 卡片线路 / 站点为 1~2 字节有效值，而库片段可能是 2 位（8 / 10 位
        // 码）或 4 位（12 位码 / 北京 10 位码，含补零）。按「完整值 / 前两位
        // / 后两位」多口径登记十六进制文本键；进制转译只在查询侧分轮进行，
        // 避免把 0x1B 的十进制 27 与库中真实站码 0x27 混为一谈。
        if (entry.system == 'tu') {
          final (lineCode, stationCode) = _tuSegmentsOf(entry);
          if (lineCode != null && stationCode != null) {
            for (final lineKey in _tuFragmentKeys(lineCode)) {
              (byLine['$cityKey|$lineKey'] ??= <StationCodeEntry>[]).add(entry);
              for (final stationKey in _tuFragmentKeys(stationCode)) {
                (byLineStation['$cityKey|$lineKey|$stationKey'] ??=
                        <StationCodeEntry>[])
                    .add(entry);
              }
            }
            for (final stationKey in _tuFragmentKeys(stationCode)) {
              (byStation['$cityKey|$stationKey'] ??= <StationCodeEntry>[]).add(
                entry,
              );
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
      const [],
    );
  }

  /// 类别优先级（数值越小越优先）：地铁 > BRT > 公交 > 自行车 > 其它。
  static int kindPriority(String? kind) => switch (kind) {
    'metro' => 0,
    'brt' => 1,
    'bus' => 2,
    'bike' => 3,
    _ => 4,
  };

  static int _kindPriority(String? kind) => kindPriority(kind);

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

  /// 线路名首个数字段（去前导零）；无数字返回 null（供 live 源默认实现）。
  static String? lineNameDigitsOf(String? line) => _lineNameDigits(line);

  /// 编码末四位（仅数字）：取字符串末尾连续数字的最后 4 位；不足 4 位
  /// 返回 null。与数据库「后四位」站点键口径一致。
  static String? tailFourDigits(String rawCode) {
    final m = RegExp(r'(\d+)$').firstMatch(rawCode);
    if (m == null) return null;
    final digits = m.group(1)!;
    return digits.length >= 4 ? digits.substring(digits.length - 4) : null;
  }

  /// 编码末尾连续数字的最后 [n] 位；不足返回 null（供 live 源默认实现）。
  static String? tailDigitsOf(String code, int n) => _tailDigits(code, n);

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

  /// 按城市 + 编码查询；未收录返回 null（live 模式先查内存再点查持久化库）。
  StationCodeEntry? lookup({required String code, String? cityCode}) {
    if (code.isEmpty || cityCode == null || cityCode.isEmpty) return null;
    final cityKey = _normalizeCity(cityCode);
    final hit = _entries['$cityKey|$code'];
    if (hit != null) return hit;
    for (final source in _liveSources) {
      final entry = source.lookupEntry(cityKey, code);
      if (entry != null) return entry;
    }
    return null;
  }

  /// 站点查询（兼容卡片侧多种编码形态）：先按完整编码精确命中，未命中
  /// 再依次按「后四位」候选键（含 HEX→十进制转译）命中（数据库站点即以
  /// 末四位登记）；均未命中返回 null（保持未知，不猜测）。
  StationCodeEntry? lookupStation({required String rawCode, String? cityCode}) {
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
    // 含 A-F 的 HEX 线路码（如昌平线 5E）不能按纯数字提取，否则 5E 会被
    // 当成 5 号线；此类编码只走 matchTuLineByCardValue 的精确通道。
    if (RegExp(r'[A-Fa-f]').hasMatch(rawLineCode)) return null;
    final digits = _lineNameDigits(rawLineCode);
    if (digits == null) return null;
    final cityKey = _normalizeCity(cityCode);
    final hit = _lineNames['$cityKey|$digits'];
    if (hit != null) return hit;
    for (final source in _liveSources) {
      final name = source.lookupLineNameDigits(cityKey, digits);
      if (name != null) return name;
    }
    return null;
  }

  /// 组合查询：候选编码按"最具体优先"依次精确匹配
  /// （城市+线路+站点完整键 → 线路+站点 → 站点 → 线路）；未收录返回 null。
  StationCodeEntry? lookupLineStation({
    String? lineCode,
    String? stationCode,
    String? cityCode,
  }) {
    final line = lineCode ?? '';
    final station = stationCode ?? '';
    final candidates = <String>[
      // TU databases retain the complete source_key, including the city prefix.
      if (cityCode != null &&
          cityCode.isNotEmpty &&
          line.isNotEmpty &&
          station.isNotEmpty)
        '${_normalizeCity(cityCode)}$line$station',
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

  /// 0x1A 站点匹配（TU 规则）：卡片进/出闸站点（8 字节编码字符串）先取
  /// 末尾数字段；给定线路号字节时按「城市+线路+站点」三键做数字归一化
  /// 精确查表，无线路号时按站点末 4 位（对齐 12 位 source_field 的 9-12
  /// 位）单维查表；只做查表命中，不做推测，未命中返回 null。
  StationCodeEntry? lookupTuStationByCardId({
    required String rawStationId,
    String? cityCode,
  }) => matchTuStationByCardId(
    rawStationId: rawStationId,
    cityCode: cityCode,
  ).entry;

  /// 0x1A 站点匹配置信版：给定线路号字节时优先「城市+线路+站点」三键组合
  /// （精确）；无线路号时只按站点末 4 位单维查表（精确）；候选站名不唯一
  /// 记歧义；查不到表一律 unmatched（已取消末 2 位站名推测通道）。
  /// [lineValue] 为卡片线路号原始字节值，同时按十进制 / HEX 两种口径尝试
  /// （兼容进制约定差异）。
  StationMatch matchTuStationByCardId({
    required String rawStationId,
    String? cityCode,
    int? lineValue,
  }) {
    if (cityCode == null || cityCode.isEmpty) return StationMatch.unmatched;
    // 站点码为 BCD / HEX 文本：末尾片段按 HEX 口径归一化（去前导零、
    // 保留 A-F）；按纯数字提取会把 001B 截成 1，与库内口径失配。
    final stationHex = _normalizeHexSegment(rawStationId);
    if (stationHex == null) {
      return StationMatch.unmatched;
    }
    final stationNum2 = _normalizeHexSegment(
      stationHex.length > 2
          ? stationHex.substring(stationHex.length - 2)
          : stationHex,
    );
    final stationNum4 = _normalizeHexSegment(
      stationHex.length > 4
          ? stationHex.substring(stationHex.length - 4)
          : stationHex,
    );
    final cityKey = _normalizeCity(cityCode);
    final tuSource = _sourceOf('tu');
    if (lineValue != null && stationNum2 != null) {
      for (final candidate in _lineValueCandidates(lineValue)) {
        final lineNum = _normalizeHexSegment(candidate);
        if (lineNum == null) continue;
        var rows = _tuByLineStation['$cityKey|$lineNum|$stationNum2'];
        if ((rows == null || rows.isEmpty) && tuSource != null) {
          rows = tuSource.fragLineStation(cityKey, lineNum, stationNum2);
        }
        if (rows != null && rows.isNotEmpty) {
          return _classifyTu(_dedupeTu(rows));
        }
      }
    }
    // 无线路号（或三键未命中）时只按站点片段单维查表；查不到表直接
    // 未匹配（末 2 位推测通道已取消）。
    if (stationNum4 == null) return StationMatch.unmatched;
    var rows = _tuByStation['$cityKey|$stationNum4'];
    if ((rows == null || rows.isEmpty) && tuSource != null) {
      rows = tuSource.fragStation(cityKey, stationNum4);
    }
    if (rows != null && rows.isNotEmpty) {
      return _classifyTu(_dedupeTu(rows));
    }
    return StationMatch.unmatched;
  }

  /// 线路号字节的两种展示口径候选：十进制字符串 + HEX 字符串（如 0x15 →
  /// {"21", "15"}），消除卡片写入约定（BCD 文本 vs 十进制值）差异。
  static List<String> _lineValueCandidates(int value) {
    final hex = value.toRadixString(16).toUpperCase();
    final dec = value.toString();
    return hex == dec ? [hex] : [hex, dec];
  }

  /// 0x1A 线路匹配（TU 规则）：线路号单维查表命中记精确；候选线路名
  /// 不唯一记歧义；未命中返回 null（不猜测）。
  StationCodeEntry? lookupTuLineByCardValue({
    required String rawLineCode,
    String? cityCode,
  }) => matchTuLineByCardValue(
    rawLineCode: rawLineCode,
    cityCode: cityCode,
  ).entry;

  /// 0x1A 线路匹配置信版：线路号单维查表命中（精确）；候选线路名不唯一
  /// 记歧义。
  StationMatch matchTuLineByCardValue({
    required String rawLineCode,
    String? cityCode,
  }) {
    if (cityCode == null || cityCode.isEmpty) return StationMatch.unmatched;
    final num = _normalizeHexSegment(rawLineCode);
    if (num == null) return StationMatch.unmatched;
    final cityKey = _normalizeCity(cityCode);
    final tuSource = _sourceOf('tu');
    var rows = _tuByLine['$cityKey|$num'];
    if ((rows == null || rows.isEmpty) && tuSource != null) {
      rows = tuSource.fragLine(cityKey, num);
    }

    if (rows == null || rows.isEmpty) return StationMatch.unmatched;
    final lineNames = rows
        .map((e) => e.line)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (lineNames.length > 1) {
      return StationMatch(_pickBestTu(rows), StationMatchConfidence.ambiguous);
    }
    return StationMatch(_pickBestTu(rows), StationMatchConfidence.exact);
  }

  /// 0x1E「线路和站点代码」字段查询（TU 规则）：卡片 BCD 前 2 位线路 +
  /// 第 5-6 位站点（或福州分段布局：第 3-4 位线路 + 第 7-8 位站点）经数字
  /// 归一化后，与库中 source_field 5-8/5-6 位线路片段、9-12/7-8 位站点
  /// 片段做数字精确匹配。站点段 "00"（未写入）跳过；两种布局均未命中
  /// 一律返回 null（已取消 line_name + 站点末两位回退通道，不猜测）。
  StationCodeEntry? lookupLineStationField({
    required String field,
    String? cityCode,
  }) => matchLineStationField(field: field, cityCode: cityCode).entry;

  /// 0x1E 线路+站点字段匹配置信版：前两位（线路代码高字节）非 0 且
  /// 通用站点段（第 5-6 位）已写入时，优先且只按「前 2 位线路 + 第 5-6
  /// 位站点」识别，避免错位布局（第 3-4 位线路 + 第 7-8 位站点）把运营
  /// 代码 / 站点低字节误当线路或站点；否则沿用原双布局探测（兼容福州
  /// 分段布局）。城市 + 线路 + 站点三键联合查表命中，候选站名唯一 → 精确；
  /// 站名不唯一 → 歧义（不强行显示站名）；查不到表 → 未匹配。
  StationMatch matchLineStationField({
    required String field,
    String? cityCode,
  }) {
    if (field.length < 8) return StationMatch.unmatched;
    if (cityCode == null || cityCode.isEmpty) return StationMatch.unmatched;
    // 0x1E 字段布局选择：前两位非 0 时卡片按通用布局写入，固定用该
    // 布局，不再尝试错位布局；前两位为 0、或通用站点段未写入（"00"，
    // 福州分段布局的形态）时沿用现有双布局探测。
    final hasFrontLine = _normalizeHexSegment(field.substring(0, 2)) != null;
    final hasFrontStation = _normalizeHexSegment(field.substring(4, 6)) != null;
    final layouts = hasFrontLine && hasFrontStation
        ? const <(int, int)>[(0, 4)]
        : const <(int, int)>[(0, 4), (2, 6)];
    final cityKey = _normalizeCity(cityCode);
    // 0x1E 属于交通联合记录：片段索引必须取 TU 源。`live` 是首个 live
    // 源（知识库装配 CU 在前），而 CU 侧不生成 kb_frag_*，
    // 用 live 会让三键精确通道永远空转。
    final tuSource = _sourceOf('tu');
    // 两轮匹配：第一轮按库内原始 HEX 文本（5E / 1B），第二轮才做进制
    // 转译兜底——避免 0x1B 的十进制 27 与库中真实站码 0x27 撞码。
    for (final round in const [0, 1]) {
      for (final layout in layouts) {
        final lineHex = _normalizeHexSegment(
          field.substring(layout.$1, layout.$1 + 2),
        );
        final stationHex = _normalizeHexSegment(
          field.substring(layout.$2, layout.$2 + 2),
        );
        if (lineHex == null || stationHex == null) continue;
        final lineNum = round == 0 ? lineHex : _hexToDec(lineHex);
        final stationNum = round == 0 ? stationHex : _hexToDec(stationHex);
        if (lineNum == null || stationNum == null) continue;
        var rows = _tuByLineStation['$cityKey|$lineNum|$stationNum'];
        if ((rows == null || rows.isEmpty) && tuSource != null) {
          rows = tuSource.fragLineStation(cityKey, lineNum, stationNum);
        }
        if (rows != null && rows.isNotEmpty) {
          return _classifyTu(_dedupeTu(rows));
        }
      }
    }
    return StationMatch.unmatched;
  }

  /// 公交/BRT 的 1E 字段只按完整的两字节线路、两字节站点查 TU 库。
  /// 不复用地铁的单字节片段或十进制兜底，防止公交码撞到地铁站。
  StationMatch matchBusLineStationField({
    required String field,
    required String cityCode,
  }) {
    final hex = field.toUpperCase();
    if (!RegExp(r'^[0-9A-F]{14}$').hasMatch(hex)) return StationMatch.unmatched;
    final city = _normalizeCity(cityCode);
    final line = hex.substring(0, 4);
    final station = hex.substring(4, 8);
    if (line == '0000' ||
        line == 'FFFF' ||
        station == '0000' ||
        station == 'FFFF') {
      return StationMatch.unmatched;
    }
    final key = '$city$line$station';
    final entry =
        _sourceOf('tu')?.lookupEntry(city, key) ?? _entries['$city|$key'];
    if (entry == null ||
        (entry.system != null && entry.system != 'tu') ||
        !(entry.kind == 'brt' ||
            entry.kind == 'bus' ||
            entry.type == 'BRT' ||
            entry.type == '公交')) {
      return StationMatch.unmatched;
    }
    return StationMatch(entry, StationMatchConfidence.exact);
  }

  /// TU 候选集置信判定：站名唯一 → 精确；站名不唯一 → 歧义；候选全部
  /// 无站名时仍记精确（查表命中，仅缺站名，展示层回退原始编码）。
  static StationMatch _classifyTu(List<StationCodeEntry> rows) {
    final best = _pickBestTu(rows);
    final names = rows
        .where((e) => _kindPriority(e.kind) == _kindPriority(best?.kind))
        .map((e) => e.station)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (names.length > 1) {
      return StationMatch(best, StationMatchConfidence.ambiguous);
    }
    return StationMatch(best, StationMatchConfidence.exact);
  }

  /// 数字段归一化：去非数字、去前导零；空或全零视为未写入（返回 null）。
  static String? _normalizeNumericSegment(String? s) {
    if (s == null) return null;
    final text = s.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) return null;
    final stripped = text.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? null : stripped;
  }

  /// TU 候选去重（同一行可能被多个候选组合命中）。
  static List<StationCodeEntry> _dedupeTu(Iterable<StationCodeEntry> rows) {
    final seen = <String>{};
    final out = <StationCodeEntry>[];
    for (final e in rows) {
      final key = '${e.system}|${e.code}|${e.line}|${e.station}';
      if (seen.add(key)) out.add(e);
    }
    return out;
  }

  /// 片段归一化（HEX 口径）：大写、保留 A-F、去前导零；空或全零视为
  /// 未写入（返回 null）。与 TuStationRepository._normalizeFragment 同
  /// 口径，避免 `5E` 被读成 `5`、`001B` 被读成 `1`。
  static String? _normalizeHexSegment(String? s) {
    if (s == null) return null;
    final text = s.trim().toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    final stripped = text.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? null : stripped;
  }

  /// HEX 片段的十进制转译候选（仅查询侧兜底使用，不进入索引键）。
  static String? _hexToDec(String hex) {
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex)) return null;
    try {
      return BigInt.parse(hex, radix: 16).toString();
    } catch (_) {
      return null;
    }
  }

  /// source_field 线路 / 站点片段的「位置多口径键」：完整值 / 前两位 /
  /// 后两位（兼容 12 位码左右补零）。**不做进制转译**——索引键必须与
  /// 库内原始编码同口径；HEX→十进制转译只在查询侧分轮兜底，否则
  /// `0x1B`（北邵洼）会以十进制 `27` 混入 `0x27`（生命科学园）的索引。
  static Set<String> _tuFragmentKeys(String? fragment) {
    final text = (fragment ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'[^0-9A-F]'),
      '',
    );
    if (text.isEmpty) return const {};
    final keys = <String>{};
    void add(String part) {
      final s = part.replaceFirst(RegExp(r'^0+'), '');
      if (s.isNotEmpty) keys.add(s);
    }

    add(text);
    if (text.length > 2) {
      add(text.substring(0, 2));
      add(text.substring(text.length - 2));
    }
    return keys;
  }

  /// 条目线路 / 站点片段：优先使用构建期切好的 lineCode / stationCode；
  /// 缺失时按编码长度回切（12 位 5-8 / 9-12、10 位 5-6 / 7-10、8 位
  /// 5-6 / 7-8）。切分保留 A-F，避免北京 HEX 码被按纯数字误读。
  static (String?, String?) _tuSegmentsOf(StationCodeEntry entry) {
    final line = entry.lineCode;
    final station = entry.stationCode;
    if (line != null && station != null) return (line, station);
    final key = entry.code.trim().toUpperCase().replaceAll(
      RegExp(r'[^0-9A-F]'),
      '',
    );
    return switch (key.length) {
      4 => (key.substring(0, 2), key.substring(2, 4)), // city-relative CSV code
      12 => (key.substring(4, 8), key.substring(8, 12)),
      10 => (key.substring(4, 6), key.substring(6, 10)),
      8 => (key.substring(4, 6), key.substring(6, 8)),
      _ => (null, null),
    };
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

/// 站点匹配置信级别（只做查表判定，不做站名推测）：
/// - exact：城市 + 线路 + 站点联合查表命中（无线路号时为站点末 4 位
///   单维查表命中）；
/// - ambiguous：联合命中但候选站名不唯一（禁止展示站名，回退原始编码）；
/// - unmatched：查不到表（展示原始编码，并标注未匹配）。
enum StationMatchConfidence { exact, ambiguous, unmatched }

/// 站点匹配结果：候选条目 + 置信级别；歧义 / 未匹配不产出名称。
class StationMatch {
  final StationCodeEntry? entry;
  final StationMatchConfidence confidence;

  const StationMatch(this.entry, this.confidence);

  static const unmatched = StationMatch(null, StationMatchConfidence.unmatched);

  bool get isUnmatched => confidence == StationMatchConfidence.unmatched;

  /// 可展示的线路名（仅精确命中给出；歧义与未匹配不给出，不强行显示）。
  String? get lineName =>
      confidence == StationMatchConfidence.exact ? entry?.line : null;

  /// 可展示的站点名（仅精确命中给出；歧义与未匹配不给出，不强行显示）。
  String? get stationName =>
      confidence == StationMatchConfidence.exact ? entry?.station : null;
}
