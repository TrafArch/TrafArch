part of 'gallery_app.dart';

class _GalleryLiveScope extends InheritedNotifier<_GalleryLiveRead> {
  const _GalleryLiveScope({required super.notifier, required super.child});

  static _GalleryLiveRead? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GalleryLiveScope>()?.notifier;
}

class _GalleryLiveRead extends ChangeNotifier implements GalleryLiveAdapter {
  _GalleryLiveRead(this.app, this.navigation, this.restoreFaceImages) {
    final result = app.lastResult;
    if (app.hasCompletedRead && result != null) {
      lastCard = _LiveCardSummary.fromRead(app, readAt: result.timestamp);
      _lastCardStamp = _readStamp(app);
    }
    navigation.attachLive(this);
    app.addListener(_appChanged);
    navigation.addListener(_navigationChanged);
    _archiveSubscription = app.cardRepository.watchAllArchiveRows().listen(
      _archiveChanged,
      onError: (Object error) {
        _archiveIssue = '$error';
        _syncController();
        notifyListeners();
      },
    );
    _restoreRoutes();
    _syncController();
  }

  final AppDependencies app;
  final GalleryController navigation;
  final Future<void> Function(Iterable<GalleryCard>) restoreFaceImages;
  StreamSubscription<List<ArchiveRows>>? _archiveSubscription;
  List<_LiveArchiveCard> _archive = const [];
  Map<String, _LiveArchiveCard> _archiveById = const {};
  _LiveReadCard? _current;

  /// Signature of the inputs that produced [_current]. A settings notification
  /// (auto-save, overdraft, logs) leaves all of them untouched, so the live
  /// projection is reused instead of being rebuilt from the snapshot.
  String? _currentKey;
  List<_LiveArchiveCard>? _syncedArchive;
  List<GalleryCard>? _syncedCards;
  bool _syncedFresh = false;
  String? _lastCardStamp;
  bool _freshCurrent = false;
  String? _archiveIssue;
  GalleryCard? _placeholder;
  _LiveCardSummary? lastCard;
  ExpertReadTab expertTab = ExpertReadTab.information;
  int manualSaveRequest = 0;
  Object? _attempt;
  String? _attemptStartedWith;
  bool _closing = false;
  bool _disposed = false;
  bool openingQr = false;
  Future<ArchiveConflictPolicy?> Function()? conflictResolver;
  bool? lastSaveSucceeded;
  String? lastSaveMessage;
  bool _routesRestored = false;
  String? _error;

  GalleryCard get currentCard => _current?.card ?? _placeholderCard;
  List<GalleryCard> get savedCards => [for (final item in _archive) item.card];
  List<GalleryRecord> get trips => _current?.records ?? const [];
  ArchiveHistoryResult? get currentHistory => _current?.history;
  String? get archiveIssue => _archiveIssue;
  SavedCard? savedCardFor(String id) => _archiveById[id]?.saved;

  // The wallet may show a current read in place of its same-ID archive card.
  // Use the saved row, not the current read, for editable archive metadata.
  _LiveArchiveCard? suicaArchiveFor(String id) {
    final archive = _archiveById[id];
    return archive?.saved.cardType == CardTypes.suica ? archive : null;
  }

  Future<void> setSuicaManualNumber(SavedCard target, String? value) async {
    final archive = suicaArchiveFor(target.id);
    if (_archiveIssue != null ||
        archive == null ||
        archive.saved.cardFingerprint != target.cardFingerprint ||
        archive.suicaManualNumberEditIssue != null) {
      throw StateError('无法确认档案身份，未修改卡面编号');
    }
    await app.cardRepository.setSuicaManualNumber(target.id, value);
  }

  Object? get currentFelicaSystems {
    final snapshot = currentHistory?.latestCapture?.snapshot;
    final decoded = app.recoveredCapture?.summary['decoded'];
    if (decoded is Map) {
      return decoded['systemResults'] ?? snapshot?.extensions['felicaSystems'];
    }
    if (app.felicaResult case final card?) return captureFelicaSystems(card);
    return snapshot?.extensions['felicaSystems'];
  }

  ArchiveHistoryResult? historyFor(String id) =>
      id == _current?.card.id ? _current?.history : _archiveById[id]?.history;
  List<ApplicationEvidence> get currentApplications =>
      _current?.applications ?? const [];

  List<String> get sources => [
    '全部来源',
    for (final value in {
      for (final record in trips)
        ...((record['sources'] as List?) ?? [record['source']])
            .whereType<String>(),
    })
      value,
  ];
  List<String> get modes => [
    '全部方式',
    for (final value in {
      for (final record in trips)
        if (record['mode'] case final String mode) mode,
    })
      value,
  ];

  GalleryCard get _placeholderCard {
    final existing = _placeholder;
    if (existing != null) return existing;
    return _placeholder = navigation.cards.isEmpty
        ? GalleryCard.live(
            id: 'live-current',
            saved: false,
            name: '待读取',
            tail: '——',
            pan: '未提供',
            rawBalance: '——',
            city: '未知',
            type: '交通卡',
            valid: '未知',
            when: '尚未读取',
            count: '0 条',
            face: 'blue',
            applications: const [],
            currencyCode: null,
          )
        : navigation.cards.first;
  }

  bool get busy => _attempt != null || (app.scanning && !app.nfcReleaseFailed);
  bool get closing => _closing;

  /// Reader percentage (0–100) of the attempt in flight, or null while the tag
  /// is still being discovered. A progress-only notification ends in
  /// [notifyListeners] without touching the projection: [_appChanged] rebuilds
  /// the read stage through [_syncController], which returns [_current]
  /// unchanged while [busy], so the prompt repaints without a card reprojection.
  int? get readProgress => app.readProgress;
  bool get hasCurrent => _current != null && !app.nfcReleaseFailed;
  bool get hasFreshCurrent =>
      _freshCurrent && _current != null && !app.nfcReleaseFailed;
  bool get _hasCompletedCurrentRead =>
      app.hasCompletedRead &&
      app.lastResult != null &&
      (_attempt == null || _readStamp(app) != _attemptStartedWith);

  // A failed repeat may show the last card only as a previous result.
  String? get _adapterInterruption =>
      _current == null ? null : '本次读取已中断，请重新读取。';

  void _appChanged() {
    if (_attempt != null &&
        app.nfcUnavailableMessage != null &&
        !_hasCompletedCurrentRead) {
      // The adapter switch ends this attempt even if discovery replies later.
      _attempt = null;
      _error = _adapterInterruption;
    }
    _restoreRoutes();
    final result = app.lastResult;
    if (app.hasCompletedRead && result != null) {
      final stamp = _readStamp(app);
      if (stamp != _lastCardStamp) {
        lastCard = _LiveCardSummary.fromRead(app, readAt: result.timestamp);
        _lastCardStamp = stamp;
      }
    }
    _syncController();
    notifyListeners();
  }

  void _archiveChanged(List<ArchiveRows> rows) {
    final archive = <_LiveArchiveCard>[];
    for (final row in rows) {
      final card = row.card;
      if (card == null) continue;
      try {
        archive.add(_LiveArchiveCard.fromArchive(app, card, row));
      } catch (_) {
        continue;
      }
    }
    _archive = List.unmodifiable(archive);
    _archiveById = Map.unmodifiable({
      for (final item in archive) item.card.id: item,
    });
    _archiveIssue = null;
    // A different archive can change which saved row matches the current read.
    _currentKey = null;
    _syncController();
    notifyListeners();
  }

  /// [publish] forces a controller notification for callers that mutated the
  /// controller directly (dismissing an overlay) without changing live data.
  void _syncController({bool publish = false}) {
    if (_disposed) return;
    final live = _buildCurrent();
    // The data projection (cards, trips, ledgers, raw evidence and face
    // restore) is expensive and only changes with the read, the archive or the
    // overdraft interpretation. Toggling auto-save/logs leaves all of them
    // untouched, so publish just the light scalar flags in that case.
    final dataChanged =
        !identical(live, _current) ||
        !identical(_archive, _syncedArchive) ||
        !identical(navigation.cards, _syncedCards) ||
        _freshCurrent != _syncedFresh;
    _current = live;
    var changed = dataChanged;
    if (dataChanged) {
      final saved = savedCards;
      final currentCard = live?.card ?? _placeholderCard;
      final cards = <GalleryCard>[
        currentCard,
        for (final card in saved)
          if (card.id != currentCard.id) card,
      ];
      navigation.cards = cards;
      unawaited(restoreFaceImages(cards));
      navigation.currentCardId = currentCard.id;
      if (!cards.any((card) => card.id == navigation.selectedCardId)) {
        navigation.selectedCardId = currentCard.id;
      }
      final fresh = _freshCurrent && live != null;
      navigation.trips = fresh ? live.records : const [];
      navigation.hasRead = live != null;
      navigation.liveLedgers = {
        for (final item in _archive) item.card.id: item.records,
        if (live != null) live.card.id: live.records,
      };
      _syncedArchive = _archive;
      _syncedCards = cards;
      _syncedFresh = _freshCurrent;
      if (!sources.contains(navigation.source)) {
        navigation.source = '全部来源';
      }
      if (!modes.contains(navigation.mode)) {
        navigation.mode = '全部方式';
      }
    }
    if (navigation.autoSave != app.autoSaveEnabled) {
      navigation.autoSave = app.autoSaveEnabled;
      changed = true;
    }
    if (navigation.includeOverdraft != app.includeShanghaiOverdraft) {
      navigation.includeOverdraft = app.includeShanghaiOverdraft;
      changed = true;
    }
    if (navigation.logsEnabled != app.loggingEnabled) {
      navigation.logsEnabled = app.loggingEnabled;
      changed = true;
    }
    if (navigation.hapticEnabled != app.hapticEnabled) {
      navigation.hapticEnabled = app.hapticEnabled;
      changed = true;
    }
    if (navigation.monet != app.monetEnabled) {
      navigation.monet = app.monetEnabled;
      changed = true;
    }
    final readState = _error != null || app.nfcReleaseFailed
        ? GalleryReadState.failed
        : busy
        ? GalleryReadState.reading
        : live != null
        ? GalleryReadState.success
        : GalleryReadState.unread;
    if (navigation.readState != readState) {
      navigation.readState = readState;
      changed = true;
    }
    if (!changed && !publish) return;
    navigation.notifyListeners();
  }

