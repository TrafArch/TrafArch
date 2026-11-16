import '../../../app/app_info.dart';
import '../../../platform/storage/app_logger.dart';
import '../../../shared/presentation/application_evidence_panel.dart';
import '../../../protocols/transit/multiapp/application_evidence.dart';
import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../domain/card_types.dart';
import '../data/card_repository.dart';
import 'archive_history.dart';
import 'cu_archive_projection.dart';
import 'suica_archive_projection.dart';
import '../../../protocols/transit/city_union/city_union_models.dart';
import '../presentation/archive_record_presenter.dart';
import '../../trips/local_card_trip_presenter.dart' as local_presenter;

/// Full-batch export uses precisely the same history query as archive detail.
class ArchiveExportService {
  final ArchiveHistory history;
  const ArchiveExportService(this.history);

  Future<String> buildText({DateTime? exportedAt}) async =>
      buildArchiveHistoryExport(
        await history.loadAll(),
        exportedAt: exportedAt,
      );
}

/// Transitional formatter for existing callers/fixtures. Parent must supply
/// histories or switch to ArchiveExportService; the scalar-only path explicitly
/// labels its incomplete scope and is never presented as a complete export.
String buildCardRecordsExport(
  List<SavedCard> cards, {
  DateTime? exportedAt,
  List<ArchiveHistoryResult>? histories,
  String? Function(String?, String?)? stationResolver,
  String? Function(String?, String?)? lineResolver,
}) {
  final source =
      histories ??
      [
        for (final card in cards)
          ArchiveHistory.project(ArchiveRows(card: card, batches: const [])),
      ];
  final text = buildArchiveHistoryExport(source, exportedAt: exportedAt);
  return histories != null ? text : '兼容导出：调用方仅提供卡片摘要，未查询完整历史批次。\n$text';
}

