import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/analysis/analysis_engine.dart';
import '../core/analysis/analysis_models.dart';
import '../core/app_info.dart';
import '../core/card/card_parser.dart';
import '../core/data/knowledge_base.dart';
import '../core/data/online_data_store.dart';
import '../core/data/settings_store.dart';
import '../core/data/station_codes.dart';
import '../core/data/tripreader_sync.dart';
import '../core/logging/app_logger.dart';
import '../core/logging/log_exporter.dart';
import '../core/nfc/nfc_models.dart';
import '../core/nfc/nfc_service.dart';
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

  bool get tunionDetected => _parsedCard != null;

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
    await _loadOnlineStationData();
    await _loadKnowledge();
  }

  /// 读取持久化设置（缺失/不可用时保持默认：在线拉取与运行日志均停用）。
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
    } catch (_) {
      // 设置存储不可用（如平台插件缺失）时按默认值降级
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
      _log('== 开始交通联合卡解析（JT/T 978.2）==');
      // v0.1 仅注册交通联合解析器；未来多卡型时改为按序探测（CardParser.probe）
      final parser = TUnionParser(_transceive);
      final parsed = await parser.parse();
      if (parsed == null) {
        _log('== 未发现交通联合应用 ==');
        return;
      }
      _parsedCard = parsed;
      _analysis = _engine?.analyze(parsed);
      _log('== 解析完成：${parsed.transactions.length} 条交易记录 / '
          '${parsed.transitProcessRecords.length} 条过程记录 ==');

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
}