import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/card/card_parser.dart';
import '../../core/nfc/nfc_models.dart';
import '../../core/transit/city_union/city_union_models.dart';
import '../../core/transit/local_card/cards/shanghai_transit_union_models.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_display.dart';
import '../../core/transit/tunion/qr/jt_t1179_qr_parser.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../core/transit/tunion/tunion_process_parser.dart';
import '../../core/ui_constants.dart';
import '../../state/app_state.dart';
import '../bank_card/domain/models/bank_card_result.dart';
import '../bank_card/presentation/bank_card_result_view.dart';
import '../settings/settings_action_button.dart';

/// 信息获取页签的展示类型：NFC 卡片识别 / 乘车码二维码 / 银行卡只读分析。
enum _InfoGetKind { card, qr, bank }

class ExpertPage extends StatefulWidget {
  final AppState app;
  const ExpertPage({super.key, required this.app});

  @override
  State<ExpertPage> createState() => _ExpertPageState();
}

class _ExpertPageState extends State<ExpertPage> {
  /// 空边框形状：去掉 ExpansionTile 展开时默认在内容上下绘制的两条分隔线。
  static const Border _borderlessShape = Border();

  /// 信息获取页签当前展示类型；随首页获取的数据自动切换
  /// （读到卡片 → 卡片识别，获取到二维码 → 二维码），
  /// 两类数据并存时由顶部分段按钮手动切换。
  _InfoGetKind _infoGetKind = _InfoGetKind.card;

  /// 上一次已见到的最新数据对象，用于自动切换展示类型。
  NfcScanResult? _seenCard;
  JtT1179QrData? _seenQr;
  BankCardResult? _seenBank;

