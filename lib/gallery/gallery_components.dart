part of 'gallery_app.dart';

/// Recolors the original two-color artwork without tinting its entire bitmap.
class _GalleryBrandColors extends ColorMapper {
  const _GalleryBrandColors(this.foreground, this.background);
  final Color foreground, background;
  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => color == const Color(0xff4e7098) ? foreground : background;
  @override
  bool operator ==(Object other) =>
      other is _GalleryBrandColors &&
      other.foreground == foreground &&
      other.background == background;
  @override
  int get hashCode => Object.hash(foreground, background);
}

extension _GalleryComponents on _GalleryViewState {
  double get _extraTextScale =>
      math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1);
  Widget _text(
    String value, {
    double? size,
    TextStyle role = GalleryTypography.body,
    Color? color,
    FontWeight? weight,
    double? height,
    int? lines,
    TextAlign? align,
    bool mono = false,
  }) => Text(
    value,
    maxLines: lines,
    overflow: lines == null ? null : TextOverflow.ellipsis,
    textAlign: align,
    style: role.copyWith(
      fontSize: size,
      height: height,
      color: color ?? t.text,
      fontWeight: weight,
      fontFamily: mono ? 'monospace' : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  Widget _gap([double value = 12]) => SizedBox(height: value);
  Widget _panel(
    Widget child, {
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    Color? color,
    double radius = 18,
    bool border = true,
    GalleryElevation elevation = GalleryElevation.card,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: t.shadows(elevation),
    ),
    child: Material(
      color: color ?? t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border ? BorderSide(color: t.line) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );

  Widget _header(
    String title, {
    String? subtitle,
    bool back = false,
    List<Widget>? actions,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              if (back) ...[
                _icon(Icons.arrow_back_rounded, '返回', c.back),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: _text(title, role: GalleryTypography.page),
                ),
              ),
              ...?actions,
              if (actions == null && !back)
                _icon(
                  Icons.settings_outlined,
                  '设置',
                  () => c.navigate(GalleryPage.settings),
                ),
            ],
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _text(
              subtitle,
              role: GalleryTypography.caption,
              color: t.muted,
              height: 20 / 12,
            ),
          ),
      ],
    ),
  );

  Widget _icon(
    IconData icon,
    String label,
    VoidCallback action, {
    Color? color,
    Color? background,
    double size = 44,
  }) => SizedBox(
    width: size,
    height: size,
    child: IconButton(
      onPressed: action,
      tooltip: label,
      style: IconButton.styleFrom(
        side: BorderSide(color: t.line),
        shape: const CircleBorder(),
        foregroundColor: color ?? t.muted,
        backgroundColor: background,
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 21),
    ),
  );

  Widget _button(
    String label,
    VoidCallback? action, {
    IconData? icon,
    bool primary = false,
    bool danger = false,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      backgroundColor: WidgetStatePropertyAll(primary ? t.action : t.surface),
      foregroundColor: WidgetStatePropertyAll(
        danger
            ? t.danger
            : primary
            ? t.onAction
            : t.onTone,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: primary ? Colors.transparent : t.line),
      ),
      shape: const WidgetStatePropertyAll(GalleryGeometry.buttonShape),
      textStyle: const WidgetStatePropertyAll(GalleryTypography.button),
    );
    return TextButton(
      onPressed: action,
      style: style,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _chip(String label, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: t.secondaryContainer,
      borderRadius: BorderRadius.circular(30),
    ),
    child: _text(
      label,
      role: GalleryTypography.caption,
      height: 18 / 11,
      color: color ?? t.onSecondaryContainer,
      weight: FontWeight.w500,
    ),
  );

  Widget _sectionTitle(String title, {String? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _text(title, role: GalleryTypography.section),
        if (trailing != null)
          _text(trailing, role: GalleryTypography.caption, color: t.muted),
      ],
    ),
  );

  Widget _kv(
    String label,
    String? value, {
    double labelWidth = 112,
  }) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: t.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: math.min(labelWidth, MediaQuery.sizeOf(context).width * .35),
          child: _text(label, role: GalleryTypography.label, color: t.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _text(
            value ?? '未知',
            role: GalleryTypography.field,
            align: TextAlign.right,
          ),
        ),
      ],
    ),
  );

  Widget _empty(
    String title,
    String subtitle, {
    IconData icon = Icons.credit_card_outlined,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 40, color: t.onTone),
        _gap(16),
        _text(
          title,
          role: GalleryTypography.card,
          weight: FontWeight.w600,
          align: TextAlign.center,
        ),
        _gap(8),
        _text(
          subtitle,
          role: GalleryTypography.label,
          color: t.muted,
          align: TextAlign.center,
        ),
        if (action != null) ...[_gap(18), action],
      ],
    ),
  );

  Widget _tabs(
    List<String> labels,
    int selected,
    ValueChanged<int> onSelected, {
    bool scroll = false,
    String? id,
  }) {
    Widget button(int i) => Padding(
      padding: const EdgeInsets.all(3),
      child: Semantics(
        selected: selected == i,
        child: TextButton(
          onPressed: () => onSelected(i),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            backgroundColor: Colors.transparent,
            foregroundColor: selected == i ? t.onTone : t.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: GalleryTypography.label,
          ),
          child: Text(labels[i], textAlign: TextAlign.center),
        ),
      ),
    );
    Widget track(List<double> widths) => Stack(
      children: [
        AnimatedPositionedDirectional(
          duration: _reduceMotion ? Duration.zero : _GalleryMotion.capsule,
          curve: _GalleryMotion.curve,
          start: widths.take(selected).fold(0.0, (a, b) => a + b) + 3,
          top: 3,
          bottom: 3,
          width: widths[selected] - 6,
          child: IgnorePointer(
            child: DecoratedBox(
              key: ValueKey('segments-${id ?? labels.first}-indicator'),
              decoration: BoxDecoration(
                color: t.tone,
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
        Row(
          children: List.generate(
            labels.length,
            (i) => SizedBox(width: widths[i], child: button(i)),
          ),
        ),
      ],
    );
    // Scrollable segments keep their natural text widths. The same indicator
    // moves across both equal-width and scrolling tracks without replacing it.
    final naturalWidths = scroll
        ? labels.map((label) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: GalleryTypography.label),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width.ceilToDouble() + 32;
            painter.dispose();
            return width;
          }).toList()
        : <double>[];
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final next = key == LogicalKeyboardKey.arrowRight
            ? (selected + 1) % labels.length
            : key == LogicalKeyboardKey.arrowLeft
            ? (selected + labels.length - 1) % labels.length
            : key == LogicalKeyboardKey.home
            ? 0
            : key == LogicalKeyboardKey.end
            ? labels.length - 1
            : null;
        if (next == null) return KeyEventResult.ignored;
        onSelected(next);
        return KeyEventResult.handled;
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.segmentTrack,
          borderRadius: BorderRadius.circular(16),
        ),
        child: scroll
            ? SingleChildScrollView(
                key: id == null
                    ? null
                    : PageStorageKey('gallery-${c.generation}-$id'),
                scrollDirection: Axis.horizontal,
                child: track(naturalWidths),
              )
            : LayoutBuilder(
                builder: (context, constraints) => track(
                  List.filled(
                    labels.length,
                    constraints.maxWidth / labels.length,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _amount(GalleryCard card, {double size = 36, Color? color}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final value = card.balance(c.includeOverdraft);
          return Semantics(
            label: card.unknownBalance ? '余额暂不可用' : '余额 $value',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _text(
                card.unknownBalance ? '余额暂不可用' : value,
                size: card.unknownBalance
                    ? math.min(size, 19)
                    : value.length > 11
                    ? size * .78
                    : size,
                weight: FontWeight.w600,
                color: color,
                height: 1.2,
              ),
            ),
          );
        },
      );

  List<Color> _faceColors(String face) {
    final palette = GalleryCardFace.byId(face);
    return [palette.start, palette.end];
  }

  GalleryBalancePresentation _balancePresentation(GalleryCard card) =>
      GalleryBalancePresentation.parse(
        card.balance(c.includeOverdraft),
        currencyCode: card.currency?.name.toUpperCase(),
      );

  Size _measureText(String value, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  Widget _face(
    GalleryCard card, {
    bool miniature = false,
    bool minimal = false,
  }) => Container(
    key: ValueKey('${miniature ? 'card-thumbnail' : 'card-face'}-${card.id}'),
    height: miniature ? 60 / (85.60 / 53.98) : null,
    constraints: miniature
        ? null
        : BoxConstraints(minHeight: 204 + _extraTextScale * 80),
    width: miniature ? 60 : double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(miniature ? 8 : 22),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _faceColors(card.face),
      ),
      image: card.image == null
          ? null
          : DecorationImage(
              image: AssetImage(card.image!),
              fit: BoxFit.cover,
              colorFilter: const ColorFilter.mode(
                Color(0x99070c16),
                BlendMode.darken,
              ),
            ),
      border: Border.all(color: const Color(0x29ffffff)),
    ),
    child: miniature
        ? Center(
            child: Icon(
              Icons.contactless_outlined,
              size: 20,
              color: GalleryCardFace.byId(card.face).secondaryForeground,
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final face = GalleryCardFace.byId(card.face);
                final balance = _balancePresentation(card);
                final numberStyle = GalleryTypography.hero.copyWith(
                  inherit: false,
                  color: face.foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
                final unitStyle = GalleryTypography.caption.copyWith(
                  inherit: false,
                  color: face.secondaryForeground,
                );
                final tailStyle = GalleryTypography.label.copyWith(
                  inherit: false,
                  fontFamily: 'monospace',
                  letterSpacing: .6,
                  color: face.secondaryForeground,
                );
                final tailText = '**** ${card.tail}';
                final amountWidth = balance.known
                    ? _measureText(balance.number, numberStyle).width +
                          (balance.currencyLabel.isEmpty
                              ? 0
                              : _measureText(
                                      balance.currencyLabel,
                                      unitStyle,
                                    ).width +
                                    8)
                    : _measureText(balance.displayText, unitStyle).width;
                final stacked =
                    _extraTextScale >= .5 ||
                    amountWidth + 16 + _measureText(tailText, tailStyle).width >
                        constraints.maxWidth;
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
                              if (balance.currencyLabel.isNotEmpty) ...[
                                Text(
                                  balance.currencyLabel,
                                  key: ValueKey('face-currency-${card.id}'),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: unitStyle,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                balance.number,
                                key: ValueKey('face-number-${card.id}'),
                                maxLines: 1,
                                softWrap: false,
                                style: numberStyle,
                              ),
                            ],
                          )
                        : Text(
                            balance.displayText,
                            key: ValueKey('face-unknown-${card.id}'),
                            style: GalleryTypography.section.copyWith(
                              color: face.secondaryForeground,
                            ),
                          ),
                  ),
                );
                final tail = Text(
                  tailText,
                  key: ValueKey('face-tail-${card.id}'),
                  style: tailStyle,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            card.name,
                            key: ValueKey('face-title-${card.id}'),
                            style: GalleryTypography.card.copyWith(
                              fontSize: 20,
                              height: 26 / 20,
                              color: face.foreground,
                            ),
                          ),
                        ),
                        if (card.type == '交通联合卡') ...[
                          const SizedBox(width: 12),
                          SvgPicture.asset(
                            'assets/gallery/tunion-logo.svg',
                            width: 68,
                            height: 68 * 49 / 78,
                            semanticsLabel: '交通联合 CHINA T-UNION',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 32),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!minimal) ...[
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '当前余额',
                                key: ValueKey('face-balance-label-${card.id}'),
                                style: unitStyle,
                              ),
                              Text('最近读取 ${card.when}', style: unitStyle),
                            ],
                          ),
                          _gap(4),
                        ],
                        if (stacked)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: amount,
                              ),
                              _gap(12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: tail,
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: amount,
                                ),
                              ),
                              const SizedBox(width: 16),
                              tail,
                            ],
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
  );

  Widget _navigation() {
    const pages = GalleryController.visibleMainPages;
    const names = ['首页', '行程', '专家', '卡包'];
    const icons = [
      Icons.home_outlined,
      Icons.route_outlined,
      Icons.science_outlined,
      Icons.credit_card_outlined,
    ];
    final selectedIndex = pages.indexOf(c.mainPage);
    final layout = _navLayout;
    final bar = Container(
      height: layout.contentHeight,
      padding: EdgeInsets.fromLTRB(
        c.docked ? 8 : 5,
        c.docked ? 4 : 5,
        c.docked ? 8 : 5,
        c.docked ? 0 : 5,
      ),
      decoration: BoxDecoration(
        color: c.docked ? t.surface2 : t.surface.withValues(alpha: .78),
        borderRadius: c.docked
            ? null
            : BorderRadius.circular(31 + _extraTextScale * 10),
        border: c.docked ? null : Border.all(color: t.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = c.docked ? 0.0 : 5.0;
          final itemWidth =
              (constraints.maxWidth - gap * (pages.length - 1)) / pages.length;
          return Stack(
            children: [
              if (!c.docked && selectedIndex >= 0)
                AnimatedPositioned(
                  duration: _reduceMotion
                      ? Duration.zero
                      : _GalleryMotion.capsule,
                  curve: _GalleryMotion.curve,
                  left: selectedIndex * (itemWidth + gap),
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('nav-capsule'),
                      decoration: BoxDecoration(
                        color: t.tone,
                        borderRadius: BorderRadius.circular(
                          25 + _extraTextScale * 10,
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < pages.length; i++) ...[
                    if (i > 0 && !c.docked) const SizedBox(width: 5),
                    Expanded(
                      child: _GalleryNavigationItem(
                        key: ValueKey('nav-${pages[i].name}'),
                        label: names[i],
                        icon: icons[i],
                        selected: selectedIndex == i,
                        docked: c.docked,
                        tokens: t,
                        reduceMotion: _reduceMotion,
                        onTap: () => c.navigate(pages[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
    if (c.docked) {
      return ColoredBox(
        key: const ValueKey('gallery-docked-bar'),
        color: t.surface2,
        child: Padding(
          padding: EdgeInsets.only(bottom: layout.bottomSpace),
          child: bar,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: layout.bottomSpace),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(31 + _extraTextScale * 10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: bar,
          ),
        ),
      ),
    );
  }

  Widget _hexBox(String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.surface2,
      borderRadius: BorderRadius.circular(14),
    ),
    child: SelectionArea(
      child: Text(
        value,
        style: GalleryTypography.caption.copyWith(
          fontFamily: 'monospace',
          color: t.text,
        ),
      ),
    ),
  );

  Widget _expand(
    String id,
    String title,
    List<Widget> children, {
    bool initiallyOpen = false,
    bool surface = true,
  }) {
    final open =
        c.expanded.contains(id) ||
        initiallyOpen && !c.expanded.contains('closed:$id');
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => c.update(() {
            if (open) {
              c.expanded.remove(id);
              c.expanded.add('closed:$id');
            } else {
              c.expanded.remove('closed:$id');
              c.expanded.add(id);
            }
          }),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: surface ? 16 : 2,
              vertical: 14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _text(
                    title,
                    role: GalleryTypography.label,
                    weight: FontWeight.w600,
                  ),
                ),
                _expandArrow(open),
              ],
            ),
          ),
        ),
        _collapse(
          open,
          (_) => Padding(
            padding: EdgeInsets.fromLTRB(
              surface ? 16 : 0,
              0,
              surface ? 16 : 0,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: surface ? _panel(body, padding: EdgeInsets.zero) : body,
    );
  }
}

/// Keep the segment strip mounted while restoring each pane's scroll offset.
class _GalleryTabbedList extends StatefulWidget {
  const _GalleryTabbedList({
    super.key,
    required this.listKey,
    required this.positionId,
    required this.padding,
    required this.children,
  });
  final PageStorageKey<String> listKey;
  final String positionId;
  final EdgeInsets padding;
  final List<Widget> children;

  @override
  State<_GalleryTabbedList> createState() => _GalleryTabbedListState();
}

class _GalleryTabbedListState extends State<_GalleryTabbedList> {
  late final ScrollController _scroll;
  PageStorageBucket? _bucket;
  final Map<String, double> _offsets = {};
  bool _ready = false, _restoring = false;
  ValueKey<String> get _storageKey =>
      ValueKey('offsets-${widget.listKey.value}');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bucket = PageStorage.maybeOf(context);
    if (_ready) return;
    _ready = true;
    final saved = _bucket?.readState(context, identifier: _storageKey);
    if (saved is Map<String, double>) _offsets.addAll(saved);
    _scroll = ScrollController(
      keepScrollOffset: false,
      initialScrollOffset: _offsets[widget.positionId] ?? 0,
    );
  }

  void _remember(String positionId) {
    if (_restoring || !_scroll.hasClients) return;
    _offsets[positionId] = _scroll.offset;
    _bucket?.writeState(
      context,
      Map<String, double>.of(_offsets),
      identifier: _storageKey,
    );
  }

  @override
  void didUpdateWidget(_GalleryTabbedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positionId == oldWidget.positionId) return;
    _remember(oldWidget.positionId);
    _restoring = true;
    final target = widget.positionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || target != widget.positionId || !_scroll.hasClients) {
        return;
      }
      // The outgoing crossfade can be taller than the incoming content. During
      // that overlap the stored incoming offset is still a valid scroll target.
      _scroll.jumpTo(
        (_offsets[target] ?? 0).clamp(0.0, _scroll.position.maxScrollExtent),
      );
      _restoring = false;
    });
  }

  @override
  void deactivate() {
    _remember(widget.positionId);
    super.deactivate();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: widget.listKey,
    controller: _scroll,
    padding: widget.padding,
    children: widget.children,
  );
}
