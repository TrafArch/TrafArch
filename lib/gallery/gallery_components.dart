part of 'gallery_app.dart';

extension _GalleryComponents on _GalleryViewState {
  double get _extraTextScale =>
      math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1);
  Widget _text(
    String value, {
    double size = 14.5,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
    int? lines,
    TextAlign? align,
    bool mono = false,
  }) => Text(
    value,
    maxLines: lines,
    overflow: lines == null ? null : TextOverflow.ellipsis,
    textAlign: align,
    style: TextStyle(
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
  }) => Material(
    color: color ?? t.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? BorderSide(color: t.line) : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
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
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (back) ...[
                _icon(Icons.arrow_back_rounded, '返回', c.back),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: _text(
                    title,
                    size: 23,
                    height: 28 / 23,
                    weight: FontWeight.w700,
                  ),
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
            child: _text(subtitle, size: 12, color: t.muted, height: 20 / 12),
          ),
      ],
    ),
  );

  Widget _icon(
    IconData icon,
    String label,
    VoidCallback action, {
    Color? color,
  }) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      onPressed: action,
      tooltip: label,
      style: IconButton.styleFrom(
        side: BorderSide(color: t.line),
        shape: const CircleBorder(),
        foregroundColor: color ?? t.muted,
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
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600),
      ),
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
      color: t.tone,
      borderRadius: BorderRadius.circular(30),
    ),
    child: _text(
      label,
      size: 11,
      height: 18 / 11,
      color: color ?? t.onTone,
      weight: FontWeight.w500,
    ),
  );

  Widget _sectionTitle(String title, {String? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
    child: Row(
      children: [
        Expanded(child: _text(title, size: 14, weight: FontWeight.w600)),
        if (trailing != null) _text(trailing, size: 11, color: t.muted),
      ],
    ),
  );

  Widget _kv(String label, String? value, {double labelWidth = 112}) =>
      Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: math.min(
                labelWidth,
                MediaQuery.sizeOf(context).width * .35,
              ),
              child: _text(label, size: 12, color: t.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _text(
                value ?? '未知',
                size: 12,
                weight: FontWeight.w500,
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
          size: 17,
          weight: FontWeight.w600,
          align: TextAlign.center,
        ),
        _gap(8),
        _text(subtitle, size: 13, color: t.muted, align: TextAlign.center),
        if (action != null) ...[_gap(18), action],
      ],
    ),
  );

  Widget _tabs(
    List<String> labels,
    int selected,
    ValueChanged<int> onSelected, {
    bool scroll = false,
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
            backgroundColor: selected == i ? t.tone : Colors.transparent,
            foregroundColor: selected == i ? t.onTone : t.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Text(labels[i], textAlign: TextAlign.center),
        ),
      ),
    );
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
          color: t.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: scroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: List.generate(labels.length, button)),
              )
            : Row(
                children: List.generate(
                  labels.length,
                  (i) => Expanded(child: button(i)),
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
                weight: FontWeight.w700,
                color: color,
                height: 1.2,
              ),
            ),
          );
        },
      );

  List<Color> _faceColors(String face) => switch (face) {
    'teal' => [const Color(0xff1d5955), const Color(0xff102f36)],
    'graphite' => [const Color(0xff434c59), const Color(0xff202733)],
    'amber' => [const Color(0xff73532d), const Color(0xff302b24)],
    _ => [const Color(0xff355777), const Color(0xff182d48)],
  };

  Widget _face(GalleryCard card, {bool miniature = false}) => Container(
    height: miniature ? 44 : 204 + _extraTextScale * 80,
    width: miniature ? 66 : double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(miniature ? 11 : 22),
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
              size: 24,
              color: const Color(0xffc5d7e8),
            ),
          )
        : Stack(
            children: [
              Positioned(
                top: 18,
                left: 18,
                right: 108,
                child: _text(
                  card.name,
                  size: 17,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (card.type == '交通联合卡')
                Positioned(
                  top: 17,
                  right: 16,
                  child: SvgPicture.asset(
                    'assets/gallery/tunion-logo.svg',
                    width: 78,
                    height: 49,
                    semanticsLabel: '交通联合 CHINA T-UNION',
                  ),
                ),
              Positioned(
                left: 18,
                bottom: 60,
                child: _text(
                  '**** ${card.tail}',
                  size: 13,
                  color: const Color(0xffacc1df),
                  mono: true,
                ),
              ),
              Positioned(
                left: 18,
                bottom: 18,
                right: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(
                            '当前余额',
                            size: 11,
                            color: const Color(0xffacc1df),
                          ),
                          _gap(4),
                          _amount(card, size: 34, color: Colors.white),
                        ],
                      ),
                    ),
                    _text(
                      '最近读取\n${card.when}',
                      size: 10,
                      color: const Color(0xffacc1df),
                      align: TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
  );

  Widget _navigation() {
    const names = ['首页', '行程', '专家', '卡包', '足迹'];
    const icons = [
      Icons.home_outlined,
      Icons.route_outlined,
      Icons.science_outlined,
      Icons.credit_card_outlined,
      Icons.location_on_outlined,
    ];
    final inset = MediaQuery.paddingOf(context).bottom;
    final bar = Container(
      height: c.docked
          ? 64 + inset + _extraTextScale * 20
          : 62 + _extraTextScale * 20,
      padding: EdgeInsets.fromLTRB(
        c.docked ? 8 : 5,
        c.docked ? 4 : 5,
        c.docked ? 8 : 5,
        c.docked ? inset : 5,
      ),
      decoration: BoxDecoration(
        color: c.docked ? t.surface2 : t.surface.withValues(alpha: .97),
        borderRadius: c.docked ? null : BorderRadius.circular(31),
        border: c.docked ? null : Border.all(color: t.line),
        boxShadow: c.docked
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        children: List.generate(
          5,
          (i) => Expanded(
            child: Semantics(
              selected: c.page.index == i,
              child: TextButton(
                key: ValueKey('nav-${GalleryPage.values[i].name}'),
                onPressed: () => c.navigate(GalleryPage.values[i]),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  foregroundColor: c.page.index == i ? t.onTone : t.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: c.docked ? 28 : 26,
                      decoration: BoxDecoration(
                        color: c.page.index == i ? t.tone : Colors.transparent,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(icons[i], size: c.docked ? 22 : 20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names[i],
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: c.page.index == i
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (c.docked) return bar;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: 18 + inset),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 352),
        child: bar,
      ),
    );
  }

  Widget _hexBox(String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xff171c23),
      borderRadius: BorderRadius.circular(14),
    ),
    child: SelectionArea(
      child: Text(
        value,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.9,
          color: Color(0xffd2dae4),
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
                  child: _text(title, size: 13, weight: FontWeight.w600),
                ),
                Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
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
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: surface ? _panel(body, padding: EdgeInsets.zero) : body,
    );
  }
}
