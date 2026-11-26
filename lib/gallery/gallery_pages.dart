part of 'gallery_app.dart';

extension _GalleryPages on _GalleryViewState {
  Widget _home() => _fade(
    'home',
    _list([
      _GalleryReadFlow(
        state: c.readState,
        hasRead: c.hasRead,
        builder: _homeContent,
      ),
    ]),
  );

  Widget _homeContent(GalleryReadState state, bool hasRead) {
    final live = _GalleryLiveScope.of(context);
    final card = c.current;
    final noNfc = live?.app.nfcHardwareUnavailable == true;
    final nfcMessage = noNfc ? '该手机不支持NFC识别' : live?.app.nfcUnavailableMessage;
    final readAction =
        nfcMessage != null ||
            live?.closing == true ||
            live?.app.qrAcquiring == true
        ? null
        : c.read;
    final reading = nfcMessage == null && state == GalleryReadState.reading;
    final failed =
        state == GalleryReadState.failed ||
        (nfcMessage != null && hasRead && live?.hasFreshCurrent == false);
    final showResult = hasRead && !reading && !failed;
    final partial =
        showResult &&
        live != null &&
        live.hasFreshCurrent &&
        live.currentCard.id == card.id &&
        live.currentApplications.any(
          (app) => app.confirmed && app.state == ApplicationProbeState.partial,
        );
    final recent = c.trips.where((r) => r['kind'] != 'event').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: showResult
              ? 0
              : _compactHeight
              ? 8
              : 32,
        ),
        SizedBox(
          key: const ValueKey('home-card-expansion'),
          child: !showResult
              ? _GalleryReadPrompt(
                  reading: reading,
                  failed: failed && nfcMessage == null,
                  compact: _compactHeight,
                  nfcMessage: nfcMessage,
                  noNfc: noNfc,
                  felicaSupported: live == null
                      ? true
                      : live.app.felicaReaderSupported,
                  failureMessage: live?.error,
                  progress: live?.readProgress,
                )
              : _face(card),
        ),
        if (showResult) ...[
          _gap(10),
          Row(
            children: [
              Icon(
                partial
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 16,
                color: partial ? t.warn : t.ok,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: _text(
                    live == null
                        ? '今天 09:41 读取成功'
                        : partial
                        ? '${card.when} 部分读取'
                        : '${card.when} 读取完成',
                    role: GalleryTypography.caption,
                    color: partial ? t.warn : t.onTone,
                  ),
                ),
              ),
              _chip(
                card.saved
                    ? c.autoSave
                          ? '已自动保存'
                          : '已保存'
                    : '未保存',
              ),
            ],
          ),
        ],
        _gap(
          showResult
              ? 16
              : _compactHeight
              ? 12
              : 28,
        ),
        if (!reading)
          if (!hasRead || failed)
            Center(
              child: SizedBox(
                width: showResult ? double.infinity : 240,
                child: _button(
                  failed ? '重新读取' : '开始读取',
                  readAction,
                  primary: true,
                  icon: Icons.contactless_outlined,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _button(
                    card.saved ? '再次读取' : '保存卡片',
                    card.saved
                        ? readAction
                        : live == null
                        ? () => c.showOverlay(GalleryOverlay.save)
                        : () => _requestLiveSave(live),
                    primary: true,
                    icon: card.saved
                        ? Icons.refresh_rounded
                        : Icons.save_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _button(
                    card.saved ? '更换卡面' : '再次读取',
                    card.saved
                        ? () => c.showOverlay(GalleryOverlay.face, card: card)
                        : readAction,
                    icon: card.saved
                        ? Icons.palette_outlined
                        : Icons.refresh_rounded,
                  ),
                ),
              ],
            ),
        if (showResult && nfcMessage != null) ...[
          _gap(8),
          Semantics(
            liveRegion: true,
            child: _text(
              nfcMessage,
              role: GalleryTypography.label,
              color: t.warn,
            ),
          ),
        ],
        if (failed && hasRead) ...[
          _gap(20),
          _text('读取失败，保留上次结果', role: GalleryTypography.label, color: t.warn),
          _gap(12),
          _face(card),
        ],
        if (showResult) ...[
          _gap(16),
          if (recent != null)
            _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _text(
                          recent['kind'] == 'rail' || recent['kind'] == 'bus'
                              ? '最近一次行程'
                              : '最近一笔记录',
                          role: GalleryTypography.caption,
                          color: t.muted,
                        ),
                      ),
                      _text(
                        recent['date'] as String? ?? '今天',
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                  _gap(8),
                  _trip(recent),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            )
          else if (partial)
            _empty('本次未读到交易记录', '可在「专家」中查看本次读取详情', icon: Icons.route_outlined)
          else
            _empty('暂无行程记录', '这张卡片没有可展示的行程', icon: Icons.route_outlined),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                TextButton(
                  onPressed: () => c.navigate(GalleryPage.trips),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                    foregroundColor: t.onTone,
                  ),
                  child: const Text(
                    '查看全部行程  ›',
                    style: GalleryTypography.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _trips() {
    final live = _GalleryLiveScope.of(context);
    final trips = c.filteredTrips;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 32;
        double titleHeight(TextStyle style, double available) {
          final painter = TextPainter(
            text: TextSpan(
              text: c.current.name,
              style: style.copyWith(fontWeight: FontWeight.w400),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: math.max(1, available));
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final scaler = MediaQuery.textScalerOf(context);
        final expandedHeight =
            32.0 +
            math.max(
              28,
              math.max(
                titleHeight(GalleryTypography.card, (width - 97) * .6),
                scaler.scale(24) * 1.2,
              ),
            );
        final compactHeight =
            18.0 +
            math.max(
              titleHeight(GalleryTypography.caption, (width - 44) * .6),
              scaler.scale(18) * 1.2,
            );
        return CustomScrollView(
          key: PageStorageKey('gallery-${c.generation}-trips-${_entry.qrView}'),
          slivers: [
            if (c.hasRead)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: _GalleryCollapsingHeaderDelegate(
                    expandedHeight: _reduceMotion
                        ? compactHeight
                        : math.max(expandedHeight, compactHeight),
                    compactHeight: compactHeight,
                    builder: _tripsSummary,
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, _navLayout.listBottom),
              sliver: SliverList.list(
                children: [
                  _gap(14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterButton(c.source, GalleryOverlay.source),
                      _filterButton(c.mode, GalleryOverlay.mode),
                    ],
                  ),
                  if (live != null &&
                      live.currentCard.applications.contains('suica')) ...[
                    _gap(12),
                    _text(
                      'Suica 履历仅含日期时不会补造进出站时刻。',
                      role: GalleryTypography.caption,
                      color: t.muted,
                    ),
                  ],
                  if (!c.hasRead)
                    _empty(
                      '尚未读取卡片',
                      '请先在首页读取一张交通卡',
                      icon: Icons.route_outlined,
                      action: _button(
                        '前往首页',
                        () => c.navigate(GalleryPage.home),
                        primary: true,
                      ),
                    )
                  else if (trips.isEmpty)
                    _empty(
                      live != null && !live.hasFreshCurrent
                          ? '暂无本次读取结果'
                          : c.trips.isEmpty
                          ? '暂无行程记录'
                          : '当前筛选下没有记录',
                      c.trips.isEmpty ? '卡内记录可能不完整' : '试试其他来源或交通方式',
                      icon: Icons.route_outlined,
                    )
                  else
                    for (final group in _tripsByDate(trips).entries) ...[
                      _tripDateHeading(group.key),
                      _panel(
                        Column(
                          children: [
                            for (final (index, trip)
                                in group.value.indexed) ...[
                              if (index > 0) Divider(height: 1, color: t.line),
                              _trip(trip),
                            ],
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        radius: 24,
                      ),
                    ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Map<String, List<GalleryRecord>> _tripsByDate(Iterable<GalleryRecord> trips) {
    final labelsByDay = <DateTime, String>{};
    final daysByLabel = <String, Set<DateTime>>{};
    for (final trip in trips) {
      final day = galleryRecordedDate(trip);
      if (day == null) continue;
      final label = labelsByDay.putIfAbsent(
        day,
        () => trip['date'] as String? ?? _dateLabel(day),
      );
      daysByLabel.putIfAbsent(label, () => {}).add(day);
    }
    final grouped = <String, List<GalleryRecord>>{};
    for (final trip in trips) {
      final day = galleryRecordedDate(trip);
      final label = labelsByDay[day] ?? trip['date'] as String? ?? '日期未记录';
      // Keep undated legacy rows under their recorded label if the year is ambiguous.
      final title = day != null && daysByLabel[label]!.length > 1
          ? '${day.year}年${day.month}月${day.day}日'
          : label;
      grouped.putIfAbsent(title, () => []).add(trip);
    }
    return grouped;
  }

  Widget _tripDateHeading(String label) => Padding(
    key: ValueKey('trip-date-$label'),
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
    child: Semantics(
      header: true,
      child: _text(label, role: GalleryJourneyTypography.date),
    ),
  );

  /// One pinned surface contracts with scrolling, without overlapping copies.
  Widget _tripsSummary(double progress) => Container(
    key: const ValueKey('trips-summary'),
    padding: EdgeInsets.symmetric(
      horizontal: 16 + 2 * progress,
      vertical: 16 - 7 * progress,
    ),
    decoration: BoxDecoration(
      color: t.tone,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 40 * (1 - progress),
          child: Opacity(
            opacity: 1 - progress,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 40,
                height: 28,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    Icons.credit_card_rounded,
                    size: 28,
                    color: t.onTone,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: _text(
            c.current.name,
            role: TextStyle.lerp(
              GalleryTypography.card,
              GalleryTypography.caption,
              progress,
            )!,
            weight: FontWeight.w400,
            color: t.onTone,
          ),
        ),
        SizedBox(width: 12 - 8 * progress),
        SizedBox(
          height: 24,
          width: 1 - progress,
          child: VerticalDivider(
            width: 1,
            color: t.onTone.withValues(alpha: .2 * (1 - progress)),
          ),
        ),
        SizedBox(width: 12 - 8 * progress),
        Expanded(
          flex: 2,
          child: Semantics(
            label: '当前余额',
            child: _amount(
              c.current,
              size: 24 - 6 * progress,
              weight: FontWeight.w400,
              alignment: Alignment.centerRight,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _filterButton(String label, GalleryOverlay overlay) => _menuAnchor(
    'filter-${overlay.name}',
    Semantics(
      button: true,
      expanded: c.overlay == overlay,
      child: Tooltip(
        message: overlay == GalleryOverlay.source ? '选择记录来源' : '选择交通方式',
        child: TextButton(
          key: ValueKey('filter-${overlay.name}'),
          onPressed: () => _openDropdown(overlay, 'filter-${overlay.name}'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            backgroundColor: label.startsWith('全部') ? t.surface : t.tone,
            foregroundColor: label.startsWith('全部') ? t.muted : t.onTone,
            shape: StadiumBorder(side: BorderSide(color: t.line)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: GalleryTypography.caption),
              const SizedBox(width: 7),
              const Icon(Icons.expand_more_rounded, size: 16),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _trip(GalleryRecord trip, {bool interactive = true}) {
    final rail = trip['kind'] == 'rail';
    final bus = trip['kind'] == 'bus';
    final event = trip['kind'] == 'event';
    final oneWay = trip['oneWay'] == true;
    final boarding = trip['entryTime'] as String? ?? '未记录';
    final sub = (trip['sub'] as String? ?? '未记录 → 未记录').split(' → ');
    String stationFallback(String label) {
      // Without a station, a projected bus transaction may reuse the
      // presenter's balance subtitle. It's not a stop name.
      if (bus &&
          (label.startsWith('记录余额 ') ||
              label.startsWith('交易后余额 ') ||
              label.startsWith('余额 '))) {
        return '未记录';
      }
      return label;
    }

    final entry = trip['entryStation'] as String? ?? stationFallback(sub.first);
    final exit =
        trip['exitStation'] as String? ??
        (sub.length > 1 ? stationFallback(sub.last) : '未记录');
    final entryLine =
        trip['entryLine'] as String? ??
        (rail
            ? (trip['title'] as String).replaceFirst('地铁 ', '')
            : (trip['title'] as String).replaceFirst('公交 ', ''));
    final exitLine =
        trip['exitLine'] as String? ??
        (rail && trip['isCrossCity'] == true ? '' : entryLine);
    final city = trip['city'] as String? ?? '';
    Widget lineBadge(String line, {required bool isEntry}) {
      if (rail) {
        final key = isEntry ? 'entryLineCity' : 'exitLineCity';
        final location = trip[key];
        return _GalleryRailLineBadge(
          key: ValueKey(
            isEntry ? 'trip-entry-line-badge' : 'trip-exit-line-badge',
          ),
          line: line,
          cityCode: location is Map ? location['code'] as String? : null,
          citySystem: location is Map ? location['system'] as String? : null,
          cityName: location is Map
              ? location['name'] as String?
              : !trip.containsKey(key) && trip['isCrossCity'] != true
              ? city
              : null,
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: t.tripBadgeBus,
          borderRadius: BorderRadius.circular(8),
        ),
        child: _text(
          line,
          role: GalleryJourneyTypography.line,
          color: t.tripBadgeOnBus,
        ),
      );
    }

    Widget endpoint(
      String line,
      String time,
      String station, {
      required bool isEntry,
    }) {
      final clock = _text(
        _tripClock(time),
        role: GalleryJourneyTypography.time,
        lines: 1,
      );
      final badge = line.trim().isEmpty
          ? null
          : lineBadge(line, isEntry: isEntry);
      return Semantics(
        label: rail ? (isEntry ? '进站' : '出站') : (isEntry ? '上车' : '下车'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rail)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FittedBox(fit: BoxFit.scaleDown, child: clock),
                  ?badge,
                ],
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    clock,
                    if (badge != null) ...[const SizedBox(width: 8), badge],
                  ],
                ),
              ),
            _gap(6),
            _text(station, role: GalleryJourneyTypography.station),
          ],
        ),
      );
    }

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: event
          ? Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 18, color: t.onTone),
                const SizedBox(width: 12),
                _text(
                  trip['time'] as String,
                  role: GalleryTypography.caption,
                  mono: true,
                  color: t.muted,
                ),
                const SizedBox(width: 12),
                _text(
                  trip['title'] as String,
                  role: GalleryTypography.label,
                  weight: FontWeight.w400,
                ),
                _text('过程记录', role: GalleryTypography.caption, color: t.muted),
              ],
            )
          : !rail && !bus
          ? _transactionRow(trip)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: rail
                                ? Colors.transparent
                                : t.secondaryContainer,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Center(
                            child: JourneyTransportIcon(
                              mode: rail
                                  ? TripModeFilter.rail
                                  : TripModeFilter.bus,
                              cityLabel: city,
                              // Different from the issuer does not mean cross-city.
                              isCrossCity: trip['isCrossCity'] == true,
                              size: 23,
                              fallbackIcon: rail
                                  ? Icons.train_outlined
                                  : Icons.directions_bus_outlined,
                              fallbackColor: rail
                                  ? t.text
                                  : t.onSecondaryContainer,
                            ),
                          ),
                        ),
                        _text(
                          rail ? '轨道交通' : '公交',
                          role: GalleryJourneyTypography.mode,
                        ),
                        if (city.isNotEmpty) ...[
                          SizedBox(
                            height: 14,
                            child: VerticalDivider(width: 1, color: t.muted),
                          ),
                          _text(
                            city,
                            role: GalleryJourneyTypography.city,
                            color: t.muted,
                          ),
                        ],
                        if (trip['foreign'] == true)
                          _chip('异地用卡', weight: FontWeight.w400),
                      ],
                    ),
                    if (rail)
                      _text(
                        galleryDisplayAmount(trip['amount'] as String),
                        role: GalleryJourneyTypography.amount,
                      ),
                  ],
                ),
                _gap(12),
                oneWay
                    ? Wrap(
                        key: const ValueKey('trip-one-way'),
                        spacing: rail ? 8 : 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _text(
                              _tripClock(boarding),
                              role: GalleryJourneyTypography.oneWayTime,
                              lines: 1,
                            ),
                          ),
                          if (entryLine.trim().isNotEmpty)
                            lineBadge(entryLine, isEntry: true),
                          _text(entry, role: GalleryJourneyTypography.station),
                        ],
                      )
                    : Row(
                        key: const ValueKey('trip-endpoints'),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: endpoint(
                              entryLine,
                              boarding,
                              entry,
                              isEntry: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Center(
                              child: Container(
                                key: const ValueKey('trip-direction-arrow'),
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: t.tone.withValues(alpha: .5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: t.muted,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: endpoint(
                              exitLine,
                              trip['time'] as String? ?? '未记录',
                              exit,
                              isEntry: false,
                            ),
                          ),
                        ],
                      ),
                if (rail && trip['transferKnown'] == false && !interactive) ...[
                  _gap(10),
                  _text(
                    '未记录换乘站',
                    role: GalleryTypography.caption,
                    color: t.onTone,
                  ),
                ],
              ],
            ),
    );
    return interactive
        ? Semantics(
            button: true,
            label: bus
                ? '${trip['title']}，$entry${oneWay ? '' : ' → $exit'}'
                : '${trip['title']}，${trip['sub']}，'
                      '${galleryDisplayAmount(trip['amount'] as String)}',
            child: InkWell(
              onTap: () => c.showOverlay(GalleryOverlay.trip, trip: trip),
              child: body,
            ),
          )
        : body;
  }

  Widget _transactionRow(GalleryRecord record) => Column(
    key: const ValueKey('gallery-transaction'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                record['kind'] == 'recharge'
                    ? Icons.account_balance_wallet_outlined
                    : Icons.receipt_long_outlined,
                color: t.onTone,
                size: 23,
              ),
              _text(
                record['title'] as String,
                role: GalleryJourneyTypography.mode,
              ),
            ],
          ),
          _text(
            galleryDisplayAmount(record['amount'] as String),
            role: GalleryJourneyTypography.amount,
          ),
        ],
      ),
      _gap(6),
      _text(
        _tripClock(record['time'] as String? ?? '时间未记录'),
        role: GalleryJourneyTypography.time,
        color: t.muted,
      ),
    ],
  );

  Widget _cards() {
    final cards = c.savedCards;
    final ids = cards.map((card) => card.id).toSet();
    if (_walletCardIds != null) {
      _walletArrivals.addAll(ids.difference(_walletCardIds!));
    }
    _walletCardIds = ids;
    if (_walletArrivals.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _walletArrivals.clear(),
      );
    }
    Color foreground(GalleryCard card, {bool secondary = false}) =>
        _walletForeground(card, secondary: secondary);
    final numberStyle = GalleryTypography.lead.copyWith(
      inherit: false,
      color: t.cardTextPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = {
      for (final card in cards) card.id: _balancePresentation(card),
    };
    double measure(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: style.copyWith(
            fontFamily: 'sans-serif',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width.ceilToDouble() + 2;
      painter.dispose();
      return width;
    }

    var numberWidth = 0.0;
    for (final value in parts.values) {
      if (!value.known) continue;
      numberWidth = math.max(numberWidth, measure(value.number, numberStyle));
    }
    Widget handle(GalleryCard card, int index) => Semantics(
      container: true,
      excludeSemantics: true,
      label: '${card.name}，长按拖动排序',
      customSemanticsActions: {
        if (index > 0)
          CustomSemanticsAction(label: '上移'): () =>
              c.reorderSavedCards(index, index - 1),
        if (index < cards.length - 1)
          CustomSemanticsAction(label: '下移'): () =>
              c.reorderSavedCards(index, index + 1),
      },
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Tooltip(
            message: '长按拖动${card.name}',
            triggerMode: TooltipTriggerMode.manual,
            child: SizedBox(
              key: ValueKey('wallet-drag-${card.id}'),
              width: 44,
              height: 48,
              child: Icon(
                Icons.drag_indicator_rounded,
                color: foreground(card, secondary: true),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 32;
        double titleHeight(TextStyle style, double available) {
          final painter = TextPainter(
            text: TextSpan(
              text: '我的卡片',
              style: style.copyWith(fontWeight: FontWeight.w400),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: math.max(1, available));
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final scaler = MediaQuery.textScalerOf(context);
        final expandedHeight =
            32.0 +
            math.max(
              26,
              math.max(
                titleHeight(GalleryTypography.card, (width - 97) * .6),
                math.max(
                  titleHeight(GalleryTypography.section, (width - 97) * .4),
                  scaler.scale(24) * 1.2,
                ),
              ),
            );
        final compactHeight =
            18.0 +
            math.max(
              titleHeight(GalleryTypography.caption, (width - 44) * .6),
              scaler.scale(18) * 1.2,
            );
        return CustomScrollView(
          key: PageStorageKey('gallery-${c.generation}-cards'),
          slivers: [
            if (cards.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: _GalleryCollapsingHeaderDelegate(
                    expandedHeight: _reduceMotion
                        ? compactHeight
                        : math.max(expandedHeight, compactHeight),
                    compactHeight: compactHeight,
                    builder: (progress) =>
                        _walletSummary(progress, cards.length),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                cards.isEmpty ? 6 : 20,
                16,
                _navLayout.listBottom,
              ),
              sliver: cards.isEmpty
                  ? SliverToBoxAdapter(
                      child: _empty(
                        '还没有保存的卡片',
                        '读取一张交通卡并保存到卡包',
                        action: _button(
                          '前往首页',
                          () => c.navigate(GalleryPage.home),
                          primary: true,
                        ),
                      ),
                    )
                  : SliverReorderableList(
                      itemCount: cards.length,
                      onReorderItem: c.reorderSavedCards,
                      proxyDecorator: (child, index, animation) =>
                          AnimatedBuilder(
                            animation: animation,
                            child: child,
                            builder: (context, child) => Transform.scale(
                              scale: _reduceMotion
                                  ? 1
                                  : 1 +
                                        .02 *
                                            _GalleryMotion.decelerate.transform(
                                              animation.value,
                                            ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: t.shadows(
                                    GalleryElevation.floating,
                                  ),
                                ),
                                child: child,
                              ),
                            ),
                          ),
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return _GalleryWalletItem(
                          key: ValueKey('wallet-item-${card.id}'),
                          id: card.id,
                          name: card.name,
                          reduceMotion: _reduceMotion,
                          inserted: _walletArrivals.contains(card.id),
                          onFace: () =>
                              c.showOverlay(GalleryOverlay.face, card: card),
                          onDelete: () =>
                              c.showOverlay(GalleryOverlay.delete, card: card),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: t.shadows(GalleryElevation.card),
                            ),
                            child: _walletCardSurface(
                              card,
                              id: 'wallet',
                              numberWidth: numberWidth,
                              trailing: handle(card, index),
                              onTap: () => c.openCard(card),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// The wallet summary contracts into a pinned capsule while scrolling,
  /// mirroring the trips summary animation.
  Widget _walletSummary(double progress, int count) => Container(
    key: const ValueKey('wallet-summary'),
    padding: EdgeInsets.symmetric(
      horizontal: 16 + 2 * progress,
      vertical: 16 - 7 * progress,
    ),
    decoration: BoxDecoration(
      color: t.tone,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 26 * (1 - progress),
          child: Opacity(
            opacity: 1 - progress,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(Icons.wallet_outlined, size: 26, color: t.onTone),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12 * (1 - progress)),
        Expanded(
          child: _text(
            '我的卡片',
            role: TextStyle.lerp(
              GalleryTypography.card,
              GalleryTypography.caption,
              progress,
            )!,
            color: t.onTone,
          ),
        ),
        _text(
          '$count 张',
          role: TextStyle.lerp(
            GalleryTypography.section,
            GalleryTypography.caption,
            progress,
          )!,
          color: t.onTone,
        ),
      ],
    ),
  );

  Future<void> _confirmDeleteWalletCard(String cardId) async {
    if (_confirmingCardDeletion ||
        c.overlay != GalleryOverlay.delete ||
        c.selectedCardId != cardId)
      return;
    final card = c.savedCards.where((card) => card.id == cardId).firstOrNull;
    if (card == null) return;
    final feedback = GalleryFeedbackHost.messengerOf(context);
    final live = _GalleryLiveScope.of(context);
    if (live == null) {
      final removal = c.deleteCard(card);
      if (removal != null) {
        feedback(
          '已删除“${card.name}”',
          actionLabel: '撤回',
          prioritizeAction: true,
          onAction: () => c.restoreCard(removal),
        );
      }
      return;
    }
    final controller = c;
    final repository = live.app.cardRepository;
    final detailRouteId = controller.navigationStack
        .where(
          (route) =>
              route.kind == GalleryRouteKind.page &&
              route.page == GalleryPage.detail,
        )
        .lastOrNull
        ?.id;
    _confirmingCardDeletion = true;
    // The confirmation closes only after the user commits. The window-level
    // feedback survives the overlay and the deleted detail route.
    controller.back();
    try {
      final deletion = await repository.deleteCardWithUndo(cardId);
      if (deletion == null) {
        feedback('卡片不存在或已删除');
        return;
      }
      if (!live._disposed &&
          detailRouteId != null &&
          controller.navigationStack.lastOrNull?.id == detailRouteId) {
        controller.back();
      }
      feedback(
        '已删除“${card.name}”',
        actionLabel: '撤回',
        prioritizeAction: true,
        onAction: () async {
          try {
            if (!await repository.undoCardDeletion(deletion)) {
              feedback('卡片已重新加入，未覆盖现有记录');
            }
          } catch (_) {
            feedback('撤回失败', type: GalleryFeedbackType.error);
          }
        },
      );
    } catch (_) {
      feedback('删除失败，请重试。', type: GalleryFeedbackType.error);
    } finally {
      _confirmingCardDeletion = false;
    }
  }

  Widget _footprints() => _list([
    IntrinsicHeight(
      child: Row(
        key: const ValueKey('footprint-summary'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, pair) in [
            ('${c.footprints.length}', '去过站点'),
            ('16', '累计到访'),
            ('3', '本月新站点'),
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _panel(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(30),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _text(pair.$1, role: GalleryTypography.stat),
                      ),
                    ),
                    _gap(4),
                    _text(
                      pair.$2,
                      role: GalleryTypography.caption,
                      color: t.muted,
                      align: TextAlign.center,
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    _gap(18),
    ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 372 / 286,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/gallery/footprints-map.svg',
                  fit: BoxFit.fill,
                  semanticsLabel: '站点地图示意，完整信息见下方站点列表',
                ),
              ),
              ...c.footprints.indexed.map(
                (item) => Positioned(
                  left: (item.$2['x'] as num) / 100 * box.maxWidth - 5,
                  top: (item.$2['y'] as num) / 100 * box.maxHeight - 5,
                  child: Semantics(
                    label: '${item.$2['name']}，${item.$2['visits']}次到访',
                    child: Container(
                      width: item.$1 == 0 ? 14 : 10,
                      height: item.$1 == 0 ? 14 : 10,
                      decoration: BoxDecoration(
                        color: item.$1 == 0 ? t.action : t.onTone,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.bg, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    _sectionTitle('全部站点'),
    _panel(
      Column(
        children: [
          for (final station in c.footprints)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        station['kind'] == 'rail'
                            ? Icons.train_outlined
                            : Icons.directions_bus_outlined,
                        color: t.onTone,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _text(
                              station['name'] as String,
                              role: GalleryTypography.body,
                              weight: FontWeight.w600,
                            ),
                            _gap(3),
                            _text(
                              station['line'] as String,
                              role: GalleryTypography.caption,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _gap(6),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _text(
                        '${station['visits']} 次到访',
                        role: GalleryTypography.caption,
                      ),
                      _text(
                        station['last'] as String,
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ]);

  Widget _settings() {
    final live = _GalleryLiveScope.of(context);
    final beta = BetaUiScope.maybeOf(context);
    return _list([
      _header('设置', back: true),
      _sectionTitle('读卡与数据'),
      _panel(
        Column(
          children: [
            _switch(
              '读取后自动保存',
              c.autoSave,
              c.setAutoSave,
              subtitle: '每次读取后保存到当前卡包',
            ),
            if (live != null) ...[
              const Divider(),
              _settingRow(
                '已存在的记录',
                () => _selectLiveConflictPolicy(live.app),
                subtitle:
                    '${live.app.archiveConflictPolicy.label} · 仅影响与当前档案相同的卡片',
                icon: Icons.fact_check_outlined,
              ),
            ],
            const Divider(),
            _switch(
              '上海交通卡可透支余额',
              c.includeOverdraft,
              c.setIncludeOverdraft,
              subtitle:
                  '总余额${c.includeOverdraft ? '包含' : '扣除'}固定 8 元额度，CU 余额不重复扣除',
            ),
            const Divider(),
            _settingRow(
              '知识库',
              () => c.navigate(GalleryPage.knowledge),
              subtitle: live == null
                  ? 'TU 41 个地区 / CU 7 个地区'
                  : '使用已安装并校验的本地 TU／CU 参考数据包',
              icon: Icons.menu_book_outlined,
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('数据与备份'),
      _panel(
        Column(
          children: [
            _settingRow(
              '导出卡片记录',
              () {
                if (live == null) {
                  c.export(all: true);
                } else {
                  unawaited(
                    exportArchiveJson(
                      context,
                      live.app,
                      onNotice: _archiveNotice,
                    ),
                  );
                }
              },
              subtitle: live == null
                  ? '预览全部已保存卡片的记录，不保存文件'
                  : '选择字段或完整备份，保存到手机本地',
              icon: Icons.download_outlined,
            ),
            const Divider(),
            _settingRow(
              '导入卡片记录',
              () => unawaited(
                live == null ? _importCardRecords() : _importLiveArchive(live),
              ),
              subtitle: live == null
                  ? '选择备份文件预览内容，不修改当前样例'
                  : '先预览字段或备份，确认后写入本机档案',
              icon: Icons.upload_outlined,
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('界面与外观'),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text('外观主题', size: 14),
                  _gap(10),
                  _tabs(
                    ['跟随系统', '浅色', '深色'],
                    [
                      ThemeMode.system,
                      ThemeMode.light,
                      ThemeMode.dark,
                    ].indexOf(c.themeMode),
                    (i) => c.update(
                      () => c.themeMode = [
                        ThemeMode.system,
                        ThemeMode.light,
                        ThemeMode.dark,
                      ][i],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            _switch(
              '莫奈取色',
              c.monet,
              c.setMonet,
              subtitle: c.monet
                  ? (t.dynamic ? '跟随 Android 系统动态配色' : '系统动态配色不可用，使用默认靛蓝')
                  : '使用手动选择的主题配色',
            ),
            _collapse(
              !c.monet,
              (_) => Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                child: Row(
                  children: GalleryPalette.values.map((palette) {
                    final roles = palette.tokens(t.dark);
                    final swatch = roles.primary;
                    return Expanded(
                      child: Semantics(
                        selected: c.palette == palette.id,
                        child: TextButton(
                          onPressed: () =>
                              c.update(() => c.palette = palette.id),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: c.palette == palette.id
                                    ? t.onTone
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: swatch,
                                  shape: BoxShape.circle,
                                ),
                                child: c.palette == palette.id
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: roles.onPrimary,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              _gap(7),
                              _text(
                                palette.name,
                                role: GalleryTypography.caption,
                                color: t.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(),
            _switch(
              '震动',
              c.hapticEnabled,
              c.setHaptic,
              subtitle: '控制开关点击与底栏切换的系统触感反馈',
            ),
            const Divider(),
            _switch('预测性返回手势', _preferences.enabled, _preferences.setEnabled),
            _collapse(
              _preferences.error != null,
              (_) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _text(
                        _preferences.error!,
                        role: GalleryTypography.caption,
                        color: t.warn,
                      ),
                    ),
                    TextButton(
                      onPressed: _preferences.loading
                          ? null
                          : _preferences.retry,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text('底栏样式', size: 14),
                  _gap(10),
                  _tabs(
                    ['悬浮', '下沉'],
                    c.docked ? 1 : 0,
                    (i) => c.update(() => c.docked = i == 1),
                  ),
                ],
              ),
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('隐私'),
      _panel(const FirebaseAnalyticsTile(), padding: EdgeInsets.zero),
      _sectionTitle('日志'),
      _panel(
        Column(
          children: [
            _switch(
              live == null ? '启用运行日志' : '记录运行日志',
              c.logsEnabled,
              c.setLogs,
              subtitle: live == null ? '仅记录本次会话中的界面操作' : '读卡会话仅保存在本机，可在下方手动导出',
            ),
            _collapse(
              c.logsEnabled || live != null,
              (_) => Column(
                children: [
                  const Divider(),
                  _settingRow(
                    live == null ? '导出日志' : '诊断日志',
                    () {
                      if (live == null) {
                        c.export(log: true);
                      } else {
                        unawaited(
                          showDiagnosticExportDialog(context, live.app),
                        );
                      }
                    },
                    subtitle: live == null ? '预览模拟日志，不保存文件' : '选择读取会话并导出到本机',
                    icon: Icons.download_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('帮助与支持'),
      _panel(
        _settingRow(
          '问题反馈',
          () => _openInformationPage(GalleryPage.feedback),
          subtitle: 'QQ 群、邮箱与问卷反馈渠道',
          icon: Icons.feedback_outlined,
        ),
        padding: EdgeInsets.zero,
      ),
      _sectionTitle('关于 TrafArch'),
      _panel(
        Column(
          children: [
            _aboutHero(live?.app.updates),
            const Divider(),
            _settingRow(
              '致谢',
              () => _openInformationPage(GalleryPage.acknowledgements),
              subtitle: '感谢读卡识途及数据贡献者',
              icon: Icons.volunteer_activism_outlined,
            ),
            const Divider(),
            _settingRow(
              '开放源代码许可',
              () => _openInformationPage(GalleryPage.licenses),
              subtitle: '查看本应用使用的开源软件与许可',
              icon: Icons.code_rounded,
            ),
            const Divider(),
            _contactRow(
              '隐私政策',
              '了解数据与隐私保护',
              Icons.privacy_tip_outlined,
              link: AppSupport.privacy,
            ),
            const Divider(),
            _contactRow(
              AppSupport.eulaLabel,
              '查看 TrafArch 的使用条款',
              Icons.description_outlined,
              link: AppSupport.eula,
            ),
            const Divider(),
            _contributorRow(),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
      _gap(24),
      _text(
        AppInfo.copyright,
        role: GalleryTypography.caption,
        color: t.muted,
        align: TextAlign.center,
      ),
      if (widget.onDisableBeta != null) ...[
        _sectionTitle('备用界面'),
        _panel(
          _switch(
            '使用 1.x 备用界面',
            false,
            beta?.switching == true ? null : (_) => widget.onDisableBeta!(),
            subtitle:
                beta?.switchError ??
                (beta?.switching == true
                    ? '正在切换到 1.x 备用界面…'
                    : '默认使用 2.x 主界面；开启后仅在本次运行切换到 1.x，重启自动恢复 2.x。'),
          ),
          padding: EdgeInsets.zero,
        ),
      ],
    ]);
  }

  Future<void> _importLiveArchive(_GalleryLiveRead live) async {
    try {
      final preview = await live.app.archiveTransfer.pickImport();
      if (!mounted || preview == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入卡片 JSON'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.name),
                const SizedBox(height: 12),
                Text(preview.summary),
                const SizedBox(height: 12),
                Text(
                  preview.isPartial
                      ? '字段导入会作为独立记录保存，缺失内容保持未知。'
                      : '相同卡片的历史记录将合并，本机自定义名称保留。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await live.app.archiveTransfer.confirmImport(preview);
      if (!mounted) return;
      _toast('导入完成：新增 ${result.insertedCards} 张，合并 ${result.mergedCards} 张');
    } catch (_) {
      if (mounted) {
        _toast('导入失败，请重试。', type: GalleryFeedbackType.error);
      }
    }
  }

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool>? onChanged, {
    String? subtitle,
  }) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: _text(label, size: 14),
    subtitle: subtitle == null
        ? null
        : _text(subtitle, role: GalleryTypography.caption, color: t.muted),
    value: value,
    onChanged: onChanged == null
        ? null
        : (next) {
            // 在点击时读取当前偏好：关闭震动的那一次点击仍然会振动，
            // 重新开启的那一次不会，所有开关共用同一规则。
            if (c.hapticEnabled) HapticFeedback.selectionClick();
            onChanged(next);
          },
  );
  Widget _settingRow(
    String label,
    VoidCallback onTap, {
    String? subtitle,
    IconData? icon,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: icon == null ? null : Icon(icon, size: 21, color: t.onTone),
    title: _text(label, size: 14),
    subtitle: subtitle == null
        ? null
        : _text(subtitle, role: GalleryTypography.caption, color: t.muted),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: onTap,
  );

  Widget _aboutHero(UpdateService? updates) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
    child: Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset('assets/icon/app_icon.png', width: 72, height: 72),
        ),
        _gap(12),
        _text(
          AppInfo.appName,
          role: GalleryTypography.section,
          weight: FontWeight.w600,
        ),
        _gap(4),
        _text(
          '版本 ${AppInfo.version} (${AppInfo.displayBuildNumber})',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
        if (updates != null && updates.isConfigured) ...[
          _gap(12),
          UpdateCheckButton(
            service: updates,
            onFeedback: (message, isError) => _toast(
              message,
              type: isError
                  ? GalleryFeedbackType.error
                  : GalleryFeedbackType.info,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _contributorAvatar(
    GalleryContributor contributor,
    int index, {
    double size = 34,
    bool ring = true,
  }) {
    final background = t.dataPalette[index % t.dataPalette.length];
    Widget fallback() => Container(
      color: background,
      alignment: Alignment.center,
      child: _text(
        contributor.initial,
        size: size * .42,
        weight: FontWeight.w600,
        color: GalleryColorEngine.readable(Colors.white, background),
      ),
    );
    final asset = contributor.asset;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: t.surface, width: 2) : null,
      ),
      child: ClipOval(
        child: asset == null
            ? fallback()
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }

  Widget _contributorRow() {
    const size = 34.0;
    const overlap = 8.0;
    final shown = galleryContributors.take(3).toList();
    final extra = galleryContributors.length - shown.length;
    final avatarWidth = size + math.max(0, shown.length - 1) * (size - overlap);
    return InkWell(
      key: const ValueKey('settings-contributors'),
      onTap: () => c.showOverlay(GalleryOverlay.contributors),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(child: _text('贡献者', size: 14)),
            SizedBox(
              width: avatarWidth + (extra > 0 ? size - overlap : 0),
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * (size - overlap),
                      child: _contributorAvatar(shown[i], i),
                    ),
                  if (extra > 0)
                    Positioned(
                      left: shown.length * (size - overlap),
                      child: Container(
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.surface, width: 2),
                        ),
                        child: _text(
                          '+$extra',
                          role: GalleryTypography.caption,
                          color: t.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _text(
              '${galleryContributors.length} 位',
              role: GalleryTypography.caption,
              color: t.muted,
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _GalleryCollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  _GalleryCollapsingHeaderDelegate({
    required this.expandedHeight,
    required this.compactHeight,
    required this.builder,
  });

  final double expandedHeight, compactHeight;
  final Widget Function(double) builder;

  @override
  double get maxExtent => expandedHeight;
  @override
  double get minExtent => compactHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final distance = maxExtent - minExtent;
    final progress = distance <= 0
        ? 1.0
        : (shrinkOffset / distance).clamp(0.0, 1.0);
    return RepaintBoundary(child: SizedBox.expand(child: builder(progress)));
  }

  @override
  bool shouldRebuild(_GalleryCollapsingHeaderDelegate oldDelegate) => true;
}

/// Journey rows read as clock times; seconds only widen the row and add noise.
String _tripClock(String value) => value.replaceFirstMapped(
  RegExp(r'(\d{1,2}:\d{2}):\d{2}(?:\.\d+)?'),
  (match) => match[1]!,
);
