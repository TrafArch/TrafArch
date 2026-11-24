part of 'gallery_app.dart';

extension _GalleryDetail on _GalleryViewState {
  Widget _detailSwipe(Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity.abs() > 100) {
        c.update(
          () =>
              c.detailTab = (c.detailTab + (velocity < 0 ? 1 : -1)).clamp(0, 2),
        );
      }
    },
    child: child,
  );

  Widget _detail() {
    final card = _selectedCard;
    final ledger = c.ledger(card);
    final body = switch (c.detailTab) {
      1 => _spendingChildren(card),
      2 => [_cardInformation(card)],
      _ => <Widget>[
        if (ledger.isEmpty) _empty('暂无交易记录', '卡内记录可能不完整'),
        for (final group in _tripsByDate(ledger).entries) ...[
          _tripDateHeading(group.key),
          for (final (index, trip) in group.value.indexed) ...[
            if (index > 0) _gap(8),
            Builder(
              builder: (_) => _panel(
                _trip(trip),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ],
        ],
        _gap(16),
        _text(
          '仅展示样例中保留的记录，可能不代表完整历史。',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
      ],
    };
    const navHeight = 56.0;
    final renderedScrollDeficit = _detailScrollDeficit;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        // Short ledgers still collapse the face fully: pad the scroll range up
        // to the shrink distance so the content can ride up. Tie the correction
        // to the padding that produced these metrics: a deferred callback must
        // not apply the same shortfall again to a newer, unrendered deficit.
        _detailMaxExtent = notification.metrics.maxScrollExtent;
        final target = math.max(
          0.0,
          renderedScrollDeficit + (_detailShrinkDistance - _detailMaxExtent),
        );
        if ((target - _detailScrollDeficit).abs() > .5) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if ((target - _detailScrollDeficit).abs() > .5) {
              _updateDetail(() => _detailScrollDeficit = target);
            }
          });
        }
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(1.0, constraints.maxWidth - 32);
          final layout = _DetailCardLayout(
            context,
            card,
            _balancePresentation(card),
            width,
          );
          final tabsHeight = math.max(
            54.0,
            MediaQuery.textScalerOf(context).scale(18) + 26,
          );
          final metadata = '${card.city} · 尾号 ${card.tail}   上次读取 ${card.when}';
          final metadataHeight =
              _measureDetailText(
                context,
                metadata,
                GalleryTypography.caption,
                width,
              ).height +
              16;
          _detailShrinkDistance = layout.expandedHeight + metadataHeight;
          return CustomScrollView(
            key: PageStorageKey('gallery-${c.generation}-detail-${card.id}'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverPersistentHeader(
                  pinned: true,
                  delegate: _TripsSummaryDelegate(
                    expandedHeight:
                        navHeight +
                        layout.expandedHeight +
                        metadataHeight +
                        tabsHeight +
                        24,
                    compactHeight: navHeight + tabsHeight + 24,
                    builder: (progress) => ColoredBox(
                      key: const ValueKey('detail-pinned-header'),
                      color: t.bg,
                      child: Column(
                        children: [
                          _detailNav(progress, card, navHeight),
                          SizedBox(
                            height: _detailLerp(
                              layout.expandedHeight,
                              0,
                              progress,
                            ),
                            child: ClipRect(
                              child: Opacity(
                                opacity: (1 - progress).clamp(0.0, 1.0),
                                child: _GalleryDetailFace(
                                  key: ValueKey('detail-face-${card.id}'),
                                  card: card,
                                  balance: _balancePresentation(card),
                                  layout: layout,
                                ),
                              ),
                            ),
                          ),
                          ClipRect(
                            child: SizedBox(
                              height: metadataHeight * (1 - progress),
                              child: OverflowBox(
                                alignment: Alignment.topLeft,
                                minHeight: metadataHeight,
                                maxHeight: metadataHeight,
                                child: Opacity(
                                  opacity: (1 - progress * 3).clamp(0.0, 1.0),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _text(
                                      metadata,
                                      role: GalleryTypography.caption,
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _gap(12),
                          SizedBox(
                            height: tabsHeight,
                            child: _tabs(
                              ['最近交易', '消费统计', '卡片信息'],
                              c.detailTab,
                              (index) => c.update(() => c.detailTab = index),
                              id: 'detail-tabs',
                            ),
                          ),
                          _gap(12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  30 +
                      MediaQuery.paddingOf(context).bottom +
                      _detailScrollDeficit,
                ),
                sliver: SliverList.builder(
                  itemCount: body.length,
                  itemBuilder: (_, index) => _detailSwipe(body[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Top navigation whose title crossfades from the page name to the card
  /// identity (name · tail) as the face collapses (spec 2.2 §13, user mock).
  Widget _detailNav(double progress, GalleryCard card, double height) {
    final titleHeight = MediaQuery.textScalerOf(context).scale(32);
    return Container(
      height: height,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.line.withValues(alpha: progress)),
        ),
      ),
      child: Row(
        children: [
          _icon(Icons.arrow_back_rounded, '返回', c.back),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: titleHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Opacity(
                    opacity: (1 - progress * 1.6).clamp(0.0, 1.0),
                    child: Semantics(
                      header: true,
                      child: _text('卡片详情', role: GalleryTypography.page),
                    ),
                  ),
                  Opacity(
                    opacity: ((progress - .25) / .75).clamp(0.0, 1.0),
                    child: Semantics(
                      header: true,
                      child: _text(
                        '${card.name} · ${card.tail}',
                        role: GalleryTypography.card.copyWith(
                          fontSize: 18,
                          height: 26 / 18,
                        ),
                        lines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _actionGroup('page', [
            _menuAnchor(
              'detail-card-${card.id}',
              _icon(
                Icons.more_horiz_rounded,
                '${card.name} 管理',
                () => _openDropdown(
                  GalleryOverlay.cardMenu,
                  'detail-card-${card.id}',
                  card: card,
                ),
                outlined: false,
                grouped: true,
              ),
            ),
            _icon(
              Icons.download_outlined,
              '导出本卡记录',
              () {
                final live = _GalleryLiveScope.of(context);
                if (live == null) {
                  c.export();
                  return;
                }
                final saved = live.savedCardFor(card.id);
                if (saved != null) {
                  unawaited(
                    exportArchiveJson(
                      context,
                      live.app,
                      card: saved,
                      onNotice: (message, failed) => _toast(
                        message,
                        type: failed
                            ? GalleryFeedbackType.error
                            : GalleryFeedbackType.success,
                      ),
                    ),
                  );
                }
              },
              outlined: false,
              grouped: true,
              color: t.text,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _cardInformation(GalleryCard card) => _panel(
    Column(
      children: [
        for (final row in <(String, String)>[
          ('完整卡号', card.pan),
          ('发卡地', card.city),
          ('卡种', card.type),
          ('有效期', card.valid == '—' ? '未知' : '${card.valid}（未记录日）'),
          ('当前余额', card.balance(c.includeOverdraft)),
          ('最近读取', card.when),
          ('协议', card.type),
        ])
          _kv(row.$1, row.$2),
      ],
    ),
  );

  Future<void> _selectSpendingPeriod(
    GallerySpendingPeriod period,
    DateTime now,
  ) async {
    if (period != GallerySpendingPeriod.custom) {
      _updateDetail(
        () => _spendingSelection = GallerySpendingSelection.forPeriod(
          period,
          now,
        ),
      );
      return;
    }
    final first = _spendingSelection.start ?? galleryCalendarDay(now);
    final last = _spendingSelection.end ?? first;
    final selected = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => _GalleryRangePickerDialog(
        initialStart: first,
        initialEnd: last,
        today: now,
      ),
    );
    if (!mounted || selected == null) return;
    _updateDetail(
      () => _spendingSelection = GallerySpendingSelection.between(
        selected.start,
        selected.end,
      ),
    );
  }

  String _spendingDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Widget _spendingPeriodButton(
    GallerySpendingPeriod period,
    String label,
    DateTime now,
  ) {
    final selected = _spendingSelection.period == period;
    return Semantics(
      button: true,
      selected: selected,
      child: Container(
        key: ValueKey('spending-period-${period.name}'),
        decoration: BoxDecoration(
          color: selected ? t.tone : t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? t.tone : t.line),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _selectSpendingPeriod(period, now),
            child: SizedBox(
              height: 40,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      label,
                      style: GalleryTypography.label.copyWith(
                        fontWeight: FontWeight.w500,
                        color: selected ? t.onTone : t.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _spendingChildren(GalleryCard card) {
    final live = _GalleryLiveScope.of(context);
    final history = live?.historyFor(card.id);
    return _spendingWidgets(
      history == null
          ? GallerySpendingSummary(
              card.currency,
              c.ledger(card),
              selection: _spendingSelection,
            )
          : projectGalleryArchiveSpending(
              history,
              selection: _spendingSelection,
            ),
      now: live == null ? GalleryController.clock : DateTime.now(),
    );
  }

  List<Widget> _spendingWidgets(
    GallerySpendingSummary summary, {
    required DateTime now,
  }) {
    final range = _spendingSelection.start == null
        ? '全部已保留记录'
        : '${_spendingDate(_spendingSelection.start!)} ～ ${_spendingDate(_spendingSelection.end!)}';
    final widgets = <Widget>[
      Row(
        key: const ValueKey('spending-periods'),
        children: [
          for (final (index, (period, label)) in [
            (GallerySpendingPeriod.all, '全部'),
            (GallerySpendingPeriod.week, '本周'),
            (GallerySpendingPeriod.month, '本月'),
            (GallerySpendingPeriod.year, '本年'),
            (GallerySpendingPeriod.custom, '自定义'),
          ].indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(child: _spendingPeriodButton(period, label, now)),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一时段',
              onPressed: _spendingSelection.start == null
                  ? null
                  : () => _updateDetail(
                      () => _spendingSelection = _spendingSelection.shift(-1),
                    ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: _text(
                range,
                role: GalleryTypography.label,
                align: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: '下一时段',
              onPressed: _spendingSelection.start == null
                  ? null
                  : () => _updateDetail(
                      () => _spendingSelection = _spendingSelection.shift(1),
                    ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
      _panel(
        Row(
          key: const ValueKey('spending-overview'),
          children: [
            for (final (index, metric) in [
              ('总消费', summary.format(summary.total)),
              ('乘车次数', '${summary.rideCount} 次'),
              (
                '日均消费',
                summary.dailyAverage == null
                    ? '暂不可用'
                    : summary.format(summary.dailyAverage!),
              ),
            ].indexed) ...[
              if (index > 0)
                SizedBox(
                  height: 40,
                  child: VerticalDivider(width: 16, color: t.line),
                ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _text(
                      metric.$1,
                      role: GalleryTypography.caption,
                      color: t.muted,
                      align: TextAlign.center,
                    ),
                    _gap(8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _text(metric.$2, role: GalleryTypography.stat),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      ),
      _sectionTitle(
        '消费趋势',
        trailing: switch (summary.bucketUnit) {
          GallerySpendingBucketUnit.day => '按日',
          GallerySpendingBucketUnit.month => '按月',
          GallerySpendingBucketUnit.year => '按年',
        },
      ),
      _panel(_spendingChart(summary)),
      _sectionTitle('分类开销'),
      _panel(_spendingCategories(summary)),
      if (summary.undatedCount > 0) ...[
        _gap(12),
        _text(
          _spendingSelection.period == GallerySpendingPeriod.all
              ? '${summary.undatedCount} 笔消费未记录完整日期，已计入总额和分类，未纳入趋势及日均。'
              : '${summary.undatedCount} 笔消费未记录完整日期，未纳入所选日期；可在“全部”中查看。',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
      ],
      _sectionTitle('消费明细', trailing: '${summary.entries.length} 笔'),
      if (summary.entries.isEmpty)
        _empty('暂无消费记录', '此范围内没有明确币种和扣款金额的记录', icon: Icons.bar_chart_rounded),
    ];
    String? previousDate;
    for (final entry in summary.entries) {
      final date = entry.date == null ? '日期未记录' : _spendingDate(entry.date!);
      if (date != previousDate) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: _text(date, role: GalleryTypography.label, color: t.muted),
          ),
        );
        previousDate = date;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _panel(
            Row(
              children: [
                Icon(
                  entry.record['kind'] == 'rail'
                      ? Icons.train_outlined
                      : entry.record['kind'] == 'bus'
                      ? Icons.directions_bus_outlined
                      : Icons.shopping_bag_outlined,
                  color: t.onTone,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        entry.record['title'] as String? ?? '消费',
                        role: GalleryTypography.body,
                      ),
                      _gap(3),
                      _text(
                        '${entry.record['time'] ?? '时间未记录'} · ${entry.category}',
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _text(
                    galleryDisplayAmount(entry.record['amount'] as String),
                    role: GalleryTypography.lead,
                    align: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    widgets.addAll([
      _gap(12),
      _text(
        '仅统计本卡已保留且币种明确的扣款，不包含充值或过程记录，可能不代表完整消费历史。',
        role: GalleryTypography.caption,
        color: t.muted,
      ),
    ]);
    return widgets;
  }

  Widget _spendingChart(GallerySpendingSummary summary) {
    final buckets = summary.buckets;
    if (buckets.isEmpty) {
      return _empty(
        '暂无可绘制的日期记录',
        '完整日期的消费将显示在这里',
        icon: Icons.bar_chart_rounded,
      );
    }
    final rawMax = buckets.map((entry) => entry.amount).reduce(math.max);
    final axis = _niceAxisScale(rawMax);
    final ticks = [for (var v = 0; v <= axis.max; v += axis.step) v];
    final tickLabels = [for (final v in ticks) summary.format(v)];
    final axisWidth =
        tickLabels
            .map((label) => _measureTextWidth(label, GalleryTypography.caption))
            .reduce(math.max) +
        12;
    const barHeight = 120.0;
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(18);
    final topOffset = labelHeight + 8;
    final totalHeight = topOffset + barHeight + 8 + labelHeight;
    final columnWidth = math.max(
      52.0,
      buckets
          .map(
            (entry) =>
                math.max(
                  _measureTextWidth(
                    summary.format(entry.amount),
                    GalleryTypography.caption,
                  ),
                  _measureTextWidth(entry.label, GalleryTypography.caption),
                ) +
                16,
          )
          .reduce(math.max),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = math.min(axisWidth, constraints.maxWidth * .5);
        final chartWidth = math.max(
          constraints.maxWidth - gutter,
          columnWidth * buckets.length,
        );
        return SizedBox(
          height: totalHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutter,
                height: totalHeight,
                child: Stack(
                  children: [
                    for (final (index, value) in ticks.indexed)
                      Positioned(
                        right: 6,
                        width: math.max(8, gutter - 10),
                        top:
                            topOffset +
                            barHeight * (1 - value / axis.max) -
                            labelHeight / 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _text(
                            tickLabels[index],
                            role: GalleryTypography.caption,
                            color: t.muted,
                            lines: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey('gallery-spending-chart'),
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: chartWidth,
                    height: totalHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: topOffset,
                          height: barHeight,
                          child: CustomPaint(
                            painter: _SpendingGridPainter(
                              ticks.length - 1,
                              t.line,
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final (index, bucket) in buckets.indexed)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  child: Semantics(
                                    label:
                                        '${bucket.label}，${summary.format(bucket.amount)}',
                                    excludeSemantics: true,
                                    child: Column(
                                      children: [
                                        _text(
                                          summary.format(bucket.amount),
                                          role: GalleryTypography.caption,
                                          lines: 1,
                                        ),
                                        _gap(8),
                                        Container(
                                          height: barHeight,
                                          alignment: Alignment.bottomCenter,
                                          child: TweenAnimationBuilder<double>(
                                            key: ValueKey(
                                              'spending-bar-$index',
                                            ),
                                            tween: Tween(
                                              begin: 0,
                                              end: bucket.amount / axis.max,
                                            ),
                                            duration: _reduceMotion
                                                ? Duration.zero
                                                : _GalleryMotion.expand,
                                            curve: _GalleryMotion.standard,
                                            builder: (_, value, _) => Container(
                                              height: math.max(
                                                2,
                                                value * barHeight,
                                              ),
                                              decoration: BoxDecoration(
                                                color: t.data1,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                          ),
                                        ),
                                        _gap(8),
                                        _text(
                                          bucket.label,
                                          role: GalleryTypography.caption,
                                          color: t.muted,
                                          lines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _spendingCategories(GallerySpendingSummary summary) {
    const names = ['轨道交通', '公共汽电车', '其他'];
    final colors = [t.data1, t.data2, t.data3];
    final fractions = [
      for (final name in names)
        summary.total == 0
            ? 0.0
            : (summary.categories[name] ?? 0) / summary.total,
    ];
    final ring = SizedBox(
      width: 144,
      height: 144,
      child: TweenAnimationBuilder<List<double>>(
        tween: _SpendingFractionsTween(
          begin: List.filled(3, 0),
          end: fractions,
        ),
        duration: _reduceMotion ? Duration.zero : _GalleryMotion.expand,
        curve: _GalleryMotion.standard,
        builder: (_, values, child) => CustomPaint(
          painter: _SpendingRingPainter(values, colors, t.chartTrack),
          child: child,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _text('总开销', role: GalleryTypography.caption, color: t.muted),
                _gap(4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _text(
                    summary.format(summary.total),
                    role: GalleryTypography.section,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.categories.isEmpty)
          _text('暂无支出数据', role: GalleryTypography.caption, color: t.muted)
        else
          for (final (index, name) in names.indexed)
            if (summary.categories.containsKey(name))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.circle, size: 9, color: colors[index]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(name, role: GalleryTypography.label),
                          _text(
                            '${summary.format(summary.categories[name]!)} · ${(fractions[index] * 100).toStringAsFixed(1)}%',
                            role: GalleryTypography.caption,
                            color: t.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 300 || _extraTextScale >= .5
          ? Column(children: [ring, _gap(12), legend])
          : Row(
              children: [
                ring,
                const SizedBox(width: 16),
                Expanded(child: legend),
              ],
            ),
    );
  }
}

double _detailLerp(double first, double last, double progress) =>
    first + (last - first) * progress;

/// Round the trend scale to a 1/2/5 unit so the axis quantum stays readable and
/// changes with the selected range's amounts. Values are currency minor units.
({int max, int step}) _niceAxisScale(int rawMax) {
  if (rawMax <= 1) return (max: 1, step: 1);
  final rough = rawMax / 4;
  final magnitude = math
      .pow(10, (math.log(rough) / math.ln10).floor())
      .toDouble();
  final residual = rough / magnitude;
  final nice = residual <= 1
      ? 1.0
      : residual <= 2
      ? 2.0
      : residual <= 5
      ? 5.0
      : 10.0;
  final step = math.max(1, (nice * magnitude).round());
  final max = ((rawMax + step - 1) ~/ step) * step;
  return (max: max, step: step);
}

Size _measureDetailText(
  BuildContext context,
  String value,
  TextStyle style,
  double width,
) {
  final painter = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: math.max(1.0, width));
  final size = painter.size;
  painter.dispose();
  return size;
}

class _DetailCardLayout {
  _DetailCardLayout(
    BuildContext context,
    GalleryCard card,
    GalleryBalancePresentation balance,
    double width,
  ) {
    final brands = _faceBrands(card);
    final titleStyle = GalleryTypography.card.copyWith(
      fontSize: 16,
      height: 23 / 16,
    );
    final amountStyle = GalleryTypography.amount.copyWith(
      fontSize: 23,
      height: 28 / 23,
    );
    final unitStyle = GalleryTypography.caption.copyWith(
      fontSize: 16,
      height: 22 / 16,
    );
    final cardNumberStyle = GalleryTypography.field.copyWith(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
    );
    final titleHeight = _measureDetailText(
      context,
      card.name,
      titleStyle,
      math.max(1.0, width - 40),
    ).height;
    final brandWidth = brands.isEmpty ? 0.0 : (brands.length > 1 ? 64.0 : 68.0);
    final logoHeight = brands.length > 1 ? 42.0 : 44.0;
    final brandHeight = brands.isEmpty
        ? 0.0
        : brands.length * logoHeight + (brands.length - 1) * 2;
    final lowerWidth = math.max(
      1.0,
      width - 40 - (brands.isEmpty ? 0 : brandWidth + 10),
    );
    lowerRightInset = 20 + (brands.isEmpty ? 0 : brandWidth + 10);
    final amountHeight = _measureDetailText(
      context,
      balance.known ? balance.number : balance.displayText,
      amountStyle,
      lowerWidth,
    ).height;
    final currencyLabel = _faceCurrencyLabel(balance.currencyLabel);
    final unitHeight = currencyLabel.isEmpty
        ? 0.0
        : _measureDetailText(
            context,
            currencyLabel,
            unitStyle,
            lowerWidth,
          ).height;
    final cardNumberHeight = _measureDetailText(
      context,
      _formatFaceCardNumber(card.pan),
      cardNumberStyle,
      lowerWidth,
    ).height;
    final balanceHeight = math.max(amountHeight, unitHeight);
    final lowerContentHeight = balanceHeight + 4 + cardNumberHeight;
    expandedHeight = math.max(
      204.0,
      40 + titleHeight + 4 + math.max(lowerContentHeight, brandHeight),
    );
  }
  late final double expandedHeight;
  late final double lowerRightInset;
}

/// The expanded identity card. On scroll the parent shrinks and fades this
/// surface to nothing while the top navigation takes over the card identity
/// (spec 2.2 §13–14, user mock); there is no separate compact capsule.
class _GalleryDetailFace extends StatelessWidget {
  const _GalleryDetailFace({
    super.key,
    required this.card,
    required this.balance,
    required this.layout,
  });
  final GalleryCard card;
  final GalleryBalancePresentation balance;
  final _DetailCardLayout layout;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    final face = GalleryCardFace.byId(card.face);
    final foreground = card.image == null
        ? face.foreground
        : GalleryCardFace.imageForeground;
    final nameStyle = GalleryTypography.card.copyWith(
      fontSize: 16,
      height: 23 / 16,
      color: foreground,
    );
    final amountStyle = GalleryTypography.amount.copyWith(
      color: foreground,
      fontSize: 23,
      height: 28 / 23,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final unitStyle = GalleryTypography.caption.copyWith(
      color: foreground,
      fontSize: 16,
      height: 22 / 16,
    );
    final cardNumberStyle = GalleryTypography.field.copyWith(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      color: foreground,
    );
    final currencyLabel = _faceCurrencyLabel(balance.currencyLabel);
    final cardNumber = _formatFaceCardNumber(card.pan);
    final amount = Semantics(
      label: '余额，${balance.displayText}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: balance.known
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (currencyLabel.isNotEmpty) ...[
                    Text(
                      currencyLabel,
                      key: ValueKey('face-currency-${card.id}'),
                      style: unitStyle,
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    balance.number,
                    key: ValueKey('face-number-${card.id}'),
                    style: amountStyle,
                  ),
                ],
              )
            : Text(
                balance.displayText,
                key: ValueKey('face-unknown-${card.id}'),
                style: amountStyle,
              ),
      ),
    );
    return SizedBox(
      key: ValueKey('card-face-${card.id}'),
      width: double.infinity,
      height: layout.expandedHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [face.start, face.end],
            ),
            border: card.image == null
                ? Border.all(color: const Color(0x29ffffff))
                : null,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (card.image != null)
                Positioned.fill(child: _FaceCropImage(card: card)),
              Positioned(
                left: 20,
                top: 20,
                right: 20,
                child: Text(
                  card.name,
                  key: ValueKey('face-title-${card.id}'),
                  style: nameStyle,
                ),
              ),
              Positioned(
                left: 20,
                right: layout.lowerRightInset,
                bottom: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    amount,
                    const SizedBox(height: 4),
                    Container(
                      key: ValueKey('face-card-number-${card.id}'),
                      decoration: card.image != null && !tokens.dark
                          ? BoxDecoration(
                              color: Colors.black.withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(6),
                            )
                          : null,
                      child: Text(
                        cardNumber,
                        semanticsLabel: '卡号，$cardNumber',
                        textAlign: TextAlign.left,
                        style: cardNumberStyle,
                      ),
                    ),
                  ],
                ),
              ),
              if (_faceBrands(card).isNotEmpty)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: _FaceBrandMark(card: card, id: 'detail-face'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpendingFractionsTween extends Tween<List<double>> {
  _SpendingFractionsTween({required super.begin, required super.end});
  @override
  List<double> lerp(double t) => [
    for (var i = 0; i < end!.length; i++) _detailLerp(begin![i], end![i], t),
  ];
}

class _SpendingRingPainter extends CustomPainter {
  _SpendingRingPainter(this.values, this.colors, this.track);
  final List<double> values;
  final List<Color> colors;
  final Color track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = track;
    canvas.drawOval(rect, paint);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] * math.pi * 2;
      if (sweep > 0) {
        canvas.drawArc(rect, start, sweep, false, paint..color = colors[i]);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SpendingRingPainter old) =>
      !listEquals(values, old.values) ||
      !listEquals(colors, old.colors) ||
      track != old.track;
}

class _SpendingGridPainter extends CustomPainter {
  _SpendingGridPainter(this.intervals, this.color);
  final int intervals;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (intervals <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i <= intervals; i++) {
      final y = size.height * (1 - i / intervals);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_SpendingGridPainter old) =>
      intervals != old.intervals || color != old.color;
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _rangeDayKey(DateTime day) =>
    'range-day-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

class _GalleryRangePickerDialog extends StatefulWidget {
  const _GalleryRangePickerDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.today,
  });
  final DateTime initialStart, initialEnd, today;
  @override
  State<_GalleryRangePickerDialog> createState() =>
      _GalleryRangePickerDialogState();
}

class _GalleryRangePickerDialogState extends State<_GalleryRangePickerDialog> {
  late DateTime? _start = widget.initialStart;
  late DateTime? _end = widget.initialEnd;
  late DateTime _month = DateTime(
    widget.initialStart.year,
    widget.initialStart.month,
  );

  void _pick(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  Widget _dayCell(DateTime day, GalleryTokens t) {
    final endpoint =
        (_start != null && _sameCalendarDay(day, _start!)) ||
        (_end != null && _sameCalendarDay(day, _end!));
    final inRange =
        _start != null &&
        _end != null &&
        !day.isBefore(_start!) &&
        !day.isAfter(_end!);
    final isToday = _sameCalendarDay(day, widget.today);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        key: ValueKey(_rangeDayKey(day)),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pick(day),
        child: Container(
          decoration: BoxDecoration(
            color: endpoint
                ? t.tone
                : inRange
                ? t.tone.withValues(alpha: .25)
                : null,
            borderRadius: BorderRadius.circular(10),
            border: isToday && !endpoint ? Border.all(color: t.line) : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: GalleryTypography.label.copyWith(
              color: endpoint ? t.onTone : t.text,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GalleryTokens>()!;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    return Dialog(
      key: const ValueKey('spending-range-dialog'),
      backgroundColor: t.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择消费日期',
                      style: GalleryTypography.section.copyWith(color: t.text),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('range-prev-month'),
                    tooltip: '上一月',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
                    icon: Icon(Icons.chevron_left_rounded, color: t.text),
                  ),
                  Text(
                    '${_month.year}年${_month.month}月',
                    key: const ValueKey('range-month-label'),
                    style: GalleryTypography.label.copyWith(color: t.text),
                  ),
                  IconButton(
                    key: const ValueKey('range-next-month'),
                    tooltip: '下一月',
                    onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
                    icon: Icon(Icons.chevron_right_rounded, color: t.text),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final weekday in ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: Text(
                          weekday,
                          style: GalleryTypography.caption.copyWith(
                            color: t.muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 7,
                children: [
                  for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                  for (var day = 1; day <= daysInMonth; day++)
                    _dayCell(DateTime(_month.year, _month.month, day), t),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('range-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '取消',
                      style: GalleryTypography.button.copyWith(color: t.muted),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('range-confirm'),
                    onPressed: _start == null
                        ? null
                        : () => Navigator.of(context).pop(
                            DateTimeRange(start: _start!, end: _end ?? _start!),
                          ),
                    child: Text(
                      '确定',
                      style: GalleryTypography.button.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
