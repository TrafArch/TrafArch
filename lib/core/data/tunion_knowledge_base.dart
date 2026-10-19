import 'dart:convert';
import 'package:flutter/services.dart';

import 'city_union_knowledge_base.dart';
import 'city_union_region_database.dart';
import 'station_codes.dart';
import 'tu_station_repository.dart';
import 'tunion_region_database.dart';

/// 城市信息。
///
/// province 为可选扩展字段：数据源条目未提供省份时为 null（不猜测）。
class CityInfo {
  final String code;
  final String name;
  final String? province;

  const CityInfo({required this.code, required this.name, this.province});
}

/// 城市码表：城市代码 → 城市信息。
///
/// 数据源为卡号前缀库（assets/data/tunion_card_prefixes.json）的 entries 字段：
/// 条目发卡机构代码（issuer，8 位）的后 4 位即城市代码（与卡片上报的
/// 2 字节城市代码同一体系），命中后取条目的 city 字段为城市名（条目的
/// province 可选字段为省份）。缺 issuer 或 city 的条目不参与匹配；
/// 未收录代码保持未知（返回 null，不猜测）。
class CityTable {
  /// 城市代码长度（发卡机构代码后 4 位）。
  static const _cityCodeLength = 4;

  final Map<String, CityInfo> _codes;
  const CityTable._(this._codes);

  factory CityTable.fromCardPrefixes(Object? json) {
    final codes = <String, CityInfo>{};
    final raw = json is Map ? json['entries'] : json;
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final issuer =
            '${e['issuer'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
        final city = e['city']?.toString();
        if (issuer.length < _cityCodeLength || city == null || city.isEmpty) {
          continue;
        }
        final code = issuer.substring(issuer.length - _cityCodeLength);
        codes.putIfAbsent(
          code,
          () => CityInfo(
            code: code,
            name: city,
            province: e['province']?.toString(),
          ),
        );
      }
    }
    return CityTable._(codes);
  }

  /// 直接由城市信息列表构建：相同城市代码保留首次出现者（调用方按
  /// 「数据库优先、JSON 兜底」的顺序传入）。
  factory CityTable.fromInfos(Iterable<CityInfo> infos) {
    final codes = <String, CityInfo>{};
    for (final info in infos) {
      if (info.code.isEmpty) continue;
      codes.putIfAbsent(info.code, () => info);
    }
    return CityTable._(codes);
  }

  /// 全部城市信息（供与外部数据源合并）。
  Iterable<CityInfo> get infos => _codes.values;

  int get length => _codes.length;

  CityInfo? lookup(String code) => _codes[code];
}

/// 发卡机构指纹：issuerId 为 SFI 0x15 发卡机构标识（8 字节 HEX）。
class IssuerInfo {
  final String issuerId;
  final String? cityCode;
  final String? cityName;
  final String? operatorName;
  final String? cardFamily;

  const IssuerInfo({
    required this.issuerId,
    this.cityCode,
    this.cityName,
    this.operatorName,
    this.cardFamily,
  });
}

/// 发卡机构指纹库。
class IssuerTable {
  final Map<String, IssuerInfo> _entries;
  const IssuerTable._(this._entries);

  /// 规范化：去除空格/冒号并大写。
  static String normalizeIssuerId(String id) =>
      id.replaceAll(' ', '').replaceAll(':', '').toUpperCase();

  factory IssuerTable.fromJson(Object? json) {
    final entries = <String, IssuerInfo>{};
    final raw = json is Map ? (json['entries'] ?? json['issuers']) : json;
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final id = '${e['issuerId'] ?? ''}';
        if (id.isEmpty) continue;
        final normalized = normalizeIssuerId(id);
        entries[normalized] = IssuerInfo(
          issuerId: normalized,
          cityCode: e['cityCode']?.toString(),
          cityName: e['cityName']?.toString(),
          operatorName: e['operator']?.toString(),
          cardFamily: e['cardFamily']?.toString(),
        );
      }
    } else if (raw is Map) {
      raw.forEach((key, value) {
        if (value is! Map) return;
        final normalized = normalizeIssuerId('$key');
        entries[normalized] = IssuerInfo(
          issuerId: normalized,
          cityCode: value['cityCode']?.toString(),
          cityName: value['cityName']?.toString(),
          operatorName: value['operator']?.toString(),
          cardFamily: value['cardFamily']?.toString(),
        );
      });
    }
    return IssuerTable._(entries);
  }

  int get length => _entries.length;

  IssuerInfo? lookup(String issuerId) => _entries[normalizeIssuerId(issuerId)];
}

