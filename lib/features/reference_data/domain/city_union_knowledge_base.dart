import 'dart:convert';

/// CU 城市参考或卡片识别结果；lookup 的卡名仅为参考，
/// resolveCard 的卡名来自发行标识匹配，可信度由 [cardNameStatus] 标注。
class CityUnionCardInfo {
  /// 邮政编码前四位（参考值，可选）。
  final String? postalPrefix;

  /// CU 城市 / 项目代码（可选）。
  final String? cuCityProjectCode;

  /// 城市 / 地区名。
  final String city;

  /// 省份或地区（可选）。
  final String? province;

  /// 地区类型（city / county_level_city / district ...）。
  final String? areaType;

  /// 本地交通卡名称参考（null 表示未找到可靠名称）。
  final String? cardName;

  /// 卡名可信度：source_supported / candidate_name / not_found_or_unverified。
  final String? cardNameStatus;

  /// 城市代码来源：wiki_listed_code / postal_prefix_reference_only /
  /// not_applicable_or_unverified。
  final String? codeStatus;

  const CityUnionCardInfo({
    required this.city,
    this.postalPrefix,
    this.cuCityProjectCode,
    this.province,
    this.areaType,
    this.cardName,
    this.cardNameStatus,
    this.codeStatus,
  });

  /// 是否存在可展示的卡名参考（source_supported / candidate_name）。
  bool get hasCardName => cardName != null && cardName!.trim().isNotEmpty;

  /// 卡名是否由公开资料明确支持（最高可信度）。
  bool get isCardNameSupported => cardNameStatus == 'source_supported';
}

/// CU 城市参考目录与公共信息前四字节发行标识名称表。
class CityUnionCardTable {
  final Map<String, CityUnionCardInfo> _byCode;
  final List<CityUnionCardInfo> _entries;
  final Map<String, String> _issuerNames;
  final List<Map<String, Object?>> _nameOverrides;

  const CityUnionCardTable._(
    this._byCode,
    this._entries,
    this._issuerNames,
    this._nameOverrides,
  );

  static const empty = CityUnionCardTable._({}, [], {}, []);

  factory CityUnionCardTable.fromJson(Object? json) {
    final byCode = <String, CityUnionCardInfo>{};
    final entries = <CityUnionCardInfo>[];
    final raw = json is Map ? json['entries'] : json;
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final city = e['city']?.toString().trim();
        if (city == null || city.isEmpty) continue;
        final postal = _digits(e['postalPrefix']);
        final cuCode = _digits(e['cuCityProjectCode']);
        final info = CityUnionCardInfo(
          city: city,
          postalPrefix: postal,
          cuCityProjectCode: cuCode,
          province: e['province']?.toString(),
          areaType: e['type']?.toString(),
          cardName: e['cardName']?.toString(),
          cardNameStatus: e['cardNameStatus']?.toString(),
          codeStatus: e['codeStatus']?.toString(),
        );
        entries.add(info);
        // 邮编前四位与 CU 城市项目代码都登记为查表键（同一代码保留首条）
        for (final key in <String?>{postal, cuCode}) {
          if (key == null || key.isEmpty) continue;
          byCode.putIfAbsent(key, () => info);
        }
      }
    }
    final issuerNames = <String, String>{};
    final overrides = <Map<String, Object?>>[];
    if (json is Map) {
      final names = json['issuerNames'];
      if (names is List) {
        for (final row in names) {
          if (row is! Map) continue;
          final code = row['issuer_code']?.toString().toUpperCase();
          final name = row['name_zh_cn']?.toString().trim();
          if (code != null &&
              RegExp(r'^[0-9A-F]{8}$').hasMatch(code) &&
              name != null &&
              name.isNotEmpty) {
            issuerNames[code] = name;
          }
        }
      }
      final rules = json['nameOverrides'];
      if (rules is List) {
        for (final rule in rules) {
          if (rule is Map<String, dynamic>) overrides.add(Map.of(rule));
        }
      }
    }
    return CityUnionCardTable._(byCode, entries, issuerNames, overrides);
  }

  /// 以原始公共信息的完整四字节发行标识识别卡名；城市仅提供地区参考。
  CityUnionCardInfo? resolveCard({String? cityCode, String? rawHex}) {
    final region = lookup(cityCode);
    final raw = rawHex?.toUpperCase();
    String? name;
    if (raw != null &&
        raw.length >= 8 &&
        raw.length.isEven &&
        RegExp(r'^[0-9A-F]+$').hasMatch(raw)) {
      final issuer = raw.substring(0, 8);
      name = _issuerNames[issuer];
      if (name != null) {
        for (final rule in _nameOverrides) {
          final minimum = rule['min_raw_length'];
          final index = rule['byte_index'];
          final nibble = rule['high_nibble'];
          final overrideName = rule['name_zh_cn'];
          if (rule['issuer_code'] != issuer ||
              rule['requires_map_match'] != 1 ||
              minimum is! int ||
              minimum < 4 ||
              index is! int ||
              index < 0 ||
              nibble is! int ||
              nibble < 0 ||
              nibble > 15 ||
              overrideName is! String ||
              overrideName.trim().isEmpty) {
            continue;
          }
          if (raw.length ~/ 2 >= minimum &&
              index < raw.length ~/ 2 &&
              int.parse(raw[index * 2], radix: 16) == nibble) {
            name = overrideName.trim();
            break;
          }
        }
      }
    }
    if (region == null && name == null) return null;
    return CityUnionCardInfo(
      city: region?.city ?? '',
      province: region?.province,
      postalPrefix: region?.postalPrefix,
      cuCityProjectCode: region?.cuCityProjectCode,
      areaType: region?.areaType,
      codeStatus: region?.codeStatus,
      cardName: name,
      cardNameStatus: name == null
          ? 'not_found_or_unverified'
          : 'source_supported',
    );
  }

  /// 归一化为纯数字代码；无有效数字时返回 null。
  static String? _digits(Object? value) {
    if (value == null) return null;
    final s = '$value'.replaceAll(RegExp(r'[^0-9]'), '');
    return s.isEmpty ? null : s;
  }

  /// 可查表的城市代码数量（去重后）。
  int get length => _byCode.length;

  /// 条目总数（含无代码、无法查表的地区，如澳门）。
  int get entryCount => _entries.length;

  /// 全部条目（只读，供设置页统计或调试）。
  List<CityUnionCardInfo> get entries => List.unmodifiable(_entries);

  /// 查询城市目录参考，不用于确认实际卡名；未收录返回 null。
  CityUnionCardInfo? lookup(String? code) {
    if (code == null) return null;
    final key = code.trim();
    if (key.isEmpty) return null;
    return _byCode[key];
  }
}

/// 便捷方法：从 JSON 字符串解析 CU 识别库（解析失败返回空表）。
CityUnionCardTable parseCityUnionCardTable(String? source) {
  if (source == null || source.isEmpty) return CityUnionCardTable.empty;
  try {
    return CityUnionCardTable.fromJson(jsonDecode(source));
  } catch (_) {
    return CityUnionCardTable.empty;
  }
}
