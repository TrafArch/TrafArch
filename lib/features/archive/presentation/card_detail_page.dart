import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/presentation/adaptive_layout.dart';
import '../../../shared/presentation/amusement_ic_summary.dart';
import '../../../shared/presentation/suica_identity_summary.dart';

import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../domain/amusement_ic_archive_identity.dart';
import '../data/card_repository.dart';
import '../application/archive_history.dart';
import '../application/archive_record_count.dart';
import '../application/cu_archive_projection.dart';
import '../application/suica_archive_projection.dart';
import '../application/amusement_ic_archive_projection.dart';
import '../domain/card_types.dart';
import '../domain/suica_archive_identity.dart';
import '../domain/suica_manual_number.dart';
import '../../trips/cu_transaction_list.dart';
import '../../trips/suica_trip_list.dart';
import '../../trips/trip_cards_view.dart';
import 'archive_trip_presenter.dart';
import 'imported_archive_records.dart';
import 'shanghai_archive_mirrored_records.dart';
import 'local_card_history_records.dart';
import 'archive_balance_display.dart';
import '../../settings/application/settings_controller.dart';

/// Archive-only detail: captured evidence/context is independent of live scans.
class CardDetailPage extends StatefulWidget {
  final CardRepository repository;
  final String cardId;
  final SettingsController? settings;
  final Map<String, List<String>>? recoveryFilters;

  const CardDetailPage({
    super.key,
    required this.repository,
    required this.cardId,
    this.settings,
    this.recoveryFilters,
  });

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late Stream<ArchiveHistoryResult> _history;

  @override
  void initState() {
    super.initState();
    widget.settings?.addListener(_onSettingsChanged);
    _subscribe();
  }

  @override
  void didUpdateWidget(CardDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings?.removeListener(_onSettingsChanged);
      widget.settings?.addListener(_onSettingsChanged);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.cardId != widget.cardId) {
      _subscribe();
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _subscribe() {
    _history = ArchiveHistory(widget.repository).watch(widget.cardId);
  }

  @override
  Widget build(BuildContext context) => FoldSafePage(
    child: Scaffold(
      appBar: AppBar(title: const Text('卡片信息')),
      body: SafeArea(
        top: false,
        child: AdaptiveContent(
          child: StreamBuilder<ArchiveHistoryResult>(
            key: ValueKey((widget.repository, widget.cardId)),
            stream: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('读取卡片历史失败，请重试。'),
                      TextButton(
                        onPressed: () => setState(_subscribe),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting ||
                  snapshot.connectionState == ConnectionState.none) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = snapshot.data;
              if (history == null || history.missing) {
                return const Center(child: Text('卡片不存在或已删除'));
              }
              return ArchiveDetailContent(
                history: history,
                repository: widget.repository,
                includeShanghaiOverdraft:
                    widget.settings?.includeShanghaiOverdraft ?? false,
                recoveryFilters: widget.recoveryFilters,
              );
            },
          ),
        ),
      ),
    ),
  );
}

enum ArchiveDetailSection { all, records, information }

class ArchiveDetailContent extends StatelessWidget {
  final ArchiveHistoryResult history;
  final CardRepository repository;
  final bool includeShanghaiOverdraft;
  final Map<String, List<String>>? recoveryFilters;
  final ArchiveDetailSection section;
  const ArchiveDetailContent({
    super.key,
    required this.history,
    required this.repository,
    required this.includeShanghaiOverdraft,
    this.recoveryFilters,
    this.section = ArchiveDetailSection.all,
  });