  void requestSave() {
    manualSaveRequest++;
    notifyListeners();
  }

  String? get error => app.nfcReleaseFailed ? 'NFC 连接未确认关闭，请重试。' : _error;
  GalleryReadState get state => busy
      ? GalleryReadState.reading
      : error != null
      ? GalleryReadState.failed
      : hasCurrent
      ? GalleryReadState.success
      : GalleryReadState.unread;

  void _navigationChanged() {
    app.recoveryTab = switch (navigation.mainPage) {
      GalleryPage.trips => 1,
      GalleryPage.cards => 2,
      GalleryPage.expert => 3,
      _ => 0,
    };
    app.recoveryRoute = switch (navigation.page) {
      GalleryPage.qr => '/qr',
      GalleryPage.settings => '/settings',
      GalleryPage.detail =>
        '/card/${Uri.encodeComponent(navigation.selectedCardId)}',
      _ => null,
    };
    if (navigation.page != GalleryPage.home && _attempt != null) {
      unawaited(cancel());
    }
  }

  void _restoreRoutes() {
    if (_routesRestored || !app.recoveryReady) return;
    _routesRestored = true;
    if (!app.pendingRecoveryNavigation) return;
    final route = app.pendingRecoveryRoute;
    app.pendingRecoveryNavigation = false;
    app.pendingRecoveryRoute = null;
    navigation.navigate(switch (app.recoveryTab) {
      1 => GalleryPage.trips,
      2 => GalleryPage.cards,
      3 => GalleryPage.expert,
      _ => GalleryPage.home,
    });
    switch (route) {
      case '/qr':
        navigation.navigate(GalleryPage.qr);
      case '/settings':
        navigation.navigate(GalleryPage.settings);
      case final String name when name.startsWith('/card/') && name.length > 6:
        navigation.openCardId(Uri.decodeComponent(name.substring(6)));
    }
  }

  _LiveReadCard? _buildCurrent() {
    final recovery = app.recoveredCapture;
    if (recovery != null) {
      _freshCurrent = true;
      // The overdraft flag changes how the captured records are projected, so
      // it is part of the signature. Archive changes reset [_currentKey].
      return _memoized(
        'recovery:${identityHashCode(recovery)}'
        '|overdraft:${app.includeShanghaiOverdraft}',
        () => _fromRecovery(recovery),
      );
    }
    if (_hasCompletedCurrentRead) {
      _freshCurrent = true;
      final pending = app.pendingCardSave;
      // A pending save can be replaced in place under the same id (verified
      // Octopus evidence rewrites the snapshot), so hash the instance too.
      final pendingKey = pending == null
          ? '-'
          : '${pending.pendingSaveId}@${identityHashCode(pending)}';
      return _memoized(
        'read:${_readStamp(app)}'
        '|overdraft:${app.includeShanghaiOverdraft}'
        '|pending:$pendingKey'
        '|fingerprint:${app.lastCardFingerprint ?? '-'}',
        _fromCompletedRead,
      );
    }
    if (busy || app.nfcReleaseFailed || _error != null) return _current;
    return null;
  }

  /// Projecting the current read decodes the captured snapshot and runs the
  /// trip presenters over every record. The signature in [_buildCurrent] covers
  /// every input that changes the result (read stamp, overdraft interpretation,
  /// pending save, fingerprint) and an archive change resets [_currentKey];
  /// settings toggles reuse [_current] instead of rebuilding it per
  /// notification.
  _LiveReadCard? _memoized(String key, _LiveReadCard? Function() build) {
    if (key == _currentKey && _current != null) return _current;
    final built = build();
    _currentKey = key;
    return built;
  }

  _LiveReadCard? _fromCompletedRead() {
    final result = app.lastResult;
    if (result == null) return _current;
    final summary = lastCard = _LiveCardSummary.fromRead(
      app,
      readAt: result.timestamp,
    );
    _lastCardStamp = _readStamp(app);
    final fingerprint =
        app.lastCardFingerprint ?? app.pendingCardSave?.fingerprint;
    final saved = _archive
        .where(
          (item) =>
              item.card.saved && item.saved.cardFingerprint == fingerprint,
        )
        .firstOrNull;
    final pending = app.pendingCardSave;
    final capture = pending ?? app.completedCardCapture;
    // A skipped save clears the prompt but leaves the new read in memory.
    // Only reuse a saved ledger if it contains this particular read.
    final sameSavedRead =
        saved != null &&
        pending == null &&
        (capture == null ||
            saved.history.batches.any(
              (batch) =>
                  batch.decoded.snapshot?.extensions['captureAttemptId'] ==
                  capture.pendingSaveId,
            ));
    final history = sameSavedRead
        ? saved.history
        : capture?.sessionDataJson != null
        ? _historyFromSnapshot(
            capture!.sessionDataJson!,
            id: capture.pendingSaveId,
            readAt: capture.readAt ?? summary.readAt,
          )
        : _currentApplicationHistory(app.applications, summary.readAt);
    final records = history == null
        ? const <GalleryRecord>[]
        : _galleryRecords(history, app.includeShanghaiOverdraft);
    final card = _liveCard(
      id: sameSavedRead
          ? saved.card.id
          : (fingerprint == null ? 'live-current' : 'live:$fingerprint'),
      saved: sameSavedRead,
      name: sameSavedRead ? saved.card.name : summary.name,
      cardNumber: summary.cardNumber,
      applicationNumbers: _observedApplicationNumbers(app.applications),
      balance: summary.balance ?? '余额未知',
      currencyCode: summary.currencyCode,
      city: summary.city,
      type: summary.type,
      valid: summary.valid,
      readAt: summary.readAt,
      count: records.length,
      applications: summary.applications,
      face: saved?.card.face,
    );
    return _LiveReadCard(
      card: card,
      history: history,
      records: records,
      applications: app.applications,
    );
  }

  _LiveReadCard? _fromRecovery(RecoveryCapture capture) {
    final summary = capture.summary;
    final readAt = capture.readAt;
    final fingerprint = capture.pending?.fingerprint;
    final saved = fingerprint == null
        ? null
        : _archive
              .where((item) => item.saved.cardFingerprint == fingerprint)
              .firstOrNull;
    final capturedHistory = capture.snapshotJson == null
        ? null
        : _historyFromSnapshot(
            capture.snapshotJson!,
            id: capture.pending?.pendingSaveId ?? 'recovery',
            readAt: readAt,
          );
    // Saved trips may supplement the ledger. Read status belongs to this capture.
    final evidence = capture.applications(
      capturedHistory?.latestCapture?.snapshot,
    );
    final history = capture.snapshotJson == null
        ? _currentApplicationHistory(evidence, readAt) ?? saved?.history
        : capturedHistory;
    final records = history == null
        ? const <GalleryRecord>[]
        : _galleryRecords(history, app.includeShanghaiOverdraft);
    final decoded = summary['decoded'];
    final local = decoded is Map ? decoded['localCard'] : null;
    final countWallet =
        decoded is Map &&
        decoded['parserId'] == CardParserIds.localCard &&
        local is Map &&
        local['countWallet'] == true;
    final rawBalance = countWallet
        ? local['remainingTrips'] is int
              ? '剩余 ${local['remainingTrips']} 次'
              : '剩余次数未知'
        : summary['balanceText'] as String?;
    final balanceFen = summary['balanceFen'] as int?;
    final currency = countWallet ? null : summary['currencyCode'] as String?;
    final cardNumber = summary['cardNumber'] as String?;
    final productType = summary['productType'] as String?;
    final applications = switch (productType) {
      'suica' => const ['suica'],
      'amusementIc' => const <String>[],
      _ when summary['idm'] is String => const ['octopus'],
      _ => [
        for (final a in evidence)
          if (a.confirmed) a.appId,
      ],
    };
    final card = _liveCard(
      id: fingerprint == null ? 'live-recovery' : 'live:$fingerprint',
      saved: false,
      name:
          officialCardDisplayName(
            summary['cardType']?.toString() ??
                capture.pending?.identity.cardType ??
                '',
            summary['cardName']?.toString(),
          ) ??
          saved?.card.name ??
          '上次读取的交通卡',
      cardNumber: cardNumber,
      applicationNumbers: _observedApplicationNumbers(evidence),
      balance:
          rawBalance ??
          (balanceFen == null
              ? '余额未知'
              : (currency == 'JPY'
                    ? formatJpyAmount(balanceFen)
                    : '${currency ?? ''} ${(balanceFen / 100).toStringAsFixed(2)}')),
      currencyCode: countWallet ? null : currency ?? saved?.card.currencyCode,
      city: saved?.card.city ?? '未知',
      type: saved?.card.type ?? '交通卡',
      valid: local is Map && local['expiryDate'] is String
          ? _LiveCardSummary._validity(
              DateTime.tryParse(local['expiryDate'] as String),
            )
          : saved?.card.valid ?? '未知',
      readAt: readAt,
      count: records.length,
      applications: applications.isEmpty
          ? saved?.card.applications ?? const []
          : applications,
    );
    lastCard = _LiveCardSummary(
      name: card.name,
      balance: card.rawBalance,
      readAt: readAt,
      cardNumber: cardNumber,
      city: card.city,
      type: card.type,
      currencyCode: currency,
      fingerprint: fingerprint,
      applications: card.applications,
      valid: card.valid,
    );
    return _LiveReadCard(
      card: card,
      history: history,
      records: records,
      applications: evidence,
    );
  }