/// Human-readable report, including all batch payloads and diagnostics. This
/// text is not a versioned restore/import format.
String buildArchiveHistoryExport(
  List<ArchiveHistoryResult> histories, {
  DateTime? exportedAt,
}) {
  final buffer = StringBuffer()
    ..writeln('=== ${AppInfo.appName} 卡片记录导出 ===')
    ..writeln('应用版本：${AppInfo.version}（Build ${AppInfo.buildNumber}）')
    ..writeln('导出时间：${AppLogger.formatTimestamp(exportedAt ?? DateTime.now())}')
    ..writeln('卡片数量：${histories.where((h) => !h.missing).length}')
    ..writeln('历史显示格式：${ArchiveHistoryResult.projectionVersion}')
    ..writeln('================================================');
  if (histories.isEmpty) buffer.writeln('（暂无已保存的卡片）');
  var index = 0;
  for (final history in histories) {
    final card = history.card;
    if (card == null) continue;
    final cityUnion = projectCuArchive(history);
    final suica = projectSuicaArchive(history);
    final cuSourceLabels = cityUnion.sourceLabels;
    index++;
    buffer
      ..writeln()
      ..writeln('【$index】${card.displayName}')
      ..writeln('卡型：${cardTypeLabel(card.cardType)}')
      ..writeln('识别信息：${card.subtitle}')
      ..writeln('卡号：${card.cardNumberText}')
      ..writeln('余额：${history.balanceText ?? '未读取到'}')
      ..writeln('摘要保留最近已观察值，本次缺失另行标注。')
      ..writeln('交易记录：${card.transactionCountText ?? '未记录'}')
      ..writeln('最近读取：${card.lastReadFullText ?? '未记录'}')
      ..writeln('已保存批次：${history.batches.length}（相同内容读取可能去重）');
    if (history.balanceObservationText case final observed?) {
      buffer.writeln(
        '${history.balanceObservationLabel}：$observed（非已验证港币账户余额）',
      );
    }
    final applicationRows =
        history.latestCapture?.snapshot?.extensions['applicationEvidence'];
    final visibleRows = applicationRows is List
        ? applicationRows
              .where((row) => !ApplicationEvidence.isRetiredBankEntry(row))
              .toList(growable: false)
        : const [];
    if (visibleRows.isNotEmpty) {
      buffer.writeln('逐应用探测（捕获时快照）：');
      for (final row in visibleRows) {
        final application = ApplicationEvidence.tryParse(row);
        if (application == null) {
          buffer.writeln('  · （损坏的应用探测条目已保留在原始快照）');
          continue;
        }
        final details = <String>[
          if (application.cardNumber case final cardNumber?) '卡号 $cardNumber',
          if (application.balanceFen case final balance?) '余额 $balance 分',
          if (application.recordCount > 0) '${application.recordCount} 条记录',
        ];
        buffer.writeln(
          '  · ${application.displayName}：'
          '${applicationProbeStateLabel(application.state)}'
          '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}',
        );
      }
    }
    for (final entry in history.latestObservedFields.entries) {
      if (!entry.value) buffer.writeln('本次未观察到：${entry.key}；摘要保留既往已观察值');
    }
    final localTrips = history.localCardRecords
        .where(
          (record) =>
              record.cardType == 'localCardTrips' ||
              record.cardType == 'lingnanTong' ||
              record.cardType == 'shenzhenTong',
        )
        .toList();
    if (history.records.isEmpty &&
        cityUnion.transactions.isEmpty &&
        suica.records.isEmpty &&
        localTrips.isEmpty) {
      buffer.writeln(
        suica.isHistoryUnobserved
            ? '尚未读取到 Suica 历史记录'
            : history.hasDiagnostics || suica.issues.isNotEmpty
            ? '行程记录：（无可解码记录，详见批次诊断）'
            : '行程记录：（无）',
      );
    } else if (history.records.isNotEmpty) {
      buffer.writeln('行程记录（${history.records.length} 条）：');
    }
    for (final record in history.records) {
      buffer
        ..writeln('  · ${archiveRecordTitle(record)}')
        ..writeln('    ${archiveRecordText(record)}')
        ..writeln(
          '    来源：${record.sources.map((s) => '${s.batchId}/${s.path} (parser ${s.capturedParseVersion})').join(', ')}',
        );
    }
    if (cityUnion.transactions.isNotEmpty) {
      buffer.writeln('城市一卡通记录（${cityUnion.transactions.length} 条）：');
    }
    for (final transaction in cityUnion.transactions) {
      buffer
        ..writeln('  · ${transaction.kindLabel} · ${transaction.locationLabel}')
        ..writeln('    ${transaction.timeLabel} | ${transaction.sourceLabel}')
        ..writeln('    终端原始编码：${transaction.record.terminalHex ?? '未知'}')
        ..writeln('    交易金额：${transaction.amountText() ?? '未知'}')
        ..writeln('    金额原始字段：${transaction.record.amountHex}')
        ..writeln('    金额四字节原始值：${transaction.record.amountRaw}')
        ..writeln('    来源：${cuSourceLabels[transaction]}')
        ..writeln('    原始记录：${transaction.record.rawHex}');
    }
    if (localTrips.isNotEmpty) {
      buffer.writeln('地方交通卡行程（${localTrips.length} 条）：');
      for (final record in localTrips) {
        final profile = local_presenter.localTripProfileOf(
          record.fields,
          cardType: record.cardType,
        );
        final trip = local_presenter.restoreLocalTripRecord(
          record.fields,
          profile: profile,
        );
        if (trip == null) {
          buffer.writeln('  · 记录不完整，原始快照已保留');
          continue;
        }
        final presentation = local_presenter.describeLocalTrip(
          trip,
          currencySymbol: '¥',
          profile: profile,
        );
        buffer
          ..writeln('  · ${presentation.info.title}')
          ..writeln(
            '    ${presentation.info.timeText ?? '时间未知'}'
            ' | ${presentation.info.amountText ?? '金额未知'}',
          )
          ..writeln(
            '    来源：${record.batchId}（本地卡 ${presentation.info.sourceLabel}）',
          );
        if (presentation.info.rawHex case final raw?) {
          buffer.writeln('    原始记录：$raw');
        }
      }
    }
    for (final issue in cityUnion.issues) {
      buffer.writeln('CU 诊断：$issue');
    }
    if (suica.records.isNotEmpty) {
      buffer.writeln('Suica 历史记录（${suica.records.length} 条）：');
      for (final record in suica.records) {
        final presentation = record.presentation;
        final start = presentation.journey.start?.station;
        final end = presentation.journey.end?.station;
        buffer
          ..writeln('  · ${presentation.entry.info.title}')
          ..writeln('    ${presentation.entry.info.timeText ?? '时间未知'}');
        if (start != null && end != null) {
          buffer.writeln('    $start → $end');
        }
        if (presentation.journey.balanceAfterText case final balance?) {
          buffer.writeln('    交易后余额：$balance');
        }
        if (presentation.entry.info.amountText case final amount?) {
          buffer.writeln('    $amount（余额差不保证等同单笔票价）');
        }
        buffer
          ..writeln(
            '    来源：${record.sources.map((source) => '${source.batchId}/${source.path}').join(', ')}',
          )
          ..writeln('    原始记录：${record.fields['rawHex']}');
      }
    }
    for (final issue in suica.issues) {
      buffer.writeln('Suica 诊断：$issue');
    }
    for (final batch in history.batches) {
      buffer
        ..writeln()
        ..writeln('批次 ${batch.id} | ${batch.origin}')
        ..writeln('读取毫秒：${batch.readAt} | 时间来源：${batch.timeSource}')
        ..writeln(
          '捕获格式：${batch.decoded.formatVersion ?? '未知'} | 批次解析版本：${batch.storedParseVersion} | ${batch.decoded.status.name}',
        );
      for (final issue in batch.issues) {
        buffer.writeln('诊断：$issue');
      }
      buffer
        ..writeln('原始 payload 开始（${batch.decoded.rawJson.length} UTF-16 单元）：')
        ..writeln(batch.decoded.rawJson)
        ..writeln('原始 payload 结束');
    }
  }
  return buffer.toString();
}
