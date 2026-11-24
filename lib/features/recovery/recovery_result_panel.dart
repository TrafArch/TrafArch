import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_dependencies.dart';
import '../../protocols/felica/models/amusement_ic_data.dart';
import '../../shared/presentation/adaptive_layout.dart';
import '../../shared/presentation/amusement_ic_summary.dart';
import '../../shared/presentation/application_evidence_panel.dart';
import '../archive/application/archive_history.dart';
import '../archive/application/cu_archive_projection.dart';
import '../archive/domain/card_session_snapshot.dart';
import '../archive/domain/card_types.dart';
import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/tunion/tunion_cash_log.dart';
import '../archive/presentation/archive_trip_presenter.dart';
import '../archive/presentation/local_card_history_records.dart';
import '../trips/trip_cards_view.dart';
import '../trips/cu_transaction_list.dart';
import '../trips/shanghai_mirrored_records.dart';
import '../trips/tunion_cash_log_view.dart';
import '../trips/suica_trip_list.dart';
import '../trips/suica_trip_presenter.dart';

/// Uses captured archive display fields, never current reference matches or NFC.
class RecoveryResultPanel extends StatelessWidget {
  const RecoveryResultPanel({
    super.key,
    required this.app,
    this.showSaveActions = true,
  });
  final AppDependencies app;
  final bool showSaveActions;

  @override
  Widget build(BuildContext context) {
    final capture = app.recoveredCapture;
    if (capture == null) return const SizedBox.shrink();
    // 旧版读卡字段只在原始证据页展示。
    final summary = switch (capture.summary['decoded']) {
      {'protocolFamily': String(), 'discoveredApplications': List()} =>
        const <String, Object?>{},
      _ => capture.summary,
    };
    final snapshot = capture.snapshotJson == null
        ? null
        : CardSessionSnapshot.decodeResult(capture.snapshotJson!);
    final decodedSnapshot = snapshot?.snapshot;
    final batch = decodedSnapshot == null
        ? null
        : ArchiveBatchEvidence(
            id: capture.pending?.pendingSaveId ?? 'recovered',
            readAt: capture.readAt.millisecondsSinceEpoch,
            storedParseVersion: decodedSnapshot.parseVersion,
            origin: 'memory_recovery',
            timeSource: 'captured',
            decoded: snapshot!,
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
    final applications = capture.applications(snapshot?.snapshot);
    final cashLog = applications
        .map((application) => application.payload)
        .whereType<TUnionCashLog>()
        .firstOrNull;
    final frozenSuica = capture.summary['suicaTrips'];
    final decoded = summary['decoded'];
    final systems = (decoded is Map ? decoded['systemResults'] : null) ??
        decodedSnapshot?.extensions['felicaSystems'];
    final amusementIc = decoded is Map
        ? AmusementIcData.fromJson(decoded['amusementIc'])
        : null;
    final isAmusementIc =
        summary['productType'] == 'amusementIc' ||
        (decoded is Map &&
            (decoded['productType'] == 'amusementIc' ||
                decoded['amusementIc'] is Map));
    final suicaTrips = <SuicaTripPresentation>[
      if (frozenSuica is List)
        for (final item in frozenSuica) ?SuicaTripPresentation.fromJson(item),
    ];
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
                          summary['parserId'] == CardParserIds.lingnanTong ||
                          summary['cardType'] == CardTypes.lingnanTong
                      ? '岭南通'
                      : summary['cardName']?.toString() ?? '卡片信息',
                ),
                if (summary['cardNumber'] case final String number)
                  SelectableText(number),
                if (isAmusementIc) ...[
                  if (summary['idm'] case final String idm)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 84, child: Text('IDm')),
                        Expanded(child: SelectableText(idm)),
                      ],
                    ),
                  AmusementIcSummary(data: amusementIc),
                ],
                Text('读取时间：${capture.readAt.toLocal()}'),
                if (summary['balanceText'] case final String text)
                  Text('读取时余额：$text')
                else if (summary['balanceFen'] case final int balance)
                  Text(
                    '读取时余额：${snapshot?.snapshot?.context.formatAmount(balance) ?? '${(balance / 100).toStringAsFixed(2)} ${summary['currencyCode'] ?? '币种未知'}'}',
                  ),
                Text(
                  capture.interrupted
                      ? '请重新贴卡读取。下方保留中断前已获取的证据。'
                      : '已恢复捕获时的数据，继续读取请重新贴卡。',
                ),
                if (capture.canSave && showSaveActions) ...[
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
        if (applications.isNotEmpty) ...[
          const SizedBox(height: 12),
          ApplicationEvidencePanel(
            applications: applications,
            title: '逐应用探测 · 捕获时快照',
          ),
        ],
        if (cashLog != null) TUnionCashLogView(log: cashLog),
        if (systems is Map)
          for (final entry in systems.entries)
            if (entry.value case final Map fields)
              ListTile(
                title: Text('FeliCa ${entry.key} · ${fields['displayName'] ?? '未知系统'}'),
                subtitle: Text([
                  if (fields['idm'] case final String idm) 'IDm $idm',
                  if (fields['stateText'] case final String state) state,
                ].join(' · ')),
                onTap: () => _evidence(context, fields),
              ),
        if (suicaTrips.isNotEmpty)
          SuicaTripList(
            trips: suicaTrips,
            initialFilters: app.recoveryFilters['live:suica'],
            onFiltersChanged: (values) =>
                app.recoveryFilters['live:suica'] = values,
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
        if (summary['decoded'] case final Map decoded)
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