  @override
  void initState() {
    super.initState();
    _seenCard = widget.app.lastResult;
    _seenQr = widget.app.qrData;
    _seenBank = widget.app.lastBankCardResult;
    if (_seenCard == null && _seenQr == null && _seenBank != null) {
      _infoGetKind = _InfoGetKind.bank;
    } else if (_seenCard == null && _seenQr != null) {
      _infoGetKind = _InfoGetKind.qr;
    }
    widget.app.addListener(_onNfcChanged);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onNfcChanged);
    super.dispose();
  }

  void _onNfcChanged() {
    if (!mounted) return;
    final app = widget.app;
    if (!identical(app.lastResult, _seenCard)) {
      _seenCard = app.lastResult;
      // 新读到卡片：自动切换到卡片识别
      if (app.lastResult != null) _infoGetKind = _InfoGetKind.card;
    }
    if (!identical(app.qrData, _seenQr)) {
      _seenQr = app.qrData;
      // 新获取到二维码：自动切换到二维码
      if (app.qrData != null) _infoGetKind = _InfoGetKind.qr;
    }
    if (!identical(app.lastBankCardResult, _seenBank)) {
      _seenBank = app.lastBankCardResult;
      // 新完成银行卡分析：自动切换到银行卡视图
      if (app.lastBankCardResult != null) _infoGetKind = _InfoGetKind.bank;
    }
    setState(() {});
  }

  NfcScanResult? get result => widget.app.lastResult;

  String _val(String? v) => v ?? '未知';

  String _fmtDate(DateTime? d) {
    if (d == null) return '未知';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '未知';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '${_fmtDate(t)} $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final parsed = app.parsedCard;
    final analysis = app.analysis;
    final processRecords = app.transitProcessRecords;
    // 解析器分派：交通联合家族（普通交通联合 / 上海交通卡（交通联合版））
    // 专属字段与页签随之展示；其它解析器不展示。
    final isTUnion = CardParserIds.isTUnionFamily(parsed?.parserId);

    // 页签随解析器动态构建：JT/T 978 符合性仅在交通联合解析器命中时存在。
    final tabs = <Tab>[
      const Tab(text: '信息获取'),
      const Tab(text: '交通数据解析'),
      if (isTUnion) const Tab(text: 'JT/T 978 符合性'),
      const Tab(text: 'APDU / Raw Data'),
    ];

    return SafeArea(
      top: false,
      child: DefaultTabController(
        // 页签数量随解析器选择变化，以数量作 key：变化时重建控制器，
        // 避免页签数与控制器长度不一致导致索引越界。
        key: ValueKey<String>('expert-tabs-${tabs.length}'),
        length: tabs.length,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              title: const Text('专家分析'),
              pinned: true,
              actions: [SettingsActionButton(app: app)],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _infoGetTabBody(app),
              _tabBody('expert-parsed', _transitDataFields(parsed)),
              if (isTUnion)
                _tabBody('expert-compliance', [
                  _kv('综合覆盖度',
                      analysis == null
                          ? '—'
                          : '${analysis.compliance.scorePercent}%'),
                  for (final item
                      in analysis?.compliance.items ?? const <ComplianceItem>[])
                    _complianceRow(context, item),
                ]),
              _tabBody('expert-apdu', [
                if (app.apduLog.isEmpty)
                  _kv('APDU', '暂无 APDU 记录')
                else
                  for (final entry in app.apduLog.length > 20
                      ? app.apduLog.sublist(app.apduLog.length - 20)
                      : app.apduLog)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _hexSelectable(entry),
                    ),
                if (processRecords.isNotEmpty) ...[
                  const Divider(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '过程记录原始数据（0x1A / 0x1E）',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  for (final r in processRecords)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '0x${r.sfi.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                            ' · ${r.recordName} · ${r.raw.length} 字节',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline),
                          ),
                          const SizedBox(height: 4),
                          _hexSelectable(r.rawHex),
                        ],
                      ),
                    ),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// 信息获取页签：卡片识别 / 二维码 / 银行卡只读分析合并展示，内容随
  /// 首页获取的数据自动切换——读到卡片展示卡片识别字段，扫码 / 相册
  /// 导入后展示二维码解析详情，银行卡（交通应用未命中）展示只读分析
  /// 结果；多类数据并存时由顶部分段按钮切换。数据获取入口统一收敛到
  /// 首页，本页不再提供读取 / 扫描 / 手动输入操作。
  Widget _infoGetTabBody(AppState app) {
    final bankResult = app.lastBankCardResult;
    // 交通卡片视图仅在有效交通解析结果存在时展示：银行卡分析结果存在
    // （交通应用未命中）时不再展示空交通识别字段。
    final hasCard = app.parsedCard != null ||
        (result != null && bankResult == null);
    final hasQrView = app.hasQrData || app.qrError != null;
    final hasBank = bankResult != null;
    if (!hasCard && !hasQrView && !hasBank) {
      return _tabBody(
        'expert-info-get',
        [
          _qrHomeHint('尚未读取卡片，请先在首页贴卡读取'),
          _qrHomeHint('尚未获取乘车码，请先在首页扫描二维码或从相册导入'),
          _qrHomeHint('尚未读取银行卡：在首页贴卡读取后自动分析'
              '（交通应用未命中时按 EMV / PBOC 只读解析）'),
        ],
        showReadHint: false,
      );
    }
    // 可用展示类型：只有一侧有内容时固定展示该侧；多侧并存时按用户选择
    // （默认跟随最近一次获取的数据，并由 _onNfcChanged 自动切换）。
    final available = <_InfoGetKind>[
      if (hasCard) _InfoGetKind.card,
      if (hasQrView) _InfoGetKind.qr,
      if (hasBank) _InfoGetKind.bank,
    ];
    final kind =
        available.contains(_infoGetKind) ? _infoGetKind : available.first;
    return _tabBody(
      'expert-info-get',
      [
        if (available.length > 1) ...[
          SegmentedButton<_InfoGetKind>(
            segments: [
              if (hasCard)
                const ButtonSegment(
                  value: _InfoGetKind.card,
                  label: Text('卡片识别'),
                ),
              if (hasQrView)
                const ButtonSegment(
                  value: _InfoGetKind.qr,
                  label: Text('二维码'),
                ),
              if (hasBank)
                const ButtonSegment(
                  value: _InfoGetKind.bank,
                  label: Text('银行卡'),
                ),
            ],
            selected: {kind},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => _infoGetKind = selection.first);
            },
          ),
          const SizedBox(height: 8),
        ],
        ...switch (kind) {
          _InfoGetKind.card => _identifyFields(app),
          _InfoGetKind.qr => _qrSection(app),
          _InfoGetKind.bank => [BankCardResultView(result: bankResult!)],
        },
      ],
      showReadHint: false,
    );
  }

  /// 卡片识别字段（交通联合 JT/T 978.2 / 城市一卡通 CJ/T 331-2016）。
  List<Widget> _identifyFields(AppState app) {
    final parsed = app.parsedCard;
    final info = app.cardInfo;
    final identity = app.analysis?.identity;
    final isTUnion = CardParserIds.isTUnionFamily(parsed?.parserId);
    final isCityUnion = parsed?.parserId == CardParserIds.cityUnion;
    final isShanghai = parsed?.parserId == CardParserIds.shanghaiTunion;
    return [
      _kv('解析器', parsed?.parserName ?? '—'),
      _kv(
          '选中 AID',
          (parsed == null || parsed.selectedAidHex.isEmpty)
              ? '—'
              : parsed.selectedAidHex),
      // 交通联合应用：交通联合解析器专属字段，仅在命中时展示
      if (isTUnion) _kv('交通联合应用', '已发现'),
      if (isShanghai) ...[
        _kv('上海交通卡识别状态', app.shanghaiTransitUnion?.status.label ?? '未知'),
        _kv('TU 应用', app.shanghaiTransitUnion?.tu.stateText ?? '未知'),
        _kv('CU 应用', app.shanghaiTransitUnion?.cu.stateText ?? '未知'),
        if (app.shanghaiTransitUnion?.matchedPrefix != null)
          _kv('辅助前缀', app.shanghaiTransitUnion!.matchedPrefix!),
      ],
      // 城市一卡通应用：城市一卡通解析器命中，或同一张卡上附带住建部
      // 应用时展示（后者标注「双应用卡」）。
      if (isCityUnion || app.cityUnionFiles.isNotEmpty)
        _kv(
          '城市一卡通应用',
          parsed?.dualApplication == true ? '已发现（双应用卡）' : '已发现',
        ),
      _kv('识别城市', identity?.cityName ?? app.cityUnionCard?.city ?? '未知'),
      _kv('卡种', identity?.cardFamily ?? '未知'),
      _kv(
          '卡片名称',
          app.cardPrefixByIssuerId(info?.issuerId)?.cardName ??
              app.cityUnionCard?.cardName ??
              '未知'),
      for (final e in identity?.evidence ?? const <Evidence>[])
        _kv(
          e.source,
          '${e.detail}${e.weight > 0 ? '（权重 ${e.weight}）' : ''}',
        ),
    ];
  }

  /// 交通数据解析页签字段：按当前解析器分派。
  /// 未命中解析器（未读取或未发现受支持应用）时不产出字段；
  /// 新增卡型解析器时在此登记对应字段分支（如城市一卡通）。
  List<Widget> _transitDataFields(ParsedCard? parsed) {
    if (parsed == null) {
      return [
        _hintLine(result == null
            ? '尚未读取卡片，读取成功后将展示交通数据字段'
            : '未发现受支持的交通应用，暂无交通数据字段'),
      ];
    }
    return switch (parsed.parserId) {
      CardParserIds.tunion || CardParserIds.shanghaiTunion => [
        ..._tunionTransitFields(parsed),
        if (parsed.cityUnionFiles.isNotEmpty) ..._dualCityUnionFields(parsed),
      ],
      CardParserIds.cityUnion => _cityUnionTransitFields(parsed),
      _ => [_hintLine('当前解析器暂未提供交通数据字段视图')],
    };
  }

  /// 双应用卡：在交通联合交通数据之后追加城市一卡通（住建部 CJ/T 331-2016）
  /// 应用视图，明确区分两套网络的文件与钱包余额（与交通联合余额互不混用）。
  List<Widget> _dualCityUnionFields(ParsedCard parsed) {
    final bal = parsed.cityUnionBalanceFen;
    return [
      const Divider(height: 32),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '城市一卡通应用（双应用 · 住建部 CJ/T 331-2016）',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      const SizedBox(height: 4),
      _kv(
        '城市一卡通钱包余额',
        bal == null ? '未知' : '${(bal / 100).toStringAsFixed(2)} 元',
      ),
      ..._cityUnionTransitFields(parsed),
    ];
  }

  /// 城市一卡通（CJ/T 331-2016）交通数据字段：按标准文件分组展示
  /// 公共应用基本信息（0x15）、电子钱包本地消费交易明细（0x18）
  /// 与充值交易明细（0x1A）的字段视图。
  List<Widget> _cityUnionTransitFields(ParsedCard parsed) {
    final files = widget.app.cityUnionFiles;
    if (files.isEmpty) {
      return [
        _hintLine('已命中城市一卡通应用，但未读取到标准文件数据'
            '（0x15 / 0x18 / 0x1A）'),
      ];
    }
    final public = files.where((f) => f.sfi == 0x15).toList();
    final local = files.where((f) => f.sfi == 0x18).toList();
    final recharge = files.where((f) => f.sfi == 0x1A).toList();
    // CU 城市代码（0x15 字节 03-04 HEX 解码 4 位）：用于终端索引同地区优先匹配。
    final cuCityCode =
        public.whereType<CjT331PublicInfo>().firstOrNull?.cityCode;

    return [
      _kv('已读取文件视图', '${files.length} 项'),
      const Divider(height: 28),
      _cjPublicInfoSection(public),
      _cjRecordGroupTile(
        title: '电子钱包本地消费交易明细（0x18）',
        storageKey: 'cj-local',
        records: local,
        cityCode: cuCityCode,
        emptyHint: '未读取到本地消费交易明细（文件不存在或记录未写入）',
      ),
      _cjRecordGroupTile(
        title: '电子钱包充值交易明细（0x1A）',
        storageKey: 'cj-recharge',
        records: recharge,
        emptyHint: '未读取到充值交易明细（文件不存在或记录未写入）',
      ),
    ];
  }

  /// 公共应用基本信息文件（0x15）：直接按字段视图展示
  /// （原始值 / 解码值 / 说明 / 异常）与原始数据；未读取到时给出提示。
  Widget _cjPublicInfoSection(List<CityUnionFileView> views) {
    final scheme = Theme.of(context).colorScheme;
    final view = views.isEmpty ? null : views.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '公共应用基本信息文件（0x15）',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: scheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            view == null
                ? '未读取到'
                : view.fields.isEmpty
                    ? '未按标准解析（保留原始数据）'
                    : '已解析 · ${view.fields.length} 字段',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
        ),
        if (view == null)
          _hintLine('未读取到公共应用基本信息文件（文件不存在或读取被拒）')
        else ...[
          if (view.fields.isEmpty)
            for (final e in view.errors) _hintLine(e)
          else
            for (final f in view.fields) _kv(f.name, _cjFieldValue(f)),
          const SizedBox(height: 6),
          _hexSelectable(view.rawHex),
        ],
      ],
    );
  }

  /// 记录文件子菜单（0x18 / 0x1A）：展开后逐条展示记录字段视图。
  Widget _cjRecordGroupTile({
    required String title,
    required String storageKey,
    required List<CityUnionFileView> records,
    required String emptyHint,
    String? cityCode,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: PageStorageKey<String>(storageKey),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: Text(title),
      subtitle: Text(
        records.isEmpty ? '未读取到' : '${records.length} 条',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: records.isEmpty
          ? [_hintLine(emptyHint)]
          : [
              for (var i = 0; i < records.length; i++)
                _cjRecordView(
                  i,
                  records[i],
                  last: i == records.length - 1,
                  cityCode: cityCode,
                ),
            ],
    );
  }

  /// 单条 City Union 记录视图：字段列表 + 原始数据；布局不符的记录
  /// 展示解析器给出的原因并保留原始字节（不猜测字段值）。本地消费
  /// （0x18）记录附带按交易终端编号经 terminal_index 解析的站点名。
  Widget _cjRecordView(
    int index,
    CityUnionFileView record, {
    required bool last,
    String? cityCode,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final stationName = _cuStationName(record, cityCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('记录 ${index + 1}',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _cjRecordSubtitle(record),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (record.fields.isEmpty)
          for (final e in record.errors) _hintLine(e)
        else
          for (final f in record.fields) _kv(f.name, _cjFieldValue(f)),
        if (stationName != null) _kv('站点（终端解析）', stationName),
        const SizedBox(height: 6),
        _hexSelectable(record.rawHex),
        if (!last) const Divider(height: 24),
      ],
    );
  }

  /// CU 本地消费记录（0x18）→ 站点名：以交易终端编号经 CU terminal_index
  /// 精确 / 前缀匹配解析；未命中或非消费记录返回 null（不展示、不猜测）。
  String? _cuStationName(CityUnionFileView record, String? cityCode) {
    if (record is CjT331WalletLocalConsumption) {
      return widget.app.resolveCuStationName(
        record.terminalNumber,
        cityCode: cityCode,
        transactionType: record.transactionType,
      );
    }
    return null;
  }

  /// 记录摘要小字：交易类记录给出日期时间与类型，复合交易给出锁定状态；
  /// 未按标准解析的记录给出字节数与原始数据提示。
  String _cjRecordSubtitle(CityUnionFileView record) => switch (record) {
        CjT331WalletLocalConsumption r =>
          '${r.transactionDate ?? '未知日期'} ${r.transactionTime ?? ''} · '
              '${r.transactionTypeName}',
        CjT331WalletRecharge r =>
          '${r.transactionDate ?? '未知日期'} ${r.transactionTime ?? ''} · '
              '${r.transactionTypeName}',
        _ => '${record.rawHex.split(' ').length} 字节 · 未按标准解析',
      };

  /// City Union 字段展示值：标准解码值优先（缺失回退原始 HEX），
  /// 附标准说明与字段级异常；原始字节始终保留在原始数据区。
  String _cjFieldValue(CjField f) {
    final base = f.decoded ?? f.rawHex;
    final notes = <String>[
      if (f.note != null) f.note!,
      if (f.error != null) f.error!,
    ];
    return notes.isEmpty ? base : '$base（${notes.join('；')}）';
  }

  /// 交通联合（JT/T 978.2）交通数据字段：钱包标准文件字段、最近交易摘要
  /// 与过程记录（0x1A / 0x1E）子菜单。仅在交通联合解析器命中时产出。
  List<Widget> _tunionTransitFields(ParsedCard parsed) {
    final app = widget.app;
    final info = parsed.info;
    final analysis = app.analysis;
    final wallet = analysis?.wallet;
    final trips = analysis?.trips ?? const <TransitTrip>[];
    final firstTrip = trips.isEmpty ? null : trips.first;
    final processRecords = app.transitProcessRecords;
    final varRecords = processRecords.where((r) => r.sfi == 0x1A).toList();
    final cycleRecords = processRecords.where((r) => r.sfi == 0x1E).toList();
    // 过程记录仅保留三类：0x1A 记录 1（城市轨道应用信息记录）、记录 2（公共
    // 汽电车应用信息记录）与全部 0x1E 过程循环记录，其余变长记录不在界面展示。
    TUnionProcessRecord? railRecord;
    TUnionProcessRecord? busRecord;
    TUnionProcessRecord? wholeVarBlob;
    for (final r in varRecords) {
      if (r.recordNumber == 1) {
        railRecord = r;
      } else if (r.recordNumber == 2) {
        busRecord = r;
      } else if (r.recordNumber == 0) {
        wholeVarBlob = r;
      }
    }
    // 逐条读取不可用、仅有整体数据时（整体读取自记录 1 读至末尾），
    // 将整体数据前缀按记录 1 解析展示城市轨道应用信息记录，避免有原始
    // 数据却显示“未写入”；记录 2 起始位置无法定位，不猜测。
    if (railRecord == null && wholeVarBlob != null) {
      final raw = wholeVarBlob.raw;
      railRecord = TUnionProcessRecord(
        sfi: 0x1A,
        recordNumber: 1,
        recordName: '城市轨道应用信息记录',
        raw: raw,
        railTransit: const TUnionProcessParser().parseRailTransit(1, raw),
      );
    }

    return [
      _kv('逻辑卡号', _val(info.displayCardNumber)),
      _kv('发卡机构标识', _val(info.issuerId)),
      _kv('应用类型标识', _val(info.appTypeId)),
      _kv('应用版本', _val(info.appVersion)),
      _kv('生效日期', _fmtDate(info.effectiveDate)),
      _kv('失效日期', _fmtDate(info.expireDate)),
      _kv('发卡机构 FCI', _val(info.issuerFci)),
      _kv('国际代码', _val(info.countryCode)),
      _kv('省级代码', _val(info.provinceCode)),
      _kv('城市代码', _val(info.cityCode)),
      _kv('互通卡种', _val(info.interopCardType)),
      _kv('卡种类型', _val(info.cardKind)),
      _kv('余额', wallet?.balanceText ?? '未知'),
      _kv('剩余有效天数', _daysRemainingText(wallet?.daysRemaining)),
      _kv('交易记录', '${trips.length} 条'),
      _kv('最近交易', _fmtTime(firstTrip?.time)),
      _kv('交易金额', firstTrip?.amountText ?? '未知'),
      _kv('交易类型', firstTrip?.typeName ?? '未知'),
      _kv('交易序号', firstTrip?.sequence.toString() ?? '未知'),
      _kv('终端编号', firstTrip?.terminalId ?? '未知'),
      _kv('终端解码', _terminalDecodeText(firstTrip)),
      _kv(
          '过程记录',
          processRecords.isEmpty
              ? '无'
              : '${processRecords.length} 条'
                  '（0x1A ${varRecords.length} · 0x1E ${cycleRecords.length}）'),
      const Divider(height: 28),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '过程记录 · 0x1A / 0x1E',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      if (processRecords.isEmpty)
        _hintLine('未读取到过程记录（卡片未实现该文件、记录为空或读取条件不满足）')
      else ...[
        _railProcessTile(railRecord),
        _busProcessTile(busRecord),
        _cycleProcessTile(cycleRecords),
      ],
    ];
  }

  /// 城市轨道应用信息记录（0x1A 记录 1）子菜单。
  /// 解析成功展示字段视图；记录过短或布局不符时按原始数据展示（不猜测）。
  Widget _railProcessTile(TUnionProcessRecord? record) {
    final scheme = Theme.of(context).colorScheme;
    final transit = record?.railTransit;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-var-1'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: const Text('城市轨道应用信息记录'),
      subtitle: Text(
        record == null ? '未写入' : _railRecordSubtitle(record),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: record == null
          ? [_hintLine('卡片未写入该记录（0x1A 记录 1）')]
          : transit != null
              ? _railTransitFields(transit)
              : _rawFallback(record),
    );
  }

  /// 城市轨道应用信息记录解析状态小字：按实际解析结果展示
  /// （未解析 / 部分解析 n/m 字段 / 已解析全文），随展开后的字段视图一致。
  String _railRecordSubtitle(TUnionProcessRecord record) {
    if (record.isBlank) return '未写入（初始值）';
    final transit = record.railTransit;
    if (transit == null) return '${record.raw.length} 字节 · 未解析';
    final (parsed, total) = _railFieldProgress(transit);
    if (parsed == 0) return '${record.raw.length} 字节 · 未解析';
    if (parsed == total) return '已解析 · 进出站配对';
    return '部分解析 · $parsed/$total 字段';
  }

  /// 城市轨道记录已解析字段进度（非空字段数 / 字段总数）；
  /// 口径与 [_railTransitFields] 展示字段一致（不含交易状态与发卡机构自定义）。
  static (int, int) _railFieldProgress(TransitRecord rec) {
    final values = <Object?>[
      rec.entryCityCode,
      rec.exitCityCode,
      rec.entryAgencyId,
      rec.exitAgencyId,
      rec.entryStationId,
      rec.exitStationId,
      rec.entryTerminalId,
      rec.exitTerminalId,
      rec.entryTime ?? rec.entryTimeBcd,
      rec.exitTime ?? rec.exitTimeBcd,
      rec.annotateAmountFen,
      rec.entryLineCode,
      rec.exitLineCode,
      rec.entryAmountFen,
      rec.entryBalanceFen,
      rec.exitAmountFen,
    ];
    return (values.where((v) => v != null).length, values.length);
  }

  /// 解析失败兜底：展示原始记录字节（不猜测字段值）。
  List<Widget> _rawFallback(TUnionProcessRecord record) {
    return [
      _kv('数据长度', '${record.raw.length} 字节'),
      const SizedBox(height: 6),
      _hexSelectable(record.rawHex),
      const SizedBox(height: 6),
      _hintLine('记录长度不足或字段布局不符，未做推测解析，按原始数据展示'),
    ];
  }

  /// 城市轨道应用信息记录字段视图（目标输出格式）。
  /// 发卡机构自定义仅在完整格式且自定义区有有效内容时展示
  /// （未读取到有效信息时解析层不产出，见 TUnionProcessParser）。
  List<Widget> _railTransitFields(TransitRecord rec) {
    return [
      _kv('交易状态', _codeName(rec.statusCode, rec.statusName)),
      _kv('进闸城市代码', _cityCell(rec.entryCityCode)),
      _kv('出闸城市代码', _cityCell(rec.exitCityCode)),
      _kv('进闸机构标识', _hexLower(rec.entryAgencyId)),
      _kv('出闸机构标识', _hexLower(rec.exitAgencyId)),
      _kv('进闸站点', _hexLower(rec.entryStationId)),
      _kv('出闸站点', _hexLower(rec.exitStationId)),
      _kv('进闸终端编号', _hexLower(rec.entryTerminalId)),
      _kv('出闸终端编号', _hexLower(rec.exitTerminalId)),
      _kv('进站时间', _bcdTimeCell(rec.entryTime, rec.entryTimeBcd)),
      _kv('出站时间', _bcdTimeCell(rec.exitTime, rec.exitTimeBcd)),
      _kv('标注金额', _amountCell(rec.annotateAmountFen)),
      _kv('入站线路号', _hexByteCell(rec.entryLineCode)),
      _kv('出站线路号', _hexByteCell(rec.exitLineCode)),
      _kv('进站交易金额', _amountCell(rec.entryAmountFen)),
      _kv('进站钱包余额', _amountCell(rec.entryBalanceFen)),
      _kv('出闸交易金额', _amountCell(rec.exitAmountFen)),
      if (rec.issuerCustom != null)
        _kv('发卡机构自定义', _hexLower(rec.issuerCustom)),
    ];
  }

  /// 公共汽电车应用信息记录（0x1A 记录 2）子菜单。
  Widget _busProcessTile(TUnionProcessRecord? record) {
    final scheme = Theme.of(context).colorScheme;
    final bus = record?.busTransit;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-var-2'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: const Text('公共汽电车应用信息记录'),
      subtitle: Text(
        record == null ? '未写入' : _busRecordSubtitle(record),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: record == null
          ? [_hintLine('卡片未写入该记录（0x1A 记录 2）')]
          : bus != null
              ? _busTransitFields(bus)
              : _rawFallback(record),
    );
  }

  /// 公共汽电车应用信息记录解析状态小字：按实际解析结果展示。
  String _busRecordSubtitle(TUnionProcessRecord record) {
    if (record.isBlank) return '未写入（初始值）';
    final bus = record.busTransit;
    if (bus == null) return '${record.raw.length} 字节 · 未解析';
    final (parsed, total) = _busFieldProgress(bus);
    if (parsed == 0) return '${record.raw.length} 字节 · 未解析';
    if (parsed == total) return '已解析 · 上下车配对';
    return '部分解析 · $parsed/$total 字段';
  }

  /// 公共汽电车记录已解析字段进度（非空字段数 / 字段总数）；
  /// 口径与 [_busTransitFields] 展示字段一致（不含交易状态与发卡机构自定义）。
  static (int, int) _busFieldProgress(BusTransitRecord rec) {
    final values = <Object?>[
      rec.entryCityCode,
      rec.entryAgencyId,
      rec.entryOperatorCode,
      rec.entryLineCode,
      rec.entryStationCode,
      rec.entryVehicleId,
      rec.entryTerminalId,
      rec.entryTime ?? rec.entryTimeBcd,
      rec.annotateAmountFen,
      rec.directionCode,
      rec.exitCityCode,
      rec.exitAgencyId,
      rec.exitOperatorCode,
      rec.exitLineCode,
      rec.exitStationCode,
      rec.exitVehicleId,
      rec.exitTerminalId,
      rec.exitTime ?? rec.exitTimeBcd,
      rec.transactionAmountFen,
      rec.mileage,
    ];
    return (values.where((v) => v != null).length, values.length);
  }

  /// 公共汽电车应用信息记录字段视图（目标输出格式）。
  /// 记录头内字段不展示；发卡机构自定义未读取到有效信息（全 0）时隐藏。
  List<Widget> _busTransitFields(BusTransitRecord rec) {
    return [
      _kv('交易状态', _codeName(rec.statusCode, rec.statusName)),
      _kv('上车城市代码', _cityCell(rec.entryCityCode)),
      _kv('上车机构标识', _hexLower(rec.entryAgencyId)),
      _kv('上车运营商代码', _hexLower(rec.entryOperatorCode)),
      _kv('上车线路号', _hexLower(rec.entryLineCode)),
      _kv('上车站点', _hexLower(rec.entryStationCode)),
      _kv('上车车辆号', _hexLower(rec.entryVehicleId)),
      _kv('上车终端编号', _hexLower(rec.entryTerminalId)),
      _kv('上车时间', _bcdTimeCell(rec.entryTime, rec.entryTimeBcd)),
      _kv('标注金额', _amountCell(rec.annotateAmountFen)),
      _kv('方向标识', rec.directionName),
      _kv('下车城市代码', _cityCell(rec.exitCityCode)),
      _kv('下车机构标识', _hexLower(rec.exitAgencyId)),
      _kv('下车运营商代码', _hexLower(rec.exitOperatorCode)),
      _kv('下车线路号', _hexLower(rec.exitLineCode)),
      _kv('下车站点', _hexLower(rec.exitStationCode)),
      _kv('下车车辆号', _hexLower(rec.exitVehicleId)),
      _kv('下车终端编号', _hexLower(rec.exitTerminalId)),
      _kv('下车时间', _bcdTimeCell(rec.exitTime, rec.exitTimeBcd)),
      _kv('交易金额', _amountCell(rec.transactionAmountFen)),
      _kv('乘车里程', _intHexCell(rec.mileage)),
      if (rec.hasIssuerCustomData)
        _kv('发卡机构自定义', _hexLower(rec.issuerCustomHex)),
    ];
  }

  /// 两位小写 HEX（如 2 → "02"）。
  String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toLowerCase();

  /// 代码 + 名称拼接（代码为卡片上报值，小写）；名称未知时仅保留"未知(0xXX)"。
  String _codeName(int code, String name) =>
      name.startsWith('未知') ? name : '${_hex2(code)}：$name';

  /// 城市代码单元格："(代码)城市名" —— 代码为卡片上报值（小写），
  /// 城市名按知识库实时查询，未收录时显示"未知城市"。
  String _cityCell(String? code) {
    if (code == null || code.isEmpty) return '未知';
    return '(${code.toLowerCase()})'
        '${widget.app.cityNameOf(code) ?? '未知城市'}';
  }

  /// HEX 值小写展示；缺省为"未知"。
  String _hexLower(String? v) =>
      (v == null || v.isEmpty) ? '未知' : v.toLowerCase();

  /// 1 字节值（两位小写 HEX）；缺省为"未知"。
  String _hexByteCell(int? v) => v == null ? '未知' : _hex2(v);

  /// 金额单元格：括号内原始 4 字节 HEX（小写）+ 金额（货币单位按当前卡片）。
  String _amountCell(int? fen) {
    if (fen == null) return '未知';
    final hex = fen.toRadixString(16).padLeft(8, '0').toLowerCase();
    return '($hex)${(fen / 100).toString()}${widget.app.cardCurrency.unit}';
  }

  /// 括号内原始 N 字节 HEX（小写）+ 十进制值。
  String _intHexCell(int? v, {int width = 4}) {
    if (v == null) return '未知';
    final hex = v.toRadixString(16).padLeft(width, '0').toLowerCase();
    return '($hex)$v';
  }

  /// 时间 `yyyy/MM/dd HH:mm:ss`；DateTime 缺失时按 BCD 原始位排布
  /// （如未写入的零值显示 0000/00/00 00:00:00）。
  String _bcdTimeCell(DateTime? t, String? bcd) {
    final digits = t != null
        ? '${t.year.toString().padLeft(4, '0')}'
            '${t.month.toString().padLeft(2, '0')}'
            '${t.day.toString().padLeft(2, '0')}'
            '${t.hour.toString().padLeft(2, '0')}'
            '${t.minute.toString().padLeft(2, '0')}'
            '${t.second.toString().padLeft(2, '0')}'
        : bcd;
    if (digits == null || digits.length != 14) return '未知';
    return '${digits.substring(0, 4)}/${digits.substring(4, 6)}/'
        '${digits.substring(6, 8)} '
        '${digits.substring(8, 10)}:${digits.substring(10, 12)}:'
        '${digits.substring(12, 14)}';
  }

  /// `yyyyMMddHHmmss`（0x1E 交易日期时间输出格式）。
  String _dateTimeDigits(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '${t.month.toString().padLeft(2, '0')}'
      '${t.day.toString().padLeft(2, '0')}'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}'
      '${t.second.toString().padLeft(2, '0')}';
  /// 公共交通过程信息循环记录（0x1E）子菜单：展开后平铺展示每条记录的解析结果。
  Widget _cycleProcessTile(List<TUnionProcessRecord> records) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const PageStorageKey<String>('process-cycle'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: const Text('公共交通过程信息循环记录'),
      subtitle: Text(
        records.isEmpty ? '未写入' : '${records.length} 条',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: records.isEmpty
          ? [_hintLine('卡片未写入过程循环记录（0x1E）')]
          : [
              for (var i = 0; i < records.length; i++)
                _cycleRecordView(records[i], last: i == records.length - 1),
            ],
    );
  }

  /// 单条 0x1E 循环记录（目标输出格式）：解码成功展示字段，失败展示原始数据。
  Widget _cycleRecordView(TUnionProcessRecord r, {required bool last}) {
    final scheme = Theme.of(context).colorScheme;
    final trip = r.trip;
    final name =
        r.recordNumber > 0 ? '循环记录 ${r.recordNumber}' : r.recordName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(name, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _processRecordSubtitle(r),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (trip != null) ...[
          _kv('交易类型', _codeName(trip.typeCode, trip.typeName)),
          _kv('终端编号', trip.terminalId),
          _kv('应用分类码', _codeName(trip.appTypeCode, trip.appTypeName)),
          _kv('线路', _val(trip.lineCode)),
          _kv('站点', _val(trip.stationCode)),
          _kv('运营代码', _val(trip.operatorCode)),
          _kv('交易金额', _amountCell(trip.amountFen)),
          _kv('交易后余额', _amountCell(trip.balanceFen)),
          _kv('交易日期时间', _dateTimeDigits(trip.time)),
          _kv('受理方城市代码', _cityCell(trip.cityCode)),
          _kv('受理方机构标识', _hexLower(trip.acquirerId)),
        ] else ...[
          _kv('字节数', '${r.raw.length} 字节'),
          _kv('说明', '记录未写入或长度不足，未能解码为字段'),
          const SizedBox(height: 6),
          _hexSelectable(r.rawHex),
        ],
        if (!last) const Divider(height: 24),
      ],
    );
  }

  String _processRecordSubtitle(TUnionProcessRecord r) {
    final trip = r.trip;
    if (trip != null) {
      return '${_dateTimeDigits(trip.time)} · '
          '${(trip.amountFen / 100).toStringAsFixed(2)} '
          '${widget.app.cardCurrency.unit}';
    }
    return '${r.raw.length} 字节 · 未解码为字段';
  }

  Widget _hintLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }

  Widget _hexSelectable(String hex) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: hex));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('原始数据已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Text(
        hex,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  String _terminalDecodeText(TransitTrip? trip) {
    if (trip == null) return '未知';
    final loc = trip.location;
    if (loc == null) return '未匹配解码规则（终端 ${trip.terminalId}）';
    final cityCode = loc.cityCode ?? '-';
    final city =
        trip.cityName == null ? cityCode : '$cityCode（${trip.cityName}）';
    return '城市 $city / 线路 ${trip.lineLabel ?? loc.lineCode ?? '-'} / '
        '站点 ${trip.stationLabel ?? loc.stationCode ?? '-'}（规则 ${loc.ruleId}）';
  }

  String _daysRemainingText(int? days) {
    if (days == null) return '未知';
    return days < 0 ? '已过期 ${-days} 天' : '$days 天';
  }

  Widget _complianceRow(BuildContext context, ComplianceItem item) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (item.status) {
      ComplianceStatus.pass => (Icons.check_circle_outline, Colors.green),
      ComplianceStatus.warn => (Icons.warning_amber_outlined, Colors.orange),
      ComplianceStatus.fail => (Icons.cancel_outlined, scheme.error),
      ComplianceStatus.info => (Icons.info_outline, scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title),
                Text(
                  item.detail,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(k)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  /// [showReadHint] 为 false 时不展示"NFC 尚未读取"提示卡片
  /// （供与 NFC 状态无关的页签使用，如信息获取页签）。
  Widget _tabBody(String storageKey, List<Widget> children,
      {bool showReadHint = true}) {
    return ListView(
      key: PageStorageKey<String>(storageKey),
      cacheExtent: 200,
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        UiConstants.floatingNavBarClearance,
      ),
      children: [
        if (showReadHint && result == null)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  Icon(Icons.touch_app,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '尚未读取，请先在首页放置票卡完成读取',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  /// 二维码视图（信息获取页签内）：解析失败详情 / 解析详情
  /// （字段 + 证书 + 原始数据）两态。独立于 NFC 卡片读取状态；
  /// 数据获取入口统一收敛到首页，本页不再提供扫描 / 手动输入操作。
  List<Widget> _qrSection(AppState app) {
    final qr = app.qrData;
    if (qr == null) {
      // 外层（_infoGetTabBody）已排除空态：qr 为 null 时必有解析失败原因
      return [
        _kv('状态', '解析失败'),
        _kv('原因', _val(app.qrError)),
        _kv('原始数据', '${app.qrRaw?.length ?? 0} 字节'),
        const SizedBox(height: 6),
        if (app.qrRaw != null) _hexSelectable(_hexBytes(app.qrRaw!)),
        const SizedBox(height: 12),
        _qrHomeHint('可返回首页重新扫描或从相册导入乘车码'),
        const SizedBox(height: 12),
        _qrClearButton(app),
      ];
    }
    return [
      ..._qrDetailFields(app, qr),
      const Divider(height: 28),
      _qrCertificateTile(qr),
      _qrRawTile(qr),
      const SizedBox(height: 12),
      _qrClearButton(app),
    ];
  }

  /// 首页获取引导行：卡片与二维码数据统一在首页获取（贴卡读取 / 扫描 / 相册导入）。
  Widget _qrHomeHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.home_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  /// 清除当前二维码解析结果（重新获取请前往首页）。
  Widget _qrClearButton(AppState app) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: app.clearQr,
        icon: const Icon(Icons.clear),
        label: const Text('清除'),
      ),
    );
  }

  /// 二维码解析字段视图（表 2 全字段）。
  List<Widget> _qrDetailFields(AppState app, JtT1179QrData qr) {
    final cert = qr.issuerCertificate;
    final issuerId = qr.issuerIdText;
    final issuerName = app.cardPrefixByIssuerId(issuerId)?.cardName ?? '未知';
    return [
      _kv('版本', qr.versionHex),
      _kv('声明长度', '${qr.declaredLength} 字节（数据体，自证书起）'),
      _kv('数据总长', '${qr.raw.length} 字节'),
      _kv('发卡机构名称', issuerName),
      _kv('发卡机构标识', issuerId ?? _hexBytes(cert.issuerIdBytes)),
      _kv('支付账户号', qr.paymentAccountDigits ?? qr.paymentAccountNumberHex),
      _kv(
        '用户账户号',
        qr.userAccountNumberText ??
            qr.userAccountDigits ??
            qr.userAccountNumberHex,
      ),
      _kv('发卡机构代码', qr.issuerCodeText ?? qr.issuerCodeHex),
      _kv('发码平台代码', qr.platformCodeText ?? qr.platformCodeHex),
      _kv('用户账户类型', '0x${_hex2(qr.userAccountType)}'),
      _kv(
        '单次消费金额上限',
        '${(qr.singleConsumptionLimitFen / 100).toStringAsFixed(2)} 元',
      ),
      _kv('支付账户用户公钥', qr.userPublicKeyHex),
      _kv(
        '授权过期时间',
        '${_fmtTime(qr.authorizationExpiryUtc.toLocal())}'
            '${qr.isAuthorizationExpired() ? '（已过期）' : ''}',
      ),
      _kv('二维码有效时间', '${qr.qrValiditySeconds} 秒'),
      _kv('二维码生成时间', _fmtTime(qr.generationTimeUtc.toLocal())),
      _kv(
        '二维码状态',
        qr.isQrExpired() ? '已超出生成时间 + 有效时间窗口' : '有效期内',
      ),
      _kv(
        '发卡机构自定义域',
        qr.issuerDefinedLength == 0
            ? '无（长度 0）'
            : '${qr.issuerDefinedLength} 字节',
      ),
      if (qr.issuerDefinedLength > 0) ...[
        const SizedBox(height: 6),
        _hexSelectable(qr.issuerDefinedDataHex),
      ],
    ];
  }

  /// 发卡机构公钥证书（117 字节）子菜单。
  Widget _qrCertificateTile(JtT1179QrData qr) {
    final scheme = Theme.of(context).colorScheme;
    final cert = qr.issuerCertificate;
    return ExpansionTile(
      key: const PageStorageKey<String>('qr-certificate'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: const Text('发卡机构公钥证书（117 字节）'),
      subtitle: Text(
        '发卡机构 ${qr.issuerIdText ?? '未知'} · '
        '失效 ${_fmtDate(cert.expiryDateUtc.toLocal())}'
        '${cert.isExpired() ? '（已过期）' : ''}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: [
        _kv('记录头', '0x${_hex2(cert.recordHeader)}'),
        _kv(
          '服务标识',
          '${cert.serviceIdHex}'
              '${cert.isTransportEcashService ? '（交通电子现金应用）' : ''}',
        ),
        _kv('中心 CA 公钥索引', '${cert.caPublicKeyIndex}'),
        _kv('证书格式', '0x${_hex2(cert.certificateFormat)}'),
        _kv('发卡机构标识', qr.issuerIdText ?? _hexBytes(cert.issuerIdBytes)),
        _kv('证书失效日期', _fmtDate(cert.expiryDateUtc.toLocal())),
        _kv('证书序列号', cert.serialNumberHex),
        _kv(
          '公钥签名算法',
          '0x${_hex2(cert.signatureAlgorithm)}'
              '${cert.usesSm2Signature ? '（SM2）' : ''}',
        ),
        _kv('公钥加密算法（保留）', '0x${_hex2(cert.encryptionAlgorithm)}'),
        _kv('公钥参数标识', '0x${_hex2(cert.publicKeyParameter)}'),
        _kv('公钥长度', '0x${_hex2(cert.publicKeyLength)}（33 字节）'),
        _kv('发卡机构公钥', cert.issuerPublicKeyHex),
        const SizedBox(height: 6),
        _titledHexBlock(
          title: '证书原始数据（117 字节）',
          hex: _hexBytes(cert.raw),
        ),
      ],
    );
  }

  /// 二维码原始数据子菜单。
  Widget _qrRawTile(JtT1179QrData qr) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: const PageStorageKey<String>('qr-raw'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      shape: _borderlessShape,
      collapsedShape: _borderlessShape,
      title: const Text('二维码原始数据'),
      subtitle: Text(
        '${qr.raw.length} 字节（声明长度 ${qr.declaredLength} 字节）',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: [_hexSelectable(_hexBytes(qr.raw))],
    );
  }

  /// 标题 + HEX 数据块（长数据展示用）。
  Widget _titledHexBlock({required String title, required String hex}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        _hexSelectable(hex),
      ],
    );
  }

  /// 字节数组 → 大写 HEX（空格分隔）。
  String _hexBytes(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}
