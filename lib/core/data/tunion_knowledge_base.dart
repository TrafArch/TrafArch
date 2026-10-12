import 'dart:convert';
import 'package:flutter/services.dart';

import 'station_codes.dart';
import 'prebuilt_station_data.dart';

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

  /// 钱包货币（ISO 4217 代码，如 'HKD' 港币）；条目未声明时为 null
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
/// 规则为 assets/data/ 下的版本化 JSON；站点代码表默认使用应用内预制
/// 快照（prebuilt_station_data.dart，读卡识途公开数据、开箱即用）。
/// 设置中开启「在线拉取数据」后，由上层注入本次会话拉取到的最新数据；
/// 进程重启后回到预制快照。
class KnowledgeBase {
  final CityTable cities;
  final IssuerTable issuers;
  final TerminalRuleSet terminalRules;

  /// 卡号前缀库（卡号前 8 位 → 卡片名称 / 发卡地）与卡种类型取值对照。
  final CardPrefixTable cardPrefixes;
  final StationCodeTable stationCodes;

  const KnowledgeBase({
    required this.cities,
    required this.issuers,
    required this.terminalRules,
    this.cardPrefixes = CardPrefixTable.empty,
    this.stationCodes = StationCodeTable.empty,
  });

  static const issuerAsset = 'assets/data/tunion_issuer_fingerprints.json';
  static const terminalRulesAsset = 'assets/data/tunion_terminal_rules.json';
  static const cardPrefixAsset = 'assets/data/tunion_card_prefixes.json';

  factory KnowledgeBase.empty() => KnowledgeBase(
        cities: CityTable.fromCardPrefixes(const {}),
        issuers: IssuerTable.fromJson(const {}),
        terminalRules: TerminalRuleSet.fromJson(const {}),
      );

  factory KnowledgeBase.fromJsonStrings({
    String? issuerFingerprints,
    String? terminalRules,
    String? cardPrefixes,
    StationCodeTable? stationCodes,
  }) {
    Object? decode(String? source, Object? fallback) {
      if (source == null || source.isEmpty) return fallback;
      try {
        return jsonDecode(source);
      } catch (_) {
        return fallback;
      }
    }

    // 城市码表与卡号前缀库同源：城市代码取条目 issuer 后 4 位，
    // 城市名取条目 city 字段。
    final prefixJson = decode(cardPrefixes, const {});
    return KnowledgeBase(
      cities: CityTable.fromCardPrefixes(prefixJson),
      issuers: IssuerTable.fromJson(decode(issuerFingerprints, const {})),
      terminalRules: TerminalRuleSet.fromJson(decode(terminalRules, const {})),
      cardPrefixes: CardPrefixTable.fromJson(prefixJson),
      stationCodes: stationCodes ?? prebuiltStationCodes,
    );
  }

  /// 加载知识库：机构/终端规则/卡号前缀（城市码表随卡号前缀库派生）读自
  /// assets；站点代码表默认使用应用内预制快照，开启「在线拉取数据」时由
  /// 调用方注入会话内存数据。
  static Future<KnowledgeBase> load(
    AssetBundle bundle, {
    StationCodeTable? stationCodes,
  }) async {
    // 卡号前缀库为增量资产：缺失/读取失败时降级为空表（城市码表随之
    // 为空），不阻断其余知识库加载
    String? cardPrefixes;
    try {
      cardPrefixes = await bundle.loadString(cardPrefixAsset);
    } catch (_) {
      cardPrefixes = null;
    }
    return KnowledgeBase.fromJsonStrings(
      issuerFingerprints: await bundle.loadString(issuerAsset),
      terminalRules: await bundle.loadString(terminalRulesAsset),
      cardPrefixes: cardPrefixes,
      stationCodes: stationCodes ?? prebuiltStationCodes,
    );
  }
}