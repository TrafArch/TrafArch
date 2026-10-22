import 'package:flutter/services.dart';

import '../../../app/app_info.dart';
import '../../../platform/storage/app_logger.dart';
import '../../../platform/storage/log_exporter.dart';
import '../../../shared/application/owned_notifier.dart';

class DiagnosticsController extends OwnedNotifier {
  DiagnosticsController(this._logger, this._logExporter);
  final AppLogger _logger;
  final LogExporter _logExporter;
  bool _exportingLog = false;
  String? _logExportMessage;
  bool _logExportFailed = false;
  bool get exportingLog => _exportingLog;
  String? get logExportMessage => _logExportMessage;
  bool get logExportFailed => _logExportFailed;
  Future<void> exportLog() async {
    if (_exportingLog) return;
    _exportingLog = true;
    _logExportMessage = null;
    _logExportFailed = false;
    _logger.log('== 导出运行日志 ==');
    notifyListeners();

    try {
      final now = DateTime.now();
      // 等待排队中的日志写入完成，保证导出内容完整
      await _logger.flush();
      final body = await _logger.readAll();
      final content = StringBuffer()
        ..writeln('=== ${AppInfo.appName} 运行日志 ===')
        ..writeln('应用版本：${AppInfo.version}（Build ${AppInfo.buildNumber}）')
        ..writeln('导出时间：${AppLogger.formatTimestamp(now)}')
        ..writeln('------------------------------------------------')
        ..writeln(body.trim().isEmpty ? '（暂无日志记录）' : body.trim());
      final path = await _logExporter.saveToDownloads(
        'transit_card_log_${_fileStamp(now)}.txt',
        content.toString(),
      );
      _logExportFailed = false;
      _logExportMessage = '已导出到下载目录：$path';
      _logger.log('== 日志导出完成：$path ==');
    } on PlatformException catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：${e.message ?? e.code}';
      _logger.log('== 日志导出失败：${e.message ?? e.code} ==');
    } catch (e) {
      _logExportFailed = true;
      _logExportMessage = '导出失败：$e';
      _logger.log('== 日志导出失败：$e ==');
    } finally {
      _exportingLog = false;
      notifyListeners();
    }
  }

  /// 导出文件名时间戳：yyyyMMdd_HHmmss。
  static String _fileStamp(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${pad2(t.month)}${pad2(t.day)}_'
        '${pad2(t.hour)}${pad2(t.minute)}${pad2(t.second)}';
  }
}
