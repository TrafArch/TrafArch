import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/analysis/tunion_analysis_engine.dart';
import '../core/analysis/tunion_analysis_models.dart';
import '../core/app_info.dart';
import '../core/card/card_parser.dart';
import '../core/data/tunion_knowledge_base.dart';
import '../core/data/online_data_store.dart';
import '../core/data/settings_store.dart';
import '../core/data/station_codes.dart';
import '../core/data/tripreader_sync.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_exporter.dart';
import '../core/nfc/nfc_models.dart';
import '../core/nfc/nfc_service.dart';
import '../core/qr/gms_qr_scanner.dart';
import '../core/qr/hms_qr_scanner.dart';
import '../core/transit/city_union/city_union_models.dart';
import '../core/transit/city_union/city_union_parser.dart';
import '../core/transit/tunion/qr/jt_t1179_qr_parser.dart';
import '../core/transit/tunion/tunion_models.dart';
import '../core/transit/tunion/tunion_parser.dart';
import '../core/transit/tunion/tunion_process_parser.dart';

/// 应用级状态与会话编排：NFC 通道 → 解析器 → 分析引擎。
///
/// 职责：
/// - 知识库加载（JSON 资产 + 站点数据：预制快照 / 在线拉取）；
/// - 扫描会话管理（世代号防止旧请求误杀新扫描）；
/// - 读卡流程编排：scanOnce → TUnionParser.parse → AnalysisEngine.analyze；
/// - APDU 日志（专家页会话展示）与运行日志（持久化，可导出）；
/// - 一切对外状态。
class AppState extends ChangeNotifier {
  AppState({
    NfcChannel? channel,
    AssetBundle? bundle,
    SettingsStore? settingsStore,
    OnlineDataStore? onlineDataStore,
    TripreaderSyncService? syncService,
    AppLogger? logger,
    LogExporter? logExporter,
  })  : _channel = channel ?? const MethodChannelNfcChannel(),
        _bundle = bundle,
        _settingsStore = settingsStore ?? FileSettingsStore(),
        _onlineDataStore = onlineDataStore ?? FileOnlineDataStore(),
        _syncService = syncService ?? TripreaderSyncService(),
        _logger = logger ?? AppLogger(),
        _logExporter = logExporter ?? const MethodChannelLogExporter();

  final NfcChannel _channel;
  final AssetBundle? _bundle;

  /// 设置持久化（app_settings.txt 文本键值对；测试注入内存实现）。
  final SettingsStore _settingsStore;

  /// 在线站点数据本地快照持久化（online_station_data.txt；
  /// 测试注入内存实现）。
  final OnlineDataStore _onlineDataStore;

  /// 读卡识途数据在线同步服务（手机端直接联网拉取，结果由本类持久化）。
  final TripreaderSyncService _syncService;

  /// 运行日志记录（应用私有目录持久化；测试注入内存实现）。
  final AppLogger _logger;

  /// 日志导出通道（保存到手机下载目录；测试注入假实现）。
  final LogExporter _logExporter;

  KnowledgeBase? _kb;
  AnalysisEngine? _engine;

  NfcScanResult? _lastResult;
  NfcScanResult? get lastResult => _lastResult;

  bool _scanning = false;
  bool get scanning => _scanning;

  bool _parsing = false;
  bool get parsing => _parsing;

  // 自动读取模式：应用启动后自动进入读取模式；
  // 仅在成功读取过一次卡片后结束，此后再次读取必须由用户点击按钮触发。
  bool _autoScanConsumed = false;
  bool get autoScanConsumed => _autoScanConsumed;

  String? _error;
  String? get error => _error;

  /// 「开启在线拉取数据」开关（默认停用，持久化到设置文件）。
  bool _onlineFetchEnabled = false;
  bool get onlineFetchEnabled => _onlineFetchEnabled;

  /// 在线拉取的站点代码表（拉取后持久化到本地，重启后继续取代预制快照；
  /// null 时使用应用内预制数据）。
  StationCodeTable? _onlineStationCodes;

  /// 当前是否使用在线拉取的数据（本地快照或本次会话拉取）。
  bool get usingOnlineData => _onlineStationCodes != null;

  bool _syncingData = false;
  /// 站点数据在线同步是否进行中。
  bool get syncingData => _syncingData;

  String? _syncError;
  /// 最近一次同步的失败原因；重新发起同步时清空。
  String? get syncError => _syncError;