/// 终端编号（TAC）解码规则。
///
/// 终端编号为 6 字节 BCD（12 位十进制字符串），线路/站点等字段的编码
/// 由各发卡方自行定义，必须通过实测校准后录入规则，禁止猜测。
class TerminalRule {
  final String id;
  final int priority;
  final String? matchTerminalPrefix;
  final String? matchCityCode;
  final String? matchIssuerId;

  /// 字段名 → [起始位, 结束位)，按 12 位数字下标。
  final Map<String, List<int>> layout;
  final String? note;

  const TerminalRule({
    required this.id,
    this.priority = 0,
    this.matchTerminalPrefix,
    this.matchCityCode,
    this.matchIssuerId,
    this.layout = const {},
    this.note,
  });

  bool matches(String digits, {String? cityCode, String? issuerId}) {
    // 三个匹配条件全空的规则视为无效，避免误配全部终端。
    if (matchTerminalPrefix == null &&
        matchCityCode == null &&
        matchIssuerId == null) {
      return false;
    }
    final prefix = matchTerminalPrefix;
    if (prefix != null && !digits.startsWith(prefix)) return false;
    if (matchCityCode != null && matchCityCode != cityCode) return false;
    if (matchIssuerId != null &&
        matchIssuerId!.toUpperCase() != issuerId?.toUpperCase()) {
      return false;
    }
    return true;
  }
}

/// 终端解码规则集（按 priority 降序匹配首个命中规则）。
class TerminalRuleSet {
  final List<TerminalRule> _rules;
  const TerminalRuleSet._(this._rules);

  factory TerminalRuleSet.fromJson(Object? json) {
    final rules = <TerminalRule>[];
    final raw = json is Map ? json['rules'] : json;
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final layout = <String, List<int>>{};
        final layoutRaw = e['layout'];
        if (layoutRaw is Map) {
          layoutRaw.forEach((key, value) {
            if (value is List && value.length >= 2) {
              layout['$key'] = [
                (value[0] as num).toInt(),
                (value[1] as num).toInt(),
              ];
            }
          });
        }
        final match = e['match'];
        rules.add(TerminalRule(
          id: '${e['id'] ?? 'rule-${rules.length}'}',
          priority: (e['priority'] as num?)?.toInt() ?? 0,
          matchTerminalPrefix:
              match is Map ? match['terminalPrefix']?.toString() : null,
          matchCityCode: match is Map ? match['cityCode']?.toString() : null,
          matchIssuerId: match is Map ? match['issuerId']?.toString() : null,
          layout: layout,
          note: e['note']?.toString(),
        ));
      }
    }
    rules.sort((a, b) => b.priority.compareTo(a.priority));
    return TerminalRuleSet._(rules);
  }

  int get length => _rules.length;

  TerminalRule? match(String digits, {String? cityCode, String? issuerId}) {
    for (final rule in _rules) {
      if (rule.matches(digits, cityCode: cityCode, issuerId: issuerId)) {
        return rule;
      }
    }
    return null;
  }
}

/// 卡号前缀（IIN）信息：交通联合卡号前 8 位 → 卡片名称 / 发卡地。
class CardPrefixInfo {
  final String prefix;
  final String cardName;
  final String? city;

  /// 钱包货币（ISO 4217 代码）；条目未声明时为 null
  /// （按人民币缺省口径处理，不猜测外币）。
  final String? currency;

  const CardPrefixInfo({
    required this.prefix,
    required this.cardName,
    this.city,
    this.currency,
  });
}

/// 卡号前缀库（卡号前 8 位 IIN 匹配）+ 卡种类型取值对照。
///
/// - entries：prefix → 卡片名称 / 发卡地（数据文件 assets/data/tunion_card_prefixes.json，
///   由公开号段资料与实测卡片持续校正）；
/// - cardKinds：SFI 0x17 管理信息文件「卡种类型」取值 → 名称，
///   未收录取值由展示层回退原始 HEX（不猜测）。
class CardPrefixTable {
  /// 标准 IIN 前缀长度（交通联合卡号前 8 位）。
  static const _prefixLength = 8;

  /// 匹配时的最短回退前缀长度（兼容录入较短的号段）。
  static const _minPrefixLength = 6;

  final Map<String, CardPrefixInfo> _entries;

