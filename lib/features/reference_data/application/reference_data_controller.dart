import 'package:flutter/services.dart';

import '../data/tunion_knowledge_base.dart';
import '../data/tunion_bus_location.dart';
import '../domain/station_codes.dart';
import '../../../shared/application/owned_notifier.dart';

class ReferenceDataController extends OwnedNotifier {
  ReferenceDataController(this.bundle);
  final AssetBundle bundle;
  KnowledgeBase? _kb;
  KnowledgeBase? get knowledge => _kb;
  String? error;
  Future<void>? _loading;
  Future<void> initialize() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final loaded = await KnowledgeBase.load(bundle);
      if (disposed) {
        loaded.close();
        return;
      }
      _kb = loaded;
    } catch (e) {
      if (!disposed) error = '$e';
    }
    notifyListeners();
  }

  String? cuCityNameOf(String? code) =>
      code == null ? null : _kb?.cuCities?.lookup(code)?.name;
  @override
  void dispose() {
    _kb?.close();
    super.dispose();
  }

  String? cityNameOf(String? code) {
    if (code == null || code.isEmpty) return null;
    final kb = _kb;
    if (kb == null) return null;
    return kb.cities.lookup(code.toUpperCase())?.name ??
        kb.cities.lookup(code)?.name;
  }

  /// 卡号（应用序列号）前缀（IIN，前 8 位）→ 卡片名称 / 发卡地；
  /// 未收录或知识库未加载时返回 null（展示层回退识别结果）。
  CardPrefixInfo? cardPrefixOf(String? cardNumber) {
    if (cardNumber == null || cardNumber.isEmpty) return null;
    return _kb?.cardPrefixes.lookup(cardNumber);
  }

  /// 发卡机构标识（SFI 0x15，8 字节 HEX）前 8 位 → 卡前缀条目
  /// （先比发卡机构代码，再回退 IIN 前缀），供卡片识别展示卡片名称；
  /// 未收录或知识库未加载时返回 null（展示层回退"未知"）。
  CardPrefixInfo? cardPrefixByIssuerId(String? issuerId) {
    if (issuerId == null || issuerId.isEmpty) return null;
    return _kb?.cardPrefixes.lookupByIssuerId(issuerId);
  }

  /// 卡种类型取值（SFI 0x17 卡种类型，HEX 字符串）→ 名称；
  /// 未收录或知识库未加载时返回 null（展示层回退原始 HEX）。
  String? cardKindName(String? hex) => _kb?.cardPrefixes.cardKindName(hex);

  /// 站点匹配（含置信级别）：TU 通道按「城市 + 线路 + 站点」三键查表
  /// （无线路号时按站点末 4 位单维查表），未命中再按 TU 完整来源键
  /// 查表；只认查表命中，查不到表一律未匹配，歧义
  /// 不强行显示站名。
  StationMatch resolveStationMatch(
    String? cityCode,
    String? rawCode, {
    int? lineValue,
  }) {
    final kb = _kb;
    if (kb == null || kb.loadIssues.containsKey('TU')) {
      return StationMatch.unavailable;
    }
    if (rawCode == null || rawCode.isEmpty) {
      return StationMatch.unmatched;
    }
    final city = _lookupCityCode(cityCode);
    if (city == null) return StationMatch.unmatched;
    final code = rawCode.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (code.isEmpty) return StationMatch.unmatched;
    final tu = kb.stationCodes.matchTuStationByCardId(
      rawStationId: code,
      cityCode: city,
      lineValue: lineValue,
    );
    if (!tu.isUnmatched) return tu;
    final fallback = kb.stationCodes.lookupStation(
      rawCode: code,
      cityCode: city,
    );
    if (fallback != null) {
      return StationMatch(fallback, StationMatchConfidence.exact);
    }
    return StationMatch.unmatched;
  }

  /// 0x1E「线路和站点代码」匹配置信版：先按原 m756j / m762p / m761o
  /// 语义走完整键、城市专用布局与终端别名，未命中时保留片段兜底。
  StationMatch resolveCycleStationMatch(
    String? cityCode,
    String? field, {
    String? terminalId,
    DateTime? time,
    int? appType,
  }) {
    final kb = _kb;
    if (kb == null || kb.loadIssues.containsKey('TU')) {
      return StationMatch.unavailable;
    }
    if (field == null || field.isEmpty) {
      return StationMatch.unmatched;
    }
    final city = _lookupCityCode(cityCode);
    final lookup = kb.tuLookup;
    if (lookup != null) {
      final source = lookup.resolveCycle(
        city: city,
        field: field,
        terminalId: terminalId,
        time: time,
        appType: appType ?? 0x01,
      );
      if (!source.isUnmatched) return source;
    }
    return kb.stationCodes.matchLineStationField(field: field, cityCode: city);
  }

  TunionBusLocation resolveBusLocation(
    String? cityCode,
    String? field, {
    TunionBusDecodeContext context = const TunionBusDecodeContext(),
  }) => resolveTunionBusLocation(
    stations: _kb?.stationCodes ?? StationCodeTable.empty,
    cityCode: _lookupCityCode(cityCode),
    field: field,
    context: context,
  );

  String? resolveStationName(String? cityCode, String? rawCode) {
    final match = resolveStationMatch(cityCode, rawCode);
    // 歧义 / 未匹配不强行显示站名（展示层回退原始编码）。
    if (match.confidence == StationMatchConfidence.exact) {
      return match.entry?.displayLabel;
    }
    return null;
  }

  String? resolveLineName(String? cityCode, String? rawLineCode) {
    final kb = _kb;
    if (kb == null || rawLineCode == null || rawLineCode.isEmpty) return null;
    final city = _lookupCityCode(cityCode);
    if (city == null) return null;
    final code = rawLineCode.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (code.isEmpty) return null;
    final tu = kb.stationCodes.matchTuLineByCardValue(
      rawLineCode: code,
      cityCode: city,
    );
    if (tu.confidence == StationMatchConfidence.ambiguous) return null;
    if (tu.entry?.line != null) return tu.entry!.line;
    return kb.stationCodes.lookupLineName(rawLineCode: code, cityCode: city);
  }

  /// 城市一卡通（CU）交易终端编号 → 站点名：经 CU 站点数据库 terminal_index
  /// 的精确 / 前缀规则匹配（严格同地区、键更长者优先、按已解码载体类型过滤）；
  /// 未命中、终端编号缺失或知识库未加载时返回 null（展示层回退，不猜测）。
  String? resolveCuStationName(
    String? terminalNumber, {
    String? cityCode,
    int? decodedCarrierType,
    DateTime? transactionTime,
    bool busLookupEnabled = false,
  }) {
    final kb = _kb;
    if (kb == null || terminalNumber == null || terminalNumber.isEmpty) {
      return null;
    }
    return kb.cuTerminals
        .match(
          terminalNumber,
          cityCode: cityCode,
          decodedCarrierType: decodedCarrierType,
          transactionTime: transactionTime,
          busLookupEnabled: busLookupEnabled,
        )
        ?.displayLabel;
  }

  /// 城市代码查询键规范化：空 / 全 0（未写入）视为无效（返回 null）；
  /// 与 [_isUnsetCityCode] 同口径，供站点名精确匹配使用。
  String? _lookupCityCode(String? code) {
    if (code == null) return null;
    final t = code.trim();
    if (t.isEmpty || t.replaceAll('0', '').isEmpty) return null;
    return t.toUpperCase();
  }
}
