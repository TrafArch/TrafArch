import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import 'app_info.dart';
import '../features/updates/update_service.dart';
import '../features/transit_analysis/tunion_analysis_models.dart';
import '../features/transit_analysis/cu_transaction_analysis.dart';
import '../features/transit_analysis/shanghai_balance_display.dart';
import '../protocols/transit/card_parser.dart';
import '../features/reference_data/data/tunion_knowledge_base.dart';
import '../features/reference_data/domain/city_union_knowledge_base.dart';
import '../platform/storage/settings_store.dart';
import '../platform/browser/feedback_browser.dart';
import '../features/reference_data/domain/station_codes.dart';
import '../features/reference_data/data/tunion_bus_location.dart';
import '../protocols/felica/felica.dart';
import '../platform/storage/app_logger.dart';
import '../platform/storage/log_exporter.dart';
import '../platform/nfc/felica_channel.dart';
import '../platform/nfc/nfc_models.dart';
import '../platform/nfc/nfc_service.dart';
import '../protocols/transit/city_union/city_union_models.dart';
import '../protocols/transit/local/cards/shanghai_transit_union_models.dart';
import '../protocols/transit/local/local_card_models.dart';
import '../protocols/transit/qr/jt_t1179_qr_parser.dart';
import '../protocols/transit/tunion/tunion_models.dart';
import '../features/archive/data/app_database.dart';
import '../protocols/bank/domain/models/bank_card_result.dart';
import '../protocols/bank/parsers/bank_card_analyzer.dart';
import '../features/archive/domain/pending_card_save.dart';
import '../features/archive/data/card_repository.dart';
import '../features/archive/application/card_identification_service.dart';

import '../shared/application/owned_notifier.dart';
import '../features/scan/application/scan_controller.dart';
import '../features/scan/application/card_read_coordinator.dart';
import '../features/scan/domain/card_read_outcome.dart';
import '../features/scan/domain/scan_presentation.dart';
import '../features/reference_data/application/reference_data_controller.dart';
import '../features/settings/application/settings_controller.dart';
import '../features/settings/application/diagnostics_controller.dart';
import '../features/qr/application/qr_controller.dart';
import '../features/archive/application/archive_controller.dart';
import '../features/archive/application/archive_transfer_controller.dart';
import '../platform/storage/archive_document_store.dart';
import '../features/archive/domain/card_types.dart';
import '../features/recovery/recovery_state.dart';
import '../features/recovery/capture_read_result.dart';
import '../features/archive/domain/card_session_snapshot.dart';
import '../features/scan/application/card_diagnostic_capture.dart';
import '../platform/memory/memory_platform.dart';