  /// 发卡机构代码（条目 issuer 字段，取前 8 位）→ 前缀条目，
  /// 供卡片识别按发卡机构标识（SFI 0x15，8 字节）前 8 位反查卡片名称。
  final Map<String, CardPrefixInfo> _byIssuer;
  final Map<String, String> _cardKinds;

  const CardPrefixTable._(this._entries, this._byIssuer, this._cardKinds);

  static const empty = CardPrefixTable._({}, {}, {});

  factory CardPrefixTable.fromJson(Object? json) {
    final entries = <String, CardPrefixInfo>{};
    final byIssuer = <String, CardPrefixInfo>{};
    final cardKinds = <String, String>{};
    if (json is List) return CardPrefixTable.fromJson({'entries': json});
    if (json is Map) {
      final raw = json['entries'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final prefix =
              '${e['prefix'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          final name = '${e['cardName'] ?? e['name'] ?? ''}';
          if (prefix.isEmpty || name.isEmpty) continue;
          final info = CardPrefixInfo(
            prefix: prefix,
            cardName: name,
            city: e['city']?.toString(),
            currency: e['currency']?.toString(),
          );
          entries[prefix] = info;
          // 发卡机构代码（issuer）登记为反查键：同一代码多条前缀时保留首条
          final issuer =
              '${e['issuer'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
          if (issuer.isNotEmpty) {
            final issuerKey = issuer.length <= _prefixLength
                ? issuer
                : issuer.substring(0, _prefixLength);
            byIssuer.putIfAbsent(issuerKey, () => info);
          }
        }
      }
      final kinds = json['cardKinds'];
      if (kinds is Map) {
        kinds.forEach((key, value) {
          final k = '$key'.replaceAll(' ', '').toUpperCase();
          if (k.isEmpty || value == null) return;
          cardKinds[k] = '$value';
        });
      }
    }
    return CardPrefixTable._(entries, byIssuer, cardKinds);
  }

  /// 由「已合并」的卡号前缀条目构建（[mergedEntries] 每项含
  /// prefix / cardName / city / issuer / currency），叠加 meta 的
  /// 卡种对照 [cardKinds]；同 prefix 保留首条（调用方按数据库优先排序）。
  factory CardPrefixTable.fromMergedEntries(
    Iterable<Map<String, dynamic>> mergedEntries, {
    Map<String, String> cardKinds = const {},
  }) {
    final entries = <String, CardPrefixInfo>{};
    final byIssuer = <String, CardPrefixInfo>{};
    for (final e in mergedEntries) {
      final prefix = '${e['prefix'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      final name = '${e['cardName'] ?? ''}';
      if (prefix.isEmpty || name.isEmpty) continue;
      final info = CardPrefixInfo(
        prefix: prefix,
        cardName: name,
        city: e['city']?.toString(),
        currency: e['currency']?.toString(),
      );
      entries[prefix] = info;
      final issuer = '${e['issuer'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (issuer.isNotEmpty) {
        final issuerKey = issuer.length <= _prefixLength
            ? issuer
            : issuer.substring(0, _prefixLength);
        byIssuer.putIfAbsent(issuerKey, () => info);
      }
    }
    return CardPrefixTable._(entries, byIssuer, cardKinds);
  }

  int get length => _entries.length;

  /// 卡号（应用序列号）→ 前缀信息：按前 8 位 IIN 匹配（最长前缀优先）；
  /// 卡号过短或未收录时返回 null（不猜测）。
  CardPrefixInfo? lookup(String? cardNumber) {
    if (cardNumber == null) return null;
    final digits = cardNumber.replaceAll(RegExp(r'[^0-9]'), '');
    for (var len = _prefixLength; len >= _minPrefixLength; len--) {
      if (digits.length < len) continue;
      final hit = _entries[digits.substring(0, len)];
      if (hit != null) return hit;
    }
    return null;
  }

  /// 发卡机构标识（SFI 0x15，8 字节 HEX）→ 前缀信息：取前 8 位先比对
  /// 条目发卡机构代码（issuer），未命中再回退比对卡号前缀（prefix）；
  /// 未收录时返回 null（不猜测）。
  CardPrefixInfo? lookupByIssuerId(String? issuerId) {
    if (issuerId == null) return null;
    final cleaned =
        issuerId.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (cleaned.isEmpty) return null;
    final key = cleaned.length <= _prefixLength
        ? cleaned
        : cleaned.substring(0, _prefixLength);
    return _byIssuer[key] ?? _entries[key];
  }

  /// 卡种类型取值（HEX 字符串）→ 名称；未收录时返回 null（展示层回退原始值）。
  String? cardKindName(String? hex) {
    if (hex == null) return null;
    final key = hex.replaceAll(' ', '').toUpperCase();
    return key.isEmpty ? null : _cardKinds[key];
  }
}

