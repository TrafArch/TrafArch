import 'package:flutter/services.dart';

import '../../../platform/storage/app_logger.dart';
import '../../../platform/storage/log_exporter.dart';
import '../../../shared/application/owned_notifier.dart';
import '../../../shared/diagnostics/diagnostic_event.dart';
import 'diagnostic_export.dart';

class DiagnosticsController extends OwnedNotifier {
  DiagnosticsController(this._logger, this._logExporter) {
    _logger.addListener(notifyListeners);
  }
  final AppLogger _logger;
  final LogExporter _logExporter;
  bool _exportingLog = false;
  String? _logExportMessage;
  bool _logExportFailed = false;
  bool get exportingLog => _exportingLog;
  String? get logExportMessage => _logExportMessage;
  bool get logExportFailed => _logExportFailed;
  String? get storageIssue => _logger.storageIssue;
  Future<List<DiagnosticSession>> sessions() async =>
      (await _logger.readSessions())
          .where((s) => s.isScan || s.legacy || s.incomplete && s.first == null)
          .toList();
  Future<void> deleteSessions(Set<String> ids) => _logger.deleteSessions(ids);

  Future<void> exportLog({Set<String>? sessionIds}) async {
    if (_exportingLog || disposed) return;
    final requestedIds = sessionIds == null ? null : Set<String>.of(sessionIds);
    _exportingLog = true;
    _logExportMessage = null;
    _logExportFailed = false;
    notifyListeners();

    try {
      final now = DateTime.now();
      // Snapshot inside the serial file queue; new events cannot move its end.
      var selected = await _logger.readSessions(ids: requestedIds);
      selected = selected
          .where((s) => s.isScan || s.legacy || s.incomplete && s.first == null)
          .toList();
      if (disposed) return;
      if (requestedIds == null && selected.isNotEmpty) {
        final scans = selected.where((s) => s.isScan);
        selected = [scans.isNotEmpty ? scans.first : selected.first];
      }
      if (requestedIds != null && selected.length != requestedIds.length) {
        throw StateError('所选日志已被清理，请重新选择');
      }
      final content = buildFullDiagnostics(selected, now);
      final path = await _logExporter.saveToDownloads(
        'transit_card_log_${_fileStamp(now)}.json',
        content,
      );
      _logExportFailed = false;
      _logExportMessage = '已导出到下载目录：$path';
    } on PlatformException catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：${e.message ?? e.code}';
    } catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：$e';
    } finally {
      _exportingLog = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logger.removeListener(notifyListeners);
    super.dispose();
  }

  /// 导出文件名时间戳：yyyyMMdd_HHmmss。
  static String _fileStamp(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${pad2(t.month)}${pad2(t.day)}_'
        '${pad2(t.hour)}${pad2(t.minute)}${pad2(t.second)}';
  }
}