/// Composition root and presentation facade. Controllers own mutable state and
/// resources; this object wires their lifetimes and propagates UI notifications.
class AppDependencies extends OwnedNotifier {
  AppDependencies({
    NfcChannel? channel,
    FelicaChannel? felicaChannel,
    AssetBundle? bundle,
    SettingsStore? settingsStore,
    AppLogger? logger,
    LogExporter? logExporter,
    AppDatabase? database,
    UpdateService? updateService,
    FeedbackBrowser? feedbackBrowser,
    ArchiveDocumentStore? archiveDocumentStore,
    MemoryPlatform? memoryPlatform,
  }) {
    updates =
        updateService ??
        UpdateService(currentBuild: int.parse(AppInfo.buildNumber));
    final assets = bundle ?? rootBundle;
    _logger =
        logger ??
        AppLogger(
          appVersion: AppInfo.version,
          buildNumber: AppInfo.buildNumber,
        );
    final exporter = logExporter ?? const MethodChannelLogExporter();
    _database = database ?? AppDatabase();
    _ownsDatabase = database == null;
    settings = SettingsController(
      settingsStore ?? FileSettingsStore(),
      _logger,
      browser: feedbackBrowser ?? const MethodChannelFeedbackBrowser(),
    );
    references = ReferenceDataController(assets);
    qr = QrController(log: (_) {});
    diagnostics = DiagnosticsController(_logger, exporter);
    archive = ArchiveController(CardRepository(_database), exporter, (_) {});
    archiveTransfer = ArchiveTransferController(
      archive.repository,
      archiveDocumentStore ?? const MethodChannelArchiveDocumentStore(),
    );
    scan = ScanController(
      channel: channel ?? const MethodChannelNfcChannel(),
      felicaChannel: felicaChannel ?? const MethodChannelFelicaChannel(),
      coordinator: CardReadCoordinator(assets),
      logEvent: (_) {},
      diagnostics: _logger,
    );
    scan.onStarted = () {
      _discardRecoveryFile();
      _view = null;
      recoveredCapture = null;
      _completedCapture = null;
      recoveryNotice = null;
      archive.clearSession();
    };
    scan.onCompleted = _complete;
    _children = [
      settings,
      references,
      qr,
      diagnostics,
      archive,
      archiveTransfer,
      scan,
    ];
    for (final child in _children) {
      child.addListener(notifyListeners);
    }
    _memory = memoryPlatform ?? MemoryPlatform.create();
    _memory.listen(handleMemoryPressure);
  }
  late final UpdateService updates;
  late final SettingsController settings;
  late final ReferenceDataController references;
  late final QrController qr;
  late final DiagnosticsController diagnostics;
  late final ArchiveController archive;
  late final ArchiveTransferController archiveTransfer;
  late final ScanController scan;
  late final AppLogger _logger;
  late final AppDatabase _database;
  late final bool _ownsDatabase;
  late final List<OwnedNotifier> _children;
  ScanPresentation? _view;
  Future<void>? _initializing;
  int _scanRequest = 0;
  late final MemoryPlatform _memory;
  PendingCardSave? _completedCapture;
  RecoveryCapture? recoveredCapture;
  String? recoveryNotice;
  bool recoveryReady = false;
  bool _preparingRecovery = false;
  Future<bool>? _killPreparation;
  int recoveryTab = 0;
  String? recoveryRoute;
  String? pendingRecoveryRoute;
  final Map<String, List<String>> recoveryFilters = {};
  bool savingRecoveredCapture = false;

  void _discardRecoveryFile() {
    unawaited(_memory.clearRecovery().catchError((Object _) {}));
  }

  Future<void> saveRecoveredCapture() async {
    final capture = recoveredCapture;
    if (savingRecoveredCapture ||
        capture?.canSave != true ||
        capture?.pending == null ||
        _preparingRecovery) {
      return;
    }
    savingRecoveredCapture = true;
    _discardRecoveryFile();
    recoveredCapture = capture!.withoutPendingSave();
    notifyListeners();
    // Explicit user action uses the existing archive save path. Recovery itself
    // never touches the archive or changes its automatic-save preference.
    archive.pending = capture.pending;
    final capturedVersion = capture.snapshotJson == null
        ? null
        : CardSessionSnapshot.decode(capture.snapshotJson!)?.parseVersion;
    final ok = await archive.accept(
      capture.pending!.pendingSaveId,
      capturedParseVersion: capturedVersion,
    );
    if (!ok && recoveredCapture != null) recoveredCapture = capture;
    archive.pending = null;
    recoveryNotice = ok ? '这次读取已保存。' : '保存失败，请重试。';
    savingRecoveredCapture = false;
    notifyListeners();
  }

  void declineRecoveredCapture() {
    if (savingRecoveredCapture || _preparingRecovery) return;
    _discardRecoveryFile();
    recoveredCapture = recoveredCapture?.withoutPendingSave();
    archive.clearSession();
    notifyListeners();
  }

  Future<void> init() => _initializing ??= () async {
    await Future.wait([
      references.initialize(),
      settings.initialize(),
      _logger.prune().catchError((Object _) {}),
      _restoreRecovery(),
    ]);
    recoveryReady = true;
    notifyListeners();
  }();

