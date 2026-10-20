import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/analysis/tunion_analysis_engine.dart';
import '../core/analysis/tunion_analysis_models.dart';
import '../core/app_info.dart';
import '../core/card/card_parser.dart';
import '../core/data/tunion_knowledge_base.dart';
import '../core/data/city_union_knowledge_base.dart';
import '../core/data/settings_store.dart';
import '../core/data/station_codes.dart';
import '../core/felica/felica.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_exporter.dart';
import '../core/nfc/felica_channel.dart';
import '../core/nfc/nfc_models.dart';
import '../core/nfc/nfc_service.dart';
import '../core/qr/gms_qr_scanner.dart';
import '../core/transit/city_union/city_union_models.dart';
import '../core/transit/local_card/cards/shanghai_transit_union_models.dart';
import '../core/transit/local_card/local_card_models.dart';
import '../core/transit/local_card/local_card_parser.dart';
import '../core/transit/tunion/qr/jt_t1179_qr_parser.dart';
import '../core/transit/tunion/tunion_models.dart';
import '../core/transit/tunion/tunion_process_parser.dart';
import '../database/app_database.dart';
import '../features/bank_card/domain/models/bank_card_result.dart';
import '../features/bank_card/parsers/bank_card_analyzer.dart';
import '../features/bank_card/parsers/bank_card_probe_impl.dart';
import '../features/bank_card/parsers/emv/emv_parser.dart';
import '../features/bank_card/parsers/pboc/pboc_parser.dart';
import '../features/card_archive/card_records_export.dart';
import '../features/card_archive/models/card_session_snapshot.dart';
import '../features/card_archive/models/pending_card_save.dart';
import '../features/card_archive/repositories/card_repository.dart';
import '../features/card_archive/services/card_identification_service.dart';

/// 应用级状态与会话编排：NFC 通道 → 解析器 → 分析引擎。
///
/// 职责：
/// - 知识库加载（JSON 资产 + 站点数据：本地数据库 / 预制快照）；
/// - 扫描会话管理（世代号防止旧请求误杀新扫描）；
/// - 读卡流程编排：scanOnce → LocalCardParser（统一识读模块，内含
///   交通联合 / 城市一卡通 / 地方交通卡探测）→ AnalysisEngine.analyze；
/// - 卡片档案：解析成功后识别卡型 / 正式卡名，待用户确认后归档
///   （不覆盖用户自定义名称）；
/// - APDU 日志（专家页会话展示）与运行日志（持久化，可导出）；
/// - 一切对外状态。
class AppState extends ChangeNotifier {
  AppState({
    NfcChannel? channel,
    FelicaChannel? felicaChannel,
    AssetBundle? bundle,
    SettingsStore? settingsStore,
    AppLogger? logger,
    LogExporter? logExporter,
    AppDatabase? database,
  })  : _channel = channel ?? const MethodChannelNfcChannel(),
        _felicaChannel = felicaChannel ?? const MethodChannelFelicaChannel(),
        _bundle = bundle,
        _settingsStore = settingsStore ?? FileSettingsStore(),
        _logger = logger ?? AppLogger(),
        _logExporter = logExporter ?? const MethodChannelLogExporter(),
        cardRepository = CardRepository(database ?? AppDatabase());

  final NfcChannel _channel;

  /// NFC-F（FeliCa）原始帧通道：与 [_channel] 共用原生 NFC 连接，
  /// 仅补充 FeliCa 帧收发（卡种识别与解析在 core/felica 模块内）。
  final FelicaChannel _felicaChannel;
  final AssetBundle? _bundle;

  /// 设置持久化（app_settings.txt 文本键值对；测试注入内存实现）。
  final SettingsStore _settingsStore;

  /// 运行日志记录（应用私有目录持久化；测试注入内存实现）。
  final AppLogger _logger;

  /// 日志导出通道（保存到手机下载目录；测试注入假实现）。
  final LogExporter _logExporter;

  /// 卡片档案仓库（识别结果与用户自定义名称分离持久化；
  /// 重复读取更新识别结果但绝不覆盖自定义名称）。
  final CardRepository cardRepository;

  KnowledgeBase? _kb;
  AnalysisEngine? _engine;

  /// 卡片识别引擎（随知识库加载）：解析结果 → 卡型 / 正式卡名 /
  /// 城市 / 发行方，供卡片档案归档使用。
  CardIdentificationService? _identification;

  /// 待用户确认保存的卡片档案（首页「是否保存」确认对话框）；
  /// 确认 / 放弃后清空，仅在最近一次读取解析成功后存在。
  PendingCardSave? _pendingSave;
  PendingCardSave? get pendingCardSave => _pendingSave;

  String? _lastFingerprint;
  /// 最近一次读取卡片的稳定指纹（用于卡片详情页匹配当前会话行程数据）；
  /// 新会话开始时清空、读取识别成功后更新，应用重启后不保留（不持久化）。
  String? get lastCardFingerprint => _lastFingerprint;

  IdentifiedCard? _lastIdentified;

  /// 最近一次读取卡片的识别结果（卡型 / 正式卡名 / 发卡地 / 发行方）；
  /// 供首页「最近扫描」等展示层直接消费（识别规则集中在识别引擎）；
  /// 新会话开始时清空，识别失败（无法生成稳定指纹）时保持 null。
  IdentifiedCard? get lastIdentified => _lastIdentified;

  NfcScanResult? _lastResult;
  NfcScanResult? get lastResult => _lastResult;

  bool _scanning = false;
  bool get scanning => _scanning;

  bool _parsing = false;
  bool get parsing => _parsing;

  /// 读卡解析进度（0–100）：等待贴卡 / 知识库准备等无法量化阶段为 null，
  /// 由统一识读模块的进度回调驱动，供首页进度条展示。
  int? _readProgress;
  int? get readProgress => _readProgress;