  @override
  Future<void> save(String name) async {
    if (_closing) return;
    final recovery = app.recoveredCapture;
    bool ok;
    if (recovery != null) {
      await app.saveRecoveredCapture();
      ok = app.recoveryNotice == '这次读取已保存。';
      lastSaveMessage = ok ? '本次读取已保存' : '卡片保存未完成';
    } else {
      final pending = app.pendingCardSave;
      if (pending == null) return;
      var policy = app.archiveConflictPolicy;
      final exists = await app.archiveCardExists(pending.fingerprint);
      if (exists && policy == ArchiveConflictPolicy.ask && !_disposed) {
        final chosen = await conflictResolver?.call();
        if (chosen == null) {
          lastSaveSucceeded = false;
          lastSaveMessage = '已取消保存';
          return;
        }
        policy = chosen;
      }
      if (exists && policy == ArchiveConflictPolicy.skip) {
        app.declinePendingSave(pending.pendingSaveId);
        lastSaveSucceeded = true;
        lastSaveMessage = '已跳过已存在的记录';
        navigation.overlay = null;
        _syncController(publish: true);
        notifyListeners();
        return;
      }
      ok = await app.acceptPendingSave(
        pending.pendingSaveId,
        conflictPolicy: policy,
      );
      if (ok && !exists && name.trim().isNotEmpty) {
        final cards = await app.cardRepository.getAllCards();
        final saved = cards
            .where((card) => card.cardFingerprint == pending.fingerprint)
            .firstOrNull;
        if (saved != null) {
          await app.cardRepository.renameCard(saved.id, name.trim());
        }
      }
      lastSaveMessage = ok ? '已保存到卡包' : '卡片保存失败';
    }
    if (_disposed) return;
    navigation.overlay = null;
    lastSaveSucceeded = ok;
    _syncController(publish: true);
    notifyListeners();
  }

  @override
  Future<void> rename(String name) async {
    final trimmed = name.trim();
    final card = navigation.selectedCard;
    if (trimmed.isEmpty || !card.saved) return;
    await app.cardRepository.renameCard(card.id, trimmed);
    navigation.overlay = null;
    _syncController(publish: true);
    notifyListeners();
  }

  @override
  Future<void> setAutoSave(bool value) async {
    // SettingsController publishes optimistically before awaiting storage, so
    // its notification already syncs the Gallery toggle in this turn;
    // _syncController publishes the flag only when it actually changed.
    final write = app.setAutoSaveEnabled(value);
    navigation.autoSave = value;
    _syncController();
    await write;
  }

  @override
  Future<void> setIncludeOverdraft(bool value) async {
    final write = app.setIncludeShanghaiOverdraft(value);
    navigation.includeOverdraft = value;
    _syncController();
    await write;
  }

  @override
  Future<void> setLogs(bool value) async {
    final write = app.setLoggingEnabled(value);
    navigation.logsEnabled = value;
    _syncController();
    await write;
  }

  @override
  Future<void> setHaptic(bool value) async {
    // Same optimistic scalar pattern as setAutoSave: the settings controller
    // publishes before awaiting storage, so this notification already syncs
    // the Gallery flag; _syncController publishes only when it changed.
    final write = app.setHapticEnabled(value);
    navigation.hapticEnabled = value;
    _syncController();
    await write;
  }

  @override
  Future<void> setMonet(bool value) => app.setMonetEnabled(value);

  Future<bool> openQr() async {
    if (_disposed || openingQr || app.qrAcquiring) return true;
    openingQr = true;
    notifyListeners();
    try {
      if (_closing) {
        await app.stop();
      } else {
        await cancel();
      }
      if (_disposed || navigation.page != GalleryPage.home) return true;
      if (app.nfcReleaseFailed) return false;
      navigation.navigate(GalleryPage.qr);
      return true;
    } finally {
      openingQr = false;
      if (!_disposed) notifyListeners();
    }
  }

