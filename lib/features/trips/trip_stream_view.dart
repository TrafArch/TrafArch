// 新建文件：lib/features/trips/trip_stream_view.dart
import 'package:flutter/material.dart';
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/data/station_codes.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../state/app_state.dart';

/// 行程流统一展示组件（行程页 / 卡片详情页共用）：
/// - 统一统计口径：交易笔数 / 过程事件数 / 实际行程数，0x1E 不重复计入消费；
/// - 日期分组、交通方式与记录来源筛选；
/// - 单条详情：记录来源（0x18 / 0x1E / 0x1A）、关联证据、站点匹配置信、
///   原始十六进制（0x18 交易明细保持行程流与统计的主干来源）。
class TripStreamView extends StatefulWidget {
  const TripStreamView({
    super.key,
    required this.stream,
    required this.app,
    required this.isRemote,
  });

  final List<TripEntry> stream;
  final AppState app;
  final bool Function(String? cityCode) isRemote;

  @override
  State<TripStreamView> createState() => _TripStreamViewState();
}

enum _SourceFilter { transaction, cycle, record }

enum _ModeFilter { rail, bus, other }

class _TripStreamViewState extends State<TripStreamView> {
  /// 选中的记录来源集合；空集合 = 不限来源（全部）。多选支持
  /// 同时勾选「0x1E 过程」「0x1A 记录」等任意组合。
  final Set<_SourceFilter> _sources = <_SourceFilter>{};

  /// 选中的交通方式集合；空集合 = 不限方式（全部）。
  final Set<_ModeFilter> _modes = <_ModeFilter>{};

  static const _sourceLabels = <_SourceFilter, String>{
    _SourceFilter.transaction: '0x18 交易',
    _SourceFilter.cycle: '0x1E 过程',
    _SourceFilter.record: '0x1A 记录',
  };
  static const _modeLabels = <_ModeFilter, String>{
    _ModeFilter.rail: '城市轨道交通',
    _ModeFilter.bus: '公共汽电车',
    _ModeFilter.other: '其他',
  };

  _SourceFilter _sourceOf(TripEntry entry) => switch (entry) {
        TransactionTripEntry() => _SourceFilter.transaction,
        ProcessTripEntry() => _SourceFilter.cycle,
        RailRecordEntry() || BusRecordEntry() => _SourceFilter.record,
      };

  _ModeFilter _modeOf(TripEntry entry) => switch (entry) {
        RailRecordEntry() => _ModeFilter.rail,
        BusRecordEntry() => _ModeFilter.bus,
        ProcessTripEntry(:final record) => record.isBus
            ? _ModeFilter.bus
            : (record.isCityRail ? _ModeFilter.rail : _ModeFilter.other),
        TransactionTripEntry(:final trip) => trip.appTypeName == '公共汽电车'
            ? _ModeFilter.bus
            : (trip.appTypeName == '城市轨道交通'
                ? _ModeFilter.rail
                : _ModeFilter.other),
      };