  Future<void> _restoreRecovery() async {
    try {
      final text = await _memory.readRecovery();
      if (text == null || disposed) return;
      final state = RecoveryState.decode(text);
      // Consume before exposing pending confirmation: an old file cannot
      // resurrect a capture after the user later saves or dismisses it.
      await _memory.clearRecovery();
      if (disposed) return;
      recoveredCapture = state.capture;
      recoveryTab = state.tab;
      recoveryRoute = state.route;
      pendingRecoveryRoute = state.route;
      recoveryFilters.addAll(state.filters);
      if (state.qrBytes != null) qr.parseQrBytes(state.qrBytes!);
      scan.autoScanConsumed = true;
      recoveryNotice = state.capture?.interrupted == true
          ? '上次读取已中断，请重新贴卡读取。已获取的原始证据已保留。'
          : '已恢复上次页面与读取结果。';
    } on MissingPluginException {
      // Non-Android hosts and unit tests have no native recovery store.
    } catch (_) {
      try {
        await _memory.clearRecovery();
      } catch (_) {}
      if (!disposed) recoveryNotice = '上次现场无法恢复或已过期，请重新读取。';
    }
  }

  /// Standard Android pressure and HONOR TRIM share safe, rebuildable caches.
  /// The KILL path has its own deadline; NFC's physical close remains truthful
  /// and may continue after the memory callback, without blocking its reply.
  Future<bool> handleMemoryPressure(bool kill) {
    if (disposed) return Future.value(false);
    if (kill) {
      return _killPreparation ??= _prepareRecovery().whenComplete(() {
        _killPreparation = null;
      });
    }
    try {
      references.releaseMemory();
      if (!scan.scanning) scan.coordinator.releaseMemory();
      PaintingBinding.instance.imageCache.clear();
      return Future.value(true);
    } catch (_) {
      return Future.value(false);
    }
  }

  Future<bool> _prepareRecovery() async {
    // Never overwrite an unconsumed recovery file during cold-start loading.
    if (!recoveryReady) return false;
    _preparingRecovery = true;
    try {
      final interrupted = scan.scanning;
      final capture =
          recoveredCapture ??
          (scan.tag != null || scan.outcome != null || interrupted
              ? RecoveryCapture(
                  readAt:
                      _completedCapture?.readAt ??
                      scan.tag?.timestamp ??
                      DateTime.now(),
                  summary: {
                    if (_view?.balanceInterpretation case final balance?)
                      'balanceText': balance.accountBalanceText,
                    if (scan.outcome case final result?) ...{
                      ...captureCardInfo(result),
                      'decoded': captureReadResult(result),
                    },
                    if (_completedCapture case final item?) ...{
                      'cardName': item.displayName,
                      'cardNumber': item.cardNumber,
                      'balanceFen': item.balanceFen,
                      'currencyCode': item.currencyCode,
                    },
                  },
                  frames: [for (final frame in scan.frames) frame.toJson()],
                  snapshotJson: _completedCapture?.sessionDataJson,
                  pending: archive.pending ?? _completedCapture,
                  canSave: !interrupted && archive.pending != null,
                  interrupted: interrupted,
                )
              : null);
      // Synchronous invalidation prevents any late result from publishing or
      // issuing another APDU. Do not await the native ten-second close barrier.
      if (interrupted) {
        unawaited(stop());
      }
      final state = RecoveryState(
        savedAt: DateTime.now(),
        tab: recoveryTab,
        route: recoveryRoute,
        capture: capture,
        qrBytes: qr.qrRaw,
        filters: Map.of(recoveryFilters),
      );
      await Future.wait([
        _memory.writeRecovery(state.encode()),
        flushDiagnostics(),
        archive.finishWrites(),
        archiveTransfer.finishWrites(),
      ]).timeout(const Duration(milliseconds: 1800));
      return _logger.storageIssue == null;
    } catch (_) {
      return false;
    } finally {
      _preparingRecovery = false;
    }
  }

