part of 'gallery_app.dart';

extension _GalleryOverlays on _GalleryViewState {
  List<Widget> _overlay() {
    final type = c.overlay!;
    final sheet = [
      GalleryOverlay.face,
      GalleryOverlay.trip,
      GalleryOverlay.export,
      GalleryOverlay.rawFeedback,
    ].contains(type);
    return [
      Positioned.fill(
        child: ModalBarrier(
          dismissible: true,
          onDismiss: c.back,
          color: const Color(0x99000000),
          semanticsLabel: '关闭弹层',
        ),
      ),
      Align(
        alignment: sheet ? Alignment.bottomCenter : Alignment.center,
        child: SafeArea(
          top: true,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sheet ? 0 : 16,
              16,
              sheet ? 0 : 16,
              sheet ? 0 : 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: sheet ? 520 : 360,
                maxHeight: MediaQuery.sizeOf(context).height * .86,
              ),
              child: FocusScope(
                autofocus: true,
                child: FocusTraversalGroup(
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    label: _overlayTitle(type),
                    explicitChildNodes: true,
                    child: Material(
                      color: t.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(sheet ? 26 : 24),
                        bottom: Radius.circular(sheet ? 0 : 24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _text(
                                    _overlayTitle(type),
                                    size: 18,
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
                            _gap(12),
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
    GalleryOverlay.about => '关于 TrafArch',
    GalleryOverlay.export => c.exportTitle,
    GalleryOverlay.rawFeedback => '反馈内容预览',
  };

  Widget _overlayBody(GalleryOverlay type) => switch (type) {
    GalleryOverlay.save => _GalleryNameForm(
      key: ValueKey('save-${c.generation}'),
      initialName: c.current.name,
      tail: c.current.tail,
      onCancel: c.back,
      onSubmit: (name) {
        c.save(name);
        _toast('已保存到演示卡包');
      },
    ),
    GalleryOverlay.rename => _GalleryNameForm(
      key: ValueKey('rename-${c.selectedCard.id}-${c.generation}'),
      initialName: c.selectedCard.name,
      tail: c.selectedCard.tail,
      onCancel: c.back,
      onSubmit: (name) {
        c.rename(name);
        _toast('已更新模拟卡片名称');
      },
    ),
    GalleryOverlay.delete => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text('删除“${c.selectedCard.name}”及其本次演示记录？', size: 14),
        _gap(8),
        _text('仅影响当前内存样例。', size: 12, color: t.muted),
        _gap(22),
        Row(
          children: [
            Expanded(child: _button('取消', c.back)),
            const SizedBox(width: 10),
            Expanded(
              child: _button('删除', () {
                c.deleteCard();
                _toast('已删除模拟卡片');
              }, danger: true),
            ),
          ],
        ),
      ],
    ),
    GalleryOverlay.cardMenu => Column(
      children: [
        _settingRow(
          '重命名',
          () => c.showOverlay(GalleryOverlay.rename),
          icon: Icons.edit_outlined,
        ),
        _settingRow(
          '更换卡面',
          () => c.showOverlay(GalleryOverlay.face),
          icon: Icons.palette_outlined,
        ),
        _settingRow('导出记录', () => c.export(), icon: Icons.download_outlined),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: t.danger),
          title: _text('删除本卡', color: t.danger),
          onTap: () => c.showOverlay(GalleryOverlay.delete),
        ),
      ],
    ),
    GalleryOverlay.source => _options(
      (c.data.json['sources'] as List).cast<String>(),
      c.source,
      (value) => c.update(() {
        c.source = value;
        c.overlay = null;
      }),
    ),
    GalleryOverlay.mode => _options(
      (c.data.json['modes'] as List).cast<String>(),
      c.mode,
      (value) => c.update(() {
        c.mode = value;
        c.overlay = null;
      }),
    ),
    GalleryOverlay.face => _faceSheet(),
    GalleryOverlay.trip => _tripSheet(),
    GalleryOverlay.about => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 56,
                height: 56,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text('TrafArch', size: 23, weight: FontWeight.w700),
                  _text(
                    '${AppInfo.version} (${AppInfo.buildNumber})',
                    size: 12,
                    color: t.muted,
                  ),
                  _text('界面设计 Demo 2.4.0', size: 11, color: t.muted),
                ],
              ),
            ),
          ],
        ),
        _gap(22),
        _text(
          '只读交通卡读取与分析工具。\n此新界面 beta 使用模拟卡片、行程与二维码，供交互和布局评审。',
          size: 14,
          color: t.muted,
        ),
        _gap(20),
        _kv('作者', AppInfo.author),
        _gap(14),
        _text(
          AppInfo.copyright,
          size: 12,
          color: t.muted,
          align: TextAlign.center,
        ),
        _gap(14),
        _button('关闭', c.back, primary: true),
      ],
    ),
    GalleryOverlay.export => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text('演示内容预览 · 尚未保存文件', size: 12, color: t.warn),
        _gap(14),
        _hexBox(c.exportText),
        _gap(14),
        _button('关闭预览', c.back, primary: true),
      ],
    ),
    GalleryOverlay.rawFeedback => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _text('演示模式下仅预览反馈内容。', size: 13, color: t.muted),
        _gap(14),
        _hexBox(
          'TrafArch 新界面 beta\n设计版本：Demo 2.4.0\n场景：${c.sceneId ?? c.page.name}\n数据：合成演示样例\n\n请描述看到的问题、操作步骤和期望结果。',
        ),
        _gap(14),
        _button('关闭预览', c.back, primary: true),
      ],
    ),
  };

  Widget _options(
    List<String> options,
    String selected,
    ValueChanged<String> onSelected,
  ) => Column(
    children: options
        .map(
          (label) => ListTile(
            title: _text(label, size: 14),
            trailing: label == selected
                ? Icon(Icons.check_rounded, color: t.onTone)
                : null,
            onTap: () => onSelected(label),
          ),
        )
        .toList(),
  );

  Widget _tripSheet() {
    final trip = c.selectedTrip;
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
        _text('本行程为演示摘要。未保留各侧原始字段，不据此补造记录。', size: 12, color: t.muted),
        _gap(16),
        _button('关闭', c.back, primary: true),
      ],
    );
  }

  Widget _faceSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _face(c.selectedCard),
      _gap(18),
      _text('卡面预设', size: 13, weight: FontWeight.w600),
      _gap(12),
      Row(
        children:
            [
                  ('blue', '蔚蓝'),
                  ('teal', '青绿'),
                  ('graphite', '石墨'),
                  ('amber', '赭金'),
                ]
                .map(
                  (pair) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextButton(
                        onPressed: () => c.update(() {
                          c.selectedCard.face = pair.$1;
                          c.selectedCard.image = null;
                        }),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color:
                                  c.selectedCard.face == pair.$1 &&
                                      c.selectedCard.image == null
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
                            _text(pair.$2, size: 11, color: t.muted),
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
        '从相册选择（演示）',
        () => c.update(() => c.expanded.add('face:samples')),
        icon: Icons.photo_library_outlined,
      ),
      if (c.expanded.contains('face:samples')) ...[
        _gap(12),
        _text('内置样例图片', size: 12, color: t.muted),
        _gap(8),
        _button(
          '选择 TrafArch 路线图案',
          () =>
              c.update(() => c.selectedCard.image = 'assets/icon/app_icon.png'),
          icon: Icons.image_outlined,
        ),
      ],
      _gap(10),
      _button(
        '恢复默认卡面',
        () => c.update(() {
          c.selectedCard.face = c.selectedCard.id == 'shanghai'
              ? 'blue'
              : c.selectedCard.id == 'shenzhen'
              ? 'teal'
              : c.selectedCard.id == 'suica'
              ? 'graphite'
              : 'amber';
          c.selectedCard.image = null;
        }),
      ),
      _gap(10),
      _button('完成', c.back, primary: true),
    ],
  );
}

class _GalleryNameForm extends StatefulWidget {
  const _GalleryNameForm({
    super.key,
    required this.initialName,
    required this.tail,
    required this.onCancel,
    required this.onSubmit,
  });
  final String initialName, tail;
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
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('卡号尾号 ${widget.tail}', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 14),
      TextField(
        controller: _input,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '卡片名称'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) widget.onSubmit(value);
        },
      ),
      const SizedBox(height: 18),
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
