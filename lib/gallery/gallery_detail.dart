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
      2 => _cardInformation(card),
      _ => <Widget>[
        if (ledger.isEmpty) _empty('暂无交易记录', '卡内记录可能不完整'),
        for (final record in ledger)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(record['date'] as String? ?? '日期未记录'),
              _panel(
                _trip(record),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ],
          ),
        _gap(16),
        _text(
          '仅展示样例中保留的记录，可能不代表完整历史。',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
      ],
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _header(
            '卡片详情',
            back: true,
            actions: [
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
                () => c.export(),
                outlined: false,
                grouped: true,
                color: t.text,
              ),
            ],
          ),
        ),
        Expanded(
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
              final metadata =
                  '${card.city} · 尾号 ${card.tail}   上次读取 ${card.when}';
              final metadataHeight =
                  _measureDetailText(
                    context,
                    metadata,
                    GalleryTypography.caption,
                    width,
                  ).height +
                  16;
              return CustomScrollView(
                key: PageStorageKey(
                  'gallery-${c.generation}-detail-${card.id}',
                ),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverPersistentHeader(
                      pinned: true,
                      delegate: _TripsSummaryDelegate(
                        expandedHeight:
                            layout.expandedHeight +
                            metadataHeight +
                            tabsHeight +
                            24,
                        compactHeight: layout.compactHeight + tabsHeight + 24,
                        builder: (progress) => ColoredBox(
                          key: const ValueKey('detail-pinned-header'),
                          color: t.bg,
                          child: Column(
                            children: [
                              SizedBox(
                                height: _detailLerp(
                                  layout.expandedHeight,
                                  layout.compactHeight,
                                  progress,
                                ),
                                child: _GalleryDetailFace(
                                  key: ValueKey('detail-face-${card.id}'),
                                  card: card,
                                  balance: _balancePresentation(card),
                                  layout: layout,
                                  progress: progress,
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
                                      opacity: (1 - progress * 3).clamp(
                                        0.0,
                                        1.0,
                                      ),
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
                                  (index) =>
                                      c.update(() => c.detailTab = index),
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
                      30 + MediaQuery.paddingOf(context).bottom,
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
        ),
      ],
    );
  }

  List<Widget> _cardInformation(GalleryCard card) {
    final raw = c.data.raw[card.id];
    return [
      _panel(
        Column(
          children: [
            for (final row in <(String, String)>[
              ('完整卡号', card.pan),
              ('发卡地', card.city),
              ('卡种', card.type),
              ('有效期', card.valid == '—' ? '未知' : '${card.valid}（未记录日）'),
              ('当前余额', card.balance(c.includeOverdraft)),
              ('最近读取', card.when),
              ('协议', card.type == 'FeliCa' ? 'FeliCa' : 'ISO-DEP / 交通联合'),
            ])
              _kv(row.$1, row.$2),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          key: const ValueKey('detail-raw-header'),
          children: [
            Expanded(child: _text('原始数据', role: GalleryTypography.section)),
            if (raw is Map) ...[
              _icon(
                Icons.copy_outlined,
                '复制原始数据',
                () {
                  Clipboard.setData(
                    ClipboardData(text: '${raw['sfi18']}\n${raw['sfi1e']}'),
                  );
                  _toast('已复制模拟原始数据');
                },
                outlined: false,
                grouped: true,
              ),
              _icon(
                Icons.feedback_outlined,
                '原始数据反馈预览',
                () => c.showOverlay(GalleryOverlay.rawFeedback),
                outlined: false,
                grouped: true,
              ),
            ],
          ],
        ),
      ),
      _text('模拟样例', role: GalleryTypography.caption, color: t.muted),
      _gap(8),
      if (raw is Map)
        _hexBox('SFI 0x18\n${raw['sfi18']}\n\nSFI 0x1E\n${raw['sfi1e']}')
      else
        _text('本样例未保留原始数据', role: GalleryTypography.caption, color: t.muted),
    ];
  }

  Future<void> _selectSpendingPeriod(GallerySpendingPeriod period) async {
    if (period != GallerySpendingPeriod.custom) {
      _updateDetail(
        () => _spendingSelection = GallerySpendingSelection.forPeriod(
          period,
          GalleryController.clock,
        ),
      );
      return;
    }
    final first =
        _spendingSelection.start ?? galleryCalendarDay(GalleryController.clock);
    final last = _spendingSelection.end ?? first;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      currentDate: GalleryController.clock,
      initialDateRange: DateTimeRange(start: first, end: last),
      helpText: '选择消费日期',
      saveText: '确定',
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

  List<Widget> _spendingChildren(GalleryCard card) {
    final summary = GallerySpendingSummary(
      card.currency,
      c.ledger(card),
      selection: _spendingSelection,
    );
    final range = _spendingSelection.start == null
        ? '全部已保留记录'
        : '${_spendingDate(_spendingSelection.start!)} ～ ${_spendingDate(_spendingSelection.end!)}';
    final widgets = <Widget>[
      Wrap(
        key: const ValueKey('spending-periods'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (period, label) in [
            (GallerySpendingPeriod.all, '全部'),
            (GallerySpendingPeriod.week, '本周'),
            (GallerySpendingPeriod.month, '本月'),
            (GallerySpendingPeriod.year, '本年'),
            (GallerySpendingPeriod.custom, '自定义'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _spendingSelection.period == period,
              onSelected: (_) => _selectSpendingPeriod(period),
            ),
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
      _sectionTitle('消费趋势'),
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
                    entry.record['amount'] as String,
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
    final maximum = math.max(
      1,
      buckets.map((entry) => entry.amount).reduce(math.max),
    );
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
      builder: (context, constraints) => SingleChildScrollView(
        key: const PageStorageKey('gallery-spending-chart'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, columnWidth * buckets.length),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (index, bucket) in buckets.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Semantics(
                      label: '${bucket.label}，${summary.format(bucket.amount)}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          _text(
                            summary.format(bucket.amount),
                            role: GalleryTypography.caption,
                          ),
                          _gap(8),
                          Container(
                            height: 120,
                            alignment: Alignment.bottomCenter,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey('spending-bar-$index'),
                              tween: Tween(
                                begin: 0,
                                end: bucket.amount / maximum,
                              ),
                              duration: _reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 260),
                              curve: Curves.easeInOutCubic,
                              builder: (_, value, _) => Container(
                                height: math.max(2, value * 120),
                                decoration: BoxDecoration(
                                  color: t.secondary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          _gap(8),
                          _text(
                            bucket.label,
                            role: GalleryTypography.caption,
                            color: t.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _spendingCategories(GallerySpendingSummary summary) {
    const names = ['轨道交通', '公共汽电车', '其他'];
    final colors = [t.action, t.secondary, t.accent];
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
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        builder: (_, values, child) => CustomPaint(
          painter: _SpendingRingPainter(values, colors, t.surface2),
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
    this.width,
  ) {
    scaler = MediaQuery.textScalerOf(context);
    final compactAmount = _measureDetailText(
      context,
      balance.displayText,
      GalleryTypography.amount,
      double.infinity,
    ).width;
    amountWidth = math.min(width * .46, math.max(80.0, compactAmount));
    compactTitleWidth = math.max(24.0, width - 44 - amountWidth);
    compactTitleHeight = _measureDetailText(
      context,
      card.name,
      GalleryTypography.label.copyWith(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
      ),
      compactTitleWidth,
    ).height;
    compactHeight = math.max(56.0, compactTitleHeight + scaler.scale(18) + 18);
    expandedTitleHeight = _measureDetailText(
      context,
      card.name,
      GalleryTypography.card.copyWith(fontSize: 20, height: 26 / 20),
      math.max(24, width - 40 - (card.type == '交通联合卡' ? 80 : 0)),
    ).height;
    tailWidth = _measureDetailText(
      context,
      '**** ${card.tail}',
      GalleryTypography.label.copyWith(
        fontFamily: 'monospace',
        letterSpacing: .6,
      ),
      double.infinity,
    ).width;
    final numberWidth = _measureDetailText(
      context,
      balance.number,
      GalleryTypography.hero,
      double.infinity,
    ).width;
    final unitWidth =
        _measureDetailText(
          context,
          balance.currencyLabel,
          GalleryTypography.caption,
          double.infinity,
        ).width +
        8;
    stacked =
        numberWidth + unitWidth + tailWidth + 16 > width - 40 ||
        scaler.scale(14) / 14 >= 1.5;
    expandedHeight = math.max(
      204.0 + math.max(0, scaler.scale(14) / 14 - 1) * 80,
      40 +
          expandedTitleHeight +
          32 +
          scaler.scale(44) +
          (stacked ? scaler.scale(18) + 12 : 0),
    );
  }
  final double width;
  late final TextScaler scaler;
  late final double amountWidth,
      compactTitleWidth,
      compactTitleHeight,
      compactHeight,
      expandedHeight,
      expandedTitleHeight,
      tailWidth;
  late final bool stacked;
}

/// One surface and one set of fields move with scroll position; no duplicate card.
class _GalleryDetailFace extends StatefulWidget {
  const _GalleryDetailFace({
    super.key,
    required this.card,
    required this.balance,
    required this.layout,
    required this.progress,
  });
  final GalleryCard card;
  final GalleryBalancePresentation balance;
  final _DetailCardLayout layout;
  final double progress;
  @override
  State<_GalleryDetailFace> createState() => _GalleryDetailFaceState();
}

class _GalleryDetailFaceState extends State<_GalleryDetailFace> {
  static final _palettes = Expando<Map<Brightness, Future<ColorScheme>>>();
  Uint8List? _image;
  Brightness? _brightness;
  ColorScheme? _scheme;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPalette();
  }

  @override
  void didUpdateWidget(_GalleryDetailFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPalette();
  }

  void _loadPalette() {
    final bytes = widget.card.image;
    final brightness = Theme.of(context).brightness;
    if (identical(bytes, _image) && _brightness == brightness) return;
    _image = bytes;
    _brightness = brightness;
    _scheme = null;
    final request = ++_request;
    if (bytes == null) return;
    final cache = _palettes[bytes] ??= {};
    final future = cache[brightness] ??= ColorScheme.fromImageProvider(
      provider: ResizeImage(MemoryImage(bytes), width: 96),
      brightness: brightness,
    );
    future.then(
      (scheme) {
        if (mounted && request == _request) setState(() => _scheme = scheme);
      },
      onError: (Object _, StackTrace _) {
        /* Keep the theme fallback. */
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    final face = GalleryCardFace.byId(widget.card.face);
    final target = widget.card.image == null
        ? face.end
        : _scheme?.primaryContainer ?? tokens.tone;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      builder: (context, capsuleColor, _) {
        final p = widget.progress;
        final card = widget.card;
        final layout = widget.layout;
        final balance = widget.balance;
        final foreground = Color.lerp(
          card.image == null
              ? face.foreground
              : GalleryCardFace.imageForeground,
          card.image == null
              ? face.foreground
              : _scheme?.onPrimaryContainer ?? tokens.onTone,
          p,
        )!;
        final secondary = Color.lerp(
          card.image == null
              ? face.secondaryForeground
              : GalleryCardFace.imageSecondaryForeground,
          foreground,
          p,
        )!;
        final nameStyle = TextStyle.lerp(
          GalleryTypography.card.copyWith(fontSize: 20, height: 26 / 20),
          GalleryTypography.label.copyWith(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w600,
          ),
          p,
        )!.copyWith(color: foreground);
        final numberStyle =
            TextStyle.lerp(
              GalleryTypography.hero,
              GalleryTypography.amount,
              p,
            )!.copyWith(
              color: foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
        final unitStyle = GalleryTypography.caption.copyWith(color: secondary);
        final height = _detailLerp(
          layout.expandedHeight,
          layout.compactHeight,
          p,
        );
        final expandedNumberTop =
            layout.expandedHeight -
            20 -
            layout.scaler.scale(44) -
            (layout.stacked ? layout.scaler.scale(18) + 12 : 0);
        final compactNumberTop =
            (layout.compactHeight - layout.scaler.scale(26)) / 2;
        final numberLeft = _detailLerp(
          20,
          layout.width - 16 - layout.amountWidth,
          p,
        );
        final expandedAmountWidth = math.max(
          1.0,
          layout.width - 40 - (layout.stacked ? 0 : layout.tailWidth + 16),
        );
        final nameWidth = _detailLerp(
          math.max(24.0, layout.width - 40 - (card.type == '交通联合卡' ? 80 : 0)),
          layout.compactTitleWidth,
          p,
        );
        final tailCompact = p >= .5;
        return Container(
          key: ValueKey('card-face-${card.id}'),
          width: double.infinity,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_detailLerp(22, 28, p)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(face.start, capsuleColor, p)!,
                Color.lerp(face.end, capsuleColor, p)!,
              ],
            ),
            image: card.image == null
                ? null
                : DecorationImage(
                    image: MemoryImage(card.image!),
                    fit: BoxFit.cover,
                    opacity: 1 - p,
                    colorFilter: const ColorFilter.mode(
                      Color(0x99070c16),
                      BlendMode.darken,
                    ),
                  ),
            border: Border.all(color: tokens.line.withValues(alpha: .3)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: _detailLerp(20, 16, p),
                top: _detailLerp(20, 9, p),
                width: nameWidth,
                child: Text(
                  card.name,
                  key: ValueKey('face-title-${card.id}'),
                  style: nameStyle,
                ),
              ),
              if (card.type == '交通联合卡')
                Positioned(
                  top: 20,
                  right: 20,
                  child: Opacity(
                    opacity: (1 - p * 3).clamp(0.0, 1.0),
                    child: SvgPicture.asset(
                      'assets/gallery/tunion-logo.svg',
                      width: 68,
                      height: 68 * 49 / 78,
                      semanticsLabel: '交通联合 CHINA T-UNION',
                    ),
                  ),
                ),
              Positioned(
                left: numberLeft,
                top: _detailLerp(expandedNumberTop, compactNumberTop, p),
                width: _detailLerp(expandedAmountWidth, layout.amountWidth, p),
                child: Semantics(
                  label: '余额，${balance.displayText}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.lerp(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      p,
                    )!,
                    child: balance.known
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              if (balance.currencyLabel.isNotEmpty) ...[
                                Text(
                                  balance.currencyLabel,
                                  key: ValueKey('face-currency-${card.id}'),
                                  style: unitStyle,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                balance.number,
                                key: ValueKey('face-number-${card.id}'),
                                style: numberStyle,
                              ),
                            ],
                          )
                        : Text(
                            balance.displayText,
                            key: ValueKey('face-unknown-${card.id}'),
                            style: unitStyle,
                          ),
                  ),
                ),
              ),
              Positioned(
                left: tailCompact ? 16 : null,
                right: tailCompact ? null : 20,
                top: tailCompact ? 9 + layout.compactTitleHeight : null,
                bottom: tailCompact ? null : 20,
                width: tailCompact
                    ? layout.compactTitleWidth
                    : layout.tailWidth + 2,
                child: Opacity(
                  opacity: tailCompact
                      ? ((p - .65) / .35).clamp(0.0, 1.0)
                      : (1 - p / .35).clamp(0.0, 1.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: tailCompact
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Text(
                      '**** ${card.tail}',
                      key: ValueKey('face-tail-${card.id}'),
                      maxLines: 1,
                      softWrap: false,
                      style: GalleryTypography.caption.copyWith(
                        fontFamily: 'monospace',
                        color: secondary,
                      ),
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
