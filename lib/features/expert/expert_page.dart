import 'package:flutter/material.dart';
import '../../core/analysis/analysis_models.dart';
import '../../core/nfc/nfc_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../core/transit/tunion/tunion_process_parser.dart';
import '../../core/ui_constants.dart';
import '../../state/app_state.dart';
import '../settings/settings_action_button.dart';

class ExpertPage extends StatefulWidget {
  final AppState app;
  const ExpertPage({super.key, required this.app});

  @override
  State<ExpertPage> createState() => _ExpertPageState();
}

class _ExpertPageState extends State<ExpertPage> {
  /// 空边框形状：去掉 ExpansionTile 展开时默认在内容上下绘制的两条分隔线。
  static const Border _borderlessShape = Border();

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onNfcChanged);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onNfcChanged);
    super.dispose();
  }

  void _onNfcChanged() {
    if (mounted) setState(() {});
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
    final info = app.cardInfo;
    final analysis = app.analysis;
    final identity = analysis?.identity;
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

    return SafeArea(
      top: false,
      child: DefaultTabController(
        length: 6,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              title: const Text('专家分析'),
              pinned: true,
              actions: [SettingsActionButton(app: app)],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'NFC / ISO-DEP'),
                  Tab(text: '卡片识别'),
                  Tab(text: '交通数据解析'),
                  Tab(text: 'JT/T 978 符合性'),
                  Tab(text: '异常检测'),
                  Tab(text: 'APDU / Raw Data'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _tabBody('expert-nfc', [
                _kv('UID', result?.uid ?? '—'),
                _kv('Technology', result?.technologies.join(' / ') ?? '—'),
                _kv('Card Type', result?.cardType ?? '—'),
                _kv('ATQA', result?.atqa ?? '—'),
                _kv('SAK', result?.sak ?? '—'),
                _kv('历史字节解读', result?.atsDescription ?? '—'),
                _kv('Historical Bytes', result?.historicalBytes ?? '—'),
                _kv('Hi-layer Response', result?.hiLayerResponse ?? '—'),
                _kv('NFC-B App Data', result?.nfcBApplicationData ?? '—'),
                _kv('NFC-B Protocol Info', result?.nfcBProtocolInfo ?? '—'),
                _kv('NFC-F System Code', result?.nfcFSystemCode ?? '—'),
                _kv('NFC-F Manufacturer', result?.nfcFManufacturer ?? '—'),
                _kv('NFC-V DSFID', result?.nfcVDsfId ?? '—'),
                _kv('NFC-V Response Flags', result?.nfcVResponseFlags ?? '—'),
                _kv('MIFARE Type', result?.mifareType ?? '—'),
                _kv('MIFARE Size', result?.mifareSize?.toString() ?? '—'),
                _kv('MIFARE Sectors',
                    result?.mifareSectorCount?.toString() ?? '—'),
                _kv('MIFARE Blocks',
                    result?.mifareBlockCount?.toString() ?? '—'),
                _kv('MIFARE Block 0',
                    result?.mifareManufacturerBlock ?? '—'),
                _kv(
                    'MIFARE BCC',
                    switch (result?.mifareBccValid) {
                      null => '—',
                      true => '校验通过',
                      false => '校验失败',
                    }),
                _kv('Max Transceive Length',
                    result?.maxTransceiveLength?.toString() ?? '—'),
                _kv(
                    'ISO-DEP Connected',
                    result == null
                        ? '—'
                        : (result!.isoDepConnected ? 'YES' : 'NO')),
              ]),
              _tabBody('expert-identify', [
                _kv('解析器', parsed?.parserName ?? '—'),
                _kv(
                    '选中 AID',
                    (parsed == null || parsed.selectedAidHex.isEmpty)
                        ? '—'
                        : parsed.selectedAidHex),
                _kv('交通联合应用', app.tunionDetected ? '已发现' : '未发现'),
                _kv('识别城市', identity?.cityName ?? '未知'),
                _kv('卡种', identity?.cardFamily ?? '未知'),
                _kv('卡片名称', app.cardPrefixByIssuerId(info?.issuerId)?.cardName ?? '未知'),
                _kv('知识库', app.knowledgeSummary),
                for (final e in identity?.evidence ?? const <Evidence>[])
                  _kv(
                    e.source,
                    '${e.detail}${e.weight > 0 ? '（权重 ${e.weight}）' : ''}',
                  ),
              ]),
              _tabBody('expert-parsed', [
                _kv('逻辑卡号', _val(info?.displayCardNumber)),
                _kv('发卡机构标识', _val(info?.issuerId)),
                _kv('应用类型标识', _val(info?.appTypeId)),
                _kv('应用版本', _val(info?.appVersion)),
                _kv('生效日期', _fmtDate(info?.effectiveDate)),
                _kv('失效日期', _fmtDate(info?.expireDate)),
                _kv('发卡机构 FCI', _val(info?.issuerFci)),
                _kv('国际代码', _val(info?.countryCode)),
                _kv('省级代码', _val(info?.provinceCode)),
                _kv('城市代码', _val(info?.cityCode)),
                _kv('互通卡种', _val(info?.interopCardType)),
                _kv('卡种类型', _val(info?.cardKind)),
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
              ]),
              _tabBody('expert-compliance', [
                _kv('综合覆盖度',
                    analysis == null
                        ? '—'
                        : '${analysis.compliance.scorePercent}%'),
                for (final item
                    in analysis?.compliance.items ?? const <ComplianceItem>[])
                  _complianceRow(context, item),
              ]),
              _tabBody('expert-anomaly', [
                if (analysis == null)
                  _kv('状态', '—')
                else if (analysis.anomalies.isEmpty)
                  _kv('状态', '未发现异常数据')
                else
                  for (final a in analysis.anomalies)
                    _anomalyRow(context, a),
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
                      child: SelectableText(
                        entry,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
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
                          SelectableText(
                            r.rawHex,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
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
        record == null
            ? '未写入'
            : record.isBlank
                ? '未写入（初始值）'
                : transit != null
                    ? '已解析 · 进出站配对'
                    : '${record.raw.length} 字节 · 未解析',
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
        record == null
            ? '未写入'
            : record.isBlank
                ? '未写入（初始值）'
                : bus != null
                    ? '已解析 · 上下车配对'
                    : '${record.raw.length} 字节 · 未解析',
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

  /// 金额单元格：括号内原始 4 字节 HEX（小写）+ 金额（元）。
  String _amountCell(int? fen) {
    if (fen == null) return '未知';
    final hex = fen.toRadixString(16).padLeft(8, '0').toLowerCase();
    return '($hex)${(fen / 100).toString()}元';
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
      return '${_dateTimeDigits(trip.time)} · ${trip.amountText}';
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
    return SelectableText(
      hex,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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

  Widget _anomalyRow(BuildContext context, Anomaly anomaly) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (anomaly.severity) {
      AnomalySeverity.critical => (Icons.error_outline, scheme.error),
      AnomalySeverity.warn => (Icons.warning_amber_outlined, Colors.orange),
      AnomalySeverity.info => (Icons.info_outline, scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${anomaly.message}（${anomaly.code}）'),
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

  Widget _tabBody(String storageKey, List<Widget> children) {
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
        if (result == null)
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
}