  // 自动读取模式：应用启动后自动进入读取模式；
  // 仅在成功读取过一次卡片后结束，此后再次读取必须由用户点击按钮触发。
  bool _autoScanConsumed = false;
  bool get autoScanConsumed => _autoScanConsumed;

  String? _error;
  String? get error => _error;

  ParsedCard? _parsedCard;
  ParsedCard? get parsedCard => _parsedCard;

  ShanghaiTransitUnionResult? _shanghaiTransitUnion;

  /// 上海交通卡（交通联合版）双路识读详情：TU / CU 各自的应用确认、
  /// 读取成功、数据完整状态与合并结果；非该卡种时为 null。
  ShanghaiTransitUnionResult? get shanghaiTransitUnion => _shanghaiTransitUnion;

  /// 地方交通卡识读结果（非地方卡时为 null）：卡信息 / 乘车流水 /
  /// 扩展槽位，供展示层按 [CardParserIds.localCard] 分派渲染。
  ReadResult? get localReadResult => _parsedCard?.localCard;

  BankCardResult? _lastBankCardResult;
  /// 最近一次银行卡只读分析结果（统一识读流程在交通应用未命中后作为一等
  /// 阶段自动分析，会话内展示用，不写入普通日志）。
  BankCardResult? get lastBankCardResult => _lastBankCardResult;

  /// FeliCa（NFC-F）识读结果：Suica / 八达通等卡由独立 FeliCa 模块解析，
  /// 与 TU / CU / 银行卡链路并列；失败时保留 IDm、原始块与读取状态。
  FelicaScanResult? _felicaResult;
  FelicaScanResult? get felicaResult => _felicaResult;

  /// 缓存的银行卡分析器（字典随资产加载，一次会话内复用，避免重复读资产）。
  BankCardAnalyzer? _bankAnalyzer;

  /// 加载银行卡解析器（字典随资产加载，失败自动降级为空字典）。
  Future<BankCardAnalyzer> _buildBankCardAnalyzer() async {
    final pboc = await PbocParser.load(
      (p) => (_bundle ?? rootBundle).loadString(p),
    );
    final emv = await EmvParser.load(
      (p) => (_bundle ?? rootBundle).loadString(p),
    );
    // PBOC 优先（更具体的规则先判定），EMV 兜底。
    return _bankAnalyzer ??= BankCardAnalyzer([pboc, emv]);
  }

  TUnionCardInfo? get cardInfo => _parsedCard?.info;

  List<TUnionTransaction> get transactions =>
      _parsedCard?.transactions ?? const [];

  /// 过程记录（JT/T 978.2 0x1A 变长 / 0x1E 循环），供专家模式展示。
  List<TUnionProcessRecord> get transitProcessRecords =>
      _parsedCard?.transitProcessRecords ?? const [];

  /// 0x1E 公共交通过程信息循环记录集合（解码成功且非空白）：供行程流
  /// 保留未与 0x18 交易关联的独立过程事件（逐条关联、无法关联不漏显），
  /// 并随快照按批次持久化。
  List<TUnionTripRecord> get cycleProcessTrips => [
        for (final r in transitProcessRecords)
          if (r.sfi == 0x1E && !r.isBlank && r.trip != null) r.trip!,
      ];

  /// 0x1A 记录 1（城市轨道应用信息记录）解析结果，供行程页展示
  /// 「城市轨道交通 · 进出站记录」卡片。完整保留记录，由行程流按侧关联去重。
  /// 逐条读取不可用、仅有整体读取数据时，将整体数据前缀按记录 1 解析
  /// （与专家模式展示一致）；记录未写入（初始值）或解析失败时返回 null
  /// （行程页不产出卡片）。
  /// 0x1E 已有城市轨道行业记录时抑制本 getter（以 0x1E 为准，不重复）。
  TransitRecord? get railTransitRecord {
    if (cycleProcessTrips.any((t) => t.isCityRail)) return null;
    TUnionProcessRecord? wholeBlob;
    for (final r in transitProcessRecords) {
      if (r.sfi != 0x1A) continue;
      if (r.recordNumber == 1) {
        return r.isBlank ? null : r.railTransit;
      }
      if (r.recordNumber == 0) wholeBlob = r;
    }
    if (wholeBlob == null) return null;
    return const TUnionProcessParser().parseRailTransit(1, wholeBlob.raw);
  }

  /// 0x1A 记录 2（公共汽电车应用信息记录）解析结果，供行程页展示
  /// 「公共汽电车 · 上下车记录」卡片。完整保留记录，由行程流按侧关联去重。
  /// 逐条读取不可用、仅有整体读取数据时，记录 2 的起始位置无法定位，
  /// 不猜测（返回 null）；记录未写入（初始值）或解析失败时也返回 null
  /// （行程页不产出卡片）。
  /// 0x1E 已有公共汽电车行业记录时抑制本 getter（以 0x1E 为准，不重复）。
  BusTransitRecord? get busTransitRecord {
    if (cycleProcessTrips.any((t) => t.isBus)) return null;
    for (final r in transitProcessRecords) {
      if (r.sfi != 0x1A) continue;
      if (r.recordNumber == 2) {
        return r.isBlank ? null : r.busTransit;
      }
    }
    return null;
  }

  /// 是否已发现交通联合应用（普通交通联合卡或上海交通卡（交通联合版））。
  bool get tunionDetected => CardParserIds.isTUnionFamily(_parsedCard?.parserId);

  /// 是否已发现城市一卡通应用（当前解析结果由城市一卡通解析器产出）。
  bool get cityUnionDetected =>
      _parsedCard?.parserId == CardParserIds.cityUnion;

  /// 是否在同一张物理卡上同时读取到交通联合与城市一卡通两个应用（双应用卡）。
  bool get dualApplicationDetected => _parsedCard?.dualApplication ?? false;