  String? _syncReport;
  /// 最近一次同步成功摘要（数据集数 / 编码数 / 来源）。
  String? get syncReport => _syncReport;

  ParsedCard? _parsedCard;
  ParsedCard? get parsedCard => _parsedCard;

  TUnionCardInfo? get cardInfo => _parsedCard?.info;

  List<TUnionTransaction> get transactions =>
      _parsedCard?.transactions ?? const [];

  /// 过程记录（JT/T 978.2 0x1A 变长 / 0x1E 循环），供专家模式展示。
  List<TUnionProcessRecord> get transitProcessRecords =>
      _parsedCard?.transitProcessRecords ?? const [];

  /// 0x1A 记录 1（城市轨道应用信息记录）解析结果，供行程页展示
  /// 「城市轨道交通 · 进出站记录」卡片。数据源优先级：当卡片同时存在
  /// 城市轨道交通行业（应用分类码 0x01）的 0x1E 循环记录时，轨道行程
  /// 已由行程列表按 0x1E 呈现，以 0x1E 为准，不展示 0x1A 记录（返回 null）。
  /// 逐条读取不可用、仅有整体读取数据时，将整体数据前缀按记录 1 解析
  /// （与专家模式展示一致）；记录未写入（初始值）或解析失败时返回 null
  /// （行程页不产出卡片）。
  TransitRecord? get railTransitRecord {
    // 0x1E 优先：城市轨道交通行业循环记录存在时隐藏 0x1A 进出站卡片
    final hasCityRailCycle = transitProcessRecords.any(
      (r) => r.sfi == 0x1E && (r.trip?.isCityRail ?? false),
    );
    if (hasCityRailCycle) return null;
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
  /// 「公共汽电车 · 上下车记录」卡片。数据源优先级：当卡片同时存在
  /// 公共汽电车行业（应用分类码 0x02）的 0x1E 循环记录时，公交行程
  /// 已由行程列表按 0x1E 呈现，以 0x1E 为准，不展示 0x1A 记录（返回 null）。
  /// 逐条读取不可用、仅有整体读取数据时，记录 2 的起始位置无法定位，
  /// 不猜测（返回 null）；记录未写入（初始值）或解析失败时也返回 null
  /// （行程页不产出卡片）。
  BusTransitRecord? get busTransitRecord {
    // 0x1E 优先：公共汽电车行业循环记录存在时隐藏 0x1A 上下车卡片
    final hasBusCycle = transitProcessRecords.any(
      (r) => r.sfi == 0x1E && (r.trip?.isBus ?? false),
    );
    if (hasBusCycle) return null;
    for (final r in transitProcessRecords) {
      if (r.sfi != 0x1A) continue;
      if (r.recordNumber == 2) {
        return r.isBlank ? null : r.busTransit;
      }
    }
    return null;
  }

  /// 是否已发现交通联合应用（当前解析结果由交通联合解析器产出）。
  bool get tunionDetected => _parsedCard?.parserId == CardParserIds.tunion;

  /// 是否已发现城市一卡通应用（当前解析结果由城市一卡通解析器产出）。
  bool get cityUnionDetected =>
      _parsedCard?.parserId == CardParserIds.cityUnion;

  /// 城市一卡通文件解析视图（CJ/T 331-2016：0x15 / 0x17 / 0x10 / 0x1A），
  /// 供专家模式按统一视图渲染；非城市一卡通卡时为空。
  List<CityUnionFileView> get cityUnionFiles =>
      _parsedCard?.cityUnionFiles ?? const [];

  /// 当前卡片的钱包货币（按卡号前缀库判定，如八达通-全国通卡为港币）；
  /// 未读取分析结果或未收录时回退人民币。
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

  bool get ready => _engine != null;

  String get knowledgeSummary => _kb == null
      ? '未加载'
      : '已加载：${_kb!.cities.length} 城市 / ${_kb!.issuers.length} 指纹 / '
          '${_kb!.terminalRules.length} 终端规则 / '
          '${_kb!.stationCodes.entryCount} 站点编码'
          '${_onlineStationCodes == null ? '（预制快照）' : '（在线拉取）'}';

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
  /// 系统扫码完成——优先 Google Play 服务；无 GMS 的华为/鸿蒙设备
  /// （鸿蒙 4.2 等）改走华为 Scan Kit；设备两者都不可用时也不回退相机
  /// （失败仅提示）；关闭开关使用应用内相机扫码。
  bool _gmsScanEnabled = false;
  bool get gmsScanEnabled => _gmsScanEnabled;

  /// 设备是否具备 Google Play 服务扫码能力（启动时探测一次）；
  /// 仅用于设置页提示与扫码预热，不参与屏蔽决策。
  bool _gmsAvailable = false;
  bool get gmsAvailable => _gmsAvailable;

  /// 设备是否具备华为 HMS Core（Scan Kit）扫码能力（启动时探测一次，
  /// 仅无 GMS 的设备探测）；鸿蒙 4.2 等无 GMS 华为设备走此通道。
  bool _hmsScanAvailable = false;
  bool get hmsScanAvailable => _hmsScanAvailable;

  /// 是否使用系统扫码（原有应用内相机扫码组件被整体屏蔽）：
  /// 仅由「使用系统扫码」开关决定——开启即屏蔽，扫码走系统扫码路径
  /// （优先 Google Play 服务，无 GMS 设备走华为 Scan Kit），不再进入
  /// 应用内相机；关闭开关时恢复相机扫码。
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
    await _loadSettings();
    await _detectScanChannels();
    await _loadOnlineStationData();
    await _loadKnowledge();
  }

