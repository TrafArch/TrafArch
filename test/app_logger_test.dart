// test/app_logger_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';

import 'support/test_database.dart';

void main() {
  group('AppLogger 运行日志', () {
    test('默认关闭不写入；开启后按时间戳前缀写入，关闭后停止写入', () async {
      final store = MemoryLogStore();
      final logger = AppLogger(store: store);

      logger.log('默认关闭时不写入');
      logger.enabled = true;
      logger.log('第一条');
      logger.enabled = false;
      logger.log('不应写入');
      await logger.flush();

      final line = (await logger.readAll()).trim();
      expect(
        RegExp(r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] 第一条$')
            .hasMatch(line),
        isTrue,
      );
      expect(await logger.readAll(), isNot(contains('不应写入')));
      expect(await logger.readAll(), isNot(contains('默认关闭时不写入')));
    });
  });

  group('AppDependencies 日志导出', () {
    test('exportLog 拼接头部并调用导出通道，文件名带时间戳', () async {
      final exporter = _RecordingExporter();
      final app = AppDependencies(
        database: testDatabase(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
        logExporter: exporter,
      );

      await app.exportLog();

      expect(app.logExportFailed, isFalse);
      expect(app.logExportMessage, contains('已导出到下载目录'));
      expect(
        exporter.fileName,
        matches(RegExp(r'^transit_card_log_\d{8}_\d{6}\.txt$')),
      );
      expect(exporter.content, contains('TrafArch 运行日志'));
      expect(app.exportingLog, isFalse);
    });

    test('导出被拒（权限）时记录失败信息', () async {
      final exporter = _RecordingExporter()..fail = true;
      final app = AppDependencies(
        database: testDatabase(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
        logExporter: exporter,
      );

      await app.exportLog();

      expect(app.logExportFailed, isTrue);
      expect(app.logExportMessage, contains('未授予存储权限'));
    });

    test('日志开关默认关闭；开启后持久化，关闭后停止写入', () async {
      final settings = MemorySettingsStore();
      final store = MemoryLogStore();
      final app = AppDependencies(
        database: testDatabase(),
        settingsStore: settings,
        logger: AppLogger(store: store),
        logExporter: _RecordingExporter(),
      );

      expect(app.loggingEnabled, isFalse);

      await app.setLoggingEnabled(true);
      expect(app.loggingEnabled, isTrue);
      expect(settings.values[SettingsKeys.loggingEnabled], 'true');
      expect(await store.readAll(), contains('== 日志记录已开启 =='));

      await app.setLoggingEnabled(false);

      expect(app.loggingEnabled, isFalse);
      expect(settings.values[SettingsKeys.loggingEnabled], 'false');
      expect(await store.readAll(), contains('== 日志记录已关闭 =='));
    });
  });
}

/// 记录调用参数的假导出通道。
class _RecordingExporter implements LogExporter {
  String? fileName;
  String? content;
  bool fail = false;

  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    if (fail) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: '未授予存储权限，无法导出到下载目录',
      );
    }
    this.fileName = fileName;
    this.content = content;
    return 'Download/$fileName';
  }
}