  /// 双应用卡上城市一卡通（住建部）应用的电子钱包余额（分）；非双应用或
  /// 未读到余额时为 null。与 [cardInfo] 的交通联合钱包余额分属两套独立钱包。
  int? get cityUnionBalanceFen => _parsedCard?.cityUnionBalanceFen;

  /// 城市一卡通文件解析视图（CJ/T 331-2016：0x15 / 0x18 / 0x1A），
  /// 供专家模式按统一视图渲染；非城市一卡通卡时为空。
  List<CityUnionFileView> get cityUnionFiles =>
      _parsedCard?.cityUnionFiles ?? const [];

  /// 城市一卡通公共应用基本信息文件（SFI 0x15）解析结果；非城市一卡通
  /// 卡或未读取到该文件时返回 null。城市代码 / 发卡方代码 / 应用序列号
  /// 等卡片标识字段均由本视图提供，供卡片识别库查表与档案指纹计算使用。
  CjT331PublicInfo? get cityUnionPublicInfo {
    for (final view in cityUnionFiles) {
      if (view is CjT331PublicInfo) return view;
    }
    return null;
  }

  /// 城市一卡通卡片识别库条目（按 0x15 城市代码 = 邮编前四位 /
  /// CU 城市项目代码查表）；未收录或知识库未加载时返回 null。
  CityUnionCardInfo? get cityUnionCard =>
      _kb?.cityUnionCards.lookup(cityUnionPublicInfo?.cityCode);

  /// 当前卡片的钱包货币（按卡号前缀库条目声明判定）；未读取分析结果
  /// 或未声明时回退人民币。
  Currency get cardCurrency => _analysis?.currency ?? Currency.cny;

  /// 卡片所属城市代码（发卡地）：识别城市优先，回退卡片管理信息城市
  /// 代码；均不可得时为 null。
  String? get cardCityCode =>
      _analysis?.identity.cityCode ?? _parsedCard?.info.cityCode;

  /// [code] 是否与卡片所属城市不同（异地用卡判定）；卡片城市或 [code]
  /// 不可判定、取值为未写入（空 / 全 0）时返回 false（不猜测）。
  bool isRemoteUse(String? code) {
    final local = cardCityCode;
    if (local == null || code == null) return false;
    final a = local.trim().toUpperCase();
    final b = code.trim().toUpperCase();
    if (_isUnsetCityCode(a) || _isUnsetCityCode(b)) return false;
    return a != b;
  }

  /// 城市代码为空或全 0（未写入）时视为未知。
  static bool _isUnsetCityCode(String code) =>
      code.isEmpty || code.replaceAll('0', '').isEmpty;

  CardAnalysisResult? _analysis;
  CardAnalysisResult? get analysis => _analysis;

  /// 已加载的知识库（未加载时为 null）：供设置「知识库」子页面展示
  /// 当前 TU / CU 数据库支持的地区、线路与站点覆盖范围。
  KnowledgeBase? get knowledgeBase => _kb;

  /// TU / CU 外部数据库与知识库是否已预热完成（false = 启动预热进行中，
  /// 知识库页据此展示加载态，预热完成后自动刷新为数据内容）。
  bool get knowledgeReady => _kb != null;

  bool get ready => _engine != null;

  String get knowledgeSummary => _kb == null
      ? '未加载'
      : '已加载：${_kb!.cities.length} 城市 / ${_kb!.issuers.length} 指纹 / '
          '${_kb!.terminalRules.length} 终端规则 / '
          '${_kb!.cityUnionCards.entryCount} 城市一卡通 / '
          '${_kb!.stationCodes.entryCount} 站点编码（本地数据库）';

  /// 「启用运行日志」开关（默认关闭，持久化到设置文件）。
  bool _loggingEnabled = false;
  bool get loggingEnabled => _loggingEnabled;

  bool _exportingLog = false;
  /// 日志导出是否进行中。
  bool get exportingLog => _exportingLog;

  String? _logExportMessage;
  /// 最近一次日志导出结果（保存路径 / 失败原因）；再次导出时清空。
  String? get logExportMessage => _logExportMessage;

  bool _logExportFailed = false;
  /// 最近一次日志导出是否失败（UI 用于区分结果颜色）。
  bool get logExportFailed => _logExportFailed;

  /// 「使用系统扫码」开关（默认关闭，持久化到设置文件）。
  /// 开启后原有应用内相机扫码组件被整体屏蔽（就当不存在）：扫码统一由
  /// 系统扫码完成——Google Play 服务扫码界面（应用无需相机权限）；
  /// 设备不具备 GMS 时也不回退相机（失败仅提示）；关闭开关使用应用内
  /// 相机扫码。
  bool _gmsScanEnabled = false;
  bool get gmsScanEnabled => _gmsScanEnabled;

  /// 「读取后自动保存」开关（默认关闭，持久化到设置文件）。
  /// 开启后每次读卡解析成功即由 AppState 直接写入卡片档案，无需首页
  /// 弹出「是否保存」确认框；关闭时保持手动确认流程。
  bool _autoSaveEnabled = false;
  bool get autoSaveEnabled => _autoSaveEnabled;

  /// 「莫奈取色（动态取色）」开关（默认关闭，持久化到设置文件）。
  /// 开启后应用主题色跟随系统壁纸取色（Android 12+ Dynamic Color，
  /// 由 dynamic_color 插件提供；不支持的系统自动回落到内置主题色）；
  /// 关闭时使用内置固定主题色（青绿色 seed）。
  bool _monetEnabled = false;
  bool get monetEnabled => _monetEnabled;

  /// 自动保存结果提示（成功 / 失败文案），供首页 SnackBar 展示；
  /// 展示后由 [clearAutoSaveNotice] 清空，新一轮读取开始时也会重置。
  String? _autoSaveNotice;
  String? get autoSaveNotice => _autoSaveNotice;

  /// 设备是否具备 Google Play 服务扫码能力（启动时探测一次）；
  /// 仅用于设置页提示与扫码预热，不参与屏蔽决策。
  bool _gmsAvailable = false;
  bool get gmsAvailable => _gmsAvailable;

