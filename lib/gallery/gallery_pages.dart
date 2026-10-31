part of 'gallery_app.dart';

extension _GalleryPages on _GalleryViewState {
  Widget _home() {
    final card = c.current;
    final reading = c.readState == GalleryReadState.reading;
    final failed = c.readState == GalleryReadState.failed;
    final recent = c.trips.where((r) => r['kind'] != 'event').firstOrNull;
    return _list([
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 14),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 30,
                  height: 30,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _text('TrafArch', size: 18, weight: FontWeight.w700),
              ),
              if (MediaQuery.sizeOf(context).width >= 390)
                _text('10月27日 周二', size: 10, color: t.onTone),
              const SizedBox(width: 6),
              _icon(
                Icons.qr_code_scanner_rounded,
                '扫码',
                () => c.navigate(GalleryPage.qr),
              ),
              const SizedBox(width: 8),
              _icon(
                Icons.settings_outlined,
                '设置',
                () => c.navigate(GalleryPage.settings),
              ),
            ],
          ),
        ),
      ),
      Stack(
        children: [
          if (!c.hasRead)
            SizedBox(
              height: 116 + _extraTextScale * 80,
              child: _panel(
                Row(
                  children: [
                    Icon(Icons.contactless_outlined, size: 32, color: t.onTone),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(
                            reading ? '正在读取卡片…' : '把交通卡贴近手机背面',
                            size: 16,
                            weight: FontWeight.w600,
                          ),
                          _gap(5),
                          _text(
                            reading ? '请保持贴卡，直到读取完成' : '读取余额与行程',
                            size: 12,
                            color: t.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                color: t.tone,
                border: false,
                radius: 22,
              ),
            )
          else if (card.saved)
            _face(card)
          else
            SizedBox(
              height: 194 + _extraTextScale * 80,
              child: _panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _text(
                            card.name,
                            size: 17,
                            weight: FontWeight.w700,
                            lines: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _text(
                          '交通联合\nCHINA T-UNION',
                          size: 10,
                          color: t.onTone,
                          align: TextAlign.right,
                        ),
                      ],
                    ),
                    _gap(5),
                    _text(
                      '**** ${card.tail}',
                      size: 12,
                      mono: true,
                      color: t.onTone,
                    ),
                    const Spacer(),
                    _text('当前余额', size: 11, color: t.muted),
                    _gap(4),
                    _amount(card),
                  ],
                ),
                color: t.tone,
                radius: 22,
                border: false,
              ),
            ),
          if (reading && c.hasRead)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: t.bg.withValues(alpha: .88),
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(Icons.contactless_outlined, color: t.onTone, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _text(
                        '请保持贴卡\n正在读取卡片…',
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      _gap(10),
      Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: failed ? t.warn : t.ok,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: _text(
                reading
                    ? '请保持贴卡 / 读取中'
                    : failed
                    ? (c.hasRead ? '读取失败，保留上次结果' : '未能读到卡片')
                    : c.hasRead
                    ? '今天 09:41 读取成功'
                    : 'NFC 已就绪（演示）',
                size: 12,
                color: failed ? t.warn : t.onTone,
              ),
            ),
          ),
          if (c.hasRead && !reading && !failed)
            _chip(
              card.saved
                  ? c.autoSave
                        ? '已自动保存'
                        : '已保存'
                  : '未保存',
            ),
        ],
      ),
      if (reading) ...[
        _gap(8),
        LinearProgressIndicator(
          minHeight: 2,
          color: t.onTone,
          backgroundColor: t.tone,
          value: MediaQuery.disableAnimationsOf(context) ? .6 : null,
        ),
      ],
      _gap(16),
      if (reading)
        _button('正在读取…', null, primary: true, icon: Icons.contactless_outlined)
      else if (!c.hasRead || failed)
        _button(
          failed ? '重新读取' : '开始读取',
          () => c.read(),
          primary: true,
          icon: Icons.contactless_outlined,
        )
      else if (!card.saved)
        Row(
          children: [
            Expanded(
              child: _button(
                '保存卡片',
                () => c.showOverlay(GalleryOverlay.save),
                primary: true,
                icon: Icons.save_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _button(
                '再次读取',
                () => c.read(),
                icon: Icons.refresh_rounded,
              ),
            ),
          ],
        )
      else
        Row(
          children: [
            Expanded(
              child: _button(
                '再次读取',
                () => c.read(),
                primary: true,
                icon: Icons.refresh_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _button(
                '更换卡面',
                () => c.showOverlay(GalleryOverlay.face, card: card),
                icon: Icons.palette_outlined,
              ),
            ),
          ],
        ),
      _gap(16),
      if (c.hasRead && recent != null)
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _text('最近一次行程', size: 12, color: t.muted)),
                  _text('今天', size: 12, color: t.muted),
                ],
              ),
              _gap(8),
              _trip(recent),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        )
      else if (c.hasRead)
        _empty('暂无行程记录', '这张卡片没有可展示的行程', icon: Icons.route_outlined)
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(Icons.nfc_rounded, size: 38, color: t.onTone),
              _gap(12),
              _text('贴卡，了解你的每一次出行', size: 15, weight: FontWeight.w600),
              _gap(8),
              _text(
                '支持交通联合、城市一卡通及部分 FeliCa 卡片\n本次为交互演示，使用模拟数据',
                size: 12,
                color: t.muted,
                align: TextAlign.center,
              ),
            ],
          ),
        ),
      if (c.hasRead)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(),
              TextButton(
                onPressed: () => c.navigate(GalleryPage.trips),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                  foregroundColor: t.onTone,
                ),
                child: const Text('查看全部行程  ›', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      _gap(8),
      _text('模拟数据', size: 11, color: t.muted),
    ]);
  }

  Widget _trips() {
    final trips = c.filteredTrips;
    final grouped = <String, List<GalleryRecord>>{};
    for (final trip in trips) {
      grouped.putIfAbsent(trip['date'] as String, () => []).add(trip);
    }
    final count = c.trips.where((t) => t['kind'] != 'event').length;
    return _list([
      _header('行程', subtitle: c.hasRead ? c.current.name : '读取卡片后查看最近行程'),
      if (c.hasRead)
        _panel(
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text('交易 $count 笔', size: 13, weight: FontWeight.w600),
                    _gap(12),
                    _text('行程 $count 次', size: 12, color: t.onTone),
                  ],
                ),
              ),
              Flexible(child: _amount(c.current, size: 28)),
            ],
          ),
          color: t.tone,
          border: false,
        ),
      _gap(14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterButton(c.source, GalleryOverlay.source),
          _filterButton(c.mode, GalleryOverlay.mode),
        ],
      ),
      if (!c.hasRead)
        _empty(
          '尚未读取卡片',
          '请先在首页读取一张交通卡',
          icon: Icons.route_outlined,
          action: _button(
            '前往首页',
            () => c.navigate(GalleryPage.home),
            primary: true,
          ),
        )
      else if (trips.isEmpty)
        _empty(
          c.trips.isEmpty ? '暂无行程记录' : '当前筛选下没有记录',
          c.trips.isEmpty ? '卡内记录可能不完整' : '试试其他来源或交通方式',
          icon: Icons.route_outlined,
        )
      else
        ...grouped.entries.expand(
          (entry) => [
            _sectionTitle(entry.key, trailing: '${entry.value.length} 条'),
            _panel(
              Column(
                children: [
                  for (int i = 0; i < entry.value.length; i++) ...[
                    if (i > 0) const Divider(),
                    _trip(entry.value[i]),
                  ],
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ],
        ),
    ]);
  }

  Widget _filterButton(String label, GalleryOverlay overlay) =>
      PopupMenuButton<String>(
        tooltip: overlay == GalleryOverlay.source ? '选择记录来源' : '选择交通方式',
        initialValue: label,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        color: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (value) => c.update(() {
          if (overlay == GalleryOverlay.source) {
            c.source = value;
          } else {
            c.mode = value;
          }
        }),
        itemBuilder: (_) =>
            (c.data.json[overlay == GalleryOverlay.source ? 'sources' : 'modes']
                    as List)
                .cast<String>()
                .map(
                  (value) => CheckedPopupMenuItem<String>(
                    value: value,
                    checked: value == label,
                    child: _text(value, size: 13),
                  ),
                )
                .toList(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: ShapeDecoration(
            color: label.startsWith('全部') ? t.surface : t.tone,
            shape: StadiumBorder(side: BorderSide(color: t.line)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: t.onTone)),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, size: 16),
            ],
          ),
        ),
      );

  Widget _trip(GalleryRecord trip, {bool interactive = true}) {
    final rail = trip['kind'] == 'rail';
    final event = trip['kind'] == 'event';
    final sub = (trip['sub'] as String? ?? '未记录 → 未记录').split(' → ');
    final entry = trip['entryStation'] as String? ?? sub.first;
    final exit =
        trip['exitStation'] as String? ?? (sub.length > 1 ? sub.last : '未记录');
    final entryLine =
        trip['entryLine'] as String? ??
        (rail
            ? (trip['title'] as String).replaceFirst('地铁 ', '')
            : (trip['title'] as String).replaceFirst('公交 ', ''));
    final exitLine = trip['exitLine'] as String? ?? entryLine;
    Widget endpoint(String phase, String line, String time, String station) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _text(phase, size: 11, color: t.muted, height: 18 / 11),
                  _chip(line),
                  _text(time, size: 10, color: t.onTone, height: 1.8),
                ],
              ),
            ),
            _gap(6),
            _text(station, size: 14, height: 22 / 14, weight: FontWeight.w600),
          ],
        );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: event
          ? Row(
              children: [
                Icon(Icons.login_rounded, size: 18, color: t.onTone),
                const SizedBox(width: 12),
                _text(
                  trip['time'] as String,
                  size: 11,
                  mono: true,
                  color: t.muted,
                ),
                const SizedBox(width: 12),
                Expanded(child: _text(trip['title'] as String, size: 13)),
                _text('过程记录', size: 10, color: t.muted),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: rail ? t.tone : t.ok.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        rail
                            ? Icons.train_outlined
                            : Icons.directions_bus_outlined,
                        size: 17,
                        color: rail ? t.onTone : t.ok,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _text(
                      rail ? '轨道交通' : '公交',
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _text(
                        trip['city'] as String? ?? '',
                        size: 11,
                        color: t.muted,
                      ),
                    ),
                    if (trip['foreign'] == true) ...[
                      _chip('异地用卡'),
                      const SizedBox(width: 6),
                    ],
                    _text(
                      trip['amount'] as String,
                      size: 13,
                      weight: FontWeight.w700,
                    ),
                  ],
                ),
                _gap(13),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: endpoint(
                        rail ? '进站' : '上车',
                        entryLine,
                        trip['entryTime'] as String? ?? '未记录',
                        entry,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 25, 8, 0),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: t.muted,
                      ),
                    ),
                    Expanded(
                      child: endpoint(
                        rail ? '出站' : '下车',
                        exitLine,
                        trip['time'] as String? ?? '未记录',
                        exit,
                      ),
                    ),
                  ],
                ),
                if (rail && trip['transferKnown'] == false) ...[
                  _gap(10),
                  _text('未记录换乘站', size: 11, color: t.onTone),
                ],
              ],
            ),
    );
    return interactive
        ? Semantics(
            button: true,
            label: '${trip['title']}，${trip['sub']}，${trip['amount']}',
            child: InkWell(
              onTap: () => c.showOverlay(GalleryOverlay.trip, trip: trip),
              child: body,
            ),
          )
        : body;
  }

  Widget _cards() => _list([
    _header(
      '卡包',
      subtitle: '已保存 ${c.savedCards.length} 张',
      actions: [
        _icon(Icons.download_outlined, '导出卡片记录', () => c.export(all: true)),
        const SizedBox(width: 8),
        _icon(
          Icons.settings_outlined,
          '设置',
          () => c.navigate(GalleryPage.settings),
        ),
      ],
    ),
    if (c.savedCards.isEmpty)
      _empty(
        '还没有保存的卡片',
        '读取一张交通卡并保存到卡包',
        action: _button(
          '前往首页',
          () => c.navigate(GalleryPage.home),
          primary: true,
        ),
      ),
    ...c.savedCards.map(
      (card) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _panel(
          InkWell(
            onTap: () => c.openCard(card),
            child: Row(
              children: [
                _face(card, miniature: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        card.name,
                        size: 14,
                        weight: FontWeight.w600,
                        lines: 1,
                      ),
                      _gap(3),
                      _text(
                        '${card.city} ${card.type}',
                        size: 11,
                        color: t.muted,
                        lines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _text(
                          card.balance(c.includeOverdraft),
                          size: 14,
                          weight: FontWeight.w700,
                        ),
                      ),
                      _gap(4),
                      _text(card.count, size: 10, color: t.muted),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 40,
                  child: IconButton(
                    tooltip: '${card.name} 管理',
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        c.showOverlay(GalleryOverlay.cardMenu, card: card),
                    icon: const Icon(Icons.more_horiz_rounded, size: 21),
                  ),
                ),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        ),
      ),
    ),
  ]);

  Widget _detail() {
    final card = c.selectedCard;
    final ledger = c.ledger(card);
    return _list([
      _header(
        '卡片详情',
        back: true,
        actions: [_icon(Icons.download_outlined, '导出本卡记录', () => c.export())],
      ),
      _face(card),
      _gap(16),
      _text(card.name, size: 18, weight: FontWeight.w600),
      _gap(4),
      _text(
        '${card.city} · 尾号 ${card.tail}   上次读取 ${card.when}',
        size: 11,
        color: t.muted,
      ),
      _gap(18),
      _tabs(
        ['最近交易', '本周消费', '卡片信息'],
        c.detailTab,
        (i) => c.update(() => c.detailTab = i),
      ),
      _gap(16),
      GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 100) {
            c.update(
              () => c.detailTab = (c.detailTab + (velocity < 0 ? 1 : -1)).clamp(
                0,
                2,
              ),
            );
          }
        },
        child: switch (c.detailTab) {
          0 => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ledger.isEmpty) _empty('暂无交易记录', '卡内记录可能不完整'),
              ...ledger.map(
                (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(r['date'] as String? ?? '日期未记录'),
                    _panel(
                      _trip(r),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ],
                ),
              ),
              _gap(16),
              _text('仅展示样例中保留的记录，可能不代表完整历史。', size: 11, color: t.muted),
            ],
          ),
          1 => _weekly(card),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                Column(
                  children: [
                    for (final row in <(String, String)>[
                      ('完整卡号', card.pan),
                      ('发卡地', card.city),
                      ('卡种', card.type),
                      ('有效期', card.valid == '—' ? '未知' : '${card.valid}（未记录日）'),
                      ('当前余额', card.balance(c.includeOverdraft)),
                      ('最近读取', card.when),
                      (
                        '协议',
                        card.type == 'FeliCa' ? 'FeliCa' : 'ISO-DEP / 交通联合',
                      ),
                    ])
                      _kv(row.$1, row.$2),
                  ],
                ),
              ),
              _sectionTitle('原始数据', trailing: '模拟样例'),
              if (c.data.raw[card.id] case final Map raw) ...[
                _hexBox(
                  'SFI 0x18\n${raw['sfi18']}\n\nSFI 0x1E\n${raw['sfi1e']}',
                ),
                _gap(8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: '${raw['sfi18']}\n${raw['sfi1e']}',
                          ),
                        );
                        _toast('已复制模拟原始数据');
                      },
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('复制'),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          c.showOverlay(GalleryOverlay.rawFeedback),
                      icon: const Icon(Icons.feedback_outlined, size: 16),
                      label: const Text('反馈预览'),
                    ),
                  ],
                ),
              ] else
                _text('本样例未保留原始数据', size: 12, color: t.muted),
              _gap(16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _button('重命名', () => c.showOverlay(GalleryOverlay.rename)),
                  _button('更换卡面', () => c.showOverlay(GalleryOverlay.face)),
                  _button('导出记录', () => c.export()),
                  _button(
                    '删除本卡',
                    () => c.showOverlay(GalleryOverlay.delete),
                    danger: true,
                  ),
                ],
              ),
            ],
          ),
        },
      ),
    ], id: 'detail-${card.id}-${c.detailTab}');
  }

  Widget _weekly(GalleryCard card) {
    final values = List<int>.filled(7, 0);
    final categories = <String, int>{};
    int count = 0;
    for (final row in c.ledger(card)) {
      final date = DateTime.tryParse(row['isoDate'] as String? ?? '');
      if (date == null) continue;
      final day = date.difference(DateTime(2026, 10, 26)).inDays;
      if (day < 0 || day > 6) continue;
      final amount = RegExp(r'[\d.]+')
          .firstMatch(row['amount'] as String? ?? '')
          ?.group(0);
      if (amount == null) continue;
      final fen = (double.parse(amount) * 100).round();
      values[day] += fen;
      final kind = row['kind'] == 'rail'
          ? '轨道交通'
          : row['kind'] == 'bus'
          ? '公共汽电车'
          : '其他';
      categories.update(kind, (value) => value + fen, ifAbsent: () => fen);
      count++;
    }
    final total = values.fold(0, (sum, value) => sum + value);
    final max = math.max(1, values.reduce(math.max));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _text('本周消费', size: 12, color: t.muted),
              _gap(6),
              _text(
                '¥${formatGalleryMoney(total)}',
                size: 36,
                weight: FontWeight.w700,
              ),
              _gap(12),
              Row(
                children: [
                  Expanded(child: _text('乘车 $count 次', size: 13)),
                  _text(
                    '日均 ¥${formatGalleryMoney((total / 7).round())}',
                    size: 12,
                    color: t.muted,
                  ),
                ],
              ),
            ],
          ),
          color: t.tone,
          border: false,
        ),
        _sectionTitle('每日消费', trailing: '10月26日 — 11月1日'),
        _panel(
          Semantics(
            label: List.generate(
              7,
              (i) =>
                  '${['周一', '周二', '周三', '周四', '周五', '周六', '周日'][i]} ${formatGalleryMoney(values[i])}元',
            ).join('，'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                7,
                (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        _text(formatGalleryMoney(values[i]), size: 10),
                        _gap(8),
                        Container(
                          height: 92,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            color: t.surface2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Container(
                            height: math.max(2, values[i] / max * 92),
                            decoration: BoxDecoration(
                              color: t.onTone,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        _gap(8),
                        _text(
                          ['一', '二', '三', '四', '五', '六', '日'][i],
                          size: 11,
                          color: t.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _gap(16),
        _sectionTitle('分类开销'),
        if (categories.isEmpty)
          _text('暂无本周可统计的样例记录', size: 12, color: t.muted)
        else
          _panel(
            Column(
              children: categories.entries
                  .map(
                    (entry) =>
                        _kv(entry.key, '¥${formatGalleryMoney(entry.value)}'),
                  )
                  .toList(),
            ),
          ),
        _gap(12),
        _text('仅统计本周有明确日期的样例记录；未记录日期的交易不计入。', size: 11, color: t.muted),
      ],
    );
  }

  Widget _footprints() => _list([
    _header('足迹'),
    Row(
      children:
          [('${c.footprints.length}', '去过站点'), ('16', '累计到访'), ('3', '本月新站点')]
              .map(
                (pair) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(pair.$1, size: 24, weight: FontWeight.w700),
                          _gap(4),
                          _text(pair.$2, size: 11, color: t.muted),
                        ],
                      ),
                      padding: const EdgeInsets.all(13),
                    ),
                  ),
                ),
              )
              .toList(),
    ),
    _gap(18),
    ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 372 / 286,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/gallery/footprints-map.svg',
                  fit: BoxFit.fill,
                  semanticsLabel: '站点地图示意，完整信息见下方站点列表',
                ),
              ),
              ...c.footprints.indexed.map(
                (item) => Positioned(
                  left: (item.$2['x'] as num) / 100 * box.maxWidth - 5,
                  top: (item.$2['y'] as num) / 100 * box.maxHeight - 5,
                  child: Semantics(
                    label: '${item.$2['name']}，${item.$2['visits']}次到访',
                    child: Container(
                      width: item.$1 == 0 ? 14 : 10,
                      height: item.$1 == 0 ? 14 : 10,
                      decoration: BoxDecoration(
                        color: item.$1 == 0 ? t.action : t.onTone,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.bg, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    _sectionTitle('全部站点'),
    _panel(
      Column(
        children: c.footprints
            .map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      s['kind'] == 'rail'
                          ? Icons.train_outlined
                          : Icons.directions_bus_outlined,
                      color: t.onTone,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(
                            s['name'] as String,
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                          _gap(3),
                          _text(s['line'] as String, size: 11, color: t.muted),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _text('${s['visits']} 次到访', size: 12),
                        _text(s['last'] as String, size: 10, color: t.muted),
                      ],
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    ),
  ]);

  Widget _settings() => _list([
    _header('设置', back: true),
    _sectionTitle('读卡与数据'),
    _panel(
      Column(
        children: [
          _switch(
            '读取后自动保存',
            c.autoSave,
            c.setAutoSave,
            subtitle: '每次模拟读取后保存到演示卡包',
          ),
          const Divider(),
          _switch(
            '上海交通卡可透支余额',
            c.includeOverdraft,
            (value) => c.update(() => c.includeOverdraft = value),
            subtitle:
                '总余额${c.includeOverdraft ? '包含' : '扣除'}固定 8 元额度，CU 余额不重复扣除',
          ),
          const Divider(),
          _settingRow(
            '知识库',
            () => c.navigate(GalleryPage.knowledge),
            subtitle: 'TU 41 个地区 / CU 7 个地区',
            icon: Icons.menu_book_outlined,
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    _sectionTitle('外观'),
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text('外观主题', size: 14),
                _gap(10),
                _tabs(
                  ['跟随系统', '浅色', '深色'],
                  [
                    ThemeMode.system,
                    ThemeMode.light,
                    ThemeMode.dark,
                  ].indexOf(c.themeMode),
                  (i) => c.update(
                    () => c.themeMode = [
                      ThemeMode.system,
                      ThemeMode.light,
                      ThemeMode.dark,
                    ][i],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          _switch(
            '莫奈取色',
            c.monet,
            (value) => c.update(() => c.monet = value),
            subtitle: c.monet ? '演示中使用雾蓝回退配色' : '使用手动选择的主题配色',
          ),
          if (!c.monet)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: Row(
                children: c.data.palettes.entries.map((entry) {
                  final value = entry.value as GalleryRecord;
                  final swatch = Color(
                    int.parse(
                      (value['swatch'] as String).replaceFirst('#', 'ff'),
                      radix: 16,
                    ),
                  );
                  return Expanded(
                    child: Semantics(
                      selected: c.palette == entry.key,
                      child: TextButton(
                        onPressed: () => c.update(() => c.palette = entry.key),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: c.palette == entry.key
                                  ? t.onTone
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: swatch,
                                shape: BoxShape.circle,
                              ),
                              child: c.palette == entry.key
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    )
                                  : null,
                            ),
                            _gap(7),
                            _text(
                              value['name'] as String,
                              size: 11,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text('底栏样式', size: 14),
                _gap(10),
                _tabs(
                  ['悬浮', '下沉'],
                  c.docked ? 1 : 0,
                  (i) => c.update(() => c.docked = i == 1),
                ),
              ],
            ),
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    _sectionTitle('日志'),
    _panel(
      Column(
        children: [
          _switch(
            '启用运行日志',
            c.logsEnabled,
            c.setLogs,
            subtitle: '仅记录本次演示会话中的界面操作',
          ),
          if (c.logsEnabled) ...[
            const Divider(),
            _settingRow(
              '导出日志',
              () => c.export(log: true),
              subtitle: '预览模拟日志，不保存文件',
              icon: Icons.download_outlined,
            ),
          ],
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    _sectionTitle('演示工具'),
    _panel(
      Column(
        children: [
          _settingRow(
            '演示场景',
            () => c.navigate(GalleryPage.scenes),
            subtitle: '52 个预置场景 · 切换后载入固定样例',
            icon: Icons.dashboard_customize_outlined,
          ),
          const Divider(),
          _settingRow(
            '恢复初始样例',
            c.reset,
            subtitle: '清空本次演示操作，回到未读卡首页',
            icon: Icons.restart_alt_rounded,
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    if (widget.onDisableBeta != null) ...[
      _gap(12),
      _panel(
        _switch(
          '启用新界面（beta）',
          true,
          (_) => widget.onDisableBeta!(),
          subtitle: '使用模拟数据；关闭后返回现有界面',
        ),
        padding: EdgeInsets.zero,
      ),
    ],
    _sectionTitle('关于'),
    _panel(
      Column(
        children: [
          _settingRow(
            '反馈',
            () => c.showOverlay(GalleryOverlay.rawFeedback),
            subtitle: '查看反馈内容预览',
            icon: Icons.feedback_outlined,
          ),
          const Divider(),
          _settingRow(
            '关于',
            () => c.showOverlay(GalleryOverlay.about),
            subtitle: '${AppInfo.version} · Demo 2.4.0',
            icon: Icons.info_outline,
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    _gap(20),
    _text(
      '交互演示 · 全部卡片和行程均为模拟数据\n重启后恢复初始样例',
      size: 11,
      color: t.muted,
      align: TextAlign.center,
    ),
  ]);

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    title: _text(label, size: 14),
    subtitle: subtitle == null
        ? null
        : _text(subtitle, size: 11, color: t.muted),
    value: value,
    onChanged: onChanged,
  );
  Widget _settingRow(
    String label,
    VoidCallback onTap, {
    String? subtitle,
    IconData? icon,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: icon == null ? null : Icon(icon, size: 21, color: t.onTone),
    title: _text(label, size: 14),
    subtitle: subtitle == null
        ? null
        : _text(subtitle, size: 11, color: t.muted),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: onTap,
  );

  Widget _scenes() {
    final grouped = <String, List<GalleryScene>>{};
    for (final s in c.data.scenes) {
      grouped.putIfAbsent(s.group, () => []).add(s);
    }
    return _list([
      _header('演示场景', back: true),
      _text('切换场景将载入独立的固定样例。所有操作仅在本次运行中保留。', size: 12, color: t.muted),
      _gap(12),
      _button('恢复初始样例', c.reset, icon: Icons.restart_alt_rounded),
      ...grouped.entries.expand(
        (entry) => [
          _sectionTitle(entry.key),
          _panel(
            Column(
              children: entry.value
                  .map(
                    (s) => _settingRow(
                      s.name,
                      () => c.applyScene(s),
                      subtitle: s.width == null ? null : '设计参考宽度 ${s.width}dp',
                    ),
                  )
                  .toList(),
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    ]);
  }
}
