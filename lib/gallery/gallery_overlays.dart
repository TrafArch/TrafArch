part of 'gallery_app.dart';

extension _GalleryOverlays on _GalleryViewState {
  List<Widget> _overlay() {
    final type = _entry.overlay!;
    final nameForm =
        type == GalleryOverlay.save || type == GalleryOverlay.rename;
    if (type == GalleryOverlay.cardMenu ||
        type == GalleryOverlay.source ||
        type == GalleryOverlay.mode) {
      return _dropdownOverlay(type);
    }
    final sheet = [
      GalleryOverlay.face,
      GalleryOverlay.trip,
      GalleryOverlay.export,
      GalleryOverlay.rawFeedback,
    ].contains(type);
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(
            0.0,
            constraints.maxHeight - MediaQuery.paddingOf(context).bottom,
          );
          final gap = available < 240 ? 0.0 : 16.0;
          return Align(
            alignment: sheet ? Alignment.bottomCenter : Alignment.center,
            child: SafeArea(
              top: true,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sheet ? 0 : 16,
                  gap,
                  sheet ? 0 : 16,
                  sheet ? 0 : gap,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: sheet ? 520 : 360,
                    maxHeight: math.max(
                      0.0,
                      math.min(
                        available * .86,
                        available - gap * (sheet ? 1 : 2),
                      ),
                    ),
                  ),
                  child: FocusScope(
                    autofocus: true,
                    child: Focus(
                      autofocus:
                          type != GalleryOverlay.save &&
                          type != GalleryOverlay.rename,
                      skipTraversal: true,
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          c.back();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: FocusTraversalGroup(
                        child: Semantics(
                          scopesRoute: true,
                          namesRoute: true,
                          label: _overlayTitle(type),
                          explicitChildNodes: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(sheet ? 26 : 24),
                                bottom: Radius.circular(sheet ? 0 : 24),
                              ),
                              boxShadow: t.shadows(GalleryElevation.modal),
                            ),
                            child: Material(
                              color: t.raised,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: t.line),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(sheet ? 26 : 24),
                                  bottom: Radius.circular(sheet ? 0 : 24),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                padding: EdgeInsets.all(nameForm ? 18 : 22),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _text(
                                            _overlayTitle(type),
                                            role: GalleryTypography.section,
                                            weight: FontWeight.w600,
                                          ),
                                        ),
                                        IconButton(
                                          autofocus:
                                              type != GalleryOverlay.save &&
                                              type != GalleryOverlay.rename,
                                          tooltip: '关闭',
                                          onPressed: c.back,
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 21,
                                          ),
                                        ),
                                      ],
                                    ),
                                    _gap(nameForm ? 8 : 12),
                                    _overlayBody(type),
                                  ],
                                ),
                              ),
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
        },
      ),
    ];
  }

  String _overlayTitle(GalleryOverlay type) => switch (type) {
    GalleryOverlay.save => '保存卡片',
    GalleryOverlay.face => '更换卡面',
    GalleryOverlay.trip => '行程详情',
    GalleryOverlay.cardMenu => '卡片管理',
    GalleryOverlay.rename => '重命名',
    GalleryOverlay.delete => '删除本卡',
    GalleryOverlay.source => '记录来源',
    GalleryOverlay.mode => '交通方式',
    GalleryOverlay.export => _entry.exportTitle,
    GalleryOverlay.rawFeedback => '反馈内容预览',
  };

  Widget _overlayBody(GalleryOverlay type) => switch (type) {
    GalleryOverlay.save => _GalleryNameForm(
      key: ValueKey('save-${c.generation}'),
      initialName: c.current.name,
      onCancel: c.back,
      onSubmit: (name) {
        c.save(name);
        _toast('已保存到卡包');
      },
    ),
    GalleryOverlay.rename => _GalleryNameForm(
      key: ValueKey('rename-${_selectedCard.id}-${c.generation}'),
      initialName: _selectedCard.name,
      onCancel: c.back,
      onSubmit: (name) {
        c.rename(name);
        _toast('已更新模拟卡片名称');
      },
    ),
    GalleryOverlay.delete => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text('删除“${_selectedCard.name}”及其本次会话记录？', size: 14),
        _gap(8),
        _text('仅影响当前内存样例。', role: GalleryTypography.caption, color: t.muted),
        _gap(22),
        Row(
          children: [
            Expanded(child: _button('取消', c.back)),
            const SizedBox(width: 10),
            Expanded(
              child: _button('删除', () {
                _deleteWalletCard(_selectedCard);
              }, danger: true),
            ),
          ],
        ),
      ],
    ),
    GalleryOverlay.cardMenu ||
    GalleryOverlay.source ||
    GalleryOverlay.mode => Column(children: _dropdownItems(type)),
    GalleryOverlay.face => _faceSheet(),
    GalleryOverlay.trip => _tripSheet(),
    GalleryOverlay.export => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text('内容预览 · 尚未保存文件', role: GalleryTypography.caption, color: t.warn),
        _gap(14),
        _hexBox(_entry.exportText),
        _gap(14),
        _button('关闭预览', c.back, primary: true),
      ],
    ),
    GalleryOverlay.rawFeedback => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text(
          '反馈草稿保留在本页，不会自动提交。',
          role: GalleryTypography.label,
          color: t.muted,
        ),
        _gap(14),
        _hexBox(
          'TrafArch 新界面 beta\n设计版本：2.4.0\n场景：${c.sceneId ?? c.page.name}\n数据：内置样例\n\n请描述看到的问题、操作步骤和期望结果。',
        ),
        _gap(14),
        _button('关闭预览', c.back, primary: true),
      ],
    ),
  };

  List<Widget> _dropdownOverlay(GalleryOverlay type) {
    final cardMenu = type == GalleryOverlay.cardMenu;
    final anchor = cardMenu
        ? 'card-${_selectedCard.id}'
        : 'filter-${type.name}';
    final radius = BorderRadius.circular(cardMenu ? 14 : 12);
    final geometry = _GalleryMenuGeometry(alignEnd: cardMenu);
    return [
      Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _GalleryMenuLayout(
            anchor: _entry.anchorId != null
                ? _menuBounds(_entry.anchorId!)
                : _entry.anchor ?? _menuBounds(anchor),
            geometry: geometry,
            alignEnd: cardMenu,
            width: (cardMenu ? 158 : 170) * (1 + _extraTextScale),
            bottomInset: MediaQuery.paddingOf(context).bottom,
          ),
          child: _GalleryMenuTransition(
            geometry: geometry,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: _overlayTitle(type),
              explicitChildNodes: true,
              child: _dropdownFocus(
                FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.arrowDown):
                          NextFocusIntent(),
                      SingleActivator(LogicalKeyboardKey.arrowUp):
                          PreviousFocusIntent(),
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: t.shadows(GalleryElevation.floating),
                      ),
                      child: Material(
                        key: const ValueKey('gallery-dropdown'),
                        color: t.raised,
                        shape: RoundedRectangleBorder(borderRadius: radius),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          primary: false,
                          padding: EdgeInsets.all(cardMenu ? 6 : 5),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, item) in _dropdownItems(
                                type,
                              ).indexed) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    color: t.line,
                                    indent: 10,
                                    endIndent: 10,
                                  ),
                                item,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _dropdownFocus(Widget child) => FocusScope(
    autofocus: true,
    child: Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          c.back();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    ),
  );

  List<Widget> _dropdownItems(GalleryOverlay type) {
    if (type == GalleryOverlay.cardMenu) {
      return [
        _dropdownItem(
          '重命名',
          () => c.showOverlay(GalleryOverlay.rename),
          icon: Icons.edit_outlined,
        ),
        _dropdownItem(
          '更改卡面',
          () => c.showOverlay(GalleryOverlay.face),
          icon: Icons.palette_outlined,
        ),
        _dropdownItem(
          '删除本卡',
          () => c.showOverlay(GalleryOverlay.delete),
          icon: Icons.delete_outline_rounded,
          danger: true,
        ),
      ];
    }
    final source = type == GalleryOverlay.source;
    final selected = source ? c.source : c.mode;
    return (c.data.json[source ? 'sources' : 'modes'] as List)
        .cast<String>()
        .map(
          (value) => _dropdownItem(
            value,
            () => c.update(() {
              if (source) {
                c.source = value;
              } else {
                c.mode = value;
              }
              c.overlay = null;
            }),
            selected: value == selected,
          ),
        )
        .toList();
  }

  Widget _dropdownItem(
    String label,
    VoidCallback action, {
    IconData? icon,
    bool selected = false,
    bool danger = false,
  }) {
    final color = danger
        ? t.danger
        : selected
        ? t.onTone
        : t.text;
    return Semantics(
      selected: icon == null ? selected : null,
      child: TextButton(
        key: ValueKey('menu-option-$label'),
        onPressed: action,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 42),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          foregroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: danger ? t.danger : t.muted),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: _text(label, role: GalleryTypography.body, color: color),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 14, color: t.control),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tripSheet() {
    final trip = _entry.trip;
    if (trip == null) return _text('暂无可用行程信息', color: t.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _trip(trip, interactive: false),
        const Divider(),
        _kv('日期', trip['isoDate'] as String? ?? trip['date'] as String?),
        _kv(
          '记录来源',
          ((trip['sources'] as List?) ?? [trip['source'] ?? '未记录']).join(' / '),
        ),
        _kv(
          '交通方式',
          trip['mode'] as String? ??
              (trip['kind'] == 'rail' ? '城市轨道交通' : '公共汽电车'),
        ),
        _kv('受理城市', trip['city'] as String? ?? '未记录'),
        _kv('交易金额', trip['amount'] as String?),
        _gap(16),
        _text(
          '本行程为内置样例摘要。未保留各侧原始字段，不据此补造记录。',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
      ],
    );
  }

  Widget _faceSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _face(_selectedCard),
      _gap(18),
      _text('卡面预设', role: GalleryTypography.label, weight: FontWeight.w600),
      _gap(12),
      Row(
        children:
            [
                  ('blue', '海蓝'),
                  ('teal', '青玉'),
                  ('graphite', '鸢紫'),
                  ('amber', '暖铜'),
                ]
                .map(
                  (pair) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextButton(
                        onPressed: () => c.update(() {
                          _selectedCard.face = pair.$1;
                          _selectedCard.image = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color:
                                  _selectedCard.face == pair.$1 &&
                                      _selectedCard.image == null
                                  ? t.onTone
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _faceColors(pair.$1),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            _gap(8),
                            _text(
                              pair.$2,
                              role: GalleryTypography.caption,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
      ),
      _gap(16),
      _button(
        _pickingFaceImage ? '正在打开相册…' : '从相册选择图片',
        _pickingFaceImage ? null : _pickFaceImage,
        icon: Icons.photo_library_outlined,
      ),
      _gap(8),
      _text(
        '仅在本次界面会话中使用，不上传图片',
        role: GalleryTypography.caption,
        color: t.muted,
      ),
      if (_faceImageError != null) ...[
        _gap(8),
        Semantics(
          liveRegion: true,
          child: _text(
            _faceImageError!,
            role: GalleryTypography.caption,
            color: t.danger,
          ),
        ),
      ],
      _gap(10),
      _button('完成', c.back, primary: true),
    ],
  );
}

class _GalleryMenuLayout extends SingleChildLayoutDelegate {
  _GalleryMenuLayout({
    required this.anchor,
    required this.geometry,
    required this.alignEnd,
    required this.width,
    required this.bottomInset,
  });
  final Rect anchor;
  final _GalleryMenuGeometry geometry;
  final bool alignEnd;
  final double width, bottomInset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final availableWidth = math.max(0.0, constraints.maxWidth - 24);
    final menuWidth = math.min(width, availableWidth);
    return BoxConstraints(
      minWidth: menuWidth,
      maxWidth: menuWidth,
      maxHeight: math.max(0, constraints.maxHeight - bottomInset - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rect = anchor;
    final x = alignEnd ? rect.right - childSize.width : rect.left;
    final below = rect.bottom + 6;
    final bottom = size.height - bottomInset - 8;
    geometry.opensUp = below + childSize.height > bottom;
    final y = geometry.opensUp ? rect.top - childSize.height - 6 : below;
    return Offset(
      x.clamp(12.0, math.max(12.0, size.width - childSize.width - 12)),
      y.clamp(8.0, math.max(8.0, bottom - childSize.height)),
    );
  }

  @override
  bool shouldRelayout(covariant _GalleryMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      alignEnd != oldDelegate.alignEnd ||
      width != oldDelegate.width ||
      bottomInset != oldDelegate.bottomInset ||
      geometry != oldDelegate.geometry;
}

class _GalleryNameForm extends StatefulWidget {
  const _GalleryNameForm({
    super.key,
    required this.initialName,
    required this.onCancel,
    required this.onSubmit,
  });
  final String initialName;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmit;
  @override
  State<_GalleryNameForm> createState() => _GalleryNameFormState();
}

class _GalleryNameFormState extends State<_GalleryNameForm> {
  late final TextEditingController _input;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: '卡片名称',
        child: TextField(
          controller: _input,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) widget.onSubmit(value);
          },
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: widget.onCancel,
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _input.text.trim().isEmpty
                  ? null
                  : () => widget.onSubmit(_input.text),
              child: const Text('确认'),
            ),
          ),
        ],
      ),
    ],
  );
}

class _GalleryMenuGeometry {
  _GalleryMenuGeometry({required this.alignEnd});
  final bool alignEnd;
  bool opensUp = false;
}

class _GalleryMenuTransition extends StatelessWidget {
  const _GalleryMenuTransition({required this.geometry, required this.child});
  final _GalleryMenuGeometry geometry;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)! as _GalleryPopupRoute;
    return AnimatedBuilder(
      animation: route.animation!,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final value = route.configuration.reduceMotion
            ? 1.0
            : route.motionProgress(route.animation!);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (geometry.opensUp ? 4 : -4) * (1 - value)),
            child: Transform.scale(
              scale: .96 + .04 * value,
              alignment: geometry.opensUp
                  ? (geometry.alignEnd
                        ? Alignment.bottomRight
                        : Alignment.bottomLeft)
                  : (geometry.alignEnd
                        ? Alignment.topRight
                        : Alignment.topLeft),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
