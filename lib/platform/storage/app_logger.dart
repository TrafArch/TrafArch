import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 运行日志本地存储抽象：文本行追加与整体读取。
abstract class LogStore {
  /// 追加一行日志（含换行符）。
  Future<void> append(String line);

  /// 读取全部日志文本；无日志时返回空字符串。
  Future<String> readAll();
}

/// 文件实现：应用私有文档目录下的 app_log.txt。
/// 超过 [maxBytes] 时滚动，仅保留最近 [keepLines] 条，防止无限增长。
class FileLogStore implements LogStore {
  static const fileName = 'app_log.txt';
  static const int maxBytes = 512 * 1024;
  static const int keepLines = 500;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<void> append(String line) async {
    final file = await _file();
    await file.writeAsString(line, mode: FileMode.append, flush: true);
    if (await file.length() > maxBytes) {
      await _roll(file);
    }
  }

  /// 滚动降载：保留最近条目，避免日志无限增长。
  Future<void> _roll(File file) async {
    try {
      final lines = const LineSplitter().convert(await file.readAsString());
      final tail = lines.length > keepLines
          ? lines.sublist(lines.length - keepLines)
          : lines;
      await file.writeAsString(
        '--- 日志已超过上限，滚动保留最近 $keepLines 条 ---\n'
        '${tail.join('\n')}\n',
        flush: true,
      );
    } catch (_) {
      // 滚动失败时保留原文件，后续追加继续尝试
    }
  }

  @override
  Future<String> readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      // 目录/文件不可用（如平台插件缺失）时按无日志降级
      return '';
    }
  }
}

/// 内存实现：测试与无文件系统环境使用。
class MemoryLogStore implements LogStore {
  final List<String> lines = [];

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<String> readAll() async => lines.join();
}

/// 应用运行日志：带时间戳记录，文件写入串行异步执行，不阻塞调用方。
class AppLogger {
  AppLogger({LogStore? store}) : _store = store ?? FileLogStore();

  final LogStore _store;

  /// 日志记录开关（由 AppDependencies 按持久化设置控制；默认关闭）。
  bool enabled = false;

  /// 文件写入串行链：保证追加顺序，单条失败不打断后续写入。
  Future<void> _chain = Future.value();

  /// 记录一条日志（立即返回；文件写入后台串行执行）。
  void log(String entry) {
    if (!enabled) return;
    final line = '[${formatTimestamp(DateTime.now())}] $entry\n';
    _chain = _chain.then((_) => _store.append(line)).catchError((_) {});
  }

  /// 等待已排队的日志写入完成（导出前调用，确保内容完整）。
  Future<void> flush() => _chain;

  /// 读取全部日志文本（无日志时返回空字符串）。
  Future<String> readAll() => _store.readAll();

  /// 时间戳格式：yyyy-MM-dd HH:mm:ss.SSS。
  static String formatTimestamp(DateTime t) {
    String pad2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
        '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}'
        '.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