  @override
  Widget build(BuildContext context) {
    final summaryCount = history.batches
        .where((batch) => batch.origin == 'imported_summary')
        .length;
    final readBatchCount = history.batches.length - summaryCount;
    final cityUnion = projectCuArchive(history);
    final suica = projectSuicaArchive(history);
    final isAmusementIc = history.card!.cardType == CardTypes.amusementIc;
    final isSuica = history.card!.cardType == CardTypes.suica;
    final suicaIdentity = isSuica
        ? SuicaArchiveIdentity.resolve(
            cardType: history.card!.cardType,
            fingerprint: history.card!.cardFingerprint,
            snapshots: history.batches
                .map((batch) => batch.decoded.snapshot)
                .nonNulls,
          )
        : null;
    final manualNumberData = history.cardExtensions['suicaManualNumber'];
    final manualNumberUnsupported =
        history.cardExtensions.containsKey('suicaManualNumber') &&
        !SuicaManualNumber.isSupportedJson(manualNumberData);
    final canIdentifyForManualNumber =
        isSuica &&
        !suicaIdentity!.hasConflict &&
        SuicaArchiveIdentity.resolve(
              cardType: history.card!.cardType,
              fingerprint: history.card!.cardFingerprint,
            ).idm !=
            null;
    final amusementIc = projectAmusementIcArchive(history);
    final cuRecords = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cityUnion,
    );
    final trips = presentArchiveTrips(
      history.records,
      batches: history.batches,
      includeShanghaiOverdraft: includeShanghaiOverdraft,
      cardType: history.card!.cardType,
      onDiagnostics: (record) => _showRecordSources(context, record.sources),
    );
    // 通用地方卡行程（武汉通 / 北京互通卡 / 深圳通本地 / 苏州苏薪·计次 /
    // 天府通）及岭南通 / 深圳通地方钱包与 TU / CU 共用票据式行程卡；
    // 澳门通仍使用独立文本记录。
    final localTrips = history.localCardRecords
        .where(
          (record) =>
              record.cardType == 'localCardTrips' ||
              record.cardType == 'lingnanTong' ||
              record.cardType == 'shenzhenTong',
        )
        .toList();
    final children = <Widget>[
      if (section != ArchiveDetailSection.records)
        _ArchiveHeader(
          card: history.card!,
          recordCount: ArchiveRecordCount.fromHistory(history),
          repository: repository,
          observedFields: history.latestObservedFields,
          balanceText: archiveCardBalanceText(
            history.card!,
            includeShanghaiOverdraft: includeShanghaiOverdraft,
            balanceSnapshot: history.balanceSource?.snapshot,
            capturedText: history.balanceText,
          ),
          balanceObservationText: history.balanceObservationText,
          balanceObservationLabel: history.balanceObservationLabel,
          amusementIc: isAmusementIc ? amusementIc : null,
          suicaIdentity: suicaIdentity,
          suicaManualNumber: SuicaManualNumber.fromJson(manualNumberData),
          suicaManualNumberEditIssue: manualNumberUnsupported
              ? '卡面编号格式暂不支持，当前版本无法编辑；原始资料已保留。'
              : !canIdentifyForManualNumber
              ? '无法确认档案身份，暂不能编辑卡面编号；原始资料已保留。'
              : null,
        ),
      if (section != ArchiveDetailSection.information) ...[
        const SizedBox(height: 12),
        Text(
          '${isAmusementIc ? '读取记录' : '行程记录'} · $readBatchCount 个已保存批次'
          '${summaryCount == 0 ? '' : ' · $summaryCount 份导入摘要'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (history.hasDiagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              summaryCount == 0
                  ? '部分历史记录无法完整显示，可在批次诊断中查看原因。'
                  : '部分历史记录无法完整显示，可在批次与摘要诊断中查看原因。',
            ),
          ),
        const SizedBox(height: 8),
        for (final issue in amusementIc.issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(issue),
          ),
        if (!isAmusementIc &&
            (trips.entries.isNotEmpty ||
                (cityUnion.transactions.isEmpty &&
                    suica.records.isEmpty &&
                    suica.issues.isEmpty &&
                    !suica.isHistoryUnobserved &&
                    history.importedRecords.isEmpty)))
          TripCardsView(
            key: ValueKey(history.card!.id),
            entries: trips.entries,
            projectedJourneys: trips.journeys,
            sourceLabels: archiveTripSourceLabels,
            summaryText: trips.summaryText,
            initialFilters: recoveryFilters?['card:${history.card!.id}'],
            onFiltersChanged: (values) {
              recoveryFilters?['card:${history.card!.id}'] = values;
            },
          ),
        if (cityUnion.transactions.isNotEmpty)
          CuApplicationRecords(
            key: ValueKey('cu:${history.card!.id}'),
            records: cuRecords,
            sourceLabels: cityUnion.sourceLabels,
            isRemote: (transaction) =>
                cityUnion.isRemoteUse(transaction, history.batches),
            initialFilters: recoveryFilters?['card:${history.card!.id}:cu'],
            onFiltersChanged: (values) {
              recoveryFilters?['card:${history.card!.id}:cu'] = values;
            },
          ),
        if (suica.records.isNotEmpty)
          SuicaTripList(
            key: ValueKey('suica:${history.card!.id}'),
            trips: suica.trips,
            initialFilters: recoveryFilters?['card:${history.card!.id}:suica'],
            onFiltersChanged: (values) {
              recoveryFilters?['card:${history.card!.id}:suica'] = values;
            },
          ),
        if (suica.isHistoryUnobserved) const Text('尚未读取到 Suica 历史记录'),
        for (final issue in suica.issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(issue),
          ),
        if (localTrips.isNotEmpty)
          ArchivedLocalCardTrips(
            key: ValueKey('local:${history.card!.id}'),
            records: localTrips,
          ),
        LocalCardHistoryRecords(records: history.localCardRecords),
        for (final issue in cityUnion.issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(issue),
          ),
        if (history.importedRecords.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImportedArchiveRecords(records: history.importedRecords),
        ],
      ],
      if (section != ArchiveDetailSection.records) ...[
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ArchiveDiagnosticsPage(history: history),
            ),
          ),
          icon: const Icon(Icons.bug_report_outlined),
          label: Text(_archiveDiagnosticsTitle(history)),
        ),
      ],
    ];
    return section == ArchiveDetailSection.all
        ? ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
            children: children,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
  }
}