  /// 是否使用系统扫码（原有应用内相机扫码组件被整体屏蔽）：
  /// 仅由「使用系统扫码」开关决定——开启即屏蔽，扫码走 Google Play
  /// 服务扫码界面，不再进入应用内相机；关闭开关时恢复相机扫码。
  bool get useGmsScanner => _gmsScanEnabled;

  /// 城市代码 → 城市名（按卡片实时上报的代码匹配卡前缀库 issuer 后 4 位）；
  /// 未收录或知识库未加载时返回 null。
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
  /// （无线路号时按站点末 4 位单维查表），未命中再按 CU / CSV 精确编码
  /// 查表；只认查表命中，查不到表一律未匹配（已取消站名推测），歧义
  /// 不强行显示站名。
  StationMatch resolveStationMatch(String? cityCode, String? rawCode,
      {int? lineValue}) {
    final kb = _kb;
    if (kb == null || rawCode == null || rawCode.isEmpty) {
      return StationMatch.unmatched;
    }
    final city = _lookupCityCode(cityCode);
    if (city == null) return StationMatch.unmatched;
    final code = rawCode.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (code.isEmpty) return StationMatch.unmatched;
    final tu = kb.stationCodes.matchTuStationByCardId(
        rawStationId: code, cityCode: city, lineValue: lineValue);
    if (!tu.isUnmatched) return tu;
    final fallback =
        kb.stationCodes.lookupStation(rawCode: code, cityCode: city);
    if (fallback != null) {
      return StationMatch(fallback, StationMatchConfidence.exact);
    }
    return StationMatch.unmatched;
  }