  Future<void> _complete(
    CardReadOutcome result,
    String id,
    DateTime readAt,
    bool Function() isCurrent,
  ) async {
    // Acquisition has already finished. Reference initialization never blocks
    // SELECT/READ APDUs or requires an active card to remain in the field.
    await Future.wait([references.initialize(), settings.initialize()]);
    if (!isCurrent()) return;
    final view = ScanPresentation(
      result,
      references.knowledge ?? KnowledgeBase.empty(),
    );
    _view = view;
    archive.stage(
      view,
      id,
      readAt,
      scan.frames,
      metadataIssues: scan.tag?.metadataIssues ?? const [],
    );
    _completedCapture = archive.pending;
    final capturedCard = view.parsedCard;
    if (capturedCard != null) {
      final identified = archive.identified;
      scan.addStructuredDiagnostic(id, 'card_info', {
        'cardNumber':
            identified?.cardNumber ??
            capturedCard.localCard?.info.cardNumber ??
            view.cityUnionPublicInfo?.cityCardNumber ??
            capturedCard.info.displayCardNumber,
        'applicationSerialRaw': capturedCard.info.applicationSerial,
        'cardName':
            identified?.displayName ??
            view.knowledge.cardPrefixes
                .lookupByIssuerId(capturedCard.info.issuerId)
                ?.cardName ??
            view.cityUnionCard?.cardName ??
            capturedCard.localCard?.info.cardKindLabel ??
            capturedCard.parserName,
        'cardType': identified?.identity.cardType ?? capturedCard.parserId,
        'cardTypeLabel': identified == null
            ? capturedCard.parserName
            : cardTypeLabel(identified.identity.cardType),
        'cardFamily': view.analysis?.identity.cardFamily,
        'cardKindRaw': capturedCard.info.cardKind,
        'cardTypeRaw': capturedCard.info.cardTypeId,
        'parserId': capturedCard.parserId,
        'parserName': capturedCard.parserName,
        'selectedAid': capturedCard.selectedAidHex,
        'identificationState': 'resolved',
      });
    }
    final parsed = view.parsedCard;
    if (parsed != null) {
      final balance = view.balanceInterpretation;
      final display = balance?.isOctopusTunion == true
          ? balance!.accountBalanceText
          : parsed.info.balanceFen == null
          ? 'n/a'
          : '${view.cardCurrency.symbol}${(parsed.info.balanceFen! / 100).toStringAsFixed(2)}';
      scan.addDiagnostic(
        '== 余额核对：parser=${parsed.parserId}; aid=${parsed.selectedAidHex}; '
        'parsedFen=${parsed.info.balanceFen}; '
        'display=$display; '
        'archiveFen=${archive.pending?.balanceFen}; cuFen=${parsed.cityUnionBalanceFen}; '
        'analysisFen=${view.analysis?.wallet.balanceFen}; '
        'accountCurrency=${balance?.accountCurrency}; '
        'accountBalanceMinor=${balance?.accountBalanceMinor}; '
        'balanceRole=${balance?.semantics.name} ==',
      );
    }
    notifyListeners();
    if (settings.autoSaveEnabled && isCurrent()) await archive.autoSave();
  }