class _ArchiveDiagnosticsPage extends StatelessWidget {
  const _ArchiveDiagnosticsPage({required this.history});
  final ArchiveHistoryResult history;

  @override
  Widget build(BuildContext context) => FoldSafePage(
    child: Scaffold(
      appBar: AppBar(title: Text(_archiveDiagnosticsTitle(history))),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            for (final batch in history.batches)
              ListTile(
                title: Text(
                  '${batch.origin == 'imported_summary' ? '导入时保留的摘要' : '批次'}'
                  ' · ${batch.decoded.status.name}',
                ),
                subtitle: Text(
                  [
                    batch.id,
                    '${batch.origin} · ${batch.timeSource}',
                    for (final issue in batch.issues) issue.toString(),
                  ].join('\n'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _archiveDiagnosticsTitle(ArchiveHistoryResult history) =>
    history.batches.any((batch) => batch.origin == 'imported_summary')
    ? '批次与摘要诊断'
    : '批次诊断';

void _showRecordSources(
  BuildContext context,
  List<ArchiveRecordSource> sources,
) {
  showDialog<void>(
    context: context,
    anchorPoint: (context.findRenderObject() as RenderBox?)?.localToGlobal(
      Offset.zero,
    ),
    builder: (context) => AlertDialog(
      title: const Text('记录来源'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final source in sources)
              ListTile(
                title: Text(source.path),
                subtitle: Text(
                  '批次 ${source.batchId}\n解析版本 ${source.capturedParseVersion}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 档案信息卡：名称 / 副标题 / 卡号 / 余额 / 交易条数 / 最近读取时间，
/// 右上角写入用户自定义名称（识别结果不被覆盖，改名后数据流即时刷新）。
class _ArchiveHeader extends StatelessWidget {
  final SavedCard card;
  final ArchiveRecordCount recordCount;
  final CardRepository repository;
  final Map<String, bool> observedFields;
  final String? balanceText;
  final String? balanceObservationText;
  final String? balanceObservationLabel;
  final AmusementIcArchiveProjection? amusementIc;
  final SuicaArchiveIdentity? suicaIdentity;
  final SuicaManualNumber? suicaManualNumber;
  final String? suicaManualNumberEditIssue;

  const _ArchiveHeader({
    required this.card,
    required this.recordCount,
    required this.repository,
    required this.observedFields,
    this.balanceText,
    this.balanceObservationText,
    this.balanceObservationLabel,
    this.amusementIc,
    this.suicaIdentity,
    this.suicaManualNumber,
    this.suicaManualNumberEditIssue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aicIdentity = amusementIc == null
        ? null
        : AmusementIcArchiveIdentity.fromCapturedData(amusementIc!.data);
    final subtitle = aicIdentity == null
        ? card.subtitle
        : aicIdentity.subtitle(card.customName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aicIdentity?.displayName(card.customName) ??
                            card.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '自定义名称',
                  onPressed: () => _rename(context),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (amusementIc case final captured?) ...[
              AmusementIcSummary(data: captured.data, showRawAccessCode: false),
              if (captured.idm case final idm?) _row(context, 'IDm', idm),
              if (captured.readAt case final readAt?)
                _row(context, '代码读取', readAt.toLocal().toString()),
            ] else ...[
              if (suicaIdentity case final identity?) ...[
                SuicaIdentitySummary(
                  idm: identity.idm,
                  hasConflict: identity.hasConflict,
                  compact: true,
                ),
                if (suicaManualNumber case final number?) ...[
                  const SizedBox(height: 8),
                  Text(
                    '卡面编号（手工填写）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          number.formatted,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '复制卡面编号',
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          await Clipboard.setData(
                            ClipboardData(text: number.value),
                          );
                          if (messenger?.mounted == true) {
                            messenger!.showSnackBar(
                              const SnackBar(content: Text('已复制卡面编号')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ],
                  ),
                ],
                if (suicaManualNumberEditIssue case final issue?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(issue, style: theme.textTheme.bodySmall),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _editSuicaNumber(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      suicaManualNumber == null ? '填写卡面编号' : '修改卡面编号',
                    ),
                  ),
              ] else
                _row(context, '已观察卡号', card.cardNumberText),
              _row(context, '已观察余额', balanceText ?? '—'),
              if (balanceObservationText case final observed?)
                _row(
                  context,
                  balanceObservationLabel ?? '历史金额',
                  '$observed（非已验证港币账户余额）',
                ),
              _row(context, recordCount.label, recordCount.valueText),
            ],
            _row(context, '最近读取', card.lastReadFullText ?? '—'),
            if (amusementIc == null)
              for (final field in const {
                'cardNumber': '卡号',
                'balanceFen': '余额',
                'currencyCode': '币种',
                'transactionCount': '交易条数',
              }.entries)
                if (observedFields[field.key] == false &&
                    !(suicaIdentity != null && field.key == 'cardNumber'))
                  _row(context, '本次缺失', '${field.value}未读到，摘要保留既往已观察值'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _editSuicaNumber(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      anchorPoint: (context.findRenderObject() as RenderBox?)?.localToGlobal(
        Offset.zero,
      ),
      builder: (_) => _SuicaManualNumberDialog(
        repository: repository,
        cardId: card.id,
        number: suicaManualNumber,
      ),
    );
  }

  /// 改名对话框：留空即清除自定义名称（回退展示正式卡名）。
  Future<void> _rename(BuildContext context) async {
    var editedName = card.customName ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      anchorPoint: (context.findRenderObject() as RenderBox?)?.localToGlobal(
        Offset.zero,
      ),
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义卡片名称'),
        // The form field owns its controller for the complete route lifetime,
        // including the dismissal animation after showDialog has returned.
        content: TextFormField(
          initialValue: editedName,
          onChanged: (value) => editedName = value,
          autofocus: true,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '留空则恢复正式卡名'),
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(editedName),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await repository.renameCard(card.id, name);
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('已更新卡片名称')));
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('名称未保存，请重试。')));
      }
    }
  }
}

class _SuicaManualNumberDialog extends StatefulWidget {
  const _SuicaManualNumberDialog({
    required this.repository,
    required this.cardId,
    this.number,
  });

  final CardRepository repository;
  final String cardId;
  final SuicaManualNumber? number;

  @override
  State<_SuicaManualNumberDialog> createState() =>
      _SuicaManualNumberDialogState();
}

class _SuicaManualNumberDialogState extends State<_SuicaManualNumberDialog> {
  final _form = GlobalKey<FormState>();
  late String _value = widget.number?.formatted ?? '';
  bool _saving = false;
  String? _saveError;

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final normalized = normalizeSuicaManualNumber(_value);
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.repository.setSuicaManualNumber(widget.cardId, normalized);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '卡面编号保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.number == null ? '填写卡面编号' : '修改卡面编号'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填写卡面印刷的编号，仅作为手工备注保存。留空可清除。'),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _value,
              enabled: !_saving,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '卡面编号',
                hintText: 'JE123 4567 8901 2345',
                errorMaxLines: 4,
              ),
              onChanged: (value) => _value = value,
              validator: (value) {
                try {
                  normalizeSuicaManualNumber(value);
                  return null;
                } on FormatException {
                  return '请输入 2 位字母和 15 位数字，例如 JE123 4567 8901 2345';
                }
              },
              onFieldSubmitted: (_) => _save(),
            ),
            if (_saveError case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
