part of 'gallery_app.dart';

extension _GalleryLiveKnowledge on _GalleryViewState {
  Widget _liveKnowledge(AppDependencies app) {
    final active = app.knowledgeBase;
    if (!identical(active, _browsedKnowledge)) {
      _browsedKnowledge = active;
      _liveKnowledgeBrowse = null;
    }
    final system = c.knowledgeTab.toUpperCase();
    return FutureBuilder<GalleryKnowledgeIndex>(
      future: _liveKnowledgeBrowse ??= widget.loadKnowledge(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _list([
            _header('知识库', back: true),
            _empty(
              '本地参考数据暂不可用',
              '无法读取当前已校验的 TU／CU 发布包。',
              icon: Icons.storage_outlined,
              action: _button(
                '重试',
                () => _updateDetail(() => _liveKnowledgeBrowse = null),
                primary: true,
              ),
            ),
          ]);
        }
        final index = snapshot.data;
        if (index == null) {
          return _list([
            _header('知识库', back: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ]);
        }
        return _knowledgePage(
          _liveKnowledgeRecord(index, system, active),
          live: true,
        );
      },
    );
  }

  GalleryRecord _liveKnowledgeRecord(
    GalleryKnowledgeIndex index,
    String system,
    KnowledgeBase? active,
  ) {
    final cities = index.cities
        .where((city) => city.system.toUpperCase() == system)
        .toList(growable: false);
    // regions 与样例数据同构：首页概况的三项统计（城市数量、线路数量、
    // 站点数量）由页面按这些真实结构推导，站点按同城同名去重；结构缺失的
    // 维度返回 null 并显示「未知」。version/sha256 来自已校验发布包。
    final regions = [
      for (final city in cities)
        {
          'code': city.code,
          'name': city.name,
          'province': city.province,
          'lineCount': city.lines.length,
          'entries': city.codeCount,
          'lines': [
            for (final line in city.lines)
              {
                'name': line.name,
                'stations': [for (final station in line.stations) station.name],
              },
          ],
        },
    ];
    final coverage = active?.coverageDatasets.where(
      (dataset) => dataset.system.toUpperCase() == system,
    );
    return {
      'name': system == 'TU' ? '交通联合' : '城市一卡通',
      'formatVersion': 1,
      'version': active?.packageVersions[system] ?? '不可用',
      'source': system == 'TU'
          ? 'TrafArch_Database_TU.sqlite'
          : 'TrafArch_Database_CU.sqlite',
      'sha256': active?.packageHashes[system] ?? '未提供',
      'regions': regions,
      'entries':
          coverage?.fold<int>(
            0,
            (total, item) => total + item.entryCountOverride,
          ) ??
          regions.fold<int>(
            0,
            (total, item) => total + (item['entries'] as int),
          ),
      'cities': active?.cities.length,
      'cards': active?.cityUnionCards.entryCount,
      'terminals': active?.cuTerminals.length,
    };
  }
}
