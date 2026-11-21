part of 'gallery_app.dart';

class _GalleryLiveScope extends InheritedNotifier<_GalleryLiveRead> {
  const _GalleryLiveScope({required super.notifier, required super.child});

  static _GalleryLiveRead? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GalleryLiveScope>()?.notifier;
}

class _GalleryLiveRead extends ChangeNotifier {
  _GalleryLiveRead(this.app, this.navigation) {
    if (app.hasCompletedRead) lastCard = _LiveCardSummary.fromRead(app);
    app.addListener(notifyListeners);
    navigation.addListener(_navigationChanged);
  }

  final AppDependencies app;
  final GalleryController navigation;
  _LiveCardSummary? lastCard;
  ExpertReadTab expertTab = ExpertReadTab.information;
  Object? _attempt;
  bool _closing = false;
  bool _disposed = false;
  String? _error;

  bool get busy => _attempt != null || (app.scanning && !app.nfcReleaseFailed);
  bool get hasCurrent =>
      !busy &&
      !app.nfcReleaseFailed &&
      app.hasCompletedRead &&
      lastCard != null;
  String? get error => app.nfcReleaseFailed ? 'NFC 连接未确认关闭，请重试。' : _error;
  GalleryReadState get state => busy
      ? GalleryReadState.reading
      : error != null
      ? GalleryReadState.failed
      : hasCurrent
      ? GalleryReadState.success
      : GalleryReadState.unread;

  void _navigationChanged() {
    if (navigation.page != GalleryPage.home && _attempt != null) {
      unawaited(cancel());
    }
  }

  void selectExpertTab(ExpertReadTab tab) {
    expertTab = tab;
    notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || busy || _closing || navigation.page != GalleryPage.home) {
      return;
    }
    final attempt = _attempt = Object();
    _error = null;
    notifyListeners();
    try {
      await app.scanOnceReadOnly();
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
    app.removeListener(notifyListeners);
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
      if (live.hasCurrent) ...[
        _liveTripSummary(live.lastCard!),
        _gap(),
        CurrentTripsBody(app: live.app, showSummary: false),
      ] else
        _liveReadHint(live, '读取卡片后展示本次行程记录', Icons.route_outlined),
    ]),
    GalleryPage.expert => _liveExpert(live),
    GalleryPage.cards => _list([
      _empty('卡包尚未接入', '请切回现有界面查看已保存的卡片。', icon: Icons.credit_card_outlined),
    ]),
    GalleryPage.settings => _liveSettings(),
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

  Widget _liveHome(_GalleryLiveRead live) => _list([
    _GalleryReadFlow(
      state: live.state,
      hasRead: live.lastCard != null,
      builder: (state, hasRead) => _liveHomeStage(live, state),
    ),
  ]);

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
              live._closing
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

  Widget _liveSettings() {
    final beta = BetaUiScope.maybeOf(context);
    return _list([
      _header('设置', back: true),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _text('2.x 实卡体验', role: GalleryTypography.section),
            _gap(8),
            _text('首页、行程和专家分析读取真实数据，不会保存档案。卡包、扫码和完整设置请使用现有界面。', color: t.muted),
            if (beta?.switchError case final error?) ...[
              _gap(),
              Semantics(liveRegion: true, child: _text(error, color: t.warn)),
            ],
            if (beta != null) ...[
              _gap(16),
              _button(
                beta.switching ? '正在关闭读卡连接…' : '返回现有界面',
                beta.switching ? null : () => beta.onChanged(false),
              ),
            ],
          ],
        ),
      ),
    ]);
  }
}
