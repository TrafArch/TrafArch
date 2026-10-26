import 'dart:async';

import 'package:flutter/services.dart';

import 'app_info.dart';
import '../features/updates/update_service.dart';
import '../features/transit_analysis/tunion_analysis_models.dart';
import '../features/transit_analysis/cu_transaction_analysis.dart';
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
  }) {
    updates =
        updateService ??
        UpdateService(currentBuild: int.parse(AppInfo.buildNumber));
    final assets = bundle ?? rootBundle;
    _logger = logger ?? AppLogger();
    final exporter = logExporter ?? const MethodChannelLogExporter();
    _database = database ?? AppDatabase();
    _ownsDatabase = database == null;
    settings = SettingsController(
      settingsStore ?? FileSettingsStore(),
      _logger,
      browser: feedbackBrowser ?? const MethodChannelFeedbackBrowser(),
    );
    references = ReferenceDataController(assets);
    qr = QrController(log: _logger.log);
    diagnostics = DiagnosticsController(_logger, exporter);
    archive = ArchiveController(
      CardRepository(_database),
      exporter,
      _logger.log,
    );
    archiveTransfer = ArchiveTransferController(
      archive.repository,
      archiveDocumentStore ?? const MethodChannelArchiveDocumentStore(),
    );
    scan = ScanController(
      channel: channel ?? const MethodChannelNfcChannel(),
      felicaChannel: felicaChannel ?? const MethodChannelFelicaChannel(),
      coordinator: CardReadCoordinator(assets),
      logEvent: _logger.log,
    );
    scan.onStarted = () {
      _view = null;
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

  Future<void> init() => _initializing ??= Future.wait([
    references.initialize(),
    settings.initialize(),
  ]);

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
  bool get exportingLog => diagnostics.exportingLog;
  String? get logExportMessage => diagnostics.logExportMessage;
  bool get logExportFailed => diagnostics.logExportFailed;
  bool get autoSaveEnabled => settings.autoSaveEnabled;
  bool get monetEnabled => settings.monetEnabled;
  bool get openingFeedbackSurvey => settings.openingFeedbackSurvey;
  String? get feedbackBrowserError => settings.feedbackBrowserError;
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
  Future<void> setLoggingEnabled(bool enabled) =>
      settings.setLoggingEnabled(enabled);
  Future<void> setAutoSaveEnabled(bool enabled) =>
      settings.setAutoSaveEnabled(enabled);
  Future<void> setMonetEnabled(bool enabled) =>
      settings.setMonetEnabled(enabled);
  Future<bool> openFeedbackEmail(String address) =>
      settings.openFeedbackEmail(address);
  Future<void> openPrivacyPolicy() => settings.openPrivacyPolicy();
  Future<void> openFeedbackSurvey(Uri url) => settings.openFeedbackSurvey(url);
  Future<void> exportLog() => diagnostics.exportLog();
  Future<String> exportCards() => archive.exportCards();
  Future<void> scanOnce() => scan.scanOnce();
  Future<void> stop() => scan.stop();
  Future<bool> acceptPendingSave(String id) => archive.accept(id);
  void declinePendingSave(String id) => archive.decline(id);
  void clearAutoSaveNotice() => archive.clearNotice();

  Future<void> _closeStorage() async {
    await archive.finishWrites();
    await archiveTransfer.finishWrites();
    if (_ownsDatabase) await _database.close();
    await _logger.flush();
  }

  @override
  void dispose() {
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
