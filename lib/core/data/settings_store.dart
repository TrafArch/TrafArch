import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 设置键名。
abstract final class SettingsKeys {
  /// 「开启在线拉取数据」开关（'true' / 'false'）。
  static const onlineFetchEnabled = 'online_fetch_enabled';

  /// 「启用运行日志」开关（'true' / 'false'；缺省视为关闭）。
  static const loggingEnabled = 'logging_enabled';

  /// 「使用系统扫码（Google Play 服务）」开关（'true' / 'false'；
  /// 缺省视为开启：原有应用内相机扫码组件被整体屏蔽；
  /// 仅显式关闭时恢复应用内相机扫码）。
  static const gmsScanEnabled = 'gms_scan_enabled';

  /// 「读取后自动保存」开关（'true' / 'false'；缺省视为关闭）。
  static const autoSaveEnabled = 'auto_save_enabled';
}

/// 应用设置持久化抽象：文本键值对（每行 key=value），不使用 JSON。
abstract class SettingsStore {
  /// 读取指定键，不存在或不可用时返回 null。
  Future<String?> read(String key);

  /// 写入指定键（保留其余键）。
  Future<void> write(String key, String value);
}

/// 文件实现：应用私有文档目录下的 app_settings.txt。
class FileSettingsStore implements SettingsStore {
  static const fileName = 'app_settings.txt';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return parseSettingsText(await file.readAsString())[key];
    } catch (_) {
      // 目录/文件不可用（如平台插件缺失）时按无设置降级
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file();
    final values = <String, String>{};
    try {
      if (await file.exists()) {
        values.addAll(parseSettingsText(await file.readAsString()));
      }
    } catch (_) {
      // 旧内容读取失败时按空文件重建
    }
    values[key] = value;
    final buffer = StringBuffer();
    values.forEach((k, v) => buffer.writeln('$k=$v'));
    await file.writeAsString(buffer.toString(), flush: true);
  }
}

/// 内存实现：测试与无文件系统环境使用。
class MemorySettingsStore implements SettingsStore {
  final Map<String, String> values;

  MemorySettingsStore([Map<String, String>? values]) : values = {...?values};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// 解析设置文本：每行 key=value，忽略空行与 # 开头的注释。
Map<String, String> parseSettingsText(String text) {
  final result = <String, String>{};
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final index = line.indexOf('=');
    if (index <= 0) continue;
    result[line.substring(0, index).trim()] = line.substring(index + 1).trim();
  }
  return result;
}