part of 'gallery_app.dart';

extension _GalleryInspection on _GalleryViewState {
  Widget _expert() {
    final live = _GalleryLiveScope.of(context);
    if (live != null) return _liveExpert(live);
    return _list([
      _tabs(
        (c.data.json['expertTabs'] as List).cast<String>(),
        c.expertTab,
        (i) => c.update(() => c.expertTab = i),
        scroll: true,
        id: 'expert-tabs',
      ),
      _gap(16),
      _fade(
        'expert-${c.hasRead}-${c.expertTab}-${c.expertKind}',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!c.hasRead)
              _empty(
                '尚未读取卡片',
                '请先在首页读取卡片，再查看技术字段与解析信息',
                icon: Icons.science_outlined,
                action: _button(
                  '前往首页',
                  () => c.navigate(GalleryPage.home),
                  primary: true,
                ),
              )
            else
              ...switch (c.expertTab) {
                0 => [
                  ..._expertSections(c.expertKind),
                  _text(
                    '以上为内置样例，未保留的字段显示未知。',
                    role: GalleryTypography.caption,
                    color: t.muted,
                  ),
                ],
                1 => [..._expertSections('transit')],
                2 => [_compliance()],
                _ => [
                  _text(
                    '保留的示例帧按原顺序完整展示。SELECT、GET BALANCE 和 0x1A 原始响应未保留。',
                    role: GalleryTypography.caption,
                    color: t.muted,
                  ),
                  ...['sfi18', 'sfi1e'].indexed.expand(
                    (item) => [
                      _sectionTitle(
                        '${item.$1 + 1} 读取${item.$1 == 0 ? '交易明细 SFI 0x18' : '过程循环 SFI 0x1E'}',
                      ),
                      _hexBox(
                        'C-APDU  ${item.$1 == 0 ? '00 B2 01 C4 00' : '00 B2 01 F4 00'}\nR-APDU  ${_spacedHex('${(c.data.raw['shanghai'] as Map)[item.$2]}9000')}',
                      ),
                    ],
                  ),
                  _gap(14),
                  _expand('expert:raw-process', '过程记录原始数据 0x1A / 0x1E', [
                    _kv('0x1A 城市轨道 / 公交', '未保留'),
                    _kv('0x1E 循环记录 1', '42 字节'),
                    _gap(10),
                    _hexBox(
                      _spacedHex(
                        (c.data.raw['shanghai'] as Map)['sfi1e'] as String,
                      ),
                    ),
                  ], initiallyOpen: true),
                ],
              },
          ],
        ),
      ),
    ], id: 'expert');
  }

  String _spacedHex(String value) =>
      RegExp(r'.{1,2}').allMatches(value).map((m) => m.group(0)).join(' ');

  List<Widget> _expertSections(
    String kind,
  ) => (c.data.expert[kind] as List).cast<GalleryRecord>().indexed.map((item) {
    final section = item.$2;
    final rows = (section['rows'] as List).cast<List>();
    String value(List row) {
      final label = row[0] as String;
      if (['余额', '记录余额'].contains(label)) {
        return c.current.unknownBalance
            ? '未知'
            : c.current.balance(c.includeOverdraft);
      }
      if (label == '卡片名称') return c.current.name;
      if (label == '交易记录' && kind == 'transit') {
        return '${c.ledger(c.current).length} 条';
      }
      if (c.trips.isEmpty &&
          ['最近交易', '交易金额', '交易类型', '交易序号', '终端编号', '终端解码'].contains(label)) {
        return '未知';
      }
      return row.length > 1 && row[1] != null ? row[1].toString() : '未知';
    }

    return _expand('expert:$kind:${item.$1}', section['title'] as String, [
      ...rows.map((row) => _kv(row[0] as String, value(row))),
      if ((section['extra'] as String? ?? '').contains('hexbox')) ...[
        _gap(12),
        _hexBox(_spacedHex((c.data.raw['shanghai'] as Map)['sfi1e'] as String)),
      ],
    ], initiallyOpen: section['open'] as bool? ?? true);
  }).toList();

  Widget _compliance() {
    final hasTrips = c.trips.any((r) => r['kind'] != 'event');
    final rows = <List<String>>[
      ['应用选择', '已选中 A000000632010105', '通过'],
      ['公共应用信息文件 (SFI 0x15)', '未保留发卡机构原始字段', '待核验'],
      ['管理信息文件 (SFI 0x17)', '示例城市为上海，未保留文件原始字节', '待核验'],
      ['持卡人基本信息文件 (SFI 0x16)', '未保留；部分卡种无此文件', '未提供'],
      [
        '余额读取 (GET BALANCE)',
        c.current.unknownBalance
            ? '未读到余额'
            : '余额 ${c.current.balance(c.includeOverdraft)}',
        c.current.unknownBalance ? '待核验' : '通过',
      ],
      [
        '交易明细文件 (SFI 0x18)',
        hasTrips ? '已保留 1 条原始示例记录' : '无交易记录',
        hasTrips ? '通过' : '未提供',
      ],
      ['日期一致性', '生效日期和完整失效日期未保留', '待核验'],
      ['卡片有效性', '仅记录失效年月，无法完整判断', '未提供'],
      [
        '交易时间合理性',
        hasTrips ? '示例交易时间未晚于读取时间' : '无交易记录',
        hasTrips ? '通过' : '未提供',
      ],
    ];
    final scored = rows.where((r) => r[2] != '未提供').toList();
    final score =
        (100 *
                scored.fold<double>(
                  0,
                  (sum, r) => sum + (r[2] == '通过' ? 1 : .5),
                ) /
                scored.length)
            .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          Column(
            children: [
              _text(
                'JT/T 978 符合性',
                role: GalleryTypography.field,
                weight: FontWeight.w600,
              ),
              _kv('综合覆盖度', '$score%'),
              _kv('检查项', '${rows.length} 项'),
              ...rows.map(
                (r) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        r[2] == '通过'
                            ? Icons.check_circle_outline_rounded
                            : Icons.more_horiz_rounded,
                        size: 20,
                        color: r[2] == '通过' ? t.ok : t.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _text(r[0], size: 13),
                            _gap(4),
                            _text(
                              r[1],
                              role: GalleryTypography.caption,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _text(
                        r[2],
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _gap(12),
        _text(
          '覆盖度为示例字段完整度，未保留字段需进一步核验。',
          role: GalleryTypography.caption,
          color: t.muted,
        ),
      ],
    );
  }

  Widget _knowledge() {
    final live = _GalleryLiveScope.of(context);
    if (live != null) return _liveKnowledge(live.app);
    final data =
        ((c.data.knowledge['systems'] as Map)[c.knowledgeTab] as GalleryRecord);
    return _knowledgePage(data);
  }

  Widget _knowledgePage(GalleryRecord data, {bool live = false}) {
    final name = data['name'] as String? ?? '参考数据';
    final rawRegions = data['regions'];
    final regions = rawRegions is List
        ? rawRegions.whereType<GalleryRecord>().toList(growable: false)
        : null;
    final stats = _knowledgeStats(regions);
    final cities = regions ?? const <GalleryRecord>[];
    final body = _list(
      [
        _gap(2),
        _tabs(
          ['交通联合 TU', '城市一卡通 CU'],
          c.knowledgeTab == 'tu' ? 0 : 1,
          (i) => c.update(() => c.knowledgeTab = i == 0 ? 'tu' : 'cu'),
          id: 'knowledge-tabs',
        ),
        _sectionTitle('数据概况'),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _text(
                      '$name参考数据',
                      role: GalleryTypography.label,
                      weight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                  _text(
                    '本地数据',
                    role: GalleryTypography.caption,
                    color: t.onTone,
                  ),
                ],
              ),
              _gap(14),
              Row(
                children: [
                  _knowledgeMetric('cities', stats.cities, '城市数量'),
                  _knowledgeMetric('lines', stats.lines, '线路数量'),
                  _knowledgeMetric('stations', stats.stations, '站点数量'),
                ],
              ),
              _gap(10),
              _text(
                live
                    ? '用于识别读卡结果中的城市、线路与站点。\n当前读取使用本机已校验的 TU／CU 发布包，两个体系独立统计。'
                    : '用于识别读卡结果中的城市、线路与站点。\n数据快照 ${c.data.knowledge['captured']}，两个体系独立统计。',
                role: GalleryTypography.caption,
                color: t.muted,
              ),
            ],
          ),
          color: t.tone,
          border: false,
          radius: 20,
        ),
        _gap(6),
        _expand('knowledge:meta', '数据来源与版本', [
          _kv('源文件', data['source'] as String?),
          _kv('数据库版本', data['version']?.toString()),
          _kv('数据包版本', data['formatVersion']?.toString()),
          _kv('来源 SHA256', data['sha256'] as String?),
          for (final pair in [
            ('cities', '城市码表'),
            ('cards', '机构指纹'),
            ('terminals', '终端规则'),
            ('routes', '线路规则'),
            ('bus', '公交资料'),
            ('prefixes', '前缀规则'),
          ])
            if (data[pair.$1] != null)
              _kv(pair.$2, _groupNumber(data[pair.$1] as int)),
        ], initiallyOpen: c.knowledgeMetadata),
        _sectionTitle(
          '城市列表',
          trailing: regions == null ? '未知' : '${cities.length} 个城市',
        ),
        if (cities.isEmpty)
          _empty(
            '暂无城市数据',
            '当前参考数据未收录该体系的城市与线路。',
            icon: Icons.location_city_outlined,
          )
        else
          ...cities.indexed.map((item) => _knowledgeCityCard(item.$1, item.$2)),
        _gap(4),
      ],
      id: 'knowledge',
      positionId: c.knowledgeTab,
    );
    // 搜索入口固定常驻，城市与概况内容独立滚动（spec §3.2）。
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: _header('知识库', back: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _GalleryKnowledgeSearchBar(
            onOpen: () => c.navigate(GalleryPage.knowledgeSearch),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _knowledgeMetric(String id, int? value, String label) => Expanded(
    key: ValueKey('knowledge-metric-$id'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          value == null ? '未知' : _groupNumber(value),
          size: 26,
          weight: FontWeight.w600,
          lines: 1,
        ),
        _gap(2),
        _text(label, role: GalleryTypography.caption, color: t.muted),
      ],
    ),
  );

  /// 城市数量/线路数量/站点数量。结构里没有的维度返回 null，界面显示未知，
  /// 不用 0 冒充。站点按同城同名去重。
  ({int? cities, int? lines, int? stations}) _knowledgeStats(
    List<GalleryRecord>? regions,
  ) {
    if (regions == null) return (cities: null, lines: null, stations: null);
    var lines = 0;
    var stations = 0;
    var linesKnown = true;
    var stationsKnown = true;
    for (final region in regions) {
      final count = knowledgeLineCountOfRegion(region);
      if (count == null) {
        linesKnown = false;
      } else {
        lines += count;
      }
      if (region['lines'] case final List rawLines) {
        final names = <String>{};
        for (final line in rawLines) {
          if (line is! Map || line['stations'] is! List) {
            stationsKnown = false;
            continue;
          }
          for (final station in line['stations'] as List) {
            names.add('$station');
          }
        }
        stations += names.length;
      } else {
        stationsKnown = false;
      }
    }
    return (
      cities: regions.length,
      lines: linesKnown ? lines : null,
      stations: stationsKnown ? stations : null,
    );
  }

  Widget _knowledgeCityCard(int index, GalleryRecord region) {
    final system = c.knowledgeTab;
    final name = '${region['name'] ?? '未知城市'}';
    final code = '${region['code'] ?? '未知'}';
    final province = '${region['province'] ?? ''}'.trim();
    final rawLines = region['lines'];
    final lines = rawLines is List
        ? rawLines.whereType<GalleryRecord>().toList(growable: false)
        : const <GalleryRecord>[];
    final lineCount = knowledgeLineCountOfRegion(region);
    final entries = region['entries'] as int?;
    return Padding(
      key: ValueKey('knowledge-city-$system:$index'),
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        InkWell(
          onTap: () => c.openKnowledgeCity(
            GalleryKnowledgeCityView.fromRegion(system, region),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _text(
                        name,
                        role: GalleryTypography.body,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _text(
                      lineCount == null ? '线路数量未知' : '收录 $lineCount 条线路',
                      role: GalleryTypography.caption,
                      color: t.muted,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: t.onTone,
                    ),
                  ],
                ),
                _gap(6),
                _text(
                  _knowledgeCityIntro(lines, lineCount, entries),
                  role: GalleryTypography.caption,
                  color: t.muted,
                ),
                _gap(6),
                Row(
                  children: [
                    _text(
                      code,
                      role: GalleryTypography.caption,
                      mono: true,
                      color: t.muted,
                    ),
                    if (province.isNotEmpty && province != 'null') ...[
                      const SizedBox(width: 8),
                      _text(
                        province,
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// 线路/编码简介：优先列出线路名，再给编码条目数。
  String _knowledgeCityIntro(
    List<GalleryRecord> lines,
    int? lineCount,
    int? entries,
  ) {
    final names = [
      for (final line in lines)
        if ('${line['name'] ?? ''}'.trim().isNotEmpty) '${line['name']}'.trim(),
    ];
    final parts = <String>[
      if (names.isNotEmpty)
        '${names.take(3).join('、')}${names.length > 3 || (lineCount != null && lineCount > names.length) ? ' 等线路' : ''}',
      if (entries != null) '${_groupNumber(entries)} 条编码',
    ];
    return parts.isEmpty ? '线路与编码简介未知' : parts.join(' · ');
  }

  String _groupNumber(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  Widget _qr() {
    final live = _GalleryLiveScope.of(context);
    if (live != null) return _liveQr(live.app);
    final q = c.qr;
    final view = _entry.qrView;
    final title = switch (view) {
      'camera' || 'camera-error' => '扫描乘车码',
      'gallery' => '相册导入',
      _ => '乘车码解析',
    };
    final note = _text(
      '使用内置二维码样例预览扫码与导入流程',
      role: GalleryTypography.caption,
      color: t.muted,
      align: TextAlign.center,
    );
    return _list([
      _header(title, back: true),
      if (view == 'camera') ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    border: Border.all(color: t.onTone, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 64,
                        color: t.onTone,
                      ),
                      _gap(14),
                      _text(
                        '扫码取景',
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                ),
              ),
              _gap(20),
              _text(
                '将乘车码二维码对准取景框',
                role: GalleryTypography.label,
                color: t.muted,
                align: TextAlign.center,
              ),
              _gap(22),
              _button(
                q.busy ? '正在解析…' : '模拟识别乘车码',
                q.busy ? null : () => q.acquire('valid'),
                primary: true,
              ),
            ],
          ),
          color: t.surface2,
          radius: 22,
        ),
        _gap(12),
        _button(
          q.torch ? '闪光灯已开启' : '闪光灯',
          q.toggleTorch,
          icon: Icons.flashlight_on_outlined,
        ),
        _gap(12),
        _button(
          '从相册导入',
          q.busy ? null : () => q.open('gallery'),
          icon: Icons.photo_library_outlined,
        ),
        _gap(20),
        note,
        _gap(16),
        _expand('qr:scenarios', '其他扫码状态', [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _button('已过期乘车码', q.busy ? null : () => q.acquire('expired')),
              _button('非乘车码', q.busy ? null : () => q.acquire('invalid')),
              _button('相机不可用', q.busy ? null : () => q.open('camera-error')),
            ],
          ),
        ], surface: false),
      ] else if (view == 'camera-error') ...[
        _empty(
          '相机不可用',
          '请检查相机权限后重试。也可从相册导入乘车码图片。',
          icon: Icons.no_photography_outlined,
        ),
        Row(
          children: [
            Expanded(
              child: _button('重新尝试', () => q.open('camera'), primary: true),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _button(
                '从相册导入',
                () => q.open('gallery'),
                icon: Icons.photo_library_outlined,
              ),
            ),
          ],
        ),
        _gap(20),
        note,
      ] else if (view == 'gallery') ...[
        _text(
          '选择一张内置图片，查看识别结果。',
          role: GalleryTypography.label,
          color: t.muted,
        ),
        _gap(18),
        for (final sample in [
          ('valid', '有效乘车码', 'JT/T 1179 模拟载荷 · 335 字节'),
          ('expired', '已过期乘车码', '结构可解析，时效已过期'),
          ('invalid', '普通二维码', '格式不符合交通乘车码标准'),
          ('no-code', '未识别图片', '保留上次解析结果'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _panel(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  sample.$1 == 'no-code'
                      ? Icons.image_outlined
                      : Icons.qr_code_2_rounded,
                  size: 30,
                  color: t.onTone,
                ),
                title: _text(
                  sample.$2,
                  role: GalleryTypography.field,
                  weight: FontWeight.w600,
                ),
                subtitle: _text(
                  sample.$3,
                  role: GalleryTypography.caption,
                  color: t.muted,
                ),
                onTap: q.busy ? null : () => q.acquire(sample.$1),
              ),
              padding: const EdgeInsets.all(16),
            ),
          ),
        if (q.busy) _qrBusy(),
        _gap(16),
        note,
      ] else ...[
        _text(
          '只读解析交通一卡通乘车码，查看账户、机构、时效和原始数据。',
          role: GalleryTypography.label,
          color: t.muted,
        ),
        _gap(18),
        Row(
          children: [
            Expanded(
              child: _button(
                '扫描二维码',
                q.busy ? null : () => q.open('camera'),
                primary: true,
                icon: Icons.qr_code_scanner_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _button(
                '从相册导入',
                q.busy ? null : () => q.open('gallery'),
                icon: Icons.photo_library_outlined,
              ),
            ),
          ],
        ),
        _gap(18),
        if (q.busy) _qrBusy(),
        if (q.error != null) ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  q.error!.startsWith('图片') ? '图片未识别到二维码' : '解析失败',
                  role: GalleryTypography.lead,
                  weight: FontWeight.w600,
                  color: t.warn,
                ),
                _gap(8),
                _text(q.error!, role: GalleryTypography.label, color: t.muted),
                _gap(8),
                _text(
                  '可重新扫描二维码或从相册导入。',
                  role: GalleryTypography.caption,
                  color: t.muted,
                ),
              ],
            ),
          ),
          _gap(14),
        ],
        if (q.result != null)
          ..._qrResult(q.result!)
        else if (q.raw.isNotEmpty)
          _expand(
            'qr:failed-raw',
            '原始数据（${q.raw.length} 字节）',
            [_hexBox(galleryHex(q.raw))],
            initiallyOpen: true,
            surface: false,
          )
        else if (q.error == null)
          _empty(
            '尚未获取二维码',
            '扫描二维码或从相册导入，\n查看 JT/T 1179 乘车码读取信息。',
            icon: Icons.qr_code_2_rounded,
          ),
        if (q.result != null || q.error != null) ...[
          _gap(12),
          _button('清除解析结果', q.clear, icon: Icons.delete_outline_rounded),
        ],
        _gap(20),
        note,
      ],
    ], id: 'qr-${q.view}');
  }

  Widget _qrBusy() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: t.onTone),
        ),
        const SizedBox(width: 12),
        _text('正在获取并解析…', role: GalleryTypography.label, color: t.onTone),
      ],
    ),
  );

  Widget _liveQr(AppDependencies app) {
    final qr = app.qrData;
    final issuer = qr == null
        ? '未知'
        : app.cardPrefixByIssuerId(qr.issuerIdText)?.cardName ?? '未知';
    final certificate = qr?.issuerCertificate;
    return _list([
      _header('乘车码解析', back: true),
      _text(
        '只读解析交通一卡通乘车码，查看账户、机构、时效和原始数据。',
        role: GalleryTypography.label,
        color: t.muted,
      ),
      _gap(18),
      Row(
        children: [
          Expanded(
            child: _button(
              '扫描二维码',
              app.qrAcquiring
                  ? null
                  : () => scanQrAndParse(
                      context,
                      app,
                      onNotice: _archiveNotice,
                      canPublish: () => c.page == GalleryPage.qr,
                    ),
              primary: true,
              icon: Icons.qr_code_scanner_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _button(
              '从相册导入',
              app.qrAcquiring
                  ? null
                  : () => importQrFromGalleryAndParse(
                      context,
                      app,
                      onNotice: _archiveNotice,
                      canPublish: () => c.page == GalleryPage.qr,
                    ),
              icon: Icons.photo_library_outlined,
            ),
          ),
        ],
      ),
      _gap(18),
      if (app.qrAcquiring) _qrBusy(),
      if (app.qrError != null) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _text(
                app.qrError!.startsWith('图片') ? '图片未识别到二维码' : '解析失败',
                role: GalleryTypography.lead,
                weight: FontWeight.w600,
                color: t.warn,
              ),
              _gap(8),
              _text(
                app.qrError!,
                role: GalleryTypography.label,
                color: t.muted,
              ),
            ],
          ),
        ),
        _gap(14),
      ],
      if (qr != null) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 28, color: t.onTone),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _text(
                          '乘车码解析成功',
                          role: GalleryTypography.lead,
                          weight: FontWeight.w600,
                        ),
                        _text(
                          'JT/T 1179 · ${qr.raw.length} 字节',
                          role: GalleryTypography.caption,
                          color: t.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _gap(16),
              _text(
                qr.isQrExpired() ? '二维码已过期' : '获取时有效',
                role: GalleryTypography.caption,
                color: qr.isQrExpired() ? t.warn : t.ok,
              ),
            ],
          ),
        ),
        _gap(14),
        _expand(
          'live-qr:info',
          '乘车码信息',
          [
            _kv('版本', qr.versionHex),
            _kv('声明长度', '${qr.declaredLength} 字节'),
            _kv('数据总长', '${qr.raw.length} 字节'),
            _kv('发卡机构名称', issuer),
            _kv(
              '发卡机构标识',
              qr.issuerIdText ?? hexBytes(qr.issuerCertificate.issuerIdBytes),
            ),
            _kv('支付账户号', qr.paymentAccountDigits ?? qr.paymentAccountNumberHex),
            _kv('用户账户号', qr.userAccountNumberText ?? qr.userAccountNumberHex),
            _kv('发卡机构代码', qr.issuerCodeText ?? qr.issuerCodeHex),
            _kv('发码平台代码', qr.platformCodeText ?? qr.platformCodeHex),
            _kv(
              '用户账户类型',
              '0x${qr.userAccountType.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            ),
            _kv(
              '单次消费金额上限',
              '${(qr.singleConsumptionLimitFen / 100).toStringAsFixed(2)} 元',
            ),
          ],
          initiallyOpen: true,
          surface: false,
        ),
        _expand(
          'live-qr:time',
          '时间信息',
          [
            _kv('授权过期时间', _qrClock(qr.authorizationExpiryUtc)),
            _kv('二维码有效时间', '${qr.qrValiditySeconds} 秒'),
            _kv('二维码生成时间', _qrClock(qr.generationTimeUtc)),
            _kv('二维码状态', qr.isQrExpired() ? '已超出生效窗口' : '有效期内'),
          ],
          initiallyOpen: true,
          surface: false,
        ),
        if (certificate != null)
          _expand(
            'live-qr:certificate',
            '证书信息',
            [
              _kv(
                '记录头',
                '0x${certificate.recordHeader.toRadixString(16).padLeft(2, '0').toUpperCase()}',
              ),
              _kv('服务标识', certificate.serviceIdHex),
              _kv('中心 CA 公钥索引', '${certificate.caPublicKeyIndex}'),
              _kv(
                '证书格式',
                '0x${certificate.certificateFormat.toRadixString(16).padLeft(2, '0').toUpperCase()}',
              ),
              _kv(
                '证书失效日期',
                certificate.expiryDateUtc.toIso8601String().split('T').first,
              ),
              _kv('证书序列号', certificate.serialNumberHex),
              _kv(
                '公钥签名算法',
                '0x${certificate.signatureAlgorithm.toRadixString(16).padLeft(2, '0').toUpperCase()}',
              ),
              _kv('公钥长度', '${certificate.publicKeyLength}'),
              _gap(10),
              _hexBox(certificate.issuerPublicKeyHex),
            ],
            initiallyOpen: false,
            surface: false,
          ),
        _expand(
          'live-qr:raw',
          '原始数据（${qr.raw.length} 字节）',
          [_hexBox(hexBytes(qr.raw))],
          initiallyOpen: false,
          surface: false,
        ),
        _gap(12),
        _button(
          '清除解析结果',
          app.qrAcquiring ? null : app.clearQr,
          icon: Icons.delete_outline_rounded,
        ),
      ] else if (app.qrRaw != null)
        _expand(
          'live-qr:failed-raw',
          '原始数据（${app.qrRaw!.length} 字节）',
          [_hexBox(hexBytes(app.qrRaw!))],
          initiallyOpen: true,
          surface: false,
        )
      else if (!app.qrAcquiring && app.qrError == null)
        _empty(
          '尚未获取二维码',
          '扫描二维码或从相册导入，\n查看 JT/T 1179 乘车码读取信息。',
          icon: Icons.qr_code_2_rounded,
        ),
    ], id: 'live-qr');
  }

  String _qrClock(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _qrTime(int epoch) =>
      DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 19)
          .replaceFirst('T', ' ');

  List<Widget> _qrResult(GalleryRecord r) {
    final expired = r['expired'] == true;
    final raw = r['raw'] as List;
    final certificate = r['certificate'] as List;
    final basic = <List<String>>[
      ['版本', '0x80'],
      ['声明长度', '${raw.length - 3} 字节（数据体，自证书起）'],
      ['数据总长', '${raw.length} 字节'],
      ['发卡机构名称', '福路通·榕城通'],
      ['发卡机构标识', '01283910'],
      ['支付账户号', '6225880123456789'],
      ['用户账户号', '1380013800'],
      ['发卡机构代码', 'SHML'],
      ['发码平台代码', 'UNIO'],
      ['用户账户类型', '0x01'],
      ['单次消费金额上限', '20.00 元'],
    ];
    final timing = <List<String>>[
      ['授权过期时间', _qrTime(2000000000)],
      ['二维码有效时间', '300 秒'],
      ['二维码生成时间', _qrTime(r['generation'] as int)],
      ['二维码状态', expired ? '已超出生成时间 + 有效时间窗口' : '有效期内（获取时）'],
    ];
    final cert = <List<String>>[
      ['记录头', '0x24'],
      ['服务标识', '01010000（交通电子现金应用）'],
      ['中心 CA 公钥索引', '1'],
      ['证书格式', '0x12'],
      ['发卡机构标识', '01283910'],
      ['证书失效日期', '2030-12-31'],
      ['证书序列号', '010203'],
      ['公钥签名算法', '0x04（SM2）'],
      ['公钥加密算法（保留）', '0x04'],
      ['公钥参数标识', '0x00'],
      ['公钥长度', '0x21（33 字节）'],
      ['发卡机构公钥', galleryHex(certificate.sublist(20, 53))],
    ];
    return [
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2_rounded, size: 28, color: t.onTone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        '乘车码解析成功',
                        role: GalleryTypography.lead,
                        weight: FontWeight.w600,
                      ),
                      _text(
                        'JT/T 1179 · ${c.qr.origin == 'gallery' ? '相册导入' : '扫描二维码'}',
                        role: GalleryTypography.caption,
                        color: t.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _gap(16),
            _text(
              '${expired ? '二维码已过期' : '获取时有效'}　有效时间 300 秒',
              role: GalleryTypography.caption,
              color: expired ? t.warn : t.ok,
            ),
          ],
        ),
      ),
      _gap(14),
      _expand(
        'qr:info',
        '乘车码信息',
        basic.map((row) => _kv(row[0], row[1])).toList(),
        initiallyOpen: true,
        surface: false,
      ),
      _expand(
        'qr:time',
        '时效信息',
        [
          ...timing.map((row) => _kv(row[0], row[1])),
          _gap(8),
          _text(
            '时间均以 UTC+08:00 显示；状态按获取时刻展示。',
            role: GalleryTypography.caption,
            color: t.muted,
          ),
        ],
        initiallyOpen: true,
        surface: false,
      ),
      _expand('qr:key', '用户公钥与自定义域', [
        _kv('支付账户用户公钥', galleryHex(r['userKey'] as List)),
        _kv('发卡机构自定义域', '3 字节'),
        _gap(8),
        _hexBox(galleryHex(r['custom'] as List)),
      ], surface: false),
      _expand('qr:certificate', '发卡机构公钥证书（117 字节）', [
        ...cert.map((row) => _kv(row[0], row[1])),
        _gap(10),
        _hexBox(galleryHex(certificate)),
      ], surface: false),
      _expand('qr:raw', '二维码原始数据（${raw.length} 字节）', [
        _hexBox(galleryHex(raw)),
      ], surface: false),
      _text(
        '仅展示解析信息，未进行密码学签名验证。',
        role: GalleryTypography.caption,
        color: t.muted,
      ),
    ];
  }
}
