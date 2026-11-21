part of 'gallery_app.dart';

const _knowledgeHint = '搜索城市、线路、站点或编码';
const _knowledgeCapsule = BorderRadius.all(Radius.circular(26));

extension _GalleryKnowledgeKindLabel on GalleryKnowledgeKind {
  String get label => switch (this) {
    GalleryKnowledgeKind.city => '城市',
    GalleryKnowledgeKind.line => '线路',
    GalleryKnowledgeKind.station => '站点',
    GalleryKnowledgeKind.code => '编码',
  };
}

class _GalleryKnowledgeSearchBar extends StatelessWidget {
  const _GalleryKnowledgeSearchBar({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<GalleryTokens>()!;
    return OutlinedButton.icon(
      key: const ValueKey('knowledge-search-entry'),
      onPressed: onOpen,
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            backgroundColor: colors.inputContainer,
            disabledBackgroundColor: colors.inputContainer,
            foregroundColor: colors.inputHint,
            disabledForegroundColor: colors.inputDisabled,
            shape: const RoundedRectangleBorder(
              borderRadius: _knowledgeCapsule,
            ),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? colors.inputFocusedOutline
                    : colors.inputOutline,
              ),
            ),
          ),
      icon: Icon(Icons.search_rounded, size: 20, color: colors.inputIcon),
      label: const Text(_knowledgeHint, style: GalleryTypography.body),
    );
  }
}

class _GalleryKnowledgeSearch extends StatefulWidget {
  const _GalleryKnowledgeSearch({
    required this.load,
    required this.onBack,
    required this.onResult,
  });

  final Future<GalleryKnowledgeIndex> Function() load;
  final VoidCallback onBack;
  final ValueChanged<GalleryKnowledgeResult> onResult;

  @override
  State<_GalleryKnowledgeSearch> createState() =>
      _GalleryKnowledgeSearchState();
}

class _GalleryKnowledgeSearchState extends State<_GalleryKnowledgeSearch> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  GalleryKnowledgeIndex? _index;
  int _revision = 0;
  bool _loading = false;
  bool _failed = false;
  bool _searched = false;
  List<(GalleryKnowledgeKind, GalleryKnowledgeResult?)> _rows = [];

  void _changed(String input, {bool immediate = false}) {
    _debounce?.cancel();
    final revision = ++_revision;
    setState(() {
      _failed = false;
      _loading = false;
      if (input.trim().isEmpty) {
        _rows = [];
        _searched = false;
      }
    });
    if (input.trim().isEmpty) return;
    if (immediate) {
      unawaited(_search(input, revision));
    } else {
      _debounce = Timer(const Duration(milliseconds: 280), () {
        unawaited(_search(input, revision));
      });
    }
  }

  Future<void> _search(String input, int revision) async {
    try {
      if (_index == null) {
        setState(() => _loading = true);
        final index = await widget.load();
        if (!mounted || revision != _revision) return;
        _index = index;
      }
      final groups = _index!.search(input);
      setState(() {
        _loading = false;
        _searched = true;
        _rows = [
          for (final group in groups.entries) ...[
            (group.key, null),
            for (final result in group.value) (group.key, result),
          ],
        ];
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<GalleryTokens>()!;
    OutlineInputBorder outline(Color color) => OutlineInputBorder(
      borderRadius: _knowledgeCapsule,
      borderSide: BorderSide(color: color),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  key: const ValueKey('knowledge-search-input'),
                  controller: _field,
                  focusNode: _focus,
                  autofocus: true,
                  style: GalleryTypography.body.copyWith(
                    color: colors.inputForeground,
                  ),
                  cursorColor: colors.inputCursor,
                  textInputAction: TextInputAction.search,
                  onChanged: _changed,
                  onSubmitted: (input) => _changed(input, immediate: true),
                  decoration: InputDecoration(
                    constraints: const BoxConstraints(minHeight: 52),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    hintText: _knowledgeHint,
                    hintStyle: GalleryTypography.body.copyWith(
                      color: colors.inputHint,
                    ),
                    fillColor: colors.inputContainer,
                    enabledBorder: outline(colors.inputOutline),
                    disabledBorder: outline(colors.inputOutline),
                    focusedBorder: outline(colors.inputFocusedOutline),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: colors.inputIcon,
                    ),
                    suffixIcon: _field.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _field.clear();
                              _changed('');
                              _focus.requestFocus();
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.inputIcon,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body(colors)),
      ],
    );
  }

  Widget _body(GalleryTokens colors) {
    final bottom = 20 + MediaQuery.paddingOf(context).bottom;
    if (!_loading && !_failed && _rows.isNotEmpty) {
      return ListView.builder(
        key: const ValueKey('knowledge-search-results'),
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _rows.length,
        itemBuilder: (context, index) {
          final (kind, result) = _rows[index];
          return result == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 8),
                  child: Semantics(
                    header: true,
                    child: Text(kind.label, style: GalleryTypography.section),
                  ),
                )
              : _GalleryKnowledgeResultTile(
                  result,
                  onTap: () {
                    _focus.unfocus();
                    widget.onResult(result);
                  },
                );
        },
      );
    }
    final (title, message) = _loading
        ? ('正在检索本地知识库…', '')
        : _failed
        ? ('知识库暂时无法搜索', '请重试。本地原始数据不会更改。')
        : _searched
        ? ('没有找到相关内容', '请尝试其他城市、线路、站点名称或编码。')
        : ('查找知识库', '试试「北京」「1号线」，或输入完整编码。可同时检索交通联合和城市一卡通。');
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, bottom),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            style: GalleryTypography.section.copyWith(
              color: _failed ? colors.danger : colors.text,
            ),
          ),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: GalleryTypography.body.copyWith(color: colors.muted),
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _changed(_field.text, immediate: true),
              child: const Text('重试'),
            ),
          ),
        ],
      ],
    );
  }
}