  /// 0x1E「线路和站点代码」匹配置信版（城市 + 线路 + 站点三键联合查表）。
  StationMatch resolveCycleStationMatch(String? cityCode, String? field) {
    final kb = _kb;
    if (kb == null || field == null || field.isEmpty) {
      return StationMatch.unmatched;
    }
    return kb.stationCodes.matchLineStationField(
      field: field,
      cityCode: _lookupCityCode(cityCode),
    );
  }

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
    final tu =
        kb.stationCodes.matchTuLineByCardValue(rawLineCode: code, cityCode: city);
    if (tu.confidence == StationMatchConfidence.ambiguous) return null;
    if (tu.entry?.line != null) return tu.entry!.line;
    return kb.stationCodes.lookupLineName(rawLineCode: code, cityCode: city);
  }

  /// 城市一卡通（CU）交易终端编号 → 站点名：经 CU 站点数据库 terminal_index
  /// 的精确 / 前缀规则匹配（同地区优先、键更长者优先、按交易类型过滤）；
  /// 未命中、终端编号缺失或知识库未加载时返回 null（展示层回退，不猜测）。
  String? resolveCuStationName(
    String? terminalNumber, {
    String? cityCode,
    int? transactionType,
  }) {
    final kb = _kb;
    if (kb == null || terminalNumber == null || terminalNumber.isEmpty) {
      return null;
    }
    return kb.cuTerminals
        .match(terminalNumber, cityCode: cityCode, transactionType: transactionType)
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

  // ---- JT/T 1179 乘车码二维码 ----

  JtT1179QrData? _qrData;

  /// 最近一次解析成功的 JT/T 1179 二维码数据；解析失败或清除后为 null。
  JtT1179QrData? get qrData => _qrData;

  List<int>? _qrRaw;

  /// 最近一次获取到的二维码原始字节（成功 / 失败均保留，供原始数据查看）。
  List<int>? get qrRaw => _qrRaw;

  String? _qrError;

  /// 最近一次二维码解析失败原因；再次解析或清除时重置。
  String? get qrError => _qrError;

  /// 是否已有二维码解析结果。
  bool get hasQrData => _qrData != null;

  /// 解析二维码原始字节（相机扫描得到的二进制数据）。
  /// 成功时保存解析结果并清除错误；失败时保留原始字节并记录错误。
  bool parseQrBytes(List<int> bytes) {
    _qrRaw = List<int>.unmodifiable(bytes);
    try {
      _qrData = JtT1179QrParser.parse(bytes);
      _qrError = null;
      _logEvent('二维码解析成功：${bytes.length} 字节');
      notifyListeners();
      return true;
    } catch (e) {
      _qrData = null;
      _qrError = '$e';
      _logEvent('二维码解析失败：$e');
      notifyListeners();
      return false;
    }
  }

  /// 解析文本形式的二维码数据（自动识别 HEX / Base64）；
  /// 无法解码为字节或解析失败时返回 false 并记录错误。
  bool parseQrText(String input) {
    final bytes = decodeQrText(input);
    if (bytes == null) {
      _qrRaw = null;
      _qrData = null;
      _qrError = '无法识别输入内容：请输入十六进制或 Base64 编码的二维码数据';
      _logEvent('二维码解析失败：输入内容无法识别为 HEX / Base64');
      notifyListeners();
      return false;
    }
    return parseQrBytes(bytes);
  }

  /// 文本 → 字节：十六进制字符串（允许空白 / `:` / `-` 分隔与 `0x` 前缀）
  /// 优先按 HEX 解码，否则回退 Base64；均无法解码时返回 null。
  static List<int>? decodeQrText(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    final compact = text.replaceAll(RegExp(r'[\s:\-]'), '');
    if (compact.isNotEmpty &&
        compact.length.isEven &&
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
      return [
        for (var i = 0; i < compact.length; i += 2)
          int.parse(compact.substring(i, i + 2), radix: 16),
      ];
    }
    try {
      final normalized = input.trim().replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(base64.normalize(normalized));
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// 清除二维码状态（解析结果、原始字节与错误）。
  void clearQr() {
    if (_qrData == null && _qrRaw == null && _qrError == null) return;
    _qrData = null;
    _qrRaw = null;
    _qrError = null;
    notifyListeners();
  }

  final List<String> _apduLog = [];
  List<String> get apduLog => List.unmodifiable(_apduLog);
  static const _maxLogEntries = 100;

  // 扫描世代号：每次开始新扫描或停止扫描时递增，
  // 用于识别已过期的扫描请求，防止旧请求的收尾逻辑误杀新扫描
  int _scanGeneration = 0;

  Future<void>? _initFuture;

  // dispose 后，异步收尾（如知识库加载完成、扫描回调）仍可能尝试发送通知；
  // 直接放行会在 debug 模式触发 "used after being disposed" 断言
  bool _disposed = false;

  /// 加载设置与知识库（幂等）。页面启动时调用一次即可。
  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    // 数据库提前预热：知识库（含 TU / CU 两个外部 SQLite 的资产解包与
    // 派生索引构建）在应用启动的第一时间发起，与设置读取、扫码通道
    // 探测并行，知识库页尽早可查，不再排在这两步之后。
    final settings = _loadSettings();
    final knowledge = _loadKnowledge(settingsLanded: settings);
    await settings;
    await _detectScanChannels();
    await knowledge;
  }

  /// 读取持久化设置（缺失/不可用时保持默认：运行日志与系统扫码均停用）。
  Future<void> _loadSettings() async {
    try {
      // 运行日志默认关闭，仅显式开启（'true'）时启用
      final logging = await _settingsStore.read(SettingsKeys.loggingEnabled);
      _loggingEnabled = logging == 'true';
      _logger.enabled = _loggingEnabled;
      // 「使用系统扫码」默认关闭，仅显式开启（'true'）时启用
      final gmsScan = await _settingsStore.read(SettingsKeys.gmsScanEnabled);
      _gmsScanEnabled = gmsScan == 'true';
      // 「读取后自动保存」默认关闭，仅显式开启（'true'）时启用
      final autoSave = await _settingsStore.read(SettingsKeys.autoSaveEnabled);
      _autoSaveEnabled = autoSave == 'true';
      // 「莫奈取色」默认关闭，仅显式开启（'true'）时启用
      final monet = await _settingsStore.read(SettingsKeys.monetEnabled);
      _monetEnabled = monet == 'true';
    } catch (_) {
      // 设置存储不可用（如平台插件缺失）时按默认值降级
    }
  }

  /// 探测设备具备的系统扫码通道（启动时一次；非 Android / 探测失败按
  /// 不具备降级，仅影响设置页提示、扫码分流与预热，不影响屏蔽决策）。
  /// 具备 GMS 且开关开启时，后台预热扫码器（缓存原生实例 + 预装扫码
  /// 模块），加快首次扫码速度。
  Future<void> _detectScanChannels() async {
    _gmsAvailable = await isGmsQrScanAvailable();
    notifyListeners();
    if (_gmsAvailable && _gmsScanEnabled) {
      // fire-and-forget：预热不阻塞启动流程，失败静默
      warmUpGmsQrScanner();
    }
  }

  Future<void> _loadKnowledge({Future<void>? settingsLanded}) async {
    KnowledgeBase kb;
    try {
      // 站点数据来自本地：TrafArch_Database_TU / CU 两个外部 SQLite 数据库
      kb = await KnowledgeBase.load(_bundle ?? rootBundle);
    } catch (_) {
      // 资产缺失或解析失败时降级为空知识库，识别引擎自动失效但流程不断
      kb = KnowledgeBase.empty();
    }
    _kb = kb;
    _engine = AnalysisEngine(kb);
    _identification = CardIdentificationService(kb);
    // 与设置读取并行预热：日志开关要等设置落地才确定，先等其完成再记
    // 「知识库加载」事件，避免开关为开启时漏记（默认口径不变）。
    await (settingsLanded ?? Future.value());
    _logEvent('知识库加载：$knowledgeSummary');
    notifyListeners();
  }

  /// 设置「启用运行日志」开关（持久化到设置文件，默认关闭）。
  Future<void> setLoggingEnabled(bool enabled) async {
    if (_loggingEnabled == enabled) return;
    _loggingEnabled = enabled;
    if (enabled) {
      _logger.enabled = true;
      _logger.log('== 日志记录已开启 ==');
    } else {
      _logger.log('== 日志记录已关闭 ==');
      _logger.enabled = false;
    }
    notifyListeners();
    try {
      await _settingsStore.write(SettingsKeys.loggingEnabled, '$enabled');
    } catch (_) {
      // 设置写入失败不影响本次会话内的开关状态
    }
  }

  /// 导出运行日志到手机下载目录（Download/transit_card_log_*.txt）。
  /// 成功路径 / 失败原因写入 [logExportMessage]，
  /// [logExportFailed] 标记失败（供 UI 区分展示）。
  Future<void> exportLog() async {
    if (_exportingLog) return;
    _exportingLog = true;
    _logExportMessage = null;
    _logExportFailed = false;
    _logger.log('== 导出运行日志 ==');
    notifyListeners();

    try {
      final now = DateTime.now();
      // 等待排队中的日志写入完成，保证导出内容完整
      await _logger.flush();
      final body = await _logger.readAll();
      final content = StringBuffer()
        ..writeln('=== ${AppInfo.appName} 运行日志 ===')
        ..writeln('应用版本：${AppInfo.version}（Build ${AppInfo.buildNumber}）')
        ..writeln('导出时间：${AppLogger.formatTimestamp(now)}')
        ..writeln('------------------------------------------------')
        ..writeln(body.trim().isEmpty ? '（暂无日志记录）' : body.trim());
      final path = await _logExporter.saveToDownloads(
        'transit_card_log_${_fileStamp(now)}.txt',
        content.toString(),
      );
      _logExportFailed = false;
      _logExportMessage = '已导出到下载目录：$path';
      _logger.log('== 日志导出完成：$path ==');
    } on PlatformException catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：${e.message ?? e.code}';
      _logger.log('== 日志导出失败：${e.message ?? e.code} ==');
    } catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：$e';
      _logger.log('== 日志导出失败：$e ==');
    } finally {
      _exportingLog = false;
      notifyListeners();
    }
  }

  /// 导出文件名时间戳：yyyyMMdd_HHmmss。
  static String _fileStamp(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${pad2(t.month)}${pad2(t.day)}_'
        '${pad2(t.hour)}${pad2(t.minute)}${pad2(t.second)}';
  }

  /// 导出全部卡片档案（含行程记录快照）到手机下载目录
  /// （Download/transit_card_records_*.txt）。返回结果文案（保存路径 /
  /// 失败原因 / 无卡片提示），供卡片列表页 SnackBar 直接展示。
  Future<String> exportCards() async {
    final cards = await cardRepository.getAllCards();
    if (cards.isEmpty) return '暂无卡片记录可导出';

    try {
      final now = DateTime.now();
      final content = buildCardRecordsExport(
        cards,
        exportedAt: now,
        stationResolver: resolveStationName,
        lineResolver: resolveLineName,
      );
      final path = await _logExporter.saveToDownloads(
        'transit_card_records_${_fileStamp(now)}.txt',
        content,
      );
      _logger.log('== 卡片记录导出完成：$path ==');
      return '已导出 ${cards.length} 张卡片到下载目录：$path';
    } on PlatformException catch (e) {
      _logger.log('== 卡片记录导出失败：${e.message ?? e.code} ==');
      return '导出失败：${e.message ?? e.code}';
    } catch (e) {
      _logger.log('== 卡片记录导出失败：$e ==');
      return '导出失败：$e';
    }
  }

  void _log(String entry) {
    _apduLog.add(entry);
    if (_apduLog.length > _maxLogEntries) {
      _apduLog.removeRange(0, _apduLog.length - _maxLogEntries);
    }
    _logger.log(entry);
  }

  /// 仅写入持久化运行日志（不进专家页 APDU 会话列表）。
  void _logEvent(String entry) => _logger.log(entry);

  Future<void> scanOnce() async {
    if (_scanning) return;
    final gen = ++_scanGeneration;
    _scanning = true;
    _error = null;
    _readProgress = null;
    _logEvent('开始扫描 NFC 标签，等待贴近…');
    notifyListeners();

    try {
      final result = await _channel.scanOnce();
      // 已被 stop() 取消并取代，本次请求作废
      if (gen != _scanGeneration) return;
      _lastResult = result;
      if (result != null) {
        // 成功读取一次后，自动读取模式结束，再次读取需手动点击按钮
        _autoScanConsumed = true;
        _logEvent('发现卡片：UID=${result.uid}'
            ' · 卡型=${result.cardType ?? '未知'}'
            ' · ISO-DEP=${result.isoDepConnected ? '已连接' : '未连接'}'
            ' · NFC-F=${result.felicaConnected ? '已连接' : '未连接'}');
      }
      if (result != null && result.isoDepConnected) {
        await _parseAndAnalyze();
      } else if (result != null && result.felicaConnected) {
        // NFC-F（FeliCa）：交给独立模块（协议探测 → 适配器 → 解析），
        // 与交通联合 / 城市一卡通 / 银行卡链路并列，不混写读取逻辑。
        await _readFelica(result);
      } else {
        _resetCard();
      }
    } on PlatformException catch (e) {
      if (gen == _scanGeneration && e.code != 'NFC_STOPPED') {
        _error = e.message ?? e.code;
        _logEvent('读取失败（${e.code}）：${e.message ?? ''}');
      }
    } catch (e) {
      if (gen == _scanGeneration) {
        _error = '$e';
        _logEvent('读取失败：$e');
      }
    } finally {
      // 仅当前世代的请求负责关闭原生扫描。
      // 过期请求若再调用 stopScan，会把之后新建立的扫描误取消
      if (gen == _scanGeneration) {
        try {
          await _channel.stopScan();
        } catch (_) {
          // 原生层关闭失败不影响流程
        }
        _scanning = false;
        _readProgress = null;
        notifyListeners();
      }
    }
  }

  Future<void> _parseAndAnalyze() async {
    _parsing = true;
    _readProgress = null;
    _resetCard();
    notifyListeners();

    try {
      await init();
      _reportReadProgress(5);
      // 卡片识读统一交由独立模块（LocalCardParser）编排：模块以新架构为主，
      // 内部串联「交通联合 → 城市一卡通 → 地方交通卡 → 银行卡（EMV / PBOC）」
      // 四类一等阶段，产出结果各自保留 tunion / cityUnion / localCard 的
      // parserId 或银行卡产物，供上层统一分派。银行卡不再是上层兜底分支。
      final parser = LocalCardParser(
        _transceive,
        onStage: (stage) => _log('== 尝试解析：$stage =='),
        onProgress: _reportReadProgress,
        bankProbe: BankCardProbeImpl(_buildBankCardAnalyzer),
      );
      final outcome = await parser.read();
      if (outcome == null) {
        _log('== 未发现受支持的卡片应用 ==');
        return;
      }
      if (outcome.isBankCard) {
        // 银行卡（EMV / PBOC）只读结果：供首页「最近扫描」与专家页统一展示。
        final result = outcome.bank as BankCardResult;
        _lastBankCardResult = result;
        _log('== 银行卡识读完成：${result.applications.length} 个应用 / '
            '${result.issues.length} 项异常 ==');
        _reportReadProgress(100);
        return;
      }
      final parsed = outcome.parsedCard!;
      _parsedCard = parsed;
      _shanghaiTransitUnion = outcome.shanghai;
      if (CardParserIds.isTUnionFamily(parsed.parserId)) {
        _analysis = _engine?.analyze(parsed);
        _log('== 解析完成：${parsed.transactions.length} 条交易记录 / '
            '${parsed.transitProcessRecords.length} 条过程记录 ==');
        final shanghai = outcome.shanghai;
        if (shanghai != null) {
          _log('== 上海交通卡（交通联合版）识别：${shanghai.status.label} / '
              '${shanghai.tu.stateText} / ${shanghai.cu.stateText}'
              '${shanghai.duplicateTripCount == 0 ? '' : ' / 行程去重 ${shanghai.duplicateTripCount} 条'} ==');
        }
        if (parsed.dualApplication) {
          final cu = parsed.cityUnionBalanceFen;
          _log('== 检测到双应用卡：交通联合 + 城市一卡通（'
              '城市一卡通 ${parsed.cityUnionFiles.length} 个文件视图'
              '${cu == null ? '' : ' / 余额 ${(cu / 100).toStringAsFixed(2)} 元'}）==');
        }
      } else {
        // 分析引擎（识别 / 行程 / 符合性）为交通联合专属：
        // 其他卡型只提供文件级解析视图，不进入分析链路。
        _analysis = null;
        _log('== 解析完成：${parsed.parserName} '
            '${parsed.cityUnionFiles.length} 个文件视图 ==');
      }
      _stageCardArchive(parsed);
      // 开启「读取后自动保存」时，解析成功即直接落库（无需首页确认框），
      // 保证读卡结果一定被保存，不受当前所在页面 / 对话框时序影响。
      if (_autoSaveEnabled) {
        await _autoSavePending();
      }
      _reportReadProgress(100);
    } catch (e) {
      _log('!! 解析异常：$e');
    } finally {
      _parsing = false;
      notifyListeners();
    }
  }

  /// 更新读卡解析进度（0–100）：仅解析阶段接受回调，且只允许前进
  /// （阶段回退不改变进度条）；每次前进通知界面刷新。
  void _reportReadProgress(int percent) {
    if (!_parsing) return;
    final value = percent.clamp(0, 100).toInt();
    if (_readProgress != null && value <= _readProgress!) return;
    _readProgress = value;
    notifyListeners();
  }

  /// 识别本次读取结果并暂存为「待确认保存」：由首页弹出是否保存对话框，
  /// 用户确认后经 [acceptPendingSave] 写入档案（重复读取更新快照但不覆盖
  /// 自定义名称）；无法生成稳定指纹（关键标识未读到）时跳过（不猜测），
  /// 识别失败仅记录日志，不影响解析与展示链路。
  void _stageCardArchive(ParsedCard parsed) {
    final identification = _identification;
    if (identification == null) return;
    try {
      final identified = identification.identify(
        parsed,
        analysisIdentity: _analysis?.identity,
      );
      if (identified == null) {
        _logEvent('卡片档案跳过：无法生成稳定指纹（关键标识未读到）');
        return;
      }
      _lastIdentified = identified;
      _pendingSave = PendingCardSave(
        fingerprint: identified.fingerprint,
        identity: identified.identity,
        cardNumber: identified.cardNumber,
        balanceFen: parsed.info.balanceFen,
        currencyCode: _analysis?.currency.code,
        transactionCount: parsed.transactions.length,
        sessionDataJson: _encodeSessionSnapshot(),
      );
      _lastFingerprint = identified.fingerprint;
      _logEvent('卡片档案待确认保存：${identified.displayName}');
    } catch (e) {
      _logEvent('卡片识别失败：$e');
    }
  }

  /// 编码本次读取的行程记录快照（交易行程 / 0x1A 进出站与上下车记录 +
  /// 读取时卡片城市代码），随档案保存；卡片详情页在读取其他卡片后改用
  /// 该快照展示记录，保证老卡片的行程数据不随新卡读取消失。
  /// 无任何行程记录时返回 null（不写入 / 不覆盖既有快照）。
  String? _encodeSessionSnapshot() {
    final snapshot = CardSessionSnapshot(
      parseVersion: kTripParseVersion,
      cardCityCode: cardCityCode,
      trips: _analysis?.trips ?? const [],
      rails: [if (railTransitRecord != null) railTransitRecord!],
      buses: [if (busTransitRecord != null) busTransitRecord!],
      processTrips: cycleProcessTrips,
    );
    return snapshot.isEmpty ? null : snapshot.encode();
  }

  /// 确认保存待归档卡片（首页确认对话框「保存」）：写入 / 更新档案并记录
  /// 读取快照（余额 / 货币 / 交易条数）与最近读取时间；返回是否保存成功
  /// （失败仅记录日志，由调用方提示，不中断流程）。
  Future<bool> acceptPendingSave() async {
    final pending = _pendingSave;
    if (pending == null) return false;
    _pendingSave = null;
    notifyListeners();
    try {
      await cardRepository.saveIdentity(
        fingerprint: pending.fingerprint,
        identity: pending.identity,
        cardNumber: pending.cardNumber,
        balanceFen: pending.balanceFen,
        currencyCode: pending.currencyCode,
        transactionCount: pending.transactionCount,
        sessionDataJson: pending.sessionDataJson,
        parseVersion: kTripParseVersion,
        readAt: DateTime.now(),
      );
      _logEvent(
        '卡片档案已保存：'
        '${pending.identity.officialName ?? pending.identity.cardType}'
        '（${pending.identity.identificationSource}）',
      );
      return true;
    } catch (e) {
      _logEvent('卡片档案保存失败：$e');
      return false;
    }
  }

  /// 放弃保存待归档卡片（首页确认对话框「不保存」）。
  void declinePendingSave() {
    if (_pendingSave == null) return;
    _pendingSave = null;
    _logEvent('卡片档案未保存（用户选择不保存）');
    notifyListeners();
  }

  /// 「读取后自动保存」开启时调用：直接把待归档卡片写入档案（复用
  /// [acceptPendingSave] 的落库逻辑），并把结果写入 [autoSaveNotice]
  /// 供首页提示；无待保存结果时静默跳过。
  Future<void> _autoSavePending() async {
    final pending = _pendingSave;
    if (pending == null) return;
    final name = pending.displayName;
    final ok = await acceptPendingSave();
    _autoSaveNotice = ok ? '已自动保存：$name' : '自动保存失败：$name';
    notifyListeners();
  }

  /// 清除自动保存提示（首页展示 SnackBar 后调用）。
  void clearAutoSaveNotice() {
    if (_autoSaveNotice == null) return;
    _autoSaveNotice = null;
    notifyListeners();
  }

  /// 带日志的 APDU 收发包装（解析器注入用）。
  Future<List<int>> _transceive(List<int> apdu) async {
    try {
      final resp = await _channel.transceive(apdu);
      _log('>> ${_hex(apdu)}\n<< ${_hex(resp)}');
      return resp;
    } on PlatformException catch (e) {
      _log('!! ${e.code}: ${e.message ?? ''}');
      return const [];
    } catch (e) {
      _log('!! $e');
      return const [];
    }
  }

  /// FeliCa（NFC-F）识读：原生只负责 NfcF 连接与原始帧收发，
  /// 协议校验 / 卡型匹配 / 记录解析全部由独立 FeliCa 模块完成。
  Future<void> _readFelica(NfcScanResult tag) async {
    _parsing = true;
    _readProgress = null;
    _resetCard();
    notifyListeners();

    try {
      final reader = FelicaReader(
        _felicaTransceive,
        onStage: (stage) => _log('== 尝试解析：$stage =='),
        onProgress: _reportReadProgress,
      );
      final result = await reader.read(
        preferredSystemCode: _hexWord(tag.nfcFSystemCode),
      );
      _felicaResult = result;
      _log('== FeliCa 识读完成：${result.displayName} / ${result.stateText} ==');
      for (final status in result.statuses) {
        _log('   ${status.stage}：${status.state.label} — ${status.message}');
      }
      _reportReadProgress(100);
    } catch (e) {
      _log('!! FeliCa 识读异常：$e');
    } finally {
      _parsing = false;
      notifyListeners();
    }
  }

  /// FeliCa 原始帧收发（带会话日志）：协议层需要感知通道错误，
  /// 因此记录后继续抛出，由 FelicaReader 统一映射为读取状态。
  Future<List<int>> _felicaTransceive(List<int> frame) async {
    try {
      final resp = await _felicaChannel.transceive(frame);
      _log('>> FeliCa ${_hex(frame)}\n<< ${_hex(resp)}');
      return resp;
    } on PlatformException catch (e) {
      _log('!! FeliCa ${e.code}：${e.message ?? ''}');
      rethrow;
    }
  }

  /// 原生提供为 "00 03" 形式的系统码 HEX，转换为 16 位整数供探测使用。
  static int? _hexWord(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.replaceAll(' ', '');
    if (cleaned.length != 4) return null;
    return int.tryParse(cleaned, radix: 16);
  }

  void _resetCard() {
    _parsedCard = null;
    _shanghaiTransitUnion = null;
    _analysis = null;
    _lastBankCardResult = null;
    _felicaResult = null;
    // 新会话开始时清除会话指纹：本次识别失败 / 未读到卡片时，卡片详情页
    // 不再误与旧会话数据关联（各自展示已保存的记录快照）。
    _lastFingerprint = null;
    // 会话识别结果随指纹一同清空（仅内存态，不持久化）。
    _lastIdentified = null;
    // 新的读取会话开始时丢弃上一次未应答的待保存结果，避免误存旧卡。
    _pendingSave = null;
    _autoSaveNotice = null;
    _apduLog.clear();
  }

  static String _hex(List<int> bytes) => bytes.isEmpty
      ? '(无响应)'
      : bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

  Future<void> stop() async {
    // 使进行中的 scanOnce 失效，避免其收尾时误杀下一次扫描
    ++_scanGeneration;
    final wasScanning = _scanning;
    final hadError = _error != null;
    _scanning = false;
    _error = null;
    if (wasScanning || hadError) {
      notifyListeners();
    }
    try {
      await _channel.stopScan();
    } catch (_) {
      // 停止失败不影响状态
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 设置「使用系统扫码」开关（持久化到设置文件，默认关闭：开关开启即
  /// 整体屏蔽应用内相机扫码（就当不存在），转用系统扫码（优先 Play 服务
  /// 扫码界面，无 GMS 设备走华为 Scan Kit）；关闭后恢复应用内相机扫码）。
  Future<void> setGmsScanEnabled(bool enabled) async {
    if (_gmsScanEnabled == enabled) return;
    _gmsScanEnabled = enabled;
    notifyListeners();
    try {
      await _settingsStore.write(SettingsKeys.gmsScanEnabled, '$enabled');
    } catch (_) {
      // 设置写入失败不影响本次会话内的开关状态
    }
  }

  /// 设置「读取后自动保存」开关（持久化到设置文件，默认关闭：开启后读卡
  /// 解析成功即自动写入卡片档案，无需首页确认；关闭后恢复手动确认）。
  Future<void> setAutoSaveEnabled(bool enabled) async {
    if (_autoSaveEnabled == enabled) return;
    _autoSaveEnabled = enabled;
    notifyListeners();
    try {
      await _settingsStore.write(SettingsKeys.autoSaveEnabled, '$enabled');
    } catch (_) {
      // 设置写入失败不影响本次会话内的开关状态
    }
  }

  /// 设置「莫奈取色（动态取色）」开关（持久化到设置文件，默认关闭：开启后
  /// 主题色跟随系统壁纸取色；关闭后使用内置固定主题色）。
  Future<void> setMonetEnabled(bool enabled) async {
    if (_monetEnabled == enabled) return;
    _monetEnabled = enabled;
    notifyListeners();
    try {
      await _settingsStore.write(SettingsKeys.monetEnabled, '$enabled');
    } catch (_) {
      // 设置写入失败不影响本次会话内的开关状态
    }
  }
}