/// 交通知识库：城市码表 + 发卡机构指纹库 + 终端解码规则库 + 站点代码表。
///
/// 数据源：城市码表由卡号前缀库（assets/data/tunion_card_prefixes.json）的
/// 发卡机构代码字段派生（后 4 位为城市代码）；发卡机构指纹与终端解码
/// 规则为 assets/data/ 下的版本化 JSON；站点代码表完全来自两个外部 SQLite
/// 数据库（交通联合 TrafArch_Database_TU.sqlite 与城市一卡通
/// TrafArch_Database_CU.sqlite，数据库优先、JSON 兜底），不再内置预制快照。
class KnowledgeBase {
  final CityTable cities;
  final IssuerTable issuers;
  final TerminalRuleSet terminalRules;

  /// 卡号前缀库（卡号前 8 位 → 卡片名称 / 发卡地）与卡种类型取值对照。
  final CardPrefixTable cardPrefixes;
  final StationCodeTable stationCodes;

  /// 城市一卡通（City Union / CJ/T 331-2016）卡片识别库：城市代码
  /// （邮编前四位 / CU 城市项目代码）→ 城市名 / 省份 / 本地卡名称参考。
  final CityUnionCardTable cityUnionCards;

  /// 城市一卡通终端索引匹配器（terminal_index 精确 / 前缀）：CU 行程交易
  /// 终端编号 → 站点。空表示未加载 CU 站点数据库（展示层回退，不猜测）。
  final CityUnionTerminalMatcher cuTerminals;

  /// 站点覆盖原始数据集（交通联合 + 城市一卡通各地区的线路 / 站点），
  /// 保留原始 system / cityName / province 与逐站点条目，供设置「知识库」
  /// 子页面展示当前数据库支持的地区、线路与站点。
  final List<StationDataset> coverageDatasets;

  /// 外部 SQLite 数据库版本号（PRAGMA user_version）：null 表示未加载
  /// 或库内未设置版本，供「知识库」页数据概况展示与 release 校验。
  final int? tuDatabaseVersion;
  final int? cuDatabaseVersion;

  /// 交通联合原始地区表查询入口（用户覆盖 + 未知站点上报）。
  /// 为 null 表示 TU 数据库未加载；页面应经此查询，不要自行拼 SQL。
  final TuStationRepository? tuStations;

  const KnowledgeBase({
    required this.cities,
    required this.issuers,
    required this.terminalRules,
    this.cardPrefixes = CardPrefixTable.empty,
    this.stationCodes = StationCodeTable.empty,
    this.cityUnionCards = CityUnionCardTable.empty,
    this.cuTerminals = CityUnionTerminalMatcher.empty,
    this.coverageDatasets = const [],
    this.tuDatabaseVersion,
    this.cuDatabaseVersion,
    this.tuStations,
  });

  static const issuerAsset = 'assets/data/tunion_issuer_fingerprints.json';
  static const terminalRulesAsset = 'assets/data/tunion_terminal_rules.json';
  static const cardPrefixAsset = 'assets/data/tunion_card_prefixes.json';
  static const cityUnionCardAsset = 'assets/data/cu_card_catalog.json';
  static const cardMetaAsset = 'assets/data/tunion_card_meta.json';

  factory KnowledgeBase.empty() => KnowledgeBase(
        cities: CityTable.fromCardPrefixes(const {}),
        issuers: IssuerTable.fromJson(const {}),
        terminalRules: TerminalRuleSet.fromJson(const {}),
      );

