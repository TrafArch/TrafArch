import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../shared/presentation/adaptive_layout.dart';
import '../archive/application/archive_history.dart';
import '../archive/application/cu_archive_projection.dart';
import '../archive/domain/card_session_snapshot.dart';
import '../archive/domain/card_types.dart';
import '../../protocols/transit/card_parser.dart';
import '../archive/presentation/archive_trip_presenter.dart';
import '../archive/presentation/local_card_history_records.dart';
import '../trips/trip_cards_view.dart';
import '../trips/cu_transaction_list.dart';
import '../trips/shanghai_mirrored_records.dart';

/// Uses captured archive display fields, never current reference matches or NFC.
class RecoveryResultPanel extends StatelessWidget {
  const RecoveryResultPanel({super.key, required this.app});
  final AppDependencies app;

  @override
  Widget build(BuildContext context) {
    final capture = app.recoveredCapture;
    if (capture == null) return const SizedBox.shrink();
    final snapshot = capture.snapshotJson == null
        ? null
        : CardSessionSnapshot.decodeResult(capture.snapshotJson!);
    final batch = snapshot == null
        ? null
        : ArchiveBatchEvidence(
            id: capture.pending?.pendingSaveId ?? 'recovered',
            readAt: capture.readAt.millisecondsSinceEpoch,
            storedParseVersion: snapshot.snapshot!.parseVersion,
            origin: 'memory_recovery',
            timeSource: 'captured',
            decoded: snapshot,
            issues: snapshot.issues,
          );
    final trips = batch == null
        ? null
        : presentArchiveTrips(
            ArchiveHistory.projectRecords([batch]),
            batches: [batch],
            cardType: capture.pending?.identity.cardType,
            includeShanghaiOverdraft: app.includeShanghaiOverdraft,
            onDiagnostics: (record) => _evidence(context, record.fields),
          );
    final cu = batch == null
        ? null
        : projectCuArchive(ArchiveHistoryResult(card: null, batches: [batch]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capture.interrupted ? '上次读取已中断' : '上次读取结果',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  capture.pending?.identity.cardType == CardTypes.lingnanTong ||
                          capture.summary['parserId'] ==
                              CardParserIds.lingnanTong ||
                          capture.summary['cardType'] == CardTypes.lingnanTong
                      ? '岭南通'
                      : capture.summary['cardName']?.toString() ?? '卡片信息',
                ),
                if (capture.summary['cardNumber'] case final String number)
                  SelectableText(number),
                Text('读取时间：${capture.readAt.toLocal()}'),
                if (capture.summary['balanceText'] case final String text)
                  Text('读取时余额：$text')
                else if (capture.summary['balanceFen'] case final int balance)
                  Text(
                    '读取时余额：${(balance / 100).toStringAsFixed(2)}'
                    ' ${capture.summary['currencyCode'] ?? '币种未知'}',
                  ),
                Text(
                  capture.interrupted
                      ? '请重新贴卡读取。下方保留中断前已获取的证据。'
                      : '已恢复捕获时的数据，继续读取请重新贴卡。',
                ),
                if (capture.canSave) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: app.savingRecoveredCapture
                            ? null
                            : () => app.saveRecoveredCapture(),
                        child: const Text('保存这次读取'),
                      ),
                      TextButton(
                        onPressed: app.savingRecoveredCapture
                            ? null
                            : app.declineRecoveredCapture,
                        child: const Text('不保存'),
                      ),
                    ],
                  ),
                ],
                if (app.recoveryNotice case final String notice) Text(notice),
                TextButton.icon(
                  onPressed: () => _evidence(context, capture.toJson()),
                  icon: const Icon(Icons.data_object),
                  label: const Text('查看上次读取的原始数据'),
                ),
              ],
            ),
          ),
        ),
        if (trips != null && trips.entries.isNotEmpty)
          TripCardsView(
            entries: trips.entries,
            projectedJourneys: trips.journeys,
            sourceLabels: archiveTripSourceLabels,
            summaryText: trips.summaryText,
            initialFilters: app.recoveryFilters['live'],
            onFiltersChanged: (values) => app.recoveryFilters['live'] = values,
          ),
        if (cu != null && cu.transactions.isNotEmpty)
          CuApplicationRecords(
            records: ShanghaiMirroredRecords(
              independent: cu.transactions,
              mirrored: const [],
            ),
            sourceLabels: cu.sourceLabels,
            isRemote: (transaction) => cu.isRemoteUse(transaction, [batch!]),
            initialFilters: app.recoveryFilters['live:cu'],
            onFiltersChanged: (values) =>
                app.recoveryFilters['live:cu'] = values,
          ),
        if (batch != null)
          ArchivedLocalCardTrips(
            records: ArchiveHistory.projectLocalCardRecords([batch])
                .where(
                  (record) =>
                      record.cardType == 'localCardTrips' ||
                      record.cardType == 'lingnanTong' ||
                      record.cardType == 'shenzhenTong',
                )
                .toList(),
          ),
        if (batch != null)
          LocalCardHistoryRecords(
            records: ArchiveHistory.projectLocalCardRecords([batch]),
          ),
        if (capture.summary['decoded'] case final Map decoded)
          if (decoded.isNotEmpty)
            Card(
              child: ExpansionTile(
                title: const Text('读取时的完整字段'),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(decoded),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  void _evidence(BuildContext context, Object value) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FoldSafePage(
            child: Scaffold(
              appBar: AppBar(title: const Text('上次读取的原始数据')),
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
