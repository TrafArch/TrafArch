part of 'gallery_app.dart';

class _GalleryLiveScope extends InheritedNotifier<_GalleryLiveRead> {
  const _GalleryLiveScope({required super.notifier, required super.child});

  static _GalleryLiveRead? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GalleryLiveScope>()?.notifier;
}

class _GalleryLiveRead extends ChangeNotifier {
  _GalleryLiveRead(this.app, this.navigation) {
    if (app.hasCompletedRead) lastCard = _LiveCardSummary.fromRead(app);
    app.addListener(_appChanged);
    navigation.addListener(_navigationChanged);
    _restoreRoutes();
  }

  final AppDependencies app;
  final GalleryController navigation;
  _LiveCardSummary? lastCard;
  ExpertReadTab expertTab = ExpertReadTab.information;
  int manualSaveRequest = 0;
  Object? _attempt;
  bool _closing = false;
  bool _disposed = false;
  bool openingQr = false;
  bool _routesRestored = false;
  String? _error;

  bool get busy => _attempt != null || (app.scanning && !app.nfcReleaseFailed);
  bool get hasCurrent =>
      !busy &&
      !app.nfcReleaseFailed &&
      app.hasCompletedRead &&
      lastCard != null;

  void _appChanged() {
    _restoreRoutes();
    if (hasCurrent) lastCard = _LiveCardSummary.fromRead(app);
    notifyListeners();
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

  Future<void> start() async {
    if (_disposed ||
        busy ||
        _closing ||
        openingQr ||
        app.qrAcquiring ||
        navigation.page != GalleryPage.home) {
      return;
    }
    final attempt = _attempt = Object();
    _error = null;
    notifyListeners();
    try {
      await app.scanOnceForGallery();
      if (_disposed || !identical(_attempt, attempt)) return;
      if (app.hasCompletedRead) {
        lastCard = _LiveCardSummary.fromRead(app);
      } else if (app.error != null) {
        _error = '读取未完成，请重新贴卡。';
      } else if (app.scan.phase != ScanPhase.cancelled) {
        _error = '未获取到卡片，请重新贴卡。';
      }
    } finally {
      if (!_disposed && identical(_attempt, attempt)) {
        _attempt = null;
        notifyListeners();
      }
    }
  }

  Future<void> cancel() async {
    if (_disposed || _closing) return;
    _attempt = null;
    _closing = true;
    try {
      await app.stop();
    } finally {
      _closing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_appChanged);
    navigation.removeListener(_navigationChanged);
    super.dispose();
  }
}

class _LiveCardSummary {
  const _LiveCardSummary(this.name, this.balance, this.readAt);

  factory _LiveCardSummary.fromRead(AppDependencies app) {
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
    if (app.isOctopusCard) {
      final verified = app.currentOctopusResult?.balanceMinor;
      balance = verified == null
          ? '港币余额未读取'
          : GalleryCurrency.hkd.format(verified);
    } else if (felica != null && parsed == null) {
      balance = felica.cardProductType == FelicaCardType.amusementIc
          ? null
          : felica.wallets.length == 1
          ? felica.wallets.single.balanceText ?? '余额未知'
          : null;
    } else if (parsed != null) {
      final parserId = parsed.parserId;
      final local = parsed.localCard?.info;
      if (CardParserIds.isTUnionFamily(parserId) ||
          parserId == CardParserIds.cityUnion) {
        final direct =
            parserId == CardParserIds.cityUnion ||
            BalanceInterpretation.fromParsedCard(parsed).semantics ==
                BalanceSemantics.direct;
        balance = direct
            ? app.balanceDisplay.formatBalance(
                    parsed.info.balanceFen,
                    symbol: app.cardCurrency.symbol,
                  ) ??
                  '余额未知'
            : '账户余额未知';
      } else if (local?.observedBalance != null &&
          local?.currencyCode == app.cardCurrency.code) {
        balance = local!.isMacauPass
            ? 'MOP \$${local.balance}'
            : '${app.cardCurrency.symbol}${(local.balance / 100).toStringAsFixed(2)}';
      } else {
        balance = '余额未知';
      }
    } else {
      balance = null;
    }
    return _LiveCardSummary(name, balance, app.lastResult!.timestamp);
  }

