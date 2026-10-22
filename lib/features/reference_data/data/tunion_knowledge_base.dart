import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/city_union_knowledge_base.dart';
import 'city_union_region_database.dart';
import '../domain/station_codes.dart';
import 'tu_station_repository.dart';
import 'tu_region_live_source.dart';
import 'tu_database.dart';

import '../domain/card_catalog.dart';
import '../domain/tu_lookup_service.dart';
export '../domain/card_catalog.dart';

/// Independently loaded TU/CU reference catalogs and owned query resources.
/// Source normalization occurs only in tools/reference_data. Runtime consumes
/// published domain documents and original SQLite fields.
class KnowledgeBase {
  final CityTable cities;
  final CityTable? cuCities;
  final Map<String, String> loadIssues;
  final Map<String, String> packageVersions;
  final Map<String, String> packageHashes;
  final List<void Function()> closers;
  final CityUnionRegionKnowledgeDb? cuRepository;
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

  /// 发布包格式版本号：null 表示未加载
  /// 或库内未设置版本，供「知识库」页数据概况展示与 release 校验。
  final int? tuDatabaseVersion;
  final int? cuDatabaseVersion;

  /// 交通联合原始地区表查询入口（用户覆盖 + 未知站点上报）。
  /// 为 null 表示 TU 数据库未加载；页面应经此查询，不要自行拼 SQL。
  final TuStationRepository? tuStations;

  /// 原 m756j / m761o / m762p 语义的离线查询入口：完整键最长前缀、
  /// 城市专用布局、本地终端别名与按日期生效的历史名称。
  /// 为 null 表示 TU 数据库未加载（展示层回退原始编码）。
  final TuLookupService? tuLookup;

  const KnowledgeBase({
    required this.cities,
    this.cuCities,
    this.loadIssues = const {},
    this.packageVersions = const {},
    this.packageHashes = const {},
    this.closers = const [],
    this.cuRepository,
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
    this.tuLookup,
  });

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
  }) {
    Object? decode(String? value) =>
        value == null ? const {} : jsonDecode(value);
    final prefixes = decode(cardPrefixes);
    return KnowledgeBase(
      cities: CityTable.fromCardPrefixes(prefixes),
      issuers: IssuerTable.fromJson(decode(issuerFingerprints)),
      terminalRules: TerminalRuleSet.fromJson(decode(terminalRules)),
      cardPrefixes: CardPrefixTable.fromJson(prefixes),
      cityUnionCards: CityUnionCardTable.fromJson(decode(cityUnionCatalog)),
      stationCodes: stationCodes ?? StationCodeTable.empty,
    );
  }

  /// The package builder resolves source priority. Runtime only decodes the
  /// published domain documents and queries the independently owned databases.
  static Future<KnowledgeBase> load(
    AssetBundle bundle, {
    StationCodeTable? stationCodes,
  }) async {
    final issues = <String, String>{};
    TuDatabase? tu;
    CityUnionRegionDatabaseContent? cu;
    final tuDocuments = <String, Object?>{};
    Object? cuCatalog;
    await Future.wait([
      () async {
        try {
          tu = await TuDatabase.open(bundle: bundle);
          final owner = tu!;
          for (final name in [
            'cities',
            'card_prefixes',
            'issuers',
            'terminal_rules',
          ]) {
            tuDocuments[name] = owner.package.document(name);
          }
          if (owner.userStorageError != null) {
            issues['user_data'] = owner.userStorageError!;
          }
        } catch (e) {
          tu?.close();
          tu = null;
          tuDocuments.clear();
          issues['TU'] = '$e';
        }
      }(),
      () async {
        try {
          cu = await CityUnionRegionDatabase.load(bundle: bundle);
          cuCatalog = cu!.live!.package.document('card_catalog');
        } catch (e) {
          cu?.live?.close();
          cu = null;
          issues['CU'] = '$e';
        }
      }(),
    ]);
    try {
      final cityDocument = tuDocuments['cities'];
      final rawCities = cityDocument is Map ? cityDocument['entries'] : null;
      final tuCities = <CityInfo>[
        if (rawCities is List)
          for (final r in rawCities)
            if (r is Map)
              CityInfo(
                code: '${r['code']}',
                name: '${r['name']}',
                province: r['province'] as String?,
              ),
      ];
      return KnowledgeBase(
        cities: CityTable.fromInfos(tuCities),
        cuCities: CityTable.fromInfos([
          for (final r in cu?.cities ?? const <CuRegionRow>[])
            CityInfo(code: r.regionCode, name: r.regionName),
        ]),
        issuers: IssuerTable.fromJson(tuDocuments['issuers']),
        terminalRules: TerminalRuleSet.fromJson(tuDocuments['terminal_rules']),
        cardPrefixes: CardPrefixTable.fromJson(tuDocuments['card_prefixes']),
        cityUnionCards: CityUnionCardTable.fromJson(cuCatalog),
        cuTerminals: cu?.terminalMatcher ?? CityUnionTerminalMatcher.empty,
        cuRepository: cu?.live,
        stationCodes: (stationCodes ?? StationCodeTable.empty).withLiveSources([
          if (tu != null) TuRegionLiveSource(tu!.repository),
        ]),
        coverageDatasets: [
          if (tu != null) ...TuRegionLiveSource(tu!.repository).lazyDatasets(),
          ...?cu?.live?.lazyDatasets(),
        ],
        tuStations: tu?.repository,
        tuLookup: tu == null ? null : TuLookupService(tu!.repository),
        tuDatabaseVersion: tu?.userVersion,
        cuDatabaseVersion: cu?.databaseVersion,
        packageVersions: {
          if (tu != null) 'TU': tu!.package.version,
          if (cu?.live != null) 'CU': cu!.live!.package.version,
        },
        packageHashes: {
          if (tu != null) 'TU': tu!.package.hash,
          if (cu?.live != null) 'CU': cu!.live!.package.hash,
        },
        loadIssues: Map.unmodifiable(issues),
        closers: [
          if (tu != null) tu!.close,
          if (cu?.live != null) cu!.live!.close,
        ],
      );
    } catch (_) {
      tu?.close();
      cu?.live?.close();
      rethrow;
    }
  }

  void close() {
    for (final close in closers) {
      close();
    }
  }
}
