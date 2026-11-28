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
      label: const Text(
        _knowledgeHint,
        style: GalleryTypography.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _GalleryKnowledgeSearch extends StatefulWidget {
  const _GalleryKnowledgeSearch({
    required this.load,
    required this.onBack,
    required this.onResult,
    this.revision,
  });

  final Future<GalleryKnowledgeIndex> Function() load;
  final VoidCallback onBack;
  final ValueChanged<GalleryKnowledgeResult> onResult;
  final Object? revision;

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

  @override
  void didUpdateWidget(covariant _GalleryKnowledgeSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.revision, widget.revision)) return;
    _index = null;
    _rows = [];
    _changed(_field.text, immediate: true);
  }

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
      // 280ms 是输入调度防抖（Motion 1.0.1 §7.3 例外），不是动效时长。
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
    // 与首页城市卡、城市页同一口径：快照声明值优先。
    final cityLines = resolveKnowledgeLineCount(
      declared: city.declaredLineCount,
      listed: city.lines.length,
    );
    final note = switch (result.kind) {
      GalleryKnowledgeKind.city =>
        cityLines == null
            ? '线路数量未知 · ${city.codeCount} 条编码'
            : '$cityLines 条线路 · ${city.codeCount} 条编码',
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
    final title = Text(
      result.title,
      style: GalleryTypography.body.copyWith(
        fontWeight: FontWeight.w600,
        fontFamily: result.kind == GalleryKnowledgeKind.code
            ? 'monospace'
            : null,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.surface,
        shape: shape.copyWith(side: BorderSide(color: colors.line)),
        child: ListTile(
          shape: shape,
          title: result.kind == GalleryKnowledgeKind.line
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  heightFactor: 1,
                  child: _GalleryRailLineBadge(
                    line: result.title,
                    cityCode: city.code,
                    cityName: city.name,
                    citySystem: city.system,
                    labelFallback: title,
                  ),
                )
              : title,
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
  /// 二级城市详情页（spec §5、§3.2）：顶部是与首页同一个吸顶搜索头，其下
  /// 为城市信息 + 线路卡。线路卡内部展开站点列表（名称 + 原始编码），不产生
  /// 新的页面层级；搜索胶囊随滚动收合进标题栏（spec §3.4 要求两页一致）。
  Widget _knowledgeCityPage() {
    final city = c.selectedKnowledgeCity;
    return CustomScrollView(
      // 滚动位置按城市分别保存：换城市或回首页再进来不会串位。
      key: PageStorageKey(
        'gallery-${c.generation}-knowledge-city-'
        '${city == null ? 'none' : '${city.system}-${city.code}'}',
      ),
      controller: _knowledgeScroll,
      slivers: [
        _knowledgeSearchHeader(
          title: city?.name ?? '城市详情',
          searchKey: const ValueKey('knowledge-city-search-position'),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            6,
            16,
            30 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: city == null
              ? SliverList.list(
                  children: [
                    _empty(
                      '未选择城市',
                      '请从知识库首页的城市列表进入。',
                      icon: Icons.location_city_outlined,
                    ),
                  ],
                )
              : _knowledgeCityBody(city),
        ),
      ],
    );
  }

  /// 城市页内容 sliver：调用方（[_knowledgeCityPage]）负责吸顶搜索头与外层
  /// 滚动视图，这里只产出城市信息与按需构建的线路卡。
  Widget _knowledgeCityBody(GalleryKnowledgeCityView city) {
    final targetIndex = c.knowledgeCityLine == null
        ? -1
        : city.lines.indexWhere((line) => line.name == c.knowledgeCityLine);
    // 每次搜索定位只消费一次：换新的 GlobalKey，旧卡片同帧释放，不会出现
    // 两个 widget 共用同一个 GlobalKey。
    if (c.knowledgeCityReveal != _knowledgeRevealToken) {
      _knowledgeRevealToken = c.knowledgeCityReveal;
      _knowledgeRevealKey = targetIndex < 0
          ? null
          : GlobalKey(debugLabel: 'knowledge-city-target');
      _scheduleKnowledgeReveal();
    }
    final system = switch (city.system.toUpperCase()) {
      'TU' => '交通联合 TU',
      'CU' => '城市一卡通 CU',
      final other => other,
    };
    final header = <Widget>[
      _text(
        [system, if (city.province.isNotEmpty) city.province].join(' · '),
        role: GalleryTypography.label,
        color: t.muted,
      ),
      _gap(14),
      _panel(
        Column(
          children: [
            _kv('城市编码', city.code),
            _kv('线路', city.lineCount == null ? '未知' : '${city.lineCount}'),
            _kv(
              '站点',
              city.stationCount == null ? '未知' : '${city.stationCount}',
            ),
            _kv('编码', city.codeCount == null ? '未知' : '${city.codeCount}'),
          ],
        ),
      ),
      _sectionTitle(
        '线路',
        trailing: city.lineCount == null
            ? '线路数量未知'
            : '收录 ${city.lineCount} 条线路',
      ),
      if (city.lines.isEmpty)
        _empty('暂无线路数据', '当前参考数据未包含该城市的线路与站点。', icon: Icons.route_outlined),
    ];
    // 城市页按需构建线路卡：只有接近视口的卡片才会建出站点容器。
    return SliverList.builder(
      itemCount: header.length + city.lines.length,
      itemBuilder: (context, index) => index < header.length
          ? header[index]
          : _knowledgeLineCard(city, index - header.length),
    );
  }

  Widget _knowledgeLineCard(GalleryKnowledgeCityView city, int index) {
    final line = city.lines[index];
    final id = GalleryKnowledgeLineView.idFor(
      city.system,
      city.code,
      line.name,
    );
    final open = c.knowledgeExpanded.contains(id);
    final target = line.name == c.knowledgeCityLine;
    final stationTarget = c.knowledgeCityStation;
    final codeTarget = c.knowledgeCityCode;
    // 编码可能挂在线路上而不属于某个站点：此时高亮线路卡并展示原值。
    final lineCodeMatch =
        target &&
        stationTarget == null &&
        codeTarget != null &&
        line.codes.contains(codeTarget);
    final stationsKnown = city.hasStationData;
    final card = Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: target ? t.action : t.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: open,
            child: InkWell(
              key: ValueKey('knowledge-line-toggle-${city.system}:$index'),
              // 整张卡片的头部区域都可点击（spec §6.1），不是只有箭头。
              onTap: () => c.update(() {
                if (open) {
                  c.knowledgeExpanded.remove(id);
                } else {
                  c.knowledgeExpanded.add(id);
                  c.knowledgeCityStation = null;
                  c.knowledgeCityCode = null;
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GalleryRailLineBadge(
                            line: line.name,
                            cityCode: city.code,
                            cityName: city.name,
                            citySystem: city.system,
                            labelFallback: _text(
                              line.name,
                              role: GalleryTypography.body,
                              weight: FontWeight.w600,
                            ),
                          ),
                          _gap(2),
                          _text(
                            line.codes.isEmpty
                                ? '线路编号未知'
                                : '线路编码 ${line.codes.join('、')}',
                            role: GalleryTypography.caption,
                            color: t.muted,
                            mono: line.codes.isNotEmpty,
                          ),
                          if (lineCodeMatch) ...[
                            _gap(2),
                            _text(
                              '匹配编码 $codeTarget',
                              role: GalleryTypography.caption,
                              color: t.action,
                              mono: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _text(
                      stationsKnown && line.stations.isNotEmpty
                          ? '${line.stations.length} 站'
                          : '站点未知',
                      role: GalleryTypography.caption,
                      color: t.muted,
                    ),
                    const SizedBox(width: 4),
                    _expandArrow(open),
                  ],
                ),
              ),
            ),
          ),
          _collapse(
            open,
            (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 1, color: t.line),
                if (line.stations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: _text(
                      stationsKnown ? '该线路暂无站点数据。' : '当前数据源只提供线路，未包含站点。',
                      role: GalleryTypography.caption,
                      color: t.muted,
                    ),
                  )
                else
                  for (final (stationIndex, station) in line.stations.indexed)
                    _knowledgeStationRow(
                      city,
                      index,
                      stationIndex,
                      station,
                      highlighted: target && station.name == stationTarget,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      key: ValueKey('knowledge-city-line-${city.system}:$index'),
      padding: const EdgeInsets.only(bottom: 10),
      child: target && _knowledgeRevealKey != null
          ? KeyedSubtree(key: _knowledgeRevealKey, child: card)
          : card,
    );
  }

  /// 站点行：名称 + 原始编码。样例快照没有站点编码，显示「编码未知」而不是
  /// 猜测或留空；有值时原样展示（等宽字体便于比对）。编码搜索结果命中的
  /// 站点行额外展示原始匹配值：站点编码在快照里可能缺失，但用户搜到的
  /// 编码必须可见（spec §7.1）。
  Widget _knowledgeStationRow(
    GalleryKnowledgeCityView city,
    int lineIndex,
    int stationIndex,
    GalleryKnowledgeStationView station, {
    required bool highlighted,
  }) {
    final matchedCode = highlighted ? c.knowledgeCityCode : null;
    return Container(
      key: ValueKey(
        'knowledge-city-station-${city.system}:$lineIndex:$stationIndex',
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: highlighted ? t.tone : null,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  station.name,
                  role: GalleryTypography.body,
                  weight: highlighted ? FontWeight.w600 : null,
                ),
                if (matchedCode != null) ...[
                  _gap(2),
                  _text(
                    '匹配编码 $matchedCode',
                    role: GalleryTypography.caption,
                    color: t.muted,
                    mono: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: _text(
              station.codes.isEmpty ? '编码未知' : station.codes.join('、'),
              role: GalleryTypography.caption,
              color: t.muted,
              mono: station.codes.isNotEmpty,
              align: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 从搜索结果定位到线路：目标线路已在进入前展开，这里只负责滚动。列表
  /// 按需构建，目标卡片还没建出来时逐屏前进，直到它的 GlobalKey 出现。
  void _scheduleKnowledgeReveal() {
    if (c.knowledgeCityLine == null || _knowledgeRevealKey == null) return;
    final token = c.knowledgeCityReveal;
    // 在同步阶段取好时长与顶栏高度，避免在异步回调里跨 gap 使用 context。
    final duration = GalleryMotion.duration(context, GalleryMotion.medium);
    // 吸顶搜索头盖住视口顶部，定位目标要多让出它的收合高度。
    final clearance = _KnowledgeSearchHeaderGeometry.of(context).compactHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var firstFrame = true;
      while (mounted &&
          c.page == GalleryPage.knowledgeCity &&
          c.knowledgeCityReveal == token &&
          _knowledgeScroll.hasClients) {
        final target = _knowledgeRevealKey?.currentContext;
        if (target != null && target.mounted) {
          await _revealKnowledgeTarget(target, clearance, duration);
          return;
        }
        final position = _knowledgeScroll.position;
        // 返回城市时可能恢复到目标之后。未构建目标时从顶部开始，逐屏走到列表末尾。
        final next = firstFrame && position.pixels > position.minScrollExtent
            ? position.minScrollExtent
            : math.min(
                position.maxScrollExtent,
                position.pixels + position.viewportDimension * .75,
              );
        if ((next - position.pixels).abs() < .5) return;
        firstFrame = false;
        _knowledgeScroll.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
      }
    });
  }

  /// 把目标滚到吸顶搜索头下方。`ensureVisible` 只按视口计算，不知道顶部还有
  /// 一个 pinned 的搜索头，会把目标顶到标题栏底下；这里显式让出收合高度。
  Future<void> _revealKnowledgeTarget(
    BuildContext target,
    double clearance,
    Duration duration,
  ) async {
    final box = target.findRenderObject();
    final viewport = Scrollable.maybeOf(target)?.context.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        viewport is RenderBox &&
        _knowledgeScroll.hasClients) {
      final position = _knowledgeScroll.position;
      // 目标相对视口顶部的距离（含吸顶头占位）→ 再让出收合高度。
      final delta = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      await _knowledgeScroll.animateTo(
        (position.pixels + delta - clearance - 8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: duration,
        curve: GalleryMotion.curve,
      );
      return;
    }
    await Scrollable.ensureVisible(
      target,
      alignment: .08,
      duration: duration,
      curve: GalleryMotion.curve,
    );
  }
}