  factory KnowledgeBase.fromJsonStrings({
    String? issuerFingerprints,
    String? terminalRules,
    String? cardPrefixes,
    String? cityUnionCatalog,
    StationCodeTable? stationCodes,
    TunionRegionDatabaseContent? regionContent,
    CityUnionRegionDatabaseContent? cuRegionContent,
    String? cardMeta,
  }) {
    Object? decode(String? source, Object? fallback) {
      if (source == null || source.isEmpty) return fallback;
      try {
        return jsonDecode(source);
      } catch (_) {
        return fallback;
      }
    }

    final prefixJson = decode(cardPrefixes, const {});
    final metaJson = decode(cardMeta, const {});
    final cardKinds = <String, String>{};
    final currencyByPrefix = <String, String>{};
    if (metaJson is Map) {
      final kinds = metaJson['cardKinds'];
      if (kinds is Map) {
        kinds.forEach((key, value) {
          final k = '$key'.replaceAll(' ', '').toUpperCase();
          if (k.isEmpty || value == null) return;
          cardKinds[k] = '$value';
        });
      }
      final currencies = metaJson['currencyByPrefix'];
      if (currencies is Map) {
        currencies.forEach((key, value) {
          final p = '$key'.replaceAll(RegExp(r'[^0-9]'), '');
          if (p.isEmpty || value == null) return;
          currencyByPrefix[p] = '$value';
        });
      }
    }

    // 1A：卡号前缀库与城市码表均以「数据库优先 + JSON 兜底」合并；
    // 数据库缺失时与既有实现完全一致（不改变旧行为）。
    final mergedPrefixEntries =
        _mergePrefixEntries(prefixJson, regionContent, currencyByPrefix);
    // meta 卡种并入（数据库不含卡种），未提供 meta 时回退旧 JSON cardKinds
    final prefixTable = CardPrefixTable.fromMergedEntries(
      mergedPrefixEntries,
      cardKinds: cardKinds.isNotEmpty
          ? cardKinds
          : _cardKindsOf(prefixJson),
    );

    final cityInfos = <CityInfo>[
      ..._regionCityInfos(regionContent),
      ..._cuCityInfos(cuRegionContent),
      ...CityTable.fromCardPrefixes(prefixJson).infos,
    ];

    final baseStations = stationCodes ?? StationCodeTable.empty;
    final tuLive = regionContent?.live;
    final cuLive = cuRegionContent?.live;
    final coverageDatasets = <StationDataset>[
      // TU / CU 均为惰性数据集：页面展开时才点查，不整表物化。
      ...?tuLive?.lazyDatasets(),
      ...?cuLive?.lazyDatasets(),
    ];

    var stationTable = baseStations;
    if (tuLive != null || cuLive != null) {
      // CU 在前保持旧「内存 CU 优先于 TU live」的查询顺序。
      stationTable = stationTable.withLiveSources([
        if (cuLive != null) cuLive,
        if (tuLive != null) tuLive,
      ]);
    }

    return KnowledgeBase(
      cities: CityTable.fromInfos(cityInfos),
      issuers: IssuerTable.fromJson(decode(issuerFingerprints, const {})),
      terminalRules: TerminalRuleSet.fromJson(decode(terminalRules, const {})),
      cardPrefixes: prefixTable,
      cityUnionCards:
          CityUnionCardTable.fromJson(decode(cityUnionCatalog, const {})),
      cuTerminals:
          cuRegionContent?.terminalMatcher ?? CityUnionTerminalMatcher.empty,
      coverageDatasets: coverageDatasets,
      tuDatabaseVersion: regionContent?.databaseVersion,
      cuDatabaseVersion: cuRegionContent?.databaseVersion,
      stationCodes: stationTable,
      tuStations: regionContent?.repository,
    );
  }

  /// JSON 前缀库 entries（列表或 {entries:[...]}）。
  static List<dynamic> _entriesOf(Object? json) {
    final raw = json is Map ? json['entries'] : json;
    return raw is List ? raw : const [];
  }

  /// 旧 JSON 内联 cardKinds（meta 未提供时的兜底）。
  static Map<String, String> _cardKindsOf(Object? json) {
    final out = <String, String>{};
    if (json is Map) {
      final kinds = json['cardKinds'];
      if (kinds is Map) {
        kinds.forEach((key, value) {
          final k = '$key'.replaceAll(' ', '').toUpperCase();
          if (k.isEmpty || value == null) return;
          out[k] = '$value';
        });
      }
    }
    return out;
  }

