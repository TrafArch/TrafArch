import 'package:flutter/material.dart';

import '../../../shared/presentation/adaptive_layout.dart';

import '../domain/station_codes.dart';
import '../domain/region_db_store.dart';
import '../data/tunion_knowledge_base.dart';
import '../../../app/app_dependencies.dart';

/// 知识库子页面：展示已安装的本地参考数据包（交通联合 TU / 城市一卡通 CU）
/// 支持的地区，以及每个地区收录的线路与站点。
class KnowledgeBasePage extends StatefulWidget {
  final AppDependencies app;
  const KnowledgeBasePage({super.key, required this.app});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  final _searchController = TextEditingController();
  String _query = '';
  List<_KnowledgeSearchHit> _hits = const [];
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(KnowledgeBase kb, String raw) async {
    final query = raw.trim();
    final generation = ++_searchGeneration;
    setState(() {
      _query = query;
      _hits = const [];
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    final hits = <_KnowledgeSearchHit>[];
    for (final dataset in kb.coverageDatasets) {
      if ([dataset.cityName, dataset.cityCode, dataset.province]
          .whereType<String>()
          .any((s) => s.toLowerCase().contains(query.toLowerCase()))) {
        hits.add(_KnowledgeSearchHit.city(dataset));
      }
      final entries = dataset.isLazy
          ? await (dataset as LiveRegionDataset).searchEntries(query)
          : dataset.codes.values
                .where(
                  (e) =>
                      [e.line, e.station].whereType<String>().any(
                        (s) => s.toLowerCase().contains(query.toLowerCase()),
                      ) ||
                      e.code.toLowerCase().startsWith(query.toLowerCase()),
                )
                .toList();
      hits.addAll(
        entries.map((entry) => _KnowledgeSearchHit.entry(dataset, entry)),
      );
    }
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _hits = hits.take(100).toList();
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return FoldSafePage(
      child: Scaffold(
        appBar: AppBar(title: const Text('知识库')),
        body: SafeArea(
          top: false,
          child: AdaptiveContent(
            child: AnimatedBuilder(
              animation: app,
              builder: (context, _) {
                final kb = app.knowledgeBase;
                if (kb == null && app.references.error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('本地参考数据不可用：${app.references.error}'),
                    ),
                  );
                }
                if (kb == null) {
                  // 数据库启动即并行预热；预热未完成前进入本页展示加载态，
                  // 加载完成（notifyListeners）后自动刷新为数据内容。
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        SizedBox(height: 12),
                        Text('数据库预热中，请稍候…'),
                      ],
                    ),
                  );
                }
                final coverage = kb.coverageDatasets;
                final tu = coverage.where((d) => d.system == 'tu').toList()
                  ..sort(_byCityCode);
                final cu = coverage.where((d) => d.system == 'cu').toList()
                  ..sort(_byCityCode);
                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) => _search(kb, value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: '搜索城市、线路、站点或编码',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: '清空搜索',
                                    onPressed: () {
                                      _searchController.clear();
                                      _search(kb, '');
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(26),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const TabBar(
                        tabs: [
                          Tab(text: '交通联合 TU'),
                          Tab(text: '城市一卡通 CU'),
                        ],
                      ),
                      Expanded(
                        child: _query.isNotEmpty
                            ? _SearchResults(
                                query: _query,
                                hits: _hits,
                                loading: _searching,
                              )
                            : TabBarView(
                                children: [
                                  _CoverageList(
                                    header: _SummaryCard(
                                      kb: kb,
                                      tu: tu,
                                      cu: cu,
                                      isTu: true,
                                    ),
                                    datasets: tu,
                                    emptyText: '交通联合暂无站点覆盖数据',
                                  ),
                                  _CoverageList(
                                    header: _SummaryCard(
                                      kb: kb,
                                      tu: tu,
                                      cu: cu,
                                      isTu: false,
                                    ),
                                    datasets: cu,
                                    emptyText: '城市一卡通暂无站点覆盖数据',
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static int _byCityCode(StationDataset a, StationDataset b) {
    final ac = a.cityCode ?? '';
    final bc = b.cityCode ?? '';
    final c = ac.compareTo(bc);
    if (c != 0) return c;
    return (a.cityName ?? '').compareTo(b.cityName ?? '');
  }
}

class _KnowledgeSearchHit {
  final StationDataset dataset;
  final StationCodeEntry? entry;
  const _KnowledgeSearchHit.city(this.dataset) : entry = null;
  const _KnowledgeSearchHit.entry(this.dataset, this.entry);
}

class _SearchResults extends StatelessWidget {
  final String query;
  final List<_KnowledgeSearchHit> hits;
  final bool loading;
  const _SearchResults({
    required this.query,
    required this.hits,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (hits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 36),
              SizedBox(height: 10),
              Text('没有找到相关内容'),
              SizedBox(height: 4),
              Text('请尝试其他城市、线路、站点名称或编码。', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final entry = hit.entry;
        final isCity = entry == null;
        final title = isCity
            ? (hit.dataset.cityName ?? hit.dataset.cityCode ?? '未知地区')
            : (entry.station?.isNotEmpty == true
                  ? entry.station!
                  : entry.line ?? entry.code);
        final subtitle = isCity
            ? '${hit.dataset.system.toUpperCase()} · ${hit.dataset.province ?? '地区'} · ${hit.dataset.lineCountOverride} 条线路 · ${hit.dataset.entryCountOverride} 条编码'
            : [
                hit.dataset.cityName ?? hit.dataset.cityCode ?? '未知地区',
                if (entry.line?.isNotEmpty == true) entry.line!,
                if (entry.code.isNotEmpty) '编码 ${entry.code}',
                hit.dataset.system.toUpperCase(),
              ].join(' · ');
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: Chip(
              label: Text(
                isCity
                    ? '城市'
                    : entry.line?.contains(query) == true
                    ? '线路'
                    : entry.code.toLowerCase().contains(query.toLowerCase())
                    ? '编码'
                    : '站点',
              ),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
          ),
        );
      },
    );
  }
}

/// 知识库概览：先突出当前体系覆盖规模，详细元数据按需展开。
class _SummaryCard extends StatelessWidget {
  final KnowledgeBase kb;
  final List<StationDataset> tu;
  final List<StationDataset> cu;
  final bool isTu;
  const _SummaryCard({
    required this.kb,
    required this.tu,
    required this.cu,
    required this.isTu,
  });

  int _entryCount(List<StationDataset> datasets) =>
      datasets.fold(0, (total, dataset) => total + dataset.entryCountOverride);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final datasets = isTu ? tu : cu;
    final systemName = isTu ? '交通联合参考数据' : '城市一卡通参考数据';
    final version = kb.packageVersions[isTu ? 'TU' : 'CU'] ?? '本地数据';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          systemName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(version, style: theme.textTheme.labelSmall),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(context, '${datasets.length}', '覆盖地区'),
                      ),
                      Expanded(
                        child: _metric(
                          context,
                          '${_entryCount(datasets)}',
                          '站点编码条目',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '用于识别读卡结果中的城市、线路与站点。数据随应用保存在本地。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              title: const Text('数据概况'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _row(
                  context,
                  'TU 数据库版本',
                  kb.tuDatabaseVersion == null
                      ? '未加载 / 未设置'
                      : 'v${kb.tuDatabaseVersion}',
                ),
                _row(
                  context,
                  'CU 数据库版本',
                  kb.cuDatabaseVersion == null
                      ? '未加载 / 未设置'
                      : 'v${kb.cuDatabaseVersion}',
                ),
                _row(
                  context,
                  '交通联合覆盖',
                  '${tu.length} 个地区 · ${_entryCount(tu)} 条站点编码',
                ),
                _row(
                  context,
                  '城市一卡通覆盖',
                  '${cu.length} 个地区 · ${_entryCount(cu)} 条站点编码',
                ),
                _row(context, 'TU 数据包版本', kb.packageVersions['TU'] ?? '未加载'),
                _row(context, 'CU 数据包版本', kb.packageVersions['CU'] ?? '未加载'),
                _row(context, 'TU 城市码表', '${kb.cities.length} 城市'),
                _row(
                  context,
                  'CU 城市码表',
                  kb.cuCities == null ? '未加载' : '${kb.cuCities!.length} 城市',
                ),
                _row(context, '发卡机构指纹', '${kb.issuers.length} 条'),
                _row(context, '终端解码规则', '${kb.terminalRules.length} 条'),
                _row(context, '城市一卡通识别卡', '${kb.cityUnionCards.entryCount} 种'),
                _row(context, 'CU 终端索引', '${kb.cuTerminals.length} 条'),
                _row(
                  context,
                  'CU 线路记录',
                  kb.cuRepository == null
                      ? '未加载'
                      : '${kb.cuRepository!.routeCount} 条',
                ),
                _row(
                  context,
                  'CU 公交映射',
                  kb.cuRepository == null
                      ? '未加载'
                      : '${kb.cuRepository!.busRouteCount} 条',
                ),
                _row(
                  context,
                  'CU 前缀字典',
                  kb.cuRepository == null
                      ? '未加载'
                      : '${kb.cuRepository!.prefixCount} 条',
                ),
                if (kb.loadIssues.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    '数据加载 / 迁移问题',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  for (final issue in kb.loadIssues.entries)
                    _row(context, issue.key, issue.value),
                  const Text('部分参考数据不可用，原始读卡结果仍保留。'),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('覆盖地区', style: theme.textTheme.titleSmall),
                ),
                Text(
                  '按城市编码排序',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _row(BuildContext context, String key, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              key,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 单个体系的地区列表（每地区一张可展开瓦片）。顶部数据概况作为列表首项
/// 随内容一起滚动，TabBar 保持在上方吸顶。
class _CoverageList extends StatelessWidget {
  final Widget header;
  final List<StationDataset> datasets;
  final String emptyText;
  const _CoverageList({
    required this.header,
    required this.datasets,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        if (datasets.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  emptyText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final ds = datasets[i];
                final widget = ds.isLazy
                    ? _LazyRegionTile(
                        key: ValueKey('${ds.system}:${ds.file}:${ds.cityCode}'),
                        dataset: ds,
                      )
                    : _RegionTile(dataset: ds);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: widget,
                );
              }, childCount: datasets.length),
            ),
          ),
      ],
    );
  }
}

/// 地区瓦片：展开后按线路分组列出站点。
class _RegionTile extends StatelessWidget {
  final StationDataset dataset;
  const _RegionTile({required this.dataset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = dataset.codes.values;
    final lines = _groupLines(entries);
    final stationTotal = _uniqueStationCount(entries);
    final regionLabel = dataset.cityName ?? dataset.cityCode ?? '未知地区';
    final province = dataset.province;
    final subtitleParts = <String>[
      '${lines.length} 条线路 · $stationTotal 个站点',
      if (province != null && province.isNotEmpty) province,
    ];
    return ExpansionTile(
      title: Text(regionLabel),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: (dataset.cityCode != null && dataset.cityCode!.isNotEmpty)
          ? Text(
              dataset.cityCode!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          : null,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [for (final line in lines) _LineTile(line: line)],
    );
  }
}

/// 惰性地区瓦片（TU / CU 共用）：展开时仅点查该地区的线路/站点。
class _LazyRegionTile extends StatefulWidget {
  final StationDataset dataset;
  const _LazyRegionTile({super.key, required this.dataset});

  @override
  State<_LazyRegionTile> createState() => _LazyRegionTileState();
}

class _LazyRegionTileState extends State<_LazyRegionTile> {
  Future<List<RegionLineCoverage>>? _lines;

  @override
  void didUpdateWidget(covariant _LazyRegionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dataset, widget.dataset)) _lines = null;
  }

  void _load() => setState(() {
    _lines = widget.dataset.linesForDisplay();
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = widget.dataset;
    final province = ds.province;
    final subtitleParts = <String>[
      '${ds.lineCountOverride} 条线路 · ${ds.entryCountOverride} 条站点条目',
      if (province != null && province.isNotEmpty) province,
    ];
    return ExpansionTile(
      title: Text(ds.cityName ?? ds.cityCode ?? '未知地区'),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: (ds.cityCode != null && ds.cityCode!.isNotEmpty)
          ? Text(
              ds.cityCode!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          : null,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      onExpansionChanged: (v) {
        if (v && _lines == null) _load();
      },
      children: _lines == null
          ? const []
          : [
              FutureBuilder<List<RegionLineCoverage>>(
                future: _lines,
                builder: (context, snap) => switch (snap) {
                  _ when !snap.hasData && snap.hasError => ListTile(
                    dense: true,
                    title: const Text('查询失败'),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ),
                  _ when !snap.hasData => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  final s => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final RegionLineCoverage l in s.data!)
                        _LineTile(line: l),
                    ],
                  ),
                },
              ),
            ],
    );
  }
}

/// 线路子瓦片：展开后以标签云列出该线路全部站点。
class _LineTile extends StatelessWidget {
  final RegionLineCoverage line;
  const _LineTile({required this.line});

  @override
  Widget build(BuildContext context) {
    if (line.stations.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(line.line),
        trailing: Text(
          '（无站点名称）',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('${line.line}（${line.stations.length} 站）'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in line.stations)
                Chip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 按线路名分组站点：同线路站点名去重；"未标注线路"排最后。
List<RegionLineCoverage> _groupLines(Iterable<StationCodeEntry> entries) {
  final byLine = <String, Set<String>>{};
  for (final e in entries) {
    final line = (e.line == null || e.line!.trim().isEmpty)
        ? '未标注线路'
        : e.line!.trim();
    final station = (e.station == null || e.station!.trim().isEmpty)
        ? null
        : e.station!.trim();
    final bucket = byLine.putIfAbsent(line, () => <String>{});
    if (station != null) bucket.add(station);
  }
  final out = <RegionLineCoverage>[];
  byLine.forEach((line, stations) {
    final list = stations.toList()..sort();
    out.add(RegionLineCoverage(line, list));
  });
  out.sort((a, b) {
    const unlabeled = '未标注线路';
    if (a.line == unlabeled && b.line != unlabeled) return 1;
    if (b.line == unlabeled && a.line != unlabeled) return -1;
    final an = _lineNumber(a.line);
    final bn = _lineNumber(b.line);
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    if (an != null && bn == null) return -1;
    if (an == null && bn != null) return 1;
    return a.line.compareTo(b.line);
  });
  return out;
}

int _uniqueStationCount(Iterable<StationCodeEntry> entries) {
  final set = <String>{};
  for (final e in entries) {
    final s = e.station?.trim();
    if (s != null && s.isNotEmpty) set.add(s);
  }
  return set.length;
}

/// 线路名内首个数字（"10号线"→10、"S1线"→1）；无数字返回 null。
int? _lineNumber(String line) {
  final m = RegExp(r'(\d+)').firstMatch(line);
  return m == null ? null : int.tryParse(m.group(1)!);
}