  /// 单条行程卡片：异地判定（按本卡发卡地城市代码）与展示数据一次算好，
  /// 避免同一入口在卡片与详情弹层间口径不一致。
  Widget _entryCard(BuildContext context, TripEntry entry) {
    final remote = widget.isRemote(_tripCityCode(entry));
    return _EntryCard(
      info: _describe(entry, widget.app, remote: remote),
      remote: remote,
      onTap: () => _showDetail(context, entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = summarizeTripStream(widget.stream);
    final filtered = widget.stream
        .where((e) =>
            (_sources.isEmpty || _sources.contains(_sourceOf(e))) &&
            (_modes.isEmpty || _modes.contains(_modeOf(e))))
        .toList();
    final groups = groupTripsByDate(filtered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stats.summaryText,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('全部来源'),
              selected: _sources.isEmpty,
              onSelected: (_) => setState(_sources.clear),
            ),
            for (final value in _SourceFilter.values)
              FilterChip(
                label: Text(_sourceLabels[value]!),
                selected: _sources.contains(value),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _sources.add(value);
                  } else {
                    _sources.remove(value);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilterChip(
              label: const Text('全部方式'),
              selected: _modes.isEmpty,
              onSelected: (_) => setState(_modes.clear),
            ),
            for (final value in _ModeFilter.values)
              FilterChip(
                label: Text(_modeLabels[value]!),
                selected: _modes.contains(value),
                onSelected: (sel) => setState(() {
                  if (sel) {
                    _modes.add(value);
                  } else {
                    _modes.remove(value);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              widget.stream.isEmpty ? '暂无记录' : '当前筛选条件下没有记录',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                '${group.dateText} · ${group.entries.length} 条',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final entry in group.entries) _entryCard(context, entry),
          ],
      ],
    );
  }

  void _showDetail(BuildContext context, TripEntry entry) {
    final remote = widget.isRemote(_tripCityCode(entry));
    final info = _describe(entry, widget.app, remote: remote);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(info.title,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('记录来源：${info.sourceLabel}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(sheetContext).colorScheme.outline)),
            if (info.remoteCityText != null) ...[
              const SizedBox(height: 4),
              Text(
                '异地用卡 · 受理城市：${info.remoteCityText}',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(sheetContext).colorScheme.tertiary),
              ),
            ],
            if (info.related != null) ...[
              const SizedBox(height: 4),
              Text('关联来源：${info.related}',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            for (final field in info.fields)
              _DetailRow(label: field.$1, value: field.$2),
            const SizedBox(height: 14),
            Text('原始数据（HEX）',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SelectableText(
              info.rawHex == null ? '未保留原始字节' : _groupHex(info.rawHex!),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// 条目的统一展示数据（卡片与详情弹层共用，避免两处口径不一致）。
class _EntryInfo {
  final String sourceLabel;
  final String title;
  final String? line;
  final String? timeText;
  final String? amountText;
  final bool isConsume;
  final String? subText;
  final String? category;
  final List<String> badges;
  final String? related;
  final String? rawHex;
  final List<(String, String)> fields;

  /// 异地用卡时的受理城市文本「城市名（城市代码）」；非异地 / 代码缺失为 null。
  final String? remoteCityText;

  const _EntryInfo({
    required this.sourceLabel,
    required this.title,
    required this.isConsume,
    this.line,
    this.timeText,
    this.amountText,
    this.subText,
    this.category,
    this.badges = const [],
    this.related,
    this.rawHex,
    this.fields = const [],
    this.remoteCityText,
  });

  /// 附加受理城市文本（不改其余字段，供 [_describe] 统一包装）。
  _EntryInfo withRemoteCity(String city) => _EntryInfo(
        sourceLabel: sourceLabel,
        title: title,
        line: line,
        timeText: timeText,
        amountText: amountText,
        isConsume: isConsume,
        subText: subText,
        category: category,
        badges: badges,
        related: related,
        rawHex: rawHex,
        fields: fields,
        remoteCityText: city,
      );
}

/// 条目发生地的城市代码（0x1A 按进 / 出侧取对应城市；异地判定与城市名
/// 解析共用同一口径）。
String? _tripCityCode(TripEntry entry) => switch (entry) {
      TransactionTripEntry(:final trip) => trip.cityCode,
      ProcessTripEntry(:final record) => record.cityCode,
      RailRecordEntry(:final record, :final isEntry) =>
        isEntry ? record.entryCityCode : record.exitCityCode,
      BusRecordEntry(:final record, :final isEntry) =>
        isEntry ? record.entryCityCode : record.exitCityCode,
    };

/// 行程展示数据：非异地直接返回基础视图；异地时补「城市名（城市代码）」
/// 文本（城市名按当前知识库实时解析，未收录显式「未知城市」，不猜测）。
_EntryInfo _describe(TripEntry entry, AppState app, {required bool remote}) {
  final info = _describeEntry(entry, app);
  if (!remote) return info;
  final code = _tripCityCode(entry);
  if (code == null || code.isEmpty) return info;
  return info.withRemoteCity('${app.cityNameOf(code) ?? '未知城市'}（$code）');
}

_EntryInfo _describeEntry(TripEntry entry, AppState app) {
  switch (entry) {
    case TransactionTripEntry(:final trip):
      final badges = <String>[
        switch (trip.stationConfidence) {
          StationMatchConfidence.probable => '站名推测',
          StationMatchConfidence.ambiguous => '站名歧义',
          _ => '',
        },
      ].where((b) => b.isNotEmpty).toList();
      return _EntryInfo(
        sourceLabel: '0x18 交易明细',
        title: <String>[
          trip.rideStatusName ?? trip.typeName,
          if (trip.stationLabel != null) trip.stationLabel!,
          '序号 ${trip.sequence}',
        ].join(' · '),
        line: trip.lineLabel,
        timeText: trip.timeText,
        amountText: trip.amountText,
        isConsume: trip.isConsume,
        subText: trip.balanceAfterText == null
            ? null
            : '余额 ${trip.balanceAfterText}',
        category: trip.appTypeName,
        badges: badges,
        related: trip.matchedProcessTrip != null
            ? '已与 0x1E 过程记录唯一关联（时间 + 金额 + 终端互证）'
            : '无过程记录关联（独立保留）',
        rawHex: trip.rawHex,
        fields: [
          ('交易类型', trip.typeName),
          ('交易序号', '${trip.sequence}'),
          ('交易时间', trip.timeText),
          ('金额', trip.amountText),
          if (trip.balanceAfterText != null) ('交易后余额', trip.balanceAfterText!),
          ('终端编号', trip.terminalId),
          if (trip.cityCode != null) ('城市代码', trip.cityCode!),
          if (trip.cityName != null) ('城市', trip.cityName!),
          if (trip.location?.lineCode != null)
            ('线路原始编码', trip.location!.lineCode!),
          if (trip.location?.stationCode != null)
            ('站点原始编码', trip.location!.stationCode!),
          if (trip.stationConfidence != null)
            ('站点匹配置信', trip.stationConfidence!.name),
          if (trip.appTypeName != null) ('应用分类', trip.appTypeName!),
        ],
      );
    case RailRecordEntry(:final record, :final isEntry):
      final cityCode = isEntry ? record.entryCityCode : record.exitCityCode;
      final rawStation = isEntry ? record.entryStationId : record.exitStationId;
      final rawLineValue =
          isEntry ? record.entryLineCode : record.exitLineCode;
      final rawLine = rawLineValue?.toString();
      final match =
          app.resolveStationMatch(cityCode, rawStation, lineValue: rawLineValue);
      final station = match.stationName ?? rawStation;
      final line = rawLineValue == null
          ? app.resolveLineName(cityCode, rawLine)
          : (app.resolveLineName(cityCode, rawLineValue.toString()) ??
              app.resolveLineName(cityCode,
                  rawLineValue.toRadixString(16).toUpperCase()) ??
              rawLine);
      final symbol = app.cardCurrency.symbol;
      final amountFen = isEntry ? record.entryAmountFen : record.exitAmountFen;
      final balanceFen = isEntry ? record.entryBalanceFen : null;
      final time = isEntry ? record.entryTime : record.exitTime;
      return _EntryInfo(
        sourceLabel: '0x1A 轨道记录',
        title: <String>[
          isEntry ? '进站' : '出站',
          if (station != null) station,
        ].join(' · '),
        line: line,
        timeText: time == null ? null : _fmtTime(time),
        amountText: amountFen == null || amountFen <= 0
            ? null
            : '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
        isConsume: (amountFen ?? 0) > 0,
        subText: balanceFen == null
            ? null
            : '余额 $symbol${(balanceFen / 100).toStringAsFixed(2)}',
        category: '城市轨道交通',
        badges: _confidenceBadges(match),
        related: '过程记录（未与交易确认重复，独立保留）',
        rawHex: record.rawHex,
        fields: [
          ('交易状态', record.statusName),
          ('进站时间', _fmtOpt(record.entryTime)),
          ('出站时间', _fmtOpt(record.exitTime)),
          ('进闸城市', _fmtOptText(record.entryCityCode)),
          ('出闸城市', _fmtOptText(record.exitCityCode)),
          ('进闸站点（原始）', _fmtOptText(record.entryStationId)),
          ('出闸站点（原始）', _fmtOptText(record.exitStationId)),
          ('进闸终端', _fmtOptText(record.entryTerminalId)),
          ('出闸终端', _fmtOptText(record.exitTerminalId)),
          if (amountFen != null && amountFen > 0)
            ('本侧金额', '-$symbol${(amountFen / 100).toStringAsFixed(2)}'),
        ],
      );
    case BusRecordEntry(:final record, :final isEntry):
      final cityCode = isEntry ? record.entryCityCode : record.exitCityCode;
      final rawStation = isEntry ? record.entryStationCode : record.exitStationCode;
      final rawLine = isEntry ? record.entryLineCode : record.exitLineCode;
      final match = app.resolveStationMatch(cityCode, rawStation);
      final station = match.stationName ?? rawStation;
      final line = app.resolveLineName(cityCode, rawLine);
      final symbol = app.cardCurrency.symbol;
      final amountFen = isEntry ? null : record.transactionAmountFen;
      final mileage = isEntry ? null : record.mileage;
      final time = isEntry ? record.entryTime : record.exitTime;
      return _EntryInfo(
        sourceLabel: '0x1A 公交记录',
        title: <String>[
          isEntry ? '上车' : '下车',
          if (station != null) station,
        ].join(' · '),
        line: line,
        timeText: time == null ? null : _fmtTime(time),
        amountText: amountFen == null || amountFen <= 0
            ? null
            : '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
        isConsume: (amountFen ?? 0) > 0,
        subText: mileage == null ? null : '里程 $mileage 站',
        category: '公共汽电车',
        badges: _confidenceBadges(match),
        related: '过程记录（未与交易确认重复，独立保留）',
        rawHex: record.rawHex,
        fields: [
          ('交易状态', record.statusName),
          ('上车时间', _fmtOpt(record.entryTime)),
          ('下车时间', _fmtOpt(record.exitTime)),
          ('上车城市', _fmtOptText(record.entryCityCode)),
          ('下车城市', _fmtOptText(record.exitCityCode)),
          ('上车站（原始）', _fmtOptText(record.entryStationCode)),
          ('下车站（原始）', _fmtOptText(record.exitStationCode)),
          ('上车终端', _fmtOptText(record.entryTerminalId)),
          ('下车终端', _fmtOptText(record.exitTerminalId)),
          ('方向', record.directionName),
        ],
      );
    case ProcessTripEntry(:final record):
      final match =
          app.resolveCycleStationMatch(record.cityCode, record.lineStationCode);
      final station = match.stationName;
      final symbol = app.cardCurrency.symbol;
      return _EntryInfo(
        sourceLabel: '0x1E 过程记录',
        title: <String>[
          record.statusShortName ?? record.typeName,
          if (station != null) station,
        ].join(' · '),
        line: match.lineName,
        timeText: _fmtTime(record.time),
        amountText: record.amountFen <= 0
            ? null
            : '-$symbol${(record.amountFen / 100).toStringAsFixed(2)}',
        isConsume: !record.isEntry && record.amountFen > 0,
        subText: record.balanceFen <= 0
            ? null
            : '余额 $symbol${(record.balanceFen / 100).toStringAsFixed(2)}',
        category: record.appTypeLabel,
        badges: _confidenceBadges(match),
        related: '未与 0x18 交易关联，作为独立过程事件保留',
        rawHex: record.rawHex,
        fields: [
          ('过程类型', record.typeName),
          ('应用分类', record.appTypeName),
          ('终端编号', record.terminalId),
          ('线路站点字段（原始）', record.lineStationCode),
          ('金额', '${(record.amountFen / 100).toStringAsFixed(2)} 元'),
          ('交易后余额', '${(record.balanceFen / 100).toStringAsFixed(2)} 元'),
          ('城市代码', _fmtOptText(record.cityCode)),
          ('受理方标识', _fmtOptText(record.acquirerId)),
        ],
      );
  }
}

List<String> _confidenceBadges(StationMatch match) => [
      switch (match.confidence) {
        StationMatchConfidence.probable => '站名推测',
        StationMatchConfidence.ambiguous => '站名歧义',
        _ => '',
      },
    ].where((b) => b.isNotEmpty).toList();

class _EntryCard extends StatelessWidget {
  final _EntryInfo info;
  final bool remote;
  final VoidCallback onTap;
  const _EntryCard({
    required this.info,
    required this.remote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      info.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final badge in info.badges) ...[
                    _TagBadge(text: badge, scheme: scheme),
                    const SizedBox(width: 4),
                  ],
                  if (remote) _TagBadge(text: '异地用卡', tertiary: true, scheme: scheme),
                ],
              ),
              if (info.remoteCityText != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: scheme.tertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '受理城市：${info.remoteCityText}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (info.line != null) ...[
                const SizedBox(height: 4),
                Text(
                  info.line!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (info.timeText != null) ...[
                const SizedBox(height: 6),
                Text(
                  info.timeText!,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (info.amountText != null)
                    Text(
                      info.amountText!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: info.isConsume ? scheme.error : scheme.primary,
                      ),
                    ),
                  if (info.subText != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      info.subText!,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                  const Spacer(),
                  if (info.category != null)
                    Text(
                      info.category!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String text;
  final bool tertiary;
  final ColorScheme scheme;
  const _TagBadge({required this.text, required this.scheme, this.tertiary = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tertiary ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color:
              tertiary ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtTime(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}

String _fmtOpt(DateTime? t) => t == null ? '未写入' : _fmtTime(t);

String _fmtOptText(String? v) => v == null || v.isEmpty ? '未写入' : v;

/// 原始 HEX 按 4 字节分组（逐字节核对用）。
String _groupHex(String hex) {
  final compact = hex.replaceAll(RegExp(r'\s'), '');
  final parts = <String>[];
  for (var i = 0; i < compact.length; i += 8) {
    parts.add(compact.substring(i, (i + 8).clamp(0, compact.length)));
  }
  return parts.join('  ');
}