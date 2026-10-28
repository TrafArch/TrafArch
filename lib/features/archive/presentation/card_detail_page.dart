import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../data/card_repository.dart';
import '../application/archive_history.dart';
import '../application/archive_record_count.dart';
import '../application/cu_archive_projection.dart';
import '../../trips/cu_transaction_list.dart';
import '../../trips/trip_cards_view.dart';
import 'archive_trip_presenter.dart';
import 'imported_archive_records.dart';
import 'shanghai_archive_mirrored_records.dart';
import 'archive_balance_display.dart';
import '../../settings/application/settings_controller.dart';

/// Archive-only detail: captured evidence/context is independent of live scans.
class CardDetailPage extends StatefulWidget {
  final CardRepository repository;
  final String cardId;
  final SettingsController? settings;

  const CardDetailPage({
    super.key,
    required this.repository,
    required this.cardId,
    this.settings,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('卡片信息')),
    body: StreamBuilder<ArchiveHistoryResult>(
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
        return _CardDetailBody(
          history: history,
          repository: widget.repository,
          includeShanghaiOverdraft:
              widget.settings?.includeShanghaiOverdraft ?? false,
        );
      },
    ),
  );
}

class _CardDetailBody extends StatelessWidget {
  final ArchiveHistoryResult history;
  final CardRepository repository;
  final bool includeShanghaiOverdraft;
  const _CardDetailBody({
    required this.history,
    required this.repository,
    required this.includeShanghaiOverdraft,
  });

  @override
  Widget build(BuildContext context) {
    final summaryCount = history.batches
        .where((batch) => batch.origin == 'imported_summary')
        .length;
    final readBatchCount = history.batches.length - summaryCount;
    final cityUnion = projectCuArchive(history);
    final cuRecords = partitionShanghaiArchiveMirroredRecords(
      history: history,
      cityUnion: cityUnion,
    );
    final trips = presentArchiveTrips(
      history.records,
      includeShanghaiOverdraft: includeShanghaiOverdraft,
      cardType: history.card!.cardType,
      onDiagnostics: (record) => _showEvidence(
        context,
        '诊断与原始证据',
        const JsonEncoder.withIndent('  ').convert({
          'context': record.context.toJson(),
          'cardCityCode': record.cardCityCode,
          'record': record.fields,
          'sources': [
            for (final source in record.sources)
              {
                'batchId': source.batchId,
                'path': source.path,
                'capturedParseVersion': source.capturedParseVersion,
                'provenance': source.provenance,
              },
          ],
        }),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
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
        ),
        const SizedBox(height: 12),
        Text(
          '行程记录 · $readBatchCount 个已保存批次'
          '${summaryCount == 0 ? '' : ' · $summaryCount 份导入摘要'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (history.hasDiagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              summaryCount == 0
                  ? '部分历史记录无法完整显示，已保留原始记录，可在批次诊断中查看。'
                  : '部分历史记录无法完整显示，已保留原始记录，可在批次与摘要诊断中查看。',
            ),
          ),
        const SizedBox(height: 8),
        if (trips.entries.isNotEmpty ||
            (cityUnion.transactions.isEmpty && history.importedRecords.isEmpty))
          TripCardsView(
            key: ValueKey(history.card!.id),
            entries: trips.entries,
            sourceLabels: archiveTripSourceLabels,
            summaryText: trips.summaryText,
          ),
        if (cityUnion.transactions.isNotEmpty)
          CuApplicationRecords(
            records: cuRecords,
            sourceLabels: cityUnion.sourceLabels,
          ),
        for (final issue in cityUnion.issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(issue),
          ),
        if (history.importedRecords.isNotEmpty) ...[
          const SizedBox(height: 12),
          ImportedArchiveRecords(records: history.importedRecords),
        ],
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
    );
  }
}

/// Technical evidence is an explicit secondary route, never the trip tap.
class _ArchiveDiagnosticsPage extends StatelessWidget {
  const _ArchiveDiagnosticsPage({required this.history});
  final ArchiveHistoryResult history;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_archiveDiagnosticsTitle(history))),
    body: ListView(
      children: [
        for (final batch in history.batches)
          ExpansionTile(
            title: Text(
              '${batch.origin == 'imported_summary' ? '导入时保留的摘要' : '批次'}'
              ' · ${batch.decoded.status.name}',
            ),
            subtitle: Text(
              '${batch.id}\n${batch.origin} · ${batch.timeSource}',
            ),
            children: [
              for (final issue in batch.issues)
                ListTile(title: Text(issue.toString())),
              TextButton(
                onPressed: () => _showEvidence(
                  context,
                  batch.origin == 'imported_summary' ? '保留摘要中的原始快照' : '批次原文',
                  batch.decoded.rawJson,
                ),
                child: Text(
                  batch.origin == 'imported_summary'
                      ? '查看摘要中的原始快照'
                      : '查看完整原始快照',
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

String _archiveDiagnosticsTitle(ArchiveHistoryResult history) =>
    history.batches.any((batch) => batch.origin == 'imported_summary')
    ? '批次、摘要与原始快照'
    : '批次诊断与原始快照';

void _showEvidence(BuildContext context, String title, String raw) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(raw)),
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

  const _ArchiveHeader({
    required this.card,
    required this.recordCount,
    required this.repository,
    required this.observedFields,
    this.balanceText,
    this.balanceObservationText,
    this.balanceObservationLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                        card.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
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
            _row(context, '已观察卡号', card.cardNumberText),
            _row(context, '已观察余额', balanceText ?? '—'),
            if (balanceObservationText case final observed?)
              _row(
                context,
                balanceObservationLabel ?? '历史金额',
                '$observed（非已验证港币账户余额）',
              ),
            _row(context, recordCount.label, recordCount.valueText),
            _row(context, '最近读取', card.lastReadFullText ?? '—'),
            for (final field in const {
              'cardNumber': '卡号',
              'balanceFen': '余额',
              'currencyCode': '币种',
              'transactionCount': '交易条数',
            }.entries)
              if (observedFields[field.key] == false)
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

  /// 改名对话框：留空即清除自定义名称（回退展示正式卡名）。
  Future<void> _rename(BuildContext context) async {
    var editedName = card.customName ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
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
    await repository.renameCard(card.id, name);
    if (messenger.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('已更新卡片名称')));
    }
  }
}