  void selectExpertTab(ExpertReadTab tab) {
    expertTab = tab;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    if (_disposed ||
        busy ||
        app.nfcUnavailableMessage != null ||
        _closing ||
        openingQr ||
        app.qrAcquiring ||
        navigation.page != GalleryPage.home) {
      return;
    }
    final attempt = _attempt = Object();
    _attemptStartedWith = _readStamp(app);
    _freshCurrent = false;
    _error = null;
    notifyListeners();
    try {
      await app.scanOnceForGallery();
      if (_disposed || !identical(_attempt, attempt)) return;
      final result = app.lastResult;
      if (app.hasCompletedRead && result != null) {
        lastCard = _LiveCardSummary.fromRead(app, readAt: result.timestamp);
      } else if (app.scan.failedForNfcAdapter) {
        _error = _adapterInterruption;
      } else if (app.error != null) {
        _error = '读取未完成，请重新贴卡。';
      } else if (app.scan.phase != ScanPhase.cancelled) {
        _error = '未获取到卡片，请重新贴卡。';
      }
    } finally {
      if (!_disposed && identical(_attempt, attempt)) {
        _attempt = null;
        _syncController();
        notifyListeners();
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed || _closing) return;
    _attempt = null;
    _closing = true;
    try {
      await app.stop();
    } finally {
      _closing = false;
      if (!_disposed) {
        _syncController();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_archiveSubscription?.cancel());
    app.removeListener(_appChanged);
    navigation.removeListener(_navigationChanged);
    super.dispose();
  }
}

String? _readStamp(AppDependencies app) {
  final result = app.lastResult;
  if (result == null) return null;
  return '${result.sessionId}|${result.uid}|${result.timestamp.microsecondsSinceEpoch}';
}

class _LiveCardSummary {
  const _LiveCardSummary({
    required this.name,
    required this.balance,
    required this.readAt,
    this.cardNumber,
    this.city = '未知',
    this.type = '交通卡',
    this.currencyCode,
    this.fingerprint,
    this.applications = const [],
    this.valid = '未知',
  });

  factory _LiveCardSummary.fromRead(
    AppDependencies app, {
    required DateTime readAt,
  }) {
    final parsed = app.parsedCard;
    final felica = app.felicaResult;
    final name = felica != null && parsed == null
        ? felica.displayName
        : transitDisplayName(
            parserId: parsed?.parserId,
            identifiedName: app.lastIdentified?.displayName,
            localName: parsed?.localCard?.info.cardKindLabel,
          );
    final String? balance;
    final String? currencyCode;
    if (app.isOctopusCard) {
      final verified = app.currentOctopusResult?.balanceMinor;
      balance = verified == null
          ? '港币余额未读取'
          : GalleryCurrency.hkd.format(verified);
      currencyCode = 'HKD';
    } else if (felica != null && parsed == null) {
      balance = felica.cardProductType == FelicaCardType.amusementIc
          ? null
          : felica.wallets.length == 1
          ? felica.wallets.single.balanceText ?? '余额未知'
          : null;
      currencyCode = felica.wallets.length == 1
          ? felica.wallets.single.currency
          : null;
    } else if (parsed != null) {
      final parserId = parsed.parserId;
      final local = parsed.localCard?.info;
      if (parserId == CardParserIds.tunionCash ||
          parserId == CardParserIds.motBmac) {
        balance = null;
        currencyCode = null;
      } else if (local?.isCika == true && parserId == CardParserIds.localCard) {
        balance = local!.observedRemainingTrips == null
            ? '剩余次数未知'
            : '剩余 ${local.observedRemainingTrips} 次';
        currencyCode = null;
      } else if (CardParserIds.isTUnionFamily(parserId) ||
          parserId == CardParserIds.cityUnion) {
        final observedBalance =
            GalleryBalancePresentation.observedCardBalanceMinor(parsed);
        final direct =
            parserId == CardParserIds.cityUnion ||
            BalanceInterpretation.fromParsedCard(parsed).semantics ==
                BalanceSemantics.direct;
        balance = direct
            ? app.balanceDisplay.formatBalance(
                    observedBalance,
                    symbol: app.cardCurrency.symbol,
                  ) ??
                  '余额未知'
            : '账户余额未知';
        currencyCode = direct ? app.cardCurrency.code : null;
      } else if (GalleryBalancePresentation.observedCardBalanceMinor(parsed)
          case final observedBalance?) {
        balance = local?.isMacauPass == true
            ? 'MOP \$${local!.balance}'
            : '${app.cardCurrency.symbol}'
                  '${(observedBalance / 100).toStringAsFixed(2)}';
        currencyCode = local?.currencyCode ?? app.cardCurrency.code;
      } else {
        balance = '余额未知';
        currencyCode = local?.currencyCode;
      }
    } else {
      balance = null;
      currencyCode = null;
    }
    final identified = app.lastIdentified;
    final city =
        identified?.identity.cityName ??
        (app.cityUnionDetected
            ? app.cuCityNameOf(app.cardCityCode)
            : app.cityNameOf(app.cardCityCode)) ??
        (parsed?.localCard?.info.isMacauPass == true ? '澳门' : '未知');
    final cardType = identified?.identity.cardType;
    final type = cardType == null
        ? felica?.displayName ?? transitTypeLabel(parsed?.parserId)
        : cardTypeLabel(cardType);
    final confirmedApplications = {
      for (final application in app.applications)
        if (application.confirmed) application.appId,
    };
    final applications = <String>[
      if (felica?.cardProductType == FelicaCardType.suica) 'suica',
      if (app.isOctopusCard && felica?.cardProductType != FelicaCardType.suica)
        'octopus',
      if ((parsed != null && CardParserIds.isTUnionFamily(parsed.parserId)) ||
          confirmedApplications.contains('tu'))
        'tu',
      if (confirmedApplications.contains('cu') ||
          parsed?.dualApplication == true ||
          parsed?.parserId == CardParserIds.cityUnion)
        'cu',
      ..._regionalApplications(
        parsed,
        confirmedApplications: confirmedApplications,
      ),
    ];
    return _LiveCardSummary(
      name: name,
      balance: balance,
      readAt: readAt,
      cardNumber:
          identified?.cardNumber ?? parsed?.localCard?.info.displayCardNumber,
      city: city,
      type: type,
      currencyCode: currencyCode,
      fingerprint: app.lastCardFingerprint ?? app.pendingCardSave?.fingerprint,
      applications: applications,
      valid: _validity(
        parsed?.info.expireDate ?? parsed?.localCard?.info.expiryDate,
      ),
    );
  }

  final String name;
  final String? balance;
  final DateTime readAt;
  final String? cardNumber;
  final String city;
  final String type;
  final String? currencyCode;
  final String? fingerprint;
  final List<String> applications;
  final String valid;

  static String _validity(DateTime? date) {
    if (date == null) return '未知';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}

class _LiveReadCard {
  const _LiveReadCard({
    required this.card,
    required this.history,
    required this.records,
    required this.applications,
  });

  final GalleryCard card;
  final ArchiveHistoryResult? history;
  final List<GalleryRecord> records;
  final List<ApplicationEvidence> applications;
}

class _LiveArchiveCard {
  const _LiveArchiveCard({
    required this.saved,
    required this.history,
    required this.card,
    required this.records,
  });

  factory _LiveArchiveCard.fromArchive(
    AppDependencies app,
    SavedCard saved,
    ArchiveRows row,
  ) {
    final history = ArchiveHistory.project(row);
    final records = _galleryRecords(history, app.includeShanghaiOverdraft);
    final count = ArchiveRecordCount.fromHistory(history);
    final confirmedApplications = _archivedConfirmedApplications(history);
    final applicationNumbers = _observedApplicationNumbers([
      ..._snapshotApplications(history.latestCapture),
      for (final batch in history.batches)
        ..._snapshotApplications(batch.decoded),
    ]);
    final card = _liveCard(
      id: saved.id,
      saved: true,
      name: saved.displayName,
      cardNumber: saved.cardNumber,
      applicationNumbers: applicationNumbers,
      balance:
          archiveCardBalanceText(
            saved,
            includeShanghaiOverdraft: app.includeShanghaiOverdraft,
            balanceSnapshot: history.balanceSource?.snapshot,
            capturedText: history.balanceText,
          ) ??
          '余额未知',
      currencyCode:
          saved.currencyCode ??
          history.latestCapture?.snapshot?.context.currencyCode,
      city: saved.cityName ?? '未知',
      type: cardTypeLabel(saved.cardType),
      valid: '未知',
      readAt: saved.lastReadAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(saved.lastReadAt!),
      count: count.savedRecordCount ?? records.length,
      applications: {
        if (confirmedApplications == null)
          ..._applicationsForCardType(
            saved.cardType,
            officialName: saved.officialName,
          )
        else
          for (final brand in const ['tu', 'cu', 'lingnan', 'shenzhen'])
            if (confirmedApplications.contains(brand)) brand,
        if (saved.cardType == CardTypes.octopusTunion) 'octopus',
      }.toList(),
    );
    return _LiveArchiveCard(
      saved: saved,
      history: history,
      card: card,
      records: records,
    );
  }

  final SavedCard saved;
  final ArchiveHistoryResult history;
  final GalleryCard card;
  final List<GalleryRecord> records;

  Object? get _manualNumberJson => history.cardExtensions['suicaManualNumber'];

  SuicaManualNumber? get suicaManualNumber =>
      SuicaManualNumber.fromJson(_manualNumberJson);

  String? get suicaManualNumberEditIssue {
    if (history.cardExtensions.containsKey('suicaManualNumber') &&
        !SuicaManualNumber.isSupportedJson(_manualNumberJson)) {
      return '卡面编号格式暂不支持，原始资料已保留。';
    }
    final fingerprintIdentity = SuicaArchiveIdentity.resolve(
      cardType: saved.cardType,
      fingerprint: saved.cardFingerprint,
    );
    if (history.documentReadIssue != null ||
        fingerprintIdentity.idm == null ||
        SuicaArchiveIdentity.resolve(
          cardType: saved.cardType,
          fingerprint: saved.cardFingerprint,
          snapshots: history.batches
              .map((batch) => batch.decoded.snapshot)
              .nonNulls,
        ).hasConflict) {
      return '无法确认档案身份，暂不能编辑卡面编号。';
    }
    return null;
  }
}

GalleryCard _liveCard({
  required String id,
  required bool saved,
  required String name,
  required String? cardNumber,
  Map<String, String> applicationNumbers = const {},
  required String balance,
  required String? currencyCode,
  required String city,
  required String type,
  required String valid,
  required DateTime? readAt,
  required int count,
  required List<String> applications,
  String? face,
}) => GalleryCard.live(
  id: id,
  saved: saved,
  name: name,
  tail: _tail(cardNumber),
  pan: cardNumber ?? '未提供',
  applicationNumbers: applicationNumbers,
  rawBalance: balance,
  city: city.isEmpty ? '未知' : city,
  type: type,
  valid: valid,
  when: _readTime(readAt),
  count: count <= 0 ? '0 条' : '$count 条',
  face: face ?? _faceFor(type, applications),
  applications: applications,
  currencyCode: currencyCode,
);

String _tail(String? number) {
  final digits = number?.replaceAll(RegExp(r'[^0-9A-Za-z]'), '') ?? '';
  if (digits.length <= 4) return digits.isEmpty ? '——' : digits;
  return digits.substring(digits.length - 4);
}

String _readTime(DateTime? date) {
  if (date == null) return '日期未记录';
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _faceFor(String type, List<String> applications) {
  if (applications.contains('suica')) return 'teal';
  if (applications.contains('octopus')) return 'amber';
  if (applications.contains('cu') && applications.contains('tu')) return 'blue';
  if (applications.contains('cu')) return 'graphite';
  if (type.contains('一卡通')) return 'graphite';
  return 'blue';
}

List<String> _regionalApplications(
  ParsedCard? parsed, {
  Set<String> confirmedApplications = const {},
}) {
  final local = parsed?.localCard?.info;
  return [
    if (parsed?.parserId == CardParserIds.lingnanTong ||
        parsed?.parserId == CardParserIds.lingnanTunion ||
        local?.isLNT == true ||
        confirmedApplications.contains('lingnan'))
      'lingnan',
    if (parsed?.parserId == CardParserIds.shenzhenTunion ||
        local?.isSZT == true ||
        confirmedApplications.contains('shenzhen'))
      'shenzhen',
  ];
}

Iterable<ApplicationEvidence> _snapshotApplications(
  SnapshotDecodeResult? capture,
) sync* {
  final raw = capture?.snapshot?.extensions['applicationEvidence'];
  if (raw is! List) return;
  for (final item in raw) {
    if (ApplicationEvidence.tryParse(item) case final application?)
      yield application;
  }
}

Map<String, String> _observedApplicationNumbers(
  Iterable<ApplicationEvidence> evidence,
) {
  final byApp = <String, ApplicationEvidence>{};
  for (final app in evidence) {
    final number = app.cardNumber?.trim();
    if (number == null || number.isEmpty || number == '未知' || number == '未提供')
      continue;
    byApp.putIfAbsent(app.appId, () => app);
  }
  return Map.unmodifiable({
    if (byApp['tu'] case final app?) 'TU': app.cardNumber!.trim(),
    if (byApp['cu'] case final app?) 'CU': app.cardNumber!.trim(),
    for (final app in byApp.values)
      if (app.appId != 'tu' && app.appId != 'cu')
        app.displayName: app.cardNumber!.trim(),
  });
}

Set<String>? _archivedConfirmedApplications(ArchiveHistoryResult history) {
  final raw =
      history.latestCapture?.snapshot?.extensions['applicationEvidence'];
  if (raw is! List || raw.isEmpty) return null;
  return {
    for (final item in raw)
      if (ApplicationEvidence.tryParse(item) case final application?
          when application.confirmed)
        application.appId,
  };
}

List<String> _applicationsForCardType(
  String cardType, {
  String? officialName,
}) => switch (cardType) {
  CardTypes.suica => const ['suica'],
  CardTypes.octopusTunion => const ['octopus'],
  CardTypes.amusementIc => const [],
  CardTypes.cityUnion => const ['cu'],
  CardTypes.shanghaiTransitUnion ||
  CardTypes.harbinTransitUnion => const ['tu', 'cu'],
  CardTypes.lingnanTong => const ['lingnan'],
  CardTypes.lingnanTunion => const ['tu', 'lingnan'],
  CardTypes.shenzhenTunion => const ['tu', 'shenzhen'],
  CardTypes.chinaTunion => const ['tu'],
  CardTypes.localCard when officialName?.contains('深圳通') == true => const [
    'shenzhen',
  ],
  CardTypes.localCard when officialName?.contains('岭南通') == true => const [
    'lingnan',
  ],
  _ => const [],
};

ArchiveHistoryResult? _currentApplicationHistory(
  List<ApplicationEvidence> applications,
  DateTime readAt,
) {
  if (!applications.any((a) => a.payload != null && a.recordCount > 0)) {
    return null;
  }
  final snapshot = CardSessionSnapshot(
    extensions: {
      'applicationEvidence': [
        for (final application in applications) application.toJson(),
      ],
    },
  );
  return _historyFromSnapshot(snapshot.encode(), id: 'current', readAt: readAt);
}

ArchiveHistoryResult? _historyFromSnapshot(
  String json, {
  required String id,
  required DateTime readAt,
}) {
  final decoded = CardSessionSnapshot.decodeResult(json);
  final snapshot = decoded.snapshot;
  if (snapshot == null) return null;
  final batch = ArchiveBatchEvidence(
    id: id,
    readAt: readAt.millisecondsSinceEpoch,
    storedParseVersion: snapshot.parseVersion,
    origin: 'live_gallery',
    timeSource: 'captured',
    decoded: decoded,
    issues: decoded.issues,
  );
  return ArchiveHistoryResult(
    card: null,
    batches: [batch],
    records: ArchiveHistory.projectRecords([batch]),
    localCardRecords: ArchiveHistory.projectLocalCardRecords([batch]),
    latestCapture: decoded,
  );
}

List<GalleryRecord> _galleryRecords(
  ArchiveHistoryResult history,
  bool includeOverdraft,
) {
  final records = <GalleryRecord>[];
  final cardType = history.card?.cardType;
  final tu = presentArchiveTrips(
    history.records,
    batches: history.batches,
    includeShanghaiOverdraft: includeOverdraft,
    cardType: cardType,
  );
  for (final journey in tu.journeys) {
    final first = journey.events.first.payload;
    final infos = [for (final event in journey.events) event.payload.info];
    records.add(
      _recordFromPresentation(
        first,
        infos: infos,
        journey: journey,
        railCitySystem: 'tu',
      ),
    );
  }
  final suica = projectSuicaArchive(history);
  final suicaRecords = <GalleryRecord>[];
  for (final record in suica.records) {
    suicaRecords.add(
      _recordFromPresentation(
        record.presentation.entry,
        infos: [
          for (final event in record.presentation.journey.events)
            event.payload.info,
        ],
        journey: record.presentation.journey,
      ),
    );
  }
  final cu = projectCuArchive(history);
  final independent = partitionShanghaiArchiveMirroredRecords(
    history: history,
    cityUnion: cu,
  ).independent;
  final cuEntries = describeCuTrips(independent);
  final cuJourneys = projectJourneys(
    cuEntries.map((entry) => entry.journeyEvent!.withPayload(entry)),
  );
  for (final journey in cuJourneys) {
    final entry = journey.events.first.payload;
    records.add(
      _recordFromPresentation(
        entry,
        infos: [for (final event in journey.events) event.payload.info],
        journey: journey.state == JourneyState.completed ? journey : null,
        event: entry.journeyEvent,
        railCitySystem: 'cu',
      ),
    );
  }
  for (final local in history.localCardRecords) {
    final profile = localTripProfileOf(local.fields, cardType: local.cardType);
    final trip = restoreLocalTripRecord(local.fields, profile: profile);
    if (trip == null) continue;
    final entry = describeLocalTrip(
      trip,
      currencySymbol: '¥',
      profile: profile,
    );
    records.add(
      _recordFromPresentation(
        entry,
        infos: [entry.info],
        event: entry.journeyEvent,
      ),
    );
  }
  final clockTime = RegExp(r'\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?');
  String sortKey(GalleryRecord record) {
    final time = clockTime.stringMatch(record['time'] as String? ?? '');
    return '${record['isoDate'] ?? ''} ${time ?? ''}';
  }

  // Equal or absent clocks keep the existing order from the card history.
  mergeSort(records, compare: (a, b) => sortKey(b).compareTo(sortKey(a)));
  if (suicaRecords.isNotEmpty) {
    // 090F blocks are newest first even when only some have a minute clock.
    // Across wallets the civil day is their shared ordering precision.
    records.addAll(suicaRecords);
    mergeSort(
      records,
      compare: (a, b) {
        final first = a['isoDate'] as String? ?? '';
        final second = b['isoDate'] as String? ?? '';
        return second.compareTo(first);
      },
    );
  }
  return List.unmodifiable(records);
}

GalleryRecord _recordFromPresentation<T extends Enum>(
  TripCardPresentation<T> entry, {
  required List<TripEntryInfo> infos,
  JourneyPresentation<TripCardPresentation<T>>? journey,
  JourneyEvent<TripEntryInfo>? event,
  String? railCitySystem,
}) {
  final info = entry.info;
  final events = journey?.events ?? const [];
  final start =
      journey?.start ?? (event == null ? null : _singleEndpoint(event));
  final end = journey?.end;
  // A standalone observation may identify the stop without establishing a direction.
  final observed = start == null && end == null
      ? events.firstOrNull?.endpoint
      : null;
  final sourceLabels = <String>{
    info.sourceLabel,
    for (final item in events) item.payload.info.sourceLabel,
    for (final item in infos) item.sourceLabel,
  };
  // A standalone operation has an event clock even without ride endpoints.
  final clock = _clockFor(
    start: start ?? observed,
    end: end,
    info: info,
    dateText: entry.dateText,
  );
  final kind = info.isRecharge
      ? 'recharge'
      : switch (entry.mode) {
          TripModeFilter.rail => 'rail',
          TripModeFilter.bus => 'bus',
          TripModeFilter.other => 'other',
        };
  final ride = kind == 'rail' || kind == 'bus';
  final completed = journey?.state == JourneyState.completed;
  final line = start?.line ?? observed?.line ?? info.line ?? end?.line;
  final title = switch (kind) {
    'recharge' => '充值',
    'rail' when line != null && line.trim().isNotEmpty => '地铁 ${line.trim()}',
    'bus' when line != null && line.trim().isNotEmpty => '公交 ${line.trim()}',
    'rail' when completed => '地铁',
    _ => info.title,
  };
  final entryStation = start?.station;
  final exitStation = end?.station;
  final sub = completed || (entryStation != null && exitStation != null)
      ? '${entryStation ?? '站点未记录'} → ${exitStation ?? '站点未记录'}'
      : observed?.station ??
            entryStation ??
            exitStation ??
            info.subText ??
            title;
  final amount = journey?.amountText ?? info.amountText ?? '—';
  final balanceAfter = journey?.balanceAfterText ?? event?.balanceAfterText;
  final city =
      journey?.cityLabel ??
      info.remoteCityText ??
      events
          .map((item) => item.payload.journeyEvent?.cityLabel)
          .nonNulls
          .firstOrNull ??
      '';
  final oneWay = start == null || end == null;
  final firstEndpoint = start ?? end ?? observed;
  Map<String, String>? lineCity(JourneyEndpoint? endpoint) {
    if (railCitySystem == null || endpoint?.line == null) return null;
    final evidence = journey == null
        ? event
        : events
              .where((side) => identical(side.endpoint, endpoint))
              .firstOrNull;
    final code = evidence?.displayCityCode;
    final name = evidence?.displayCityLabel;
    if (code == null && name == null) return null;
    return {'system': railCitySystem, 'code': ?code, 'name': ?name};
  }

  final terminals = <_GalleryTripTerminal>{
    if (events.isEmpty)
      ?_capturedTripTerminal(info, event?.role, entry.mode)
    else
      for (final item in events)
        ?_capturedTripTerminal(item.payload.info, item.role, item.mode),
  };

  return <String, dynamic>{
    'kind': kind,
    'date': clock.date,
    'isoDate': ?clock.isoDate,
    'time': clock.exitTime ?? clock.entryTime ?? info.timeText ?? '未记录',
    if (ride) ...{
      'entryTime': ?clock.entryTime,
      'exitTime': ?clock.exitTime,
      'entryStation': ?entryStation,
      'exitStation': ?exitStation,
      if (completed || (kind == 'rail' ? firstEndpoint : start)?.line != null)
        'entryLine': (kind == 'rail' ? firstEndpoint : start)?.line ?? '',
      if (completed || end?.line != null) 'exitLine': end?.line ?? '',
      if (kind == 'rail') ...{
        'entryLineCity': lineCity(firstEndpoint),
        'exitLineCity': lineCity(end),
      },
      'oneWay': oneWay,
      'transferKnown': true,
    },
    'title': title,
    'sub': sub,
    'amount': amount,
    'balanceAfter': ?balanceAfter,
    'source': sourceLabels.first,
    'sources': sourceLabels.toList(growable: false),
    'mode': switch (kind) {
      'rail' => '城市轨道交通',
      'bus' => '公共汽电车',
      'recharge' => '充值',
      _ => '其他',
    },
    if (city.isNotEmpty) 'city': city,
    'foreign': info.remoteCityText != null,
    'rawHex': info.rawHex,
    if (terminals.isNotEmpty)
      'terminalNumbers': List<_GalleryTripTerminal>.unmodifiable(terminals),
    'infoFields': [
      for (final field in info.fields) [field.$1, field.$2],
    ],
    'events': [
      for (final item in infos)
        {
          'title': item.title,
          'source': item.sourceLabel,
          'time': item.timeText,
          'amount': item.amountText,
          'fields': [
            for (final field in item.fields) [field.$1, field.$2],
          ],
        },
    ],
  };
}

typedef _GalleryTripTerminal = (
  String source,
  String? operation,
  String number,
);

_GalleryTripTerminal? _capturedTripTerminal(
  TripEntryInfo info,
  JourneyEventRole? role,
  TripModeFilter mode,
) {
  final sideField = switch (role) {
    JourneyEventRole.entry => '进入终端',
    JourneyEventRole.exit => '离开终端',
    _ => null,
  };
  for (final (label, value) in info.fields) {
    // TU 0x18/0x1E name the terminal directly, while 0x1A carries both
    // sides in each payload. CU and local wallets already expose the raw field.
    if (label != '终端编号' &&
        label != '终端原始编码' &&
        label != '终端 HEX' &&
        label != sideField) {
      continue;
    }
    final checked = value.trim();
    if (checked.isEmpty ||
        const {'未知', '未记录', '—'}.contains(checked) ||
        RegExp(r'^(?:0+|[Ff]+)$').hasMatch(checked)) {
      continue;
    }
    final operation = switch (role) {
      JourneyEventRole.entry => mode == TripModeFilter.bus ? '上车' : '进站',
      JourneyEventRole.exit => mode == TripModeFilter.bus ? '下车' : '出站',
      JourneyEventRole.fareAdjustment => '补票',
      _ => null,
    };
    return (info.sourceLabel, operation, value);
  }
  return null;
}

JourneyEndpoint _singleEndpoint(JourneyEvent<TripEntryInfo> event) =>
    JourneyEndpoint(
      line: event.endpoint.line,
      station:
          event.endpoint.station ??
          event.payload.fields
              .where((field) => field.$1 == '地点')
              .map((field) => field.$2)
              .firstOrNull,
      time: event.endpoint.time,
      timeText: event.endpoint.timeText ?? event.payload.timeText,
      locationCityCode: event.endpoint.locationCityCode,
      locationCityLabel: event.endpoint.locationCityLabel,
    );

({String date, String? isoDate, String? entryTime, String? exitTime})
_clockFor({
  required JourneyEndpoint? start,
  required JourneyEndpoint? end,
  required TripEntryInfo info,
  required String dateText,
}) {
  final source = end ?? start;
  final text = source?.timeText ?? info.timeText;
  DateTime? date = source?.time;
  if (date == null && text != null) {
    for (final pattern in [
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})'),
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})'),
      RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日'),
    ]) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      date = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        match.groupCount >= 5 ? int.parse(match.group(4)!) : 0,
        match.groupCount >= 5 ? int.parse(match.group(5)!) : 0,
      );
      break;
    }
  }
  final parsedClock = date != null && text != null && _looksTime(text)
      ? _hhmm(date)
      : null;
  // The presentation can retain a civil date after a card clock fails validation.
  date ??= galleryRecordedDate({'isoDate': dateText});
  final entryText =
      start?.timeText ?? (start?.time == null ? null : _hhmm(start!.time!));
  final exitText =
      end?.timeText ?? (end?.time == null ? null : _hhmm(end!.time!));
  return (
    date: date == null ? '日期未记录' : _dateLabel(date),
    isoDate: date == null
        ? null
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    entryTime: entryText ?? (text != null && _looksTime(text) ? text : null),
    exitTime: exitText ?? (end == null ? null : parsedClock),
  );
}