  final String name;
  final String? balance;
  final DateTime readAt;
}

extension _GalleryLivePages on _GalleryViewState {
  Widget _livePage(GalleryPage page, _GalleryLiveRead live) => switch (page) {
    GalleryPage.home => _liveHome(live),
    GalleryPage.trips => _list([
      if (live.app.recoveredCapture != null)
        RecoveryResultPanel(app: live.app, showSaveActions: false)
      else if (live.hasCurrent) ...[
        _liveTripSummary(live.lastCard!),
        _gap(),
        CurrentTripsBody(app: live.app, showSummary: false),
      ] else
        _liveReadHint(live, '读取卡片后展示本次行程记录', Icons.route_outlined),
    ]),
    GalleryPage.expert => _liveExpert(live),
    GalleryPage.cards => _liveCards(live.app),
    GalleryPage.detail => _liveArchiveDetail(live.app),
    GalleryPage.settings => _liveSettings(live.app),
    GalleryPage.qr => _list([
      _header('乘车码解析', back: true),
      _panel(
        QrReadContent(
          app: live.app,
          onNotice: _archiveNotice,
          canPublish: () => c.page == GalleryPage.qr,
        ),
      ),
    ]),
    GalleryPage.knowledge => _liveKnowledge(live.app),
    GalleryPage.knowledgeSearch => _GalleryKnowledgeSearch(
      load: widget.loadKnowledge,
      onBack: c.back,
      onResult: c.openKnowledgeResult,
      revision: live.app.knowledgeBase,
    ),
    GalleryPage.knowledgeCity ||
    GalleryPage.knowledgeLine ||
    GalleryPage.knowledgeStation => _knowledgeDetails(_entry.knowledgeResult!),
    GalleryPage.feedback => _feedback(),
    _ => _list([_header('尚未接入', back: true), _text('请在现有界面使用此功能。')]),
  };

