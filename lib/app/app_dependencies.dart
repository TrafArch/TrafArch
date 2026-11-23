import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

import 'app_info.dart';
import '../features/updates/update_service.dart';
import '../features/transit_analysis/tunion_analysis_models.dart';
import '../features/transit_analysis/cu_transaction_analysis.dart';
import '../features/transit_analysis/shanghai_balance_display.dart';
import '../features/transit_analysis/balance_interpretation.dart';
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
import '../protocols/transit/multiapp/application_evidence.dart';
import '../protocols/transit/qr/jt_t1179_qr_parser.dart';
import '../protocols/transit/tunion/tunion_models.dart';
import '../features/archive/data/app_database.dart';
import '../features/archive/domain/pending_card_save.dart';
import '../features/archive/data/card_repository.dart';
import '../features/archive/application/card_identification_service.dart';

import '../shared/application/owned_notifier.dart';
import '../shared/domain/archive_conflict_policy.dart';
import '../features/scan/application/scan_controller.dart';
import '../features/scan/application/card_read_coordinator.dart';
import '../features/scan/domain/card_read_outcome.dart';
import '../features/scan/domain/scan_presentation.dart';
import '../features/reference_data/application/reference_data_controller.dart';
import '../features/reference_data/application/card_provider_resolver.dart';
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
import '../features/trips/suica_trip_presenter.dart';
import '../features/reference_data/data/suica_station_repository.dart';
import '../features/octopus/octopus_balance_controller.dart';
import '../platform/nfc/octopus_channel.dart';
import '../protocols/octopus/octopus_balance_reader.dart';
import '../protocols/octopus/octopus_balance.dart';

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
    OctopusBalanceController? octopusController,
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
    final store = settingsStore ?? FileSettingsStore();
    settings = SettingsController(
      store,
      _logger,
      browser: feedbackBrowser ?? const MethodChannelFeedbackBrowser(),
    );
    octopus =
        octopusController ??
        OctopusBalanceController(
          channel: const MethodChannelOctopusNfcChannel(),
          execute: const OctopusBalanceReader().execute,
          diagnostics: _logger,
        );
    references = ReferenceDataController(assets);
    qr = QrController(log: (_) {}, diagnostics: _logger);
    diagnostics = DiagnosticsController(_logger, exporter);
    archive = ArchiveController(CardRepository(_database), exporter, (_) {});
    archiveTransfer = ArchiveTransferController(
      archive.repository,
      archiveDocumentStore ?? const MethodChannelArchiveDocumentStore(),
    );
    scan = ScanController(
      channel: channel ?? const MethodChannelNfcChannel(),
      felicaChannel: felicaChannel ?? const MethodChannelFelicaChannel(),
      coordinator: const CardReadCoordinator(),
      logEvent: (_) {},
      diagnostics: _logger,
    );
    scan.onStarted = () {
      _octopusView = null;
      _octopusResult = null;
      _octopusAttempted = false;
      octopus.clearResult();
      _discardRecoveryFile();
      _view = null;
      _completedRead = false;
      _galleryCaptureId = null;
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
      octopus,
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
  late final OctopusBalanceController octopus;
  late final AppLogger _logger;
  late final AppDatabase _database;
  late final bool _ownsDatabase;
  late final List<OwnedNotifier> _children;
  ScanPresentation? _view;
  Future<void>? _initializing;
  int _scanRequest = 0;
  int? _unifiedScanRequest;
  bool _completedRead = false;
  bool _gallerySave = false;
  bool _qrAcquiring = false;
  int _qrAcquisitionRevision = 0;
  String? _galleryCaptureId;
  ScanPresentation? _octopusView;
  OctopusBalanceResult? _octopusResult;
  bool _octopusAttempted = false;
  Future<void>? _ordinaryStop;
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
  bool pendingRecoveryNavigation = false;
  final Map<String, List<String>> recoveryFilters = {};
  bool savingRecoveredCapture = false;

  void _discardRecoveryFile() {
    unawaited(_memory.clearRecovery().catchError((Object _) {}));
  }

  Future<void> saveRecoveredCapture() async {
    final capture = recoveredCapture;
    if (savingRecoveredCapture ||
        capture?.canSave != true ||
        capture?.interrupted == true ||
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
      pendingRecoveryNavigation = true;
      recoveryFilters.addAll(state.filters);
      if (state.qrBytes case final bytes?) {
        qr.parseQrBytes(bytes, recordDiagnostics: false);
      }
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
    _qrAcquisitionRevision++;
    try {
      final interrupted =
          scan.scanning || (_gallerySave && !_completedRead && scanning);
      final capture =
          recoveredCapture ??
          (scan.tag != null || scan.outcome != null || interrupted
              ? RecoveryCapture(
                  readAt:
                      _completedCapture?.readAt ??
                      scan.tag?.timestamp ??
                      DateTime.now(),
                  summary: {
                    if (octopusBalanceText case final octopusBalance?)
                      'balanceText': octopusBalance
                    else if (_view?.balanceInterpretation case final balance?)
                      'balanceText': balance.accountBalanceText,
                    if (scan.outcome case final result?) ...{
                      ...captureCardInfo(result),
                      'decoded': captureReadResult(result),
                    },
                    if (suicaTrips.isNotEmpty)
                      'suicaTrips': [
                        for (final trip in suicaTrips) trip.toJson(),
                      ],
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
      if (interrupted || octopus.busy || _unifiedScanRequest != null) {
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
      tag: scan.tag,
    );
    _view = view;
    if (_gallerySave) _galleryCaptureId = id;
    for (final trip in view.suicaTrips) {
      scan.addStructuredDiagnostic(id, 'parser_record', {
        'parserId': 'felica.suica',
        'fieldCategory': 'journeyPresentation',
        'fields': trip.toJson(),
      });
    }
    archive.stage(
      view,
      id,
      readAt,
      scan.frames,
      metadataIssues: scan.tag?.metadataIssues ?? const [],
      prepareSave: !_gallerySave,
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
    if (!_gallerySave && settings.autoSaveEnabled && isCurrent()) {
      await archive.autoSave(policy: settings.archiveConflictPolicy);
    }
  }

  CardRepository get cardRepository => archive.repository;
  PendingCardSave? get pendingCardSave => archive.pending;
  String? get lastCardFingerprint => archive.fingerprint;
  IdentifiedCard? get lastIdentified => archive.identified;
  NfcScanResult? get lastResult => scan.tag;
  bool get hasCompletedRead => _completedRead;
  bool get nfcReleaseFailed =>
      scan.releaseError != null || octopus.releaseError != null;
  bool get scanning =>
      _unifiedScanRequest != null || scan.scanning || octopus.busy;
  bool get isOctopusCard =>
      (parsedCard != null &&
          BalanceInterpretation.fromParsedCard(parsedCard!).isOctopusTunion) ||
      felicaResult?.systemCodes.contains(0x8008) == true;
  OctopusBalanceResult? get currentOctopusResult =>
      isOctopusCard &&
          _view != null &&
          identical(_octopusView, _view) &&
          identical(_octopusResult, octopus.result)
      ? _octopusResult
      : null;
  String? get octopusBalanceText {
    if (!isOctopusCard) return null;
    final hkd = currentOctopusResult?.balanceMinor;
    final primary = hkd == null ? '港币余额未读取' : _formatHkdMinor(hkd);
    final card = parsedCard;
    final tu =
        card != null &&
            BalanceInterpretation.fromParsedCard(card).isOctopusTunion
        ? card.info.balanceFen
        : null;
    return tu == null
        ? primary
        : '$primary (￥${(tu / 100).toStringAsFixed(2)})';
  }

  String? get octopusReadFailure =>
      isOctopusCard && _octopusAttempted && identical(_octopusView, _view)
      ? octopus.releaseError ?? octopus.error
      : null;

  String? get octopusReadNotice {
    if (!isOctopusCard) return null;
    if (scan.releaseError != null) return '原读卡连接尚未确认关闭，请停止后重试。';
    if (octopus.progressMessage case final progress?) return progress;
    if (octopusReadFailure case final failure?) return failure;
    return currentOctopusResult == null ? '再次读取可读取八达通港币余额。' : null;
  }

  bool get parsing => scan.parsing;
  int? get readProgress => scan.progress;
  bool get autoScanConsumed => scan.autoScanConsumed;
  String? get error => scan.error ?? scan.releaseError;
  ParsedCard? get parsedCard => _view?.parsedCard;
  CardProviderInfo? get cardProviders => _view?.cardProviders;
  List<ApplicationEvidence> get applications => _view?.applications ?? const [];
  ShanghaiTransitUnionResult? get shanghaiTransitUnion =>
      _view?.shanghaiTransitUnion;
  ReadResult? get localReadResult => _view?.localReadResult;
  FelicaScanResult? get felicaResult => _view?.felicaResult;
  List<SuicaTripPresentation> get suicaTrips => _view?.suicaTrips ?? const [];
  SuicaStationRepository? get suicaStations =>
      _view?.knowledge.suicaStations ?? references.knowledge?.suicaStations;
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
  ArchiveConflictPolicy get archiveConflictPolicy =>
      settings.archiveConflictPolicy;
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
  bool get qrAcquiring => _qrAcquiring;

  Future<bool> runQrAcquisition(
    Future<void> Function(bool Function()) acquire,
  ) async {
    if (disposed || _qrAcquiring || _preparingRecovery) return false;
    _qrAcquiring = true;
    final revision = ++_qrAcquisitionRevision;
    bool isCurrent() => !disposed && revision == _qrAcquisitionRevision;
    notifyListeners();
    try {
      await stop();
      if (!isCurrent() || nfcReleaseFailed) return false;
      await acquire(isCurrent);
      return true;
    } finally {
      _qrAcquiring = false;
      notifyListeners();
    }
  }

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
  Future<void> setArchiveConflictPolicy(ArchiveConflictPolicy policy) =>
      settings.setArchiveConflictPolicy(policy);
  Future<void> setMonetEnabled(bool enabled) =>
      settings.setMonetEnabled(enabled);
  Future<void> setIncludeShanghaiOverdraft(bool enabled) =>
      settings.setIncludeShanghaiOverdraft(enabled);
  Future<bool> openFeedbackEmail(String address) =>
      settings.openFeedbackEmail(address);
  Future<bool> openFeedbackQqGroup(String groupNumber, Uri joinUrl) =>
      settings.openFeedbackQqGroup(groupNumber, joinUrl);
  Future<void> openWebLink(Uri url) => settings.openWebLink(url);
  Future<void> openFeedbackSurvey(Uri url) => settings.openFeedbackSurvey(url);
  Future<void> exportLog({Set<String>? sessionIds}) =>
      diagnostics.exportLog(sessionIds: sessionIds);
  Future<String> exportCards() => archive.exportCards();
  Future<void> scanOnce() => _scanOnce();

  Future<void> scanOnceForGallery() => _scanOnce(gallerySave: true);

  Future<void> _scanOnce({bool gallerySave = false}) async {
    if (_qrAcquiring) return;
    final request = ++_scanRequest;
    if (disposed || _preparingRecovery || savingRecoveredCapture) {
      return;
    }
    final supersedesRead = _unifiedScanRequest != null || scan.scanning;
    _unifiedScanRequest = request;
    notifyListeners();
    try {
      if (octopus.busy || octopus.releaseError != null) await octopus.cancel();
      if (supersedesRead || scan.releaseError != null) {
        await _stopOrdinaryScan();
      }
      if (_ordinaryStop case final closing?) await closing;
      if (disposed || request != _scanRequest || nfcReleaseFailed) {
        return;
      }
      // Keep the initialized ordinary reader's synchronous discovery start.
      if (!settings.initialized) await settings.initialize();
      if (disposed || request != _scanRequest) return;
      _gallerySave = gallerySave;
      // scanOnce completes only after its physical NFC close barrier.
      await scan.scanOnce();
      if (disposed || request != _scanRequest || scan.releaseError != null) {
        return;
      }
      final view = _view;
      if (view == null) return;
      if (isOctopusCard) await _queryCurrentOctopus(request, view);
      if (!disposed &&
          request == _scanRequest &&
          !nfcReleaseFailed &&
          scan.phase == ScanPhase.complete &&
          identical(_view, view)) {
        _completedRead = true;
        if (_galleryCaptureId case final id? when gallerySave) {
          await _stageGalleryCapture(view, id, request);
        }
      }
    } finally {
      if (_unifiedScanRequest == request) {
        _unifiedScanRequest = null;
        if (!disposed) notifyListeners();
      }
    }
  }

  Future<void> _stageGalleryCapture(
    ScanPresentation view,
    String id,
    int request,
  ) async {
    final readAt = scan.tag!.timestamp;
    archive.stage(
      view,
      id,
      readAt,
      scan.frames,
      metadataIssues: scan.tag!.metadataIssues,
    );
    _completedCapture = archive.pending;
    final pending = archive.pending;
    if (currentOctopusResult case final result? when pending != null) {
      await archive.attachVerifiedAccountBalance(
        fingerprint: pending.fingerprint,
        readAt: readAt,
        balanceMinor: result.balanceMinor,
        evidenceSource:
            'octopus.nfc-f:${result.idmHex}:${result.readAt.toUtc().toIso8601String()}',
        persistSaved: false,
      );
      if (!disposed && id == _galleryCaptureId) {
        _completedCapture = archive.pending;
      }
    }
    if (!disposed && request == _scanRequest && settings.autoSaveEnabled) {
      await archive.autoSave(policy: settings.archiveConflictPolicy);
    }
  }

  Future<void> readOctopus() async {
    if (_qrAcquiring ||
        disposed ||
        _preparingRecovery ||
        savingRecoveredCapture ||
        scanning ||
        !isOctopusCard) {
      return;
    }
    final view = _view;
    if (view == null) return;
    final request = ++_scanRequest;
    // Do not auto-start the normal discovery when returning to the home tab
    // after an explicit balance reading. It would discard that reading.
    scan.autoScanConsumed = true;
    await _stopOrdinaryScan();
    if (disposed || request != _scanRequest) return;
    if (scan.releaseError != null) {
      notifyListeners();
      return;
    }
    await _queryCurrentOctopus(request, view);
  }

  Future<void> _queryCurrentOctopus(int request, ScanPresentation view) async {
    if (disposed || request != _scanRequest || !identical(_view, view)) return;
    _octopusView = view;
    _octopusAttempted = true;
    _octopusResult = null;
    // A successful ordinary FeliCa read already carries this card's IDm. Use it
    // even when optional tag metadata omitted the NFC-F system code, but only
    // when that read actually found the Octopus system. A missing IDm still
    // relies on the documented continuous-tap context.
    final felica = view.felicaResult;
    final felicaIdm = felica != null && felica.systemCodes.contains(0x8008)
        ? felica.idm?.replaceAll(' ', '').toUpperCase()
        : null;
    final expectedIdm = _validIdm(felicaIdm) ? felicaIdm : null;
    final cancellationRevision = octopus.cancellationRevision;
    await octopus.read(expectedCardIdm: expectedIdm);
    if (disposed ||
        request != _scanRequest ||
        !identical(_view, view) ||
        octopus.cancellationRevision != cancellationRevision) {
      return;
    }
    if (octopus.lastAttemptSucceeded) {
      final result = _octopusResult = octopus.result;
      final capture = _completedCapture;
      if (!_gallerySave && result != null && capture != null) {
        await archive.attachVerifiedAccountBalance(
          fingerprint: capture.fingerprint,
          readAt: capture.readAt ?? DateTime.now(),
          balanceMinor: result.balanceMinor,
          evidenceSource:
              'octopus.nfc-f:${result.idmHex}:'
              '${result.readAt.toUtc().toIso8601String()}',
        );
        // Recovery and a still-pending save must carry the HKD evidence too.
        if (archive.pending case final pending?) _completedCapture = pending;
      }
    }
    notifyListeners();
  }

  Future<void> flushDiagnostics() => _logger.flush();
  Future<void> stop() async {
    _scanRequest++;
    _unifiedScanRequest = null;
    await Future.wait([_stopOrdinaryScan(), octopus.cancel()]);
  }

  Future<void> _stopOrdinaryScan() {
    if (_ordinaryStop case final pending?) return pending;
    final done = Completer<void>();
    // Reserve before scan.stop notifies listeners, so a reentrant request joins
    // the same native close instead of clearing the current close owner.
    final stopping = done.future.whenComplete(() => _ordinaryStop = null);
    _ordinaryStop = stopping;
    scan.stop().then(done.complete, onError: done.completeError);
    return stopping;
  }

  Future<bool> acceptPendingSave(
    String id, {
    ArchiveConflictPolicy? conflictPolicy,
  }) {
    _discardRecoveryFile();
    final policy = conflictPolicy ?? settings.archiveConflictPolicy;
    return archive.accept(id, conflictPolicy: policy);
  }

  Future<bool> archiveCardExists(String fingerprint) =>
      archive.cardExists(fingerprint);

  void declinePendingSave(String id) {
    _discardRecoveryFile();
    archive.decline(id);
  }

  void clearAutoSaveNotice() => archive.clearNotice();

  Future<void> _closeStorage() async {
    await scan.finishPending();
    await octopus.finishPending();
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
    octopus.dispose();
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

String _formatHkdMinor(int minor) {
  final sign = minor < 0 ? '-' : '';
  final cents = minor.abs();
  return 'HK\$$sign${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

bool _validIdm(String? idm) =>
    idm != null &&
    RegExp(r'^[0-9A-F]{16}$').hasMatch(idm) &&
    idm != '0000000000000000';
