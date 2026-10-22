import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../data/card_repository.dart';
import '../application/archive_history.dart';
import '../../trips/trip_cards_view.dart';
import 'archive_trip_presenter.dart';

/// Archive-only detail: captured evidence/context is independent of live scans.
class CardDetailPage extends StatefulWidget {
  final CardRepository repository;
  final String cardId;

  const CardDetailPage({
    super.key,
    required this.repository,
    required this.cardId,
  });

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  late Stream<ArchiveHistoryResult> _history;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CardDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.cardId != widget.cardId) {
      _subscribe();
    }
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
        return _CardDetailBody(history: history, repository: widget.repository);
      },
    ),
  );
}

class _CardDetailBody extends StatelessWidget {
  final ArchiveHistoryResult history;
  final CardRepository repository;
  const _CardDetailBody({required this.history, required this.repository});

  @override
  Widget build(BuildContext context) {
    final trips = presentArchiveTrips(
      history.records,
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
          repository: repository,
          observedFields: history.latestObservedFields,
          balanceText: history.balanceText,
          balanceObservationText: history.balanceObservationText,
          balanceObservationLabel: history.balanceObservationLabel,
        ),
        const SizedBox(height: 12),
        Text(
          '行程记录 · ${history.batches.length} 个已保存批次',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (history.hasDiagnostics)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('部分历史记录无法完整显示，已保留原始记录，可在批次诊断中查看。'),
          ),
        const SizedBox(height: 8),
        TripCardsView(
          key: ValueKey(history.card!.id),
          entries: trips.entries,
          sourceLabels: archiveTripSourceLabels,
          summaryText: trips.summaryText,
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ArchiveDiagnosticsPage(history: history),
            ),
          ),
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('批次诊断与原始快照'),
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
    appBar: AppBar(title: const Text('批次诊断与原始快照')),
    body: ListView(
      children: [
        for (final batch in history.batches)
          ExpansionTile(
            title: Text('批次 · ${batch.decoded.status.name}'),
            subtitle: Text(
              '${batch.id}\n${batch.origin} · ${batch.timeSource}',
            ),
            children: [
              for (final issue in batch.issues)
                ListTile(title: Text(issue.toString())),
              TextButton(
                onPressed: () =>
                    _showEvidence(context, '批次原文', batch.decoded.rawJson),
                child: const Text('查看完整原始快照'),
              ),
            ],
          ),
      ],
    ),
  );
}

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
  final CardRepository repository;
  final Map<String, bool> observedFields;
  final String? balanceText;
  final String? balanceObservationText;
  final String? balanceObservationLabel;

  const _ArchiveHeader({
    required this.card,
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
            _row(context, '交易记录', card.transactionCountText ?? '—'),
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
