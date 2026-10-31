part of 'gallery_app.dart';

extension _GalleryInspection on _GalleryViewState {
  Widget _expert() => _list([
    _header('专家分析'),
    _tabs(
      (c.data.json['expertTabs'] as List).cast<String>(),
      c.expertTab,
      (i) => c.update(() => c.expertTab = i),
      scroll: true,
    ),
    _gap(16),
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
          _tabs(
            ['交通卡', '银行卡', 'FeliCa'],
            ['card', 'bank', 'felica'].indexOf(c.expertKind),
            (i) => c.update(() => c.expertKind = ['card', 'bank', 'felica'][i]),
          ),
          _gap(14),
          ..._expertSections(c.expertKind),
          _text('以上为演示样例，未保留的字段显示未知。', size: 12, color: t.muted),
        ],
        1 => [..._expertSections('transit')],
        2 => [_compliance()],
        _ => [
          _text(
            '保留的示例帧按原顺序完整展示。SELECT、GET BALANCE 和 0x1A 原始响应未保留。',
            size: 12,
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
              _spacedHex((c.data.raw['shanghai'] as Map)['sfi1e'] as String),
            ),
          ], initiallyOpen: true),
        ],
      },
  ], id: 'expert-${c.expertTab}-${c.expertKind}');

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
              _text('JT/T 978 符合性', size: 14, weight: FontWeight.w600),
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
                            _text(r[1], size: 11, color: t.muted),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _text(r[2], size: 11, color: t.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _gap(12),
        _text('覆盖度为示例字段完整度，未保留字段需进一步核验。', size: 12, color: t.muted),
      ],
    );
  }

  Widget _knowledge() {
    final data =
        ((c.data.knowledge['systems'] as Map)[c.knowledgeTab] as GalleryRecord);
    final regions = (data['regions'] as List).cast<GalleryRecord>();
    return _list([
      _header('知识库', back: true),
      _tabs(
        ['交通联合 TU', '城市一卡通 CU'],
        c.knowledgeTab == 'tu' ? 0 : 1,
        (i) => c.update(() => c.knowledgeTab = i == 0 ? 'tu' : 'cu'),
      ),
      _gap(16),
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _text(
                    '${data['name']}参考数据',
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                ),
                _text('本地数据', size: 11, color: t.onTone),
              ],
            ),
            _gap(18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        '${regions.length}',
                        size: 28,
                        weight: FontWeight.w700,
                      ),
                      _text('覆盖地区', size: 12, color: t.muted),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        _groupNumber(data['entries'] as int),
                        size: 28,
                        weight: FontWeight.w700,
                      ),
                      _text('站点编码条目', size: 12, color: t.muted),
                    ],
                  ),
                ),
              ],
            ),
            _gap(14),
            _text(
              '用于识别读卡结果中的城市、线路与站点。\n数据快照 ${c.data.knowledge['captured']}，两个体系独立统计。',
              size: 11,
              color: t.muted,
            ),
          ],
        ),
        color: t.tone,
        border: false,
        radius: 20,
      ),
      _gap(16),
      _expand('knowledge:meta', '数据概况', [
        _kv('源文件', data['source'] as String),
        _kv('数据库版本', data['version'].toString()),
        _kv('数据包版本', '${data['formatVersion']}'),
        _kv('来源 SHA256', data['sha256'] as String),
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
      _sectionTitle('覆盖地区', trailing: '按城市编码排序'),
      ...regions.indexed.map((item) {
        final r = item.$2;
        final key = '${c.knowledgeTab}:${item.$1}';
        final open = c.knowledgeExpanded.contains(key);
        final lines = (r['lines'] as List).cast<GalleryRecord>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _panel(
            Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: _text(
                    r['name'] as String,
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                  subtitle: _text(
                    '${r['lineCount']} 条线路 · ${_groupNumber(r['entries'] as int)} 条编码\n${r['province'] ?? ''}',
                    size: 11,
                    color: t.muted,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _text(
                        r['code'] as String,
                        size: 11,
                        mono: true,
                        color: t.muted,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        open
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                      ),
                    ],
                  ),
                  onTap: () => c.update(
                    () => open
                        ? c.knowledgeExpanded.remove(key)
                        : c.knowledgeExpanded.add(key),
                  ),
                ),
                if (open) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: lines.indexed.map((lineItem) {
                        final line = lineItem.$2;
                        final lineKey = '$key:${lineItem.$1}';
                        final lineOpen = c.knowledgeExpanded.contains(lineKey);
                        final stations = (line['stations'] as List)
                            .cast<String>();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InkWell(
                              onTap: () => c.update(
                                () => lineOpen
                                    ? c.knowledgeExpanded.remove(lineKey)
                                    : c.knowledgeExpanded.add(lineKey),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _text(
                                        line['name'] as String,
                                        size: 13,
                                      ),
                                    ),
                                    _text(
                                      '${stations.length} 站',
                                      size: 11,
                                      color: t.muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      lineOpen
                                          ? Icons.expand_more_rounded
                                          : Icons.chevron_right_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (lineOpen)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: stations
                                      .map(
                                        (s) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: t.surface2,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: _text(s, size: 12),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            const Divider(),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
            padding: EdgeInsets.zero,
          ),
        );
      }),
    ], id: 'knowledge-${c.knowledgeTab}');
  }

  String _groupNumber(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  Widget _qr() {
    final q = c.qr;
    final title = switch (q.view) {
      'camera' || 'camera-error' => '扫描乘车码',
      'gallery' => '相册导入演示',
      _ => '乘车码解析',
    };
    final note = _text(
      '演示模式 · 使用模拟数据预览扫码与导入流程',
      size: 11,
      color: t.muted,
      align: TextAlign.center,
    );
    return _list([
      _header(title, back: true),
      if (q.view == 'camera') ...[
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
                      _text('扫码取景演示', size: 12, color: t.muted),
                    ],
                  ),
                ),
              ),
              _gap(20),
              _text(
                '将乘车码二维码对准取景框',
                size: 13,
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
          q.torch ? '闪光灯已开启（演示）' : '闪光灯（演示）',
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
        _expand('qr:scenarios', '演示其他状态', [
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
      ] else if (q.view == 'camera-error') ...[
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
      ] else if (q.view == 'gallery') ...[
        _text('选择一张样例图片，演示识别与错误恢复流程。', size: 13, color: t.muted),
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
                title: _text(sample.$2, size: 14, weight: FontWeight.w600),
                subtitle: _text(sample.$3, size: 12, color: t.muted),
                onTap: q.busy ? null : () => q.acquire(sample.$1),
              ),
              padding: const EdgeInsets.all(16),
            ),
          ),
        if (q.busy) _qrBusy(),
        _gap(16),
        note,
      ] else ...[
        _text('只读解析交通一卡通乘车码，查看账户、机构、时效和原始数据。', size: 13, color: t.muted),
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
                  size: 16,
                  weight: FontWeight.w600,
                  color: t.warn,
                ),
                _gap(8),
                _text(q.error!, size: 13, color: t.muted),
                _gap(8),
                _text('可重新扫描二维码或从相册导入。', size: 12, color: t.muted),
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
        _text('正在获取并解析…', size: 13, color: t.onTone),
      ],
    ),
  );

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
      ['发卡机构名称', '福路通·榕城通（演示）'],
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
                      _text('乘车码解析成功', size: 16, weight: FontWeight.w600),
                      _text(
                        'JT/T 1179 · ${c.qr.origin == 'gallery' ? '相册导入' : '扫描二维码'} · 模拟数据',
                        size: 11,
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
              size: 12,
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
          _text('时间均以 UTC+08:00 显示；状态按获取时刻展示。', size: 11, color: t.muted),
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
      _text('仅展示解析信息，未进行密码学签名验证。', size: 11, color: t.muted),
    ];
  }
}