class _GalleryKnowledgeResultTile extends StatelessWidget {
  const _GalleryKnowledgeResultTile(this.result, {required this.onTap});

  final GalleryKnowledgeResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<GalleryTokens>()!;
    final city = result.city;
    final line = result.line;
    final note = switch (result.kind) {
      GalleryKnowledgeKind.city =>
        '${city.lines.length} 条线路 · ${city.codeCount} 条编码',
      GalleryKnowledgeKind.line => '${city.name} · ${line!.stations.length} 站',
      GalleryKnowledgeKind.station => '${city.name} · ${line!.name}',
      GalleryKnowledgeKind.code => [
        city.name,
        if (line != null) line.name,
        if (result.station case final station?) station.name,
        if (result.source case final source? when source.isNotEmpty) source,
      ].join(' · '),
    };
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surface,
        shape: shape.copyWith(side: BorderSide(color: colors.line)),
        child: ListTile(
          shape: shape,
          title: Text(
            result.title,
            style: GalleryTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: result.kind == GalleryKnowledgeKind.code
                  ? 'monospace'
                  : null,
            ),
          ),
          subtitle: Text(
            '${result.kind.label} · ${city.system}\n$note',
            style: GalleryTypography.caption.copyWith(color: colors.muted),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: colors.inputIcon),
          onTap: onTap,
        ),
      ),
    );
  }
}

extension _GalleryKnowledgeDetails on _GalleryViewState {
  Widget _knowledgeDetails(GalleryKnowledgeResult result) {
    final city = result.city;
    final line = result.line;
    final station = result.station;
    final stationPage = _viewPage == GalleryPage.knowledgeStation;
    final title = stationPage ? (station?.name ?? '编码详情') : result.title;
    final contextLabel = [
      city.system,
      if (_viewPage != GalleryPage.knowledgeCity) city.name,
      if (line != null && stationPage) line.name,
    ].join(' · ');
    final details = <Widget>[
      _header(title, back: true),
      _text(contextLabel, role: GalleryTypography.label, color: t.muted),
      _gap(14),
      if (_viewPage == GalleryPage.knowledgeCity) ...[
        _panel(
          Column(
            children: [
              _kv('地区编码', city.code),
              if (city.province.isNotEmpty) _kv('省份／地区', city.province),
              _kv('线路', '${city.lines.length}'),
              _kv('编码', '${city.codeCount}'),
            ],
          ),
        ),
        _sectionTitle('线路'),
      ],
      if (_viewPage == GalleryPage.knowledgeLine) ...[
        if (line!.codes.isNotEmpty) _panel(_kv('线路编码', line.codes.join('、'))),
        _sectionTitle('站点', trailing: '${line.stations.length} 站'),
      ],
      if (stationPage) ...[
        if (result.code case final code?)
          _panel(
            Column(
              children: [
                _kv('匹配编码', code),
                if (result.source case final source? when source.isNotEmpty)
                  _kv('来源字段', source),
              ],
            ),
            color: t.tone,
          ),
        if (station != null) _sectionTitle('站点编码'),
      ],
    ];
    final related = switch (_viewPage) {
      GalleryPage.knowledgeCity => [
        for (final item in city.lines)
          GalleryKnowledgeResult(GalleryKnowledgeKind.line, city, line: item),
      ],
      GalleryPage.knowledgeLine => [
        for (final item in line!.stations)
          GalleryKnowledgeResult(
            GalleryKnowledgeKind.station,
            city,
            line: line,
            station: item,
          ),
      ],
      _ => const <GalleryKnowledgeResult>[],
    };
    final keys = station?.codes.toList() ?? const <(String, String)>[];
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        6,
        16,
        30 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: details.length + related.length + keys.length,
      itemBuilder: (context, index) {
        if (index < details.length) return details[index];
        final position = index - details.length;
        if (position < related.length) {
          final item = related[position];
          return _GalleryKnowledgeResultTile(
            item,
            onTap: () => c.openKnowledgeResult(item),
          );
        }
        final (code, source) = keys[position - related.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _panel(_kv(source.isEmpty ? '编码' : source, code)),
        );
      },
    );
  }
}