  CardRepository get cardRepository => archive.repository;
  PendingCardSave? get pendingCardSave => archive.pending;
  String? get lastCardFingerprint => archive.fingerprint;
  IdentifiedCard? get lastIdentified => archive.identified;
  NfcScanResult? get lastResult => scan.tag;
  bool get scanning => scan.scanning;
  bool get parsing => scan.parsing;
  int? get readProgress => scan.progress;
  bool get autoScanConsumed => scan.autoScanConsumed;
  String? get error => scan.error ?? scan.releaseError;
  ParsedCard? get parsedCard => _view?.parsedCard;
  ShanghaiTransitUnionResult? get shanghaiTransitUnion =>
      _view?.shanghaiTransitUnion;
  ReadResult? get localReadResult => _view?.localReadResult;
  BankCardResult? get lastBankCardResult => _view?.lastBankCardResult;
  FelicaScanResult? get felicaResult => _view?.felicaResult;
  TUnionCardInfo? get cardInfo => _view?.cardInfo;
  List<TUnionTransaction> get transactions => _view?.transactions ?? const [];
  List<TUnionProcessRecord> get transitProcessRecords =>
      _view?.transitProcessRecords ?? const [];
  List<TUnionTripRecord> get cycleProcessTrips =>
      _view?.cycleProcessTrips ?? const [];
  TransitRecord? get railTransitRecord => _view?.railTransitRecord;
  BusTransitRecord? get busTransitRecord => _view?.busTransitRecord;
  bool get tunionDetected => _view?.tunionDetected ?? false;
  bool get cityUnionDetected => _view?.cityUnionDetected ?? false;
  bool get dualApplicationDetected => _view?.dualApplicationDetected ?? false;
  int? get cityUnionBalanceFen => _view?.cityUnionBalanceFen;
  List<CityUnionFileView> get cityUnionFiles =>
      _view?.cityUnionFiles ?? const [];
  List<CuTransactionView> get cityUnionTransactions =>
      _view?.cityUnionTransactions ?? const [];
  CjT331PublicInfo? get cityUnionPublicInfo => _view?.cityUnionPublicInfo;
  CityUnionCardInfo? get cityUnionCard => _view?.cityUnionCard;
  Currency get cardCurrency => _view?.cardCurrency ?? Currency.cny;
  ShanghaiBalanceDisplay get balanceDisplay => ShanghaiBalanceDisplay.forCard(
    includeShanghaiOverdraft: includeShanghaiOverdraft,
    parserId: parsedCard?.parserId,
    applicationId: parsedCard?.selectedAidHex,
    currencyCode: cardCurrency.code,
  );
  String? get cardCityCode => _view?.cardCityCode;
  bool isRemoteUse(String? code) => _view?.isRemoteUse(code) ?? false;
  CardAnalysisResult? get analysis => _view?.analysis;
  KnowledgeBase? get knowledgeBase => references.knowledge;
  bool get knowledgeReady => knowledgeBase != null;
  bool get ready => knowledgeReady;
  String get knowledgeSummary => knowledgeBase == null
      ? (references.error ?? '加载中')
      : 'TU ${knowledgeBase!.tuStations?.stationCount ?? 0} 条 / CU ${knowledgeBase!.cuRepository?.totalEntryCount ?? 0} 条；'
            '${knowledgeBase!.loadIssues.isEmpty ? '本地数据已加载' : '部分数据不可用'}';
  bool get loggingEnabled => settings.loggingEnabled;
  bool get includeShanghaiOverdraft => settings.includeShanghaiOverdraft;
  bool get exportingLog => diagnostics.exportingLog;
  String? get logExportMessage => diagnostics.logExportMessage;
  bool get logExportFailed => diagnostics.logExportFailed;
  bool get autoSaveEnabled => settings.autoSaveEnabled;
  bool get monetEnabled => settings.monetEnabled;
  bool get openingFeedbackSurvey => settings.openingFeedbackSurvey;
  String? get feedbackBrowserError => settings.feedbackBrowserError;
  String? get feedbackBrowserNotice => settings.feedbackBrowserNotice;
  void clearFeedbackBrowserNotice() => settings.clearFeedbackBrowserNotice();
  String? get autoSaveNotice => archive.autoSaveNotice;
  List<String> get apduLog => scan.trace;
  JtT1179QrData? get qrData => qr.qrData;
  List<int>? get qrRaw => qr.qrRaw;
  String? get qrError => qr.qrError;
  bool get hasQrData => qr.hasQrData;

