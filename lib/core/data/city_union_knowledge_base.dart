import 'dart:convert';

/// 城市一卡通（City Union / CJ/T 331-2016）本地卡名称参考信息。
///
/// 数据源为 CU 卡片识别库（assets/data/cu_card_catalog.json）条目：
/// 城市代码（邮政编码前四位 / CU 城市项目代码）→ 城市名 / 省份 /
/// 本地交通卡名称参考。cardName 为公开资料查到的名称参考，不代表
/// 已确认该卡种带 City Union 应用，可信度由 [cardNameStatus] 标注。
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

/// 城市一卡通卡片识别库：城市代码（4 位）→ 本地卡信息。
///
/// 城市代码取自公共应用基本信息文件（SFI 0x15）字节 03-04 的 HEX 解码
/// 4 位数字（等同 BCD 编码的邮编前四位）。索引同时登记 postalPrefix 与
/// cuCityProjectCode 两个键；缺 city 或无任何代码的条目不参与匹配，
/// 未收录代码保持未知（返回 null，不猜测）。
class CityUnionCardTable {
  final Map<String, CityUnionCardInfo> _byCode;
  final List<CityUnionCardInfo> _entries;

  const CityUnionCardTable._(this._byCode, this._entries);

  static const empty = CityUnionCardTable._({}, []);

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
    return CityUnionCardTable._(byCode, entries);
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

  /// 城市代码（SFI 0x15 字节 03-04 的 HEX 解码 4 位数字）→ 本地卡信息；
  /// 未收录返回 null（不猜测）。
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