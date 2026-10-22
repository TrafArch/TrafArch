import '../../../app/app_info.dart';
import '../../../platform/storage/app_logger.dart';
import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../domain/card_types.dart';
import '../data/card_repository.dart';
import 'archive_history.dart';
import '../presentation/archive_record_presenter.dart';

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
    for (final entry in history.latestObservedFields.entries) {
      if (!entry.value) buffer.writeln('本次未观察到：${entry.key}；摘要保留既往已观察值');
    }
    if (history.records.isEmpty) {
      buffer.writeln(
        history.hasDiagnostics ? '行程记录：（无可解码记录，详见批次诊断）' : '行程记录：（无）',
      );
    } else {
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