  /// 合并卡号前缀条目：JSON 建基表，数据库同前缀覆盖非空字段（1A 数据库
  /// 优先），最后套用 meta 的按前缀货币覆盖。
  static List<Map<String, dynamic>> _mergePrefixEntries(
    Object? prefixJson,
    TunionRegionDatabaseContent? region,
    Map<String, String> currencyByPrefix,
  ) {
    const prefixLength = 8;
    final map = <String, Map<String, dynamic>>{};
    for (final e in _entriesOf(prefixJson)) {
      if (e is! Map) continue;
      final prefix = '${e['prefix'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (prefix.isEmpty) continue;
      map[prefix] = {
        'prefix': prefix,
        'cardName': e['cardName'] ?? e['name'],
        'city': e['city'],
        'currency': e['currency'],
        'issuer': e['issuer'],
      };
    }
    if (region != null) {
      for (final row in region.issuerCityCodes) {
        final raw = row.prefix.isNotEmpty ? row.prefix : row.issuer;
        if (raw.isEmpty) continue;
        final key = raw.length > prefixLength
            ? raw.substring(0, prefixLength)
            : raw;
        final entry = map[key] ?? <String, dynamic>{'prefix': key};
        if ((row.cardName ?? '').isNotEmpty) entry['cardName'] = row.cardName;
        if (row.cityName.isNotEmpty) entry['city'] = row.cityName;
        if (row.issuer.isNotEmpty) entry['issuer'] = row.issuer;
        map[key] = entry;
      }
    }
    currencyByPrefix.forEach((prefix, code) {
      final entry = map[prefix];
      if (entry != null) entry['currency'] = code;
    });
    return map.values.toList();
  }

  /// 数据库城市信息（地区名 + 发卡号段城市名，均优先于 JSON 派生城市）。
  static List<CityInfo> _regionCityInfos(TunionRegionDatabaseContent? region) {
    if (region == null) return const [];
    final out = <CityInfo>[];
    for (final r in region.regions) {
      if (r.regionCode.isEmpty || r.regionName.isEmpty) continue;
      out.add(CityInfo(
        code: r.regionCode,
        name: r.regionName,
        province: r.province,
      ));
    }
    for (final i in region.issuerCityCodes) {
      final code = i.regionCode.isNotEmpty
          ? i.regionCode
          : (i.issuer.length >= 4
              ? i.issuer.substring(i.issuer.length - 4)
              : '');
      if (code.isEmpty || i.cityName.isEmpty) continue;
      out.add(CityInfo(code: code, name: i.cityName));
    }
    return out;
  }

  /// 城市一卡通（CU）数据库城市信息：regions + region_codes 城市字典
  /// （4 位 CU 邮编前缀 → 地区名），排在交通联合之后、JSON 之前。
  static List<CityInfo> _cuCityInfos(CityUnionRegionDatabaseContent? cu) {
    if (cu == null) return const [];
    final out = <CityInfo>[];
    for (final c in cu.cities) {
      if (c.regionCode.isEmpty || c.regionName.isEmpty) continue;
      out.add(CityInfo(code: c.regionCode, name: c.regionName));
    }
    return out;
  }

  /// 加载知识库：机构/终端规则/城市一卡通识别库读自 assets；站点数据完全
  /// 迁移至两个外部 SQLite 数据库——交通联合 TrafArch_Database_TU.sqlite
  /// 与城市一卡通 TrafArch_Database_CU.sqlite（数据库优先、JSON 兜底），
  /// 卡号前缀库合并进城市码表，cardKinds / currency 从独立 meta 资产读取。
  /// 任一数据库 / meta 缺失或读取失败均降级，不阻断其余知识库加载。
  static Future<KnowledgeBase> load(
    AssetBundle bundle, {
    StationCodeTable? stationCodes,
  }) async {
    // 所有小资产与两个数据库同时发起加载；任一缺失仅降级，不阻断其余源。
    final cardPrefixesFuture = _safeLoadString(bundle, cardPrefixAsset);
    final cityUnionCatalogFuture = _safeLoadString(bundle, cityUnionCardAsset);
    final cardMetaFuture = _safeLoadString(bundle, cardMetaAsset);
    final issuerFuture = _safeLoadString(bundle, issuerAsset);
    final terminalRulesFuture = _safeLoadString(bundle, terminalRulesAsset);
    final regionFuture = TunionRegionDatabase.load(bundle: bundle);
    final cuRegionFuture = CityUnionRegionDatabase.load(bundle: bundle);

    return KnowledgeBase.fromJsonStrings(
      issuerFingerprints: await issuerFuture,
      terminalRules: await terminalRulesFuture,
      cardPrefixes: await cardPrefixesFuture,
      cityUnionCatalog: await cityUnionCatalogFuture,
      stationCodes: stationCodes ?? StationCodeTable.empty,
      regionContent: await regionFuture,
      cuRegionContent: await cuRegionFuture,
      cardMeta: await cardMetaFuture,
    );
  }

  /// 安全读取文本资产：缺失 / 读取异常返回 null（调用方按缺省口径降级，
  /// 不阻断其余数据源加载）。
  static Future<String?> _safeLoadString(AssetBundle bundle, String path) async {
    try {
      return await bundle.loadString(path);
    } catch (_) {
      return null;
    }
  }
}