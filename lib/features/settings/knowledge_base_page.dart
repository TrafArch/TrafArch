import 'package:flutter/material.dart';
import '../../core/data/region_db_store.dart'
    show LiveRegionDataset, RegionLineCoverage;
import '../../core/data/station_codes.dart';
import '../../core/data/tunion_knowledge_base.dart';
import '../../state/app_state.dart';

/// 知识库子页面：展示当前外部数据库（交通联合 TU / 城市一卡通 CU）
/// 支持的地区，以及每个地区收录的线路与站点。
class KnowledgeBasePage extends StatelessWidget {
  final AppState app;
  const KnowledgeBasePage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知识库')),
      body: AnimatedBuilder(
        animation: app,
        builder: (context, _) {
          final kb = app.knowledgeBase;
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
          final tu =
              coverage.where((d) => d.system == 'tu').toList()..sort(_byCityCode);
          final cu =
              coverage.where((d) => d.system == 'cu').toList()..sort(_byCityCode);
          final summary = _SummaryCard(kb: kb, tu: tu, cu: cu);
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: '交通联合 TU'),
                    Tab(text: '城市一卡通 CU'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _CoverageList(
                        header: summary,
                        datasets: tu,
                        emptyText: '交通联合暂无站点覆盖数据',
                      ),
                      _CoverageList(
                        header: summary,
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

/// 顶部数据概况卡片：覆盖地区 / 站点条目数与其他知识库规模。
class _SummaryCard extends StatelessWidget {
  final KnowledgeBase kb;
  final List<StationDataset> tu;
  final List<StationDataset> cu;
  const _SummaryCard({
    required this.kb,
    required this.tu,
    required this.cu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int entryCount(List<StationDataset> d) =>
        d.fold(0, (a, x) => a + x.entryCountOverride);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据概况', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _row(context, 'TU 数据库版本',
                kb.tuDatabaseVersion == null
                    ? '未加载 / 未设置'
                    : 'v${kb.tuDatabaseVersion}'),
            _row(context, 'CU 数据库版本',
                kb.cuDatabaseVersion == null
                    ? '未加载 / 未设置'
                    : 'v${kb.cuDatabaseVersion}'),
            _row(context, '交通联合覆盖',
                '${tu.length} 个地区 · ${entryCount(tu)} 条站点编码'),
            _row(context, '城市一卡通覆盖',
                '${cu.length} 个地区 · ${entryCount(cu)} 条站点编码'),
            _row(context, '城市码表', '${kb.cities.length} 城市'),
            _row(context, '发卡机构指纹', '${kb.issuers.length} 条'),
            _row(context, '终端解码规则', '${kb.terminalRules.length} 条'),
            _row(context, '城市一卡通识别卡', '${kb.cityUnionCards.entryCount} 种'),
            _row(context, 'CU 终端索引', '${kb.cuTerminals.length} 条'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              k,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
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
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final ds = datasets[i];
                  final widget = ds is LiveRegionDataset
                      ? _LazyRegionTile(dataset: ds)
                      : _RegionTile(dataset: ds);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: widget,
                  );
                },
                childCount: datasets.length,
              ),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
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
  final LiveRegionDataset dataset;
  const _LazyRegionTile({required this.dataset});

  @override
  State<_LazyRegionTile> createState() => _LazyRegionTileState();
}

class _LazyRegionTileState extends State<_LazyRegionTile> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = widget.dataset;
    final province = ds.province;
    final subtitleParts = <String>[
      '${ds.overview.lineCount} 条线路 · ${ds.entryCountOverride} 条站点条目',
      if (province != null && province.isNotEmpty) province,
    ];
    return ExpansionTile(
      title: Text(ds.cityName ?? ds.cityCode ?? '未知地区'),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: (ds.cityCode != null && ds.cityCode!.isNotEmpty)
          ? Text(
              ds.cityCode!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            )
          : null,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      onExpansionChanged: (v) {
        if (v && !_loaded) setState(() => _loaded = true);
      },
      children: !_loaded
          ? const []
          : [
              FutureBuilder<List<RegionLineCoverage>>(
                future: ds.linesOnce(),
                builder: (context, snap) => switch (snap) {
                  _ when !snap.hasData && snap.hasError =>
                    const ListTile(dense: true, title: Text('查询失败')),
                  _ when !snap.hasData => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )),
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
          style: Theme.of(context)
              .textTheme
              .bodySmall
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