  String? cityNameOf(String? code) => references.cityNameOf(code);
  String? cuCityNameOf(String? code) => references.cuCityNameOf(code);
  CardPrefixInfo? cardPrefixOf(String? cardNumber) =>
      references.cardPrefixOf(cardNumber);
  CardPrefixInfo? cardPrefixByIssuerId(String? issuerId) =>
      references.cardPrefixByIssuerId(issuerId);
  String? cardKindName(String? hex) => references.cardKindName(hex);
  StationMatch resolveStationMatch(
    String? cityCode,
    String? rawCode, {
    int? lineValue,
  }) => references.resolveStationMatch(cityCode, rawCode, lineValue: lineValue);
  StationMatch resolveCycleStationMatch(
    String? cityCode,
    String? field, {
    String? terminalId,
    DateTime? time,
    int? appType,
  }) => references.resolveCycleStationMatch(
    cityCode,
    field,
    terminalId: terminalId,
    time: time,
    appType: appType,
  );
  TunionBusLocation resolveBusLocation(
    String? cityCode,
    String? field, {
    TunionBusDecodeContext context = const TunionBusDecodeContext(),
  }) => references.resolveBusLocation(cityCode, field, context: context);
  String? resolveStationName(String? cityCode, String? rawCode) =>
      references.resolveStationName(cityCode, rawCode);
  String? resolveLineName(String? cityCode, String? rawLineCode) =>
      references.resolveLineName(cityCode, rawLineCode);
  String? resolveCuStationName(
    String? terminalNumber, {
    String? cityCode,
    int? decodedCarrierType,
    DateTime? transactionTime,
    bool busLookupEnabled = false,
  }) => references.resolveCuStationName(
    terminalNumber,
    cityCode: cityCode,
    decodedCarrierType: decodedCarrierType,
    transactionTime: transactionTime,
    busLookupEnabled: busLookupEnabled,
  );
  bool parseQrBytes(List<int> bytes) => qr.parseQrBytes(bytes);
  bool parseQrText(String input) => qr.parseQrText(input);
  static List<int>? decodeQrText(String input) =>
      QrController.decodeQrText(input);
  void clearQr() => qr.clearQr();
  Future<void> setLoggingEnabled(bool enabled) {
    final write = settings.setLoggingEnabled(enabled);
    if (enabled) scan.refreshWaitingDiagnostics();
    return write;
  }

  Future<void> setAutoSaveEnabled(bool enabled) =>
      settings.setAutoSaveEnabled(enabled);
  Future<void> setMonetEnabled(bool enabled) =>
      settings.setMonetEnabled(enabled);
  Future<void> setIncludeShanghaiOverdraft(bool enabled) =>
      settings.setIncludeShanghaiOverdraft(enabled);
  Future<bool> openFeedbackEmail(String address) =>
      settings.openFeedbackEmail(address);
  Future<bool> openFeedbackQqGroup(String groupNumber, Uri joinUrl) =>
      settings.openFeedbackQqGroup(groupNumber, joinUrl);
  Future<void> openPrivacyPolicy() => settings.openPrivacyPolicy();
  Future<void> openFeedbackSurvey(Uri url) => settings.openFeedbackSurvey(url);
  Future<void> exportLog({Set<String>? sessionIds}) =>
      diagnostics.exportLog(sessionIds: sessionIds);
  Future<String> exportCards() => archive.exportCards();
  Future<void> scanOnce() {
    final request = ++_scanRequest;
    if (disposed || _preparingRecovery || savingRecoveredCapture) {
      return Future.value();
    }
    if (settings.initialized) return scan.scanOnce();
    return settings.initialize().then((_) async {
      if (!disposed && request == _scanRequest) await scan.scanOnce();
    });
  }

  Future<void> flushDiagnostics() => _logger.flush();
  Future<void> stop() {
    _scanRequest++;
    return scan.stop();
  }

  Future<bool> acceptPendingSave(String id) {
    _discardRecoveryFile();
    return archive.accept(id);
  }

  void declinePendingSave(String id) {
    _discardRecoveryFile();
    archive.decline(id);
  }

  void clearAutoSaveNotice() => archive.clearNotice();

  Future<void> _closeStorage() async {
    await scan.finishPending();
    await archive.finishWrites();
    await archiveTransfer.finishWrites();
    if (_ownsDatabase) await _database.close();
    await _logger.close();
  }

  @override
  void dispose() {
    _memory.dispose();
    for (final child in _children) {
      child.removeListener(notifyListeners);
    }
    scan.dispose();
    archive.dispose();
    archiveTransfer.dispose();
    references.dispose();
    settings.dispose();
    qr.dispose();
    diagnostics.dispose();
    unawaited(_closeStorage());
    super.dispose();
  }
}
