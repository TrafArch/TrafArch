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
        final cities = snapshot.data?.cities
            .where((city) => city.system == system)
            .toList();
        final coverage = active?.coverageDatasets.where(
          (dataset) => dataset.system.toUpperCase() == system,
        );
        final headings = <Widget>[
          _header('知识库', back: true),
          _GalleryKnowledgeSearchBar(
            onOpen: () => c.navigate(GalleryPage.knowledgeSearch),
          ),
          _gap(14),
          _tabs(
            const ['交通联合 TU', '城市一卡通 CU'],
            system == 'TU' ? 0 : 1,
            (index) =>
                c.update(() => c.knowledgeTab = index == 0 ? 'tu' : 'cu'),
            id: 'live-knowledge-system',
          ),
          _sectionTitle('数据概况'),
          _panel(
            Column(
              children: [
                _kv('$system 本地参考包', active?.packageVersions[system] ?? '不可用'),
                if (coverage != null &&
                    active!.packagePaths.containsKey(system)) ...[
                  _kv('覆盖地区', '${coverage.length}'),
                  _kv(
                    '站点条目',
                    '${coverage.fold(0, (total, item) => total + item.entryCountOverride)}',
                  ),
                ],
              ],
            ),
          ),
          _gap(),
          if (snapshot.hasError)
            _empty(
              '参考包暂不可用',
              '无法建立本地浏览索引，不会使用模拟数据。',
              action: _button(
                '重试',
                () => _updateDetail(() => _liveKnowledgeBrowse = null),
              ),
            )
          else if (cities == null)
            const Center(child: CircularProgressIndicator())
          else if (cities.isEmpty)
            _empty('$system 暂无地区数据', '可切换到另一套参考包。')
          else
            _sectionTitle('覆盖地区'),
        ];
        final visibleCities =
            snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError
            ? cities ?? const <GalleryKnowledgeCity>[]
            : const <GalleryKnowledgeCity>[];
        return ListView.builder(
          key: PageStorageKey('live-knowledge-$system'),
          padding: EdgeInsets.fromLTRB(
            16,
            6,
            16,
            30 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: headings.length + visibleCities.length,
          itemBuilder: (context, index) {
            if (index < headings.length) return headings[index];
            final city = visibleCities[index - headings.length];
            final result = GalleryKnowledgeResult(
              GalleryKnowledgeKind.city,
              city,
            );
            return _GalleryKnowledgeResultTile(
              result,
              onTap: () => c.openKnowledgeResult(result),
            );
          },
        );
      },
    );
  }
}