  /// 读取持久化设置（缺失/不可用时保持默认：在线拉取、运行日志与系统扫码均停用）。
  Future<void> _loadSettings() async {
    try {
      // 在线拉取默认关闭，仅显式开启（'true'）时启用
      final enabled =
          await _settingsStore.read(SettingsKeys.onlineFetchEnabled);
      _onlineFetchEnabled = enabled == 'true';
      // 运行日志默认关闭，仅显式开启（'true'）时启用
      final logging = await _settingsStore.read(SettingsKeys.loggingEnabled);
      _loggingEnabled = logging == 'true';
      _logger.enabled = _loggingEnabled;
      // 「使用系统扫码」默认关闭，仅显式开启（'true'）时启用
      final gmsScan = await _settingsStore.read(SettingsKeys.gmsScanEnabled);
      _gmsScanEnabled = gmsScan == 'true';
    } catch (_) {
      // 设置存储不可用（如平台插件缺失）时按默认值降级
    }
  }

  /// 探测设备具备的系统扫码通道（启动时一次；非 Android / 探测失败按
  /// 不具备降级，仅影响设置页提示、扫码分流与预热，不影响屏蔽决策）。
  /// 优先探测 Google Play 服务；无 GMS 时再探测华为 HMS Core（Scan Kit，
  /// 鸿蒙 4.2 等华为设备）。具备 GMS 且开关开启时，后台预热扫码器
  /// （缓存原生实例 + 预装扫码模块），加快首次扫码速度。
  Future<void> _detectScanChannels() async {
    _gmsAvailable = await isGmsQrScanAvailable();
    _hmsScanAvailable = !_gmsAvailable && await isHmsQrScanAvailable();
    notifyListeners();
    if (_gmsAvailable && _gmsScanEnabled) {
      // fire-and-forget：预热不阻塞启动流程，失败静默
      warmUpGmsQrScanner();
    }
  }

  /// 加载本地在线数据快照（仅开关开启时）：存在则取代应用内预制快照。
  Future<void> _loadOnlineStationData() async {
    if (!_onlineFetchEnabled) return;
    try {
      final datasets = await _onlineDataStore.load();
      if (datasets.isNotEmpty) {
        _onlineStationCodes = StationCodeTable.fromDatasets(datasets);
      }
    } catch (_) {
      // 快照读取失败（文件损坏等）时回退应用内预制快照
    }
  }

  Future<void> _loadKnowledge() async {
    KnowledgeBase kb;
    try {
      kb = await KnowledgeBase.load(
        _bundle ?? rootBundle,
        // 已有在线拉取数据（本地快照或本次会话拉取）时用在线数据；
        // 否则回退应用内预制快照
        stationCodes: _onlineStationCodes,
      );
    } catch (_) {
      // 资产缺失或解析失败时降级为空知识库，识别引擎自动失效但流程不断
      kb = KnowledgeBase.empty();
    }
    _kb = kb;
    _engine = AnalysisEngine(kb);
    _logEvent('知识库加载：$knowledgeSummary');
    notifyListeners();
  }

  /// 重建知识库与识别引擎（在线数据变化后刷新查询层；不重读设置）。
  Future<void> reloadKnowledge() async {
    _initFuture = _loadKnowledge();
    await _initFuture;
  }