  Widget _liveTripSummary(_LiveCardSummary card) => _panel(
    Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _text(card.name, role: GalleryTypography.card),
        if (card.balance case final balance?)
          _text(balance, role: GalleryTypography.amount),
      ],
    ),
    color: t.surface2,
    radius: 24,
  );

  Widget _liveHome(_GalleryLiveRead live) => PendingSavePresenter(
    app: live.app,
    active: live.hasCurrent,
    canPresent: () => c.page == GalleryPage.home && live.hasCurrent,
    manualRequest: live.manualSaveRequest,
    onNotice: _archiveNotice,
    child: _list([
      if (live.app.recoveryNotice case final notice?) ...[
        _panel(_text(notice, color: t.onTone)),
        _gap(),
      ],
      if (live.app.recoveredCapture != null) ...[
        RecoveryResultPanel(app: live.app),
        _gap(),
      ],
      _GalleryReadFlow(
        state: live.state,
        hasRead: live.lastCard != null,
        builder: (state, hasRead) => _liveHomeStage(live, state),
      ),
    ]),
  );

  Widget _liveHomeStage(_GalleryLiveRead live, GalleryReadState state) {
    final reading = state == GalleryReadState.reading;
    final failed = state == GalleryReadState.failed;
    final current = state == GalleryReadState.success && live.hasCurrent;
    final card = live.lastCard;
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!current) ...[
          _gap(_compactHeight ? 8 : 32),
          _GalleryReadPrompt(
            reading: reading,
            failed: failed,
            compact: _compactHeight,
          ),
          if (live.app.octopus.progressMessage case final progress?
              when reading) ...[
            _gap(),
            _text(progress, align: TextAlign.center, color: t.muted),
          ],
          if (live.error case final error? when failed) ...[
            _gap(),
            Semantics(
              liveRegion: true,
              child: _text(error, align: TextAlign.center, color: t.warn),
            ),
          ],
          _gap(_compactHeight ? 12 : 24),
        ],
        if (card != null && !reading) ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  card.name,
                  role: GalleryTypography.card,
                  weight: FontWeight.w600,
                ),
                if (card.balance case final balance?) ...[
                  _gap(20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _text(balance, role: GalleryTypography.stat),
                  ),
                ],
                _gap(),
                _text(
                  '${current ? '本次读取' : '上次成功读取'} · '
                  '${localizations.formatShortDate(card.readAt)} '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(card.readAt))}',
                  role: GalleryTypography.caption,
                  color: t.muted,
                ),
              ],
            ),
            radius: 24,
          ),
          _gap(16),
        ],
        Center(
          child: SizedBox(
            width: 240,
            child: _button(
              reading
                  ? '取消读取'
                  : failed
                  ? '重新读取'
                  : current
                  ? '再次读取'
                  : '开始读取',
              live._closing || live.openingQr || live.app.qrAcquiring
                  ? null
                  : reading
                  ? live.cancel
                  : live.start,
              primary: !reading,
              icon: reading ? Icons.close_rounded : Icons.contactless_outlined,
            ),
          ),
        ),
        if (current) ...[
          if (live.app.pendingCardSave != null) ...[
            _gap(),
            _button(
              '保存卡片',
              live.requestSave,
              icon: Icons.save_outlined,
              primary: true,
            ),
          ],
          _gap(16),
          _panel(TransitSummaryPanel(app: live.app)),
          _gap(),
          _button(
            '查看全部行程',
            () => c.navigate(GalleryPage.trips),
            icon: Icons.route_outlined,
          ),
        ],
      ],
    );
  }

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
    if (live.app.recoveredCapture != null) {
      return _list([
        RecoveryResultPanel(app: live.app, showSaveActions: false),
      ]);
    }
    if (!live.hasCurrent) {
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
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections.content(context, tab),
          ),
        ),
      ),
    ], positionId: tab.storageKey);
  }

  Widget _liveSettings(AppDependencies app) {
    final beta = BetaUiScope.maybeOf(context);
    return _list([
      _header('设置', back: true),
      _sectionTitle('读卡与数据'),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _switch(
              '自动保存卡片',
              app.autoSaveEnabled,
              app.setAutoSaveEnabled,
              subtitle: '读取完成并关闭 NFC 后，按下方策略保存。',
            ),
            _settingRow(
              '已存在的记录',
              () => _selectLiveConflictPolicy(app),
              subtitle: app.archiveConflictPolicy.label,
            ),
            _switch(
              '显示上海交通卡透支额度',
              app.includeShanghaiOverdraft,
              app.setIncludeShanghaiOverdraft,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ArchiveTransferButtons(app: app, onNotice: _archiveNotice),
            ),
            _settingRow(
              '知识库',
              () => c.navigate(GalleryPage.knowledge),
              subtitle: '在当前已校验的本地 TU／CU 参考包中浏览和搜索。',
              icon: Icons.storage_outlined,
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('外观'),
      _panel(
        _switch(
          '预测性返回手势',
          _preferences.enabled,
          _preferences.setEnabled,
          subtitle: _preferences.error ?? '支持的 Android 设备上可预览返回目标。',
        ),
        padding: EdgeInsets.zero,
      ),
      if (_preferences.error != null)
        TextButton(
          onPressed: _preferences.loading ? null : _preferences.retry,
          child: const Text('重试'),
        ),
      _sectionTitle('隐私与日志'),
      _panel(
        Column(
          children: [
            _switch(
              '记录运行日志',
              app.loggingEnabled,
              app.setLoggingEnabled,
              subtitle: '读卡日志仅存在本机。',
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('导出诊断日志'),
              subtitle: Text(app.logExportMessage ?? '选择读取会话，手动导出到本机「下载」。'),
              onTap: _diagnosticsOpen || app.exportingLog
                  ? null
                  : () => _openLiveDiagnostics(app),
            ),
            const FirebaseAnalyticsTile(),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      if (app.settings.persistenceError != null) ...[
        _gap(),
        _text('设置未能保存到本机，请重试。', color: t.warn),
      ],
      _sectionTitle('帮助与支持'),
      _panel(
        _settingRow(
          '问题反馈',
          () => c.navigate(GalleryPage.feedback),
          icon: Icons.feedback_outlined,
          subtitle: '打开反馈渠道，不会自动附加日志。',
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('体验'),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _text('2.x 实卡体验', role: GalleryTypography.section),
            _gap(8),
            _text('此界面使用真实本地数据。扫码与贴卡分别进行，诊断只在你主动导出时保存。', color: t.muted),
            if (beta?.switchError case final error?) ...[
              _gap(),
              Semantics(liveRegion: true, child: _text(error, color: t.warn)),
            ],
            if (beta != null) ...[
              _gap(16),
              _button(
                beta.switching ? '正在关闭读卡连接…' : '返回现有界面',
                beta.switching || app.qrAcquiring
                    ? null
                    : () => beta.onChanged(false),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  Future<void> _openLiveDiagnostics(AppDependencies app) async {
    if (_diagnosticsOpen || app.exportingLog) return;
    _updateDetail(() => _diagnosticsOpen = true);
    try {
      await showDiagnosticExportDialog(
        context,
        app,
        canPresent: () => c.page == GalleryPage.settings,
      );
    } finally {
      if (mounted) _updateDetail(() => _diagnosticsOpen = false);
    }
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