bool _looksTime(String text) => RegExp(r'\d{2}:\d{2}').hasMatch(text);

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final delta = today.difference(day).inDays;
  if (delta == 0) return '今天';
  if (delta == 1) return '昨天';
  if (date.year == now.year) return '${date.month}月${date.day}日';
  return '${date.year}年${date.month}月${date.day}日';
}

String _hhmm(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

extension _GalleryLivePages on _GalleryViewState {
  Widget _liveReadHint(_GalleryLiveRead live, String subtitle, IconData icon) =>
      _empty(
        live.busy ? '正在读取卡片' : '暂无本次读取结果',
        subtitle,
        icon: icon,
        action: _button(
          '前往首页',
          () => c.navigate(GalleryPage.home),
          primary: true,
        ),
      );

  Widget _liveExpert(_GalleryLiveRead live) {
    if (!live.hasFreshCurrent) {
      return _list([
        _liveReadHint(live, '读取卡片后展示解析字段与原始数据', Icons.science_outlined),
      ]);
    }
    final sections = ExpertReadSections(live.app);
    final tabs = sections.tabs;
    final tab = tabs.contains(live.expertTab) ? live.expertTab : tabs.first;
    return _list([
      _tabs(
        [for (final item in tabs) item.label],
        tabs.indexOf(tab),
        (index) => live.selectExpertTab(tabs[index]),
        scroll: true,
        id: 'expert-live-tabs',
      ),
      _gap(16),
      _fade(
        tab,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (tab) {
            ExpertReadTab.information || ExpertReadTab.transit => [
              for (final section in _liveExpertSections(live.app, tab))
                _expand(
                  'live-expert:${tab.name}:${section['title']}',
                  section['title'] as String,
                  _liveExpertSectionChildren(section),
                  initiallyOpen: section['open'] == true,
                  collapsible: section['fixedOpen'] != true,
                ),
              if (tab == ExpertReadTab.information) ...[
                ApplicationEvidencePanel(
                  applications: live.currentApplications,
                ),
                ..._felicaSystemPanels(live.currentFelicaSystems),
              ],
              _gap(),
              _text(
                '以上为本次读取保存在内存中的字段，未捕获内容保持未知。',
                role: GalleryTypography.caption,
                color: t.muted,
              ),
            ],
            ExpertReadTab.compliance => [
              _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in _liveComplianceRows(live.app))
                      _kv(row.$1, row.$2),
                  ],
                ),
              ),
              _gap(),
              _text(
                '此处仅汇总本次已读取文件；未读取项不推断为通过。',
                role: GalleryTypography.caption,
                color: t.muted,
              ),
            ],
            ExpertReadTab.raw => _liveRawSections(live.app),
          },
        ),
      ),
    ], positionId: tab.storageKey);
  }

  List<Widget> _liveExpertSectionChildren(GalleryRecord section) {
    final children = <Widget>[];
    if (section['groups'] case final List groups) {
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index] as Map;
        children.add(
          _liveExpertGroupHeader(group['title'] as String, first: index == 0),
        );
        for (final row in (group['rows'] as List).cast<List>()) {
          children.add(_kv(row[0] as String, row[1] as String));
        }
      }
    }
    if (section['rows'] case final List rows) {
      for (final row in rows.cast<List>()) {
        children.add(_kv(row[0] as String, row[1] as String));
      }
    }
    return children;
  }

  Widget _liveExpertGroupHeader(String title, {required bool first}) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : 18, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text(title, role: GalleryTypography.label, weight: FontWeight.w600),
        _gap(6),
        Divider(height: 1, color: t.line),
      ],
    ),
  );

  List<GalleryRecord> _liveExpertSections(
    AppDependencies app,
    ExpertReadTab tab,
  ) {
    final parsed = app.parsedCard;
    final felica = app.felicaResult;
    final local = app.localReadResult;
    final identified = app.lastIdentified;
    if (tab == ExpertReadTab.information) {
      return [
        {
          'title': '卡片识别',
          'open': true,
          'rows': <List<String>>[
            ['卡片名称', c.current.name],
            ['解析器', parsed?.parserName ?? felica?.displayName ?? '未知'],
            ['选中 AID', parsed?.selectedAidHex ?? '未提供'],
            ['识别状态', identified?.identity.identificationSource ?? '未提供'],
            if (c.current.applicationNumbers.isEmpty)
              ['卡号', identified?.cardNumber ?? c.current.pan]
            else
              for (final entry in c.current.applicationNumbers.entries)
                ['${entry.key} 卡号', entry.value],
            ['识别城市', identified?.identity.cityName ?? c.current.city],
            ['卡种', identified?.identity.cardType ?? c.current.type],
            if (local?.info.isCika != true) ['货币', app.cardCurrency.code],
            ['读取时间', c.current.when],
          ],
        },
        if (app.lastResult != null)
          {
            'title': '机构信息',
            'open': true,
            'rows': <List<String>>[
              ['芯片提供机构', app.cardProviders?.chip.displayText ?? '未提供'],
              ['IC卡提供机构', app.cardProviders?.icCard.displayText ?? '未提供'],
            ],
          },
        if (felica != null)
          {
            'title': 'FeliCa',
            'open': true,
            'rows': <List<String>>[
              ['产品', felica.displayName],
              ['IDm', felica.idm ?? '未知'],
              ['系统码', felica.systemCodeText],
              ['识别状态', felica.stateText],
              if (felica.transitCapability case final capability?)
                ['交通功能', capability],
            ],
          },
        if (local != null && app.applications.isEmpty)
          {
            'title': '本地卡应用',
            'open': true,
            'rows': <List<String>>[
              ['卡型', local.info.cardKindLabel],
              [
                '卡号',
                local.info.cardNumber.isEmpty ? '未知' : local.info.cardNumber,
              ],
              [
                '钱包余额',
                local.info.observedBalance == null
                    ? '未知'
                    : '${local.info.observedBalance}',
              ],
              ['交易记录', '${local.trips.length} 条'],
            ],
          },
      ];
    }
    return _liveTransitSections(app);
  }

  List<Widget> _felicaSystemPanels(Object? systems) => [
    if (systems is Map)
      for (final entry in systems.entries)
        if (entry.value case final Map fields)
          _expand(
            'felica-system-${entry.key}',
            'FeliCa ${entry.key} · ${fields['displayName'] ?? '未知系统'}',
            [
              _kv('IDm', fields['idm']?.toString() ?? '未知'),
              _kv('识别状态', fields['stateText']?.toString() ?? '未知'),
              if (fields['wallets'] case final List wallets)
                for (final wallet in wallets.whereType<Map>())
                  _kv(
                    [
                      wallet['name'] ?? '钱包',
                      if (wallet['currency'] case final String code
                          when code.isNotEmpty)
                        code,
                    ].join(' · '),
                    (wallet['balanceText'] ??
                            wallet['errorMessage'] ??
                            wallet['note'] ??
                            '余额未知')
                        .toString(),
                  ),
            ],
          ),
  ];

  List<GalleryRecord> _liveTransitSections(AppDependencies app) {
    final parsed = app.parsedCard;
    final info = parsed?.info;
    final analysis = app.analysis;
    final wallet = analysis?.wallet;
    final trips = analysis?.trips ?? const <TransitTrip>[];
    final process = app.transitProcessRecords;
    final values = ExpertValues(
      currency: app.cardCurrency,
      balanceDisplay: app.balanceDisplay,
      cityNameOf: app.cityNameOf,
    );
    final balance = parsed == null
        ? null
        : BalanceInterpretation.fromParsedCard(parsed);
    final isCountWallet =
        parsed?.parserId == CardParserIds.localCard &&
        app.localReadResult?.info.isCika == true;
    final sections = <GalleryRecord>[
      {
        'title': '交通应用信息',
        'open': true,
        'fixedOpen': true,
        'rows': <List<String>>[
          [
            isCountWallet ? '剩余次数' : '余额',
            c.current.unknownBalance
                ? '未知'
                : c.current.balance(c.includeOverdraft),
          ],
          if (!isCountWallet) ['币种', app.cardCurrency.code],
          if (!isCountWallet)
            [
              '余额语义',
              app.balanceDisplay.isCityUnionBalance ? '城市一卡通钱包' : '读取结果',
            ],
          ['卡种', info?.cardKind ?? '未知'],
          ['发卡机构', info?.issuerId ?? '未知'],
          ['剩余有效天数', daysRemainingText(wallet?.daysRemaining)],
          if (balance != null &&
              parsed != null &&
              balance.semantics != BalanceSemantics.direct &&
              !app.balanceDisplay.isCityUnionBalance &&
              balance.observedBalanceText != null)
            [balance.observationLabel, balance.observedBalanceText!],
          if (CardParserIds.isTUnionFamily(parsed?.parserId)) ...[
            ['逻辑卡号', expertValue(info?.displayCardNumber)],
            ['应用类型标识', expertValue(info?.appTypeId)],
            ['应用版本', expertValue(info?.appVersion)],
            ['生效日期', expertDate(info?.effectiveDate)],
            ['失效日期', expertDate(info?.expireDate)],
            ['发卡机构 FCI', expertValue(info?.issuerFci)],
            ['国际代码', expertValue(info?.countryCode)],
            ['省级代码', expertValue(info?.provinceCode)],
            ['城市代码', expertValue(info?.cityCode)],
            ['互通卡种', expertValue(info?.interopCardType)],
            ['卡种类型', expertValue(info?.cardKind)],
          ],
        ],
      },
    ];
    if (CardParserIds.isTUnionFamily(parsed?.parserId)) {
      sections.addAll(_liveProcessSections(app, process, values));
      if (trips.isNotEmpty) {
        sections.add(_liveTransactionsSection(trips));
      }
    }
    if (app.cityUnionFiles.isNotEmpty) {
      sections.addAll(_liveCityUnionSections(app, parsed?.cityUnionBalanceFen));
    }
    return sections;
  }

  GalleryRecord _liveTransactionsSection(List<TransitTrip> trips) => {
    'title': '交易明细',
    'open': false,
    'groups': <GalleryRecord>[
      for (var index = 0; index < trips.length; index++)
        {
          'title': '交易 ${index + 1} · ${expertTime(trips[index].time)}',
          'rows': _liveTransactionRows(trips[index]),
        },
    ],
  };

  List<List<String>> _liveTransactionRows(TransitTrip trip) => [
    ['时间', expertTime(trip.time)],
    ['交易金额', trip.amountText],
    ['交易类型', trip.typeName],
    ['交易序号', '${trip.sequence}'],
    ['终端编号', trip.terminalId],
    ['终端解码', terminalDecodeText(trip)],
    if (trip.rawHex case final raw? when raw.isNotEmpty) ['原始数据', raw],
  ];

  List<GalleryRecord> _liveProcessSections(
    AppDependencies app,
    List<TUnionProcessRecord> process,
    ExpertValues values,
  ) {
    if (process.isEmpty) {
      return [
        {
          'title': '过程记录 · 0x1A / 0x1E',
          'open': false,
          'rows': <List<String>>[
            ['说明', '未读取到过程记录（卡片未实现该文件、记录为空或读取条件不满足）'],
          ],
        },
      ];
    }
    final varRecords = process.where((record) => record.sfi == 0x1A).toList();
    TUnionProcessRecord? railRecord;
    TUnionProcessRecord? busRecord;
    TUnionProcessRecord? wholeVarBlob;
    for (final record in varRecords) {
      switch (record.recordNumber) {
        case 1:
          railRecord = record;
          break;
        case 2:
          busRecord = record;
          break;
        case 0:
          wholeVarBlob = record;
          break;
      }
    }
    final railView = railRecord ?? wholeVarBlob;
    final railFallback = railRecord == null ? app.railTransitRecord : null;
    final cycleRecords = process.where((record) => record.sfi == 0x1E).toList();
    final sections = <GalleryRecord>[
      {
        'title': '0x1A · 城市轨道应用信息记录',
        'open': false,
        'rows': _liveRailRows(
          railView,
          railView?.railTransit ?? railFallback,
          values,
        ),
      },
      {
        'title': '0x1A · 公共汽电车应用信息记录',
        'open': false,
        'rows': _liveBusRows(busRecord, busRecord?.busTransit, values),
      },
    ];
    if (cycleRecords.isNotEmpty) {
      sections.add({
        'title': '0x1E · 循环记录（${cycleRecords.length} 条）',
        'open': false,
        'groups': <GalleryRecord>[
          for (final record in cycleRecords)
            {
              'title':
                  '${record.recordNumber > 0 ? '循环记录 ${record.recordNumber}' : record.recordName}'
                  ' · ${values.processRecordSubtitle(record)}',
              'rows': record.trip == null
                  ? <List<String>>[
                      ['字节数', '${record.raw.length} 字节'],
                      ['说明', '记录未写入或长度不足，未能解码为字段'],
                      ['原始数据', record.rawHex],
                    ]
                  : _liveCycleRows(record.trip!, values),
            },
        ],
      });
    }
    return sections;
  }

  List<List<String>> _liveRailRows(
    TUnionProcessRecord? record,
    TransitRecord? transit,
    ExpertValues values,
  ) {
    if (transit != null) {
      return [
        ['交易状态', codeName(transit.statusCode, transit.statusName)],
        ['进闸城市代码', values.cityCell(transit.entryCityCode)],
        ['出闸城市代码', values.cityCell(transit.exitCityCode)],
        ['进闸机构标识', hexLower(transit.entryAgencyId)],
        ['出闸机构标识', hexLower(transit.exitAgencyId)],
        ['进闸站点', hexLower(transit.entryStationId)],
        ['出闸站点', hexLower(transit.exitStationId)],
        ['进闸终端编号', hexLower(transit.entryTerminalId)],
        ['出闸终端编号', hexLower(transit.exitTerminalId)],
        ['进站时间', bcdTimeCell(transit.entryTime, transit.entryTimeBcd)],
        ['出站时间', bcdTimeCell(transit.exitTime, transit.exitTimeBcd)],
        ['标注金额', values.amountCell(transit.annotateAmountFen)],
        ['入站线路号', hexByteCell(transit.entryLineCode)],
        ['出站线路号', hexByteCell(transit.exitLineCode)],
        ['进站交易金额', values.amountCell(transit.entryAmountFen)],
        ['进站钱包余额', values.balanceCell(transit.entryBalanceFen)],
        ['出闸交易金额', values.amountCell(transit.exitAmountFen)],
        if (transit.issuerCustom != null)
          ['发卡机构自定义', hexLower(transit.issuerCustom)],
      ];
    }
    if (record != null) {
      return [
        ['数据长度', '${record.raw.length} 字节'],
        ['原始数据', record.rawHex],
        ['说明', '记录长度不足或字段布局不符，未做推测解析，按原始数据展示'],
      ];
    }
    return [
      ['说明', '卡片未写入该记录（0x1A 记录 1）'],
    ];
  }

  List<List<String>> _liveBusRows(
    TUnionProcessRecord? record,
    BusTransitRecord? transit,
    ExpertValues values,
  ) {
    if (transit != null) {
      return [
        ['交易状态', codeName(transit.statusCode, transit.statusName)],
        ['上车城市代码', values.cityCell(transit.entryCityCode)],
        ['上车机构标识', hexLower(transit.entryAgencyId)],
        ['上车运营商代码', hexLower(transit.entryOperatorCode)],
        ['上车线路号', hexLower(transit.entryLineCode)],
        ['上车站点', hexLower(transit.entryStationCode)],
        ['上车车辆号', hexLower(transit.entryVehicleId)],
        ['上车终端编号', hexLower(transit.entryTerminalId)],
        ['上车时间', bcdTimeCell(transit.entryTime, transit.entryTimeBcd)],
        ['标注金额', values.amountCell(transit.annotateAmountFen)],
        ['方向标识', transit.directionName],
        ['下车城市代码', values.cityCell(transit.exitCityCode)],
        ['下车机构标识', hexLower(transit.exitAgencyId)],
        ['下车运营商代码', hexLower(transit.exitOperatorCode)],
        ['下车线路号', hexLower(transit.exitLineCode)],
        ['下车站点', hexLower(transit.exitStationCode)],
        ['下车车辆号', hexLower(transit.exitVehicleId)],
        ['下车终端编号', hexLower(transit.exitTerminalId)],
        ['下车时间', bcdTimeCell(transit.exitTime, transit.exitTimeBcd)],
        ['交易金额', values.amountCell(transit.transactionAmountFen)],
        ['乘车里程', intHexCell(transit.mileage)],
        if (transit.hasIssuerCustomData)
          ['发卡机构自定义', hexLower(transit.issuerCustomHex)],
      ];
    }
    if (record != null) {
      return [
        ['数据长度', '${record.raw.length} 字节'],
        ['原始数据', record.rawHex],
        ['说明', '记录长度不足或字段布局不符，未做推测解析，按原始数据展示'],
      ];
    }
    return [
      ['说明', '卡片未写入该记录（0x1A 记录 2）'],
    ];
  }

  List<List<String>> _liveCycleRows(
    TUnionTripRecord trip,
    ExpertValues values,
  ) => [
    ['交易类型', codeName(trip.typeCode, trip.typeName)],
    ['终端编号', trip.terminalId],
    ['应用分类码', codeName(trip.appTypeCode, trip.appTypeName)],
    ['线路', expertValue(trip.lineCode)],
    ['站点', expertValue(trip.stationCode)],
    ['运营代码', expertValue(trip.operatorCode)],
    ['交易金额', values.amountCell(trip.amountFen)],
    ['记录余额', values.balanceCell(trip.balanceFen)],
    ['交易日期时间', dateTimeDigits(trip.time)],
    ['受理方城市代码', values.cityCell(trip.cityCode)],
    ['受理方机构标识', hexLower(trip.acquirerId)],
  ];

  List<GalleryRecord> _liveCityUnionSections(
    AppDependencies app,
    int? walletFen,
  ) {
    final files = app.cityUnionFiles;
    final public = files.where((file) => file.sfi == 0x15).toList();
    final local = files.whereType<CjT331WalletLocalConsumption>().toList();
    final recharge = files.whereType<CjT331WalletRecharge>().toList();
    final foreign = files.whereType<CjT331WalletOfflineTransaction>().toList();
    final unparsed = files
        .whereType<CityUnionRawFileView>()
        .where((file) => file.sfi != 0x15)
        .toList();
    final cityCode = public.whereType<CjT331PublicInfo>().firstOrNull?.cityCode;
    final sections = <GalleryRecord>[
      {
        'title': '城市一卡通应用',
        'open': false,
        'rows': <List<String>>[
          if (walletFen != null)
            ['城市一卡通钱包余额', '${(walletFen / 100).toStringAsFixed(2)} 元'],
          ['已读取文件视图', '${files.length} 项'],
        ],
      },
    ];
    final publicView = public.firstOrNull;
    sections.add({
      'title': '0x15 · 公共应用基本信息文件',
      'open': false,
      'rows': publicView == null
          ? <List<String>>[
              ['说明', '未读取到公共应用基本信息文件（文件不存在或读取被拒）'],
            ]
          : <List<String>>[
              if (publicView.fields.isEmpty)
                ['说明', '未按标准解析（保留原始数据）']
              else
                for (final field in publicView.fields)
                  [field.name, cuFieldValue(field)],
              if (publicView.rawHex.isNotEmpty) ['原始数据', publicView.rawHex],
            ],
    });
    void addRecords(
      String title,
      List<CityUnionFileView> records, {
      String? emptyHint,
    }) {
      if (records.isEmpty) {
        if (emptyHint != null) {
          sections.add({
            'title': title,
            'open': false,
            'rows': <List<String>>[
              ['说明', emptyHint],
            ],
          });
        }
        return;
      }
      for (var index = 0; index < records.length; index++) {
        final record = records[index];
        final station = _liveCuStationName(app, record, cityCode);
        sections.add({
          'title': '$title · ${cuRecordSource(record, index + 1)}',
          'open': false,
          'rows': <List<String>>[
            if (record.fields.isEmpty)
              ['说明', record.errors.join('；')]
            else
              for (final field in record.fields)
                [field.name, cuFieldValue(field)],
            if (station != null) ['站点（终端解析）', station],
            if (record.rawHex.isNotEmpty) ['原始数据', record.rawHex],
          ],
        });
      }
    }

    addRecords('电子钱包本地消费交易明细', local, emptyHint: '未读取到本地消费交易明细（文件不存在或记录未写入）');
    addRecords('电子钱包充值交易明细', recharge, emptyHint: '未读取到充值交易明细（文件不存在或记录未写入）');
    addRecords('电子钱包异地消费交易明细', foreign, emptyHint: '未读取到异地消费交易明细（文件不存在或记录未写入）');
    addRecords('未解析记录', unparsed);
    return sections;
  }

  String? _liveCuStationName(
    AppDependencies app,
    CityUnionFileView record,
    String? cityCode,
  ) {
    if (record is! CityUnionWalletTransaction ||
        record.kind == CityUnionTransactionKind.recharge) {
      return null;
    }
    final identity = CityUnionLookupRules.identifyTerminal(record.terminalHex);
    if (identity == null) return null;
    return app.resolveCuStationName(
      identity.terminal,
      cityCode: identity.regionCode,
      decodedCarrierType: identity.carrier,
      transactionTime: CityUnionLookupRules.transactionTime(
        record.transactionDate,
        record.transactionTime,
      ),
      busLookupEnabled: true,
    );
  }

  List<(String, String)> _liveComplianceRows(AppDependencies app) {
    final parsed = app.parsedCard;
    if (parsed == null) {
      return const [('应用选择', '未发现受支持的交通应用')];
    }
    return [
      (
        '应用选择',
        parsed.selectedAidHex.isEmpty ? '未提供 AID' : parsed.selectedAidHex,
      ),
      ('解析器', parsed.parserName),
      (
        '余额读取',
        GalleryBalancePresentation.observedCardBalanceMinor(parsed) == null
            ? '未读到余额'
            : '已读取',
      ),
      ('交易文件', '${app.transactions.length} 条'),
      ('应用证据', '${app.applications.length} 项'),
      ('城市一卡通文件', '${app.cityUnionFiles.length} 个'),
      (
        '日期一致性',
        parsed.info.expireDate == null
            ? '未读取有效期'
            : '有效期 ${parsed.info.expireDate!.year}-${parsed.info.expireDate!.month}',
      ),
    ];
  }

  List<Widget> _liveRawSections(AppDependencies app) {
    final log = app.apduLog;
    final records = app.transitProcessRecords;
    return [
      _text(
        '以下为本次会话保留的原始命令、响应和应用记录。',
        role: GalleryTypography.caption,
        color: t.muted,
      ),
      _gap(12),
      _expand('live-expert:raw:apdu', 'APDU 命令 / 响应（${log.length} 项）', [
        _hexBox(log.isEmpty ? '本次读取未保留 APDU 详细日志。' : log.join('\n')),
      ], initiallyOpen: true),
      _gap(10),
      _expand(
        'live-expert:raw:process',
        '0x1A / 0x1E 原始记录（${records.length} 条）',
        [
          if (records.isEmpty)
            _text('本次读取未保留过程记录。', color: t.muted)
          else
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _hexBox(
                  'SFI 0x${record.sfi.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                  ' · 记录 ${record.recordNumber + 1}\n${record.rawHex}',
                ),
              ),
        ],
        initiallyOpen: true,
      ),
    ];
  }

  Future<void> _selectLiveConflictPolicy(AppDependencies app) async {
    final selected = await showDialog<ArchiveConflictPolicy>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('已存在的记录'),
        children: [
          RadioGroup<ArchiveConflictPolicy>(
            groupValue: app.archiveConflictPolicy,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final policy in ArchiveConflictPolicy.values)
                  RadioListTile(value: policy, title: Text(policy.label)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mounted && selected != null) {
      await app.setArchiveConflictPolicy(selected);
    }
  }
}