  /// 设置「开启在线拉取数据」开关（持久化到设置文件）。
  /// 关闭时清除在线数据（内存 + 本地快照）与同步结果，
  /// 回到应用内预制快照。
  Future<void> setOnlineFetchEnabled(bool enabled) async {
    if (_onlineFetchEnabled == enabled) return;
    _onlineFetchEnabled = enabled;
    notifyListeners();
    try {
      await _settingsStore.write(
        SettingsKeys.onlineFetchEnabled,
        '$enabled',
      );
    } catch (_) {
      // 设置写入失败不影响本次会话内的开关状态
    }
    if (!enabled) {
      // 一并清除同步报告/错误，避免再次开启时展示过期结果
      _syncError = null;
      _syncReport = null;
      final hadOnlineData = _onlineStationCodes != null;
      _onlineStationCodes = null;
      try {
        await _onlineDataStore.clear();
      } catch (_) {
        // 本地快照删除失败不影响流程（再次在线更新会整体覆盖）
      }
      if (hadOnlineData) {
        await reloadKnowledge();
      } else {
        notifyListeners();
      }
    }
  }

  /// 在线拉取读卡识途站点数据（手机端直接联网，从 GitHub 主源
  /// 下载归档，主分支失败自动尝试备用分支）。需开启「在线拉取数据」
  /// 开关；拉取成功后持久化到本地快照并取代预制数据（重启后继续生效）。
  /// 失败原因写入 [syncError]，成功摘要写入 [syncReport]。
  Future<void> syncTripreaderData() async {
    if (_syncingData || !_onlineFetchEnabled) return;
    _syncingData = true;
    _syncError = null;
    notifyListeners();
    try {
      final result = await _syncService.sync();
      // 拉取期间若开关被关闭（在线数据已按设计清除），丢弃本次结果，
      // 避免把已清除的在线数据重新写回内存与本地快照
      if (!_onlineFetchEnabled) return;
      _onlineStationCodes = StationCodeTable.fromDatasets(result.datasets);
      _syncReport = result.report;
      try {
        // 持久化快照：拉取的数据取代预制数据，重启后继续生效
        await _onlineDataStore.save(result.datasets);
      } catch (_) {
        // 保存失败时降级为仅本次运行生效（重启后回退预制快照）
        _syncReport = '${result.report}（本地保存失败，仅本次运行生效）';
      }
      await reloadKnowledge();
    } catch (e) {
      _syncError = '$e';
    } finally {
      _syncingData = false;
      notifyListeners();
    }
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
            ' · ISO-DEP=${result.isoDepConnected ? '已连接' : '未连接'}');
      }
      if (result != null && result.isoDepConnected) {
        await _parseAndAnalyze();
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
        notifyListeners();
      }
    }
  }

  Future<void> _parseAndAnalyze() async {
    _parsing = true;
    _resetCard();
    notifyListeners();

    try {
      await init();
      // 按序探测已注册解析器：交通联合（JT/T 978.2）优先，未命中时
      // 尝试城市一卡通（CJ/T 331-2016）；双标准卡以交通联合载荷为主。
      final cardParsers = <CardParser>[
        TUnionParser(_transceive),
        CityUnionParser(_transceive),
      ];
      ParsedCard? parsed;
      for (final parser in cardParsers) {
        _log('== 尝试解析：${parser.parserName} ==');
        parsed = await parser.parse();
        if (parsed != null) break;
      }
      if (parsed == null) {
        _log('== 未发现受支持的交通应用（交通联合 / 城市一卡通）==');
        return;
      }
      _parsedCard = parsed;
      if (parsed.parserId == CardParserIds.tunion) {
        _analysis = _engine?.analyze(parsed);
        _log('== 解析完成：${parsed.transactions.length} 条交易记录 / '
            '${parsed.transitProcessRecords.length} 条过程记录 ==');
      } else {
        // 分析引擎（识别 / 行程 / 符合性）为交通联合专属：
        // 其他卡型只提供文件级解析视图，不进入分析链路。
        _analysis = null;
        _log('== 解析完成：${parsed.parserName} '
            '${parsed.cityUnionFiles.length} 个文件视图 ==');
      }
    } catch (e) {
      _log('!! 解析异常：$e');
    } finally {
      _parsing = false;
      notifyListeners();
    }
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

  void _resetCard() {
    _parsedCard = null;
    _analysis = null;
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
}