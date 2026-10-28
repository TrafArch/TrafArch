import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 设置键名。
abstract final class SettingsKeys {
  /// 「启用运行日志」开关（'true' / 'false'；缺省视为关闭）。
  static const loggingEnabled = 'logging_enabled';

  /// 「读取后自动保存」开关（'true' / 'false'；缺省视为关闭）。
  static const autoSaveEnabled = 'auto_save_enabled';

  /// 「上海交通卡可透支余额」开关（'true' / 'false'；缺省视为关闭）。
  /// 开启显示包含固定 8 元可透支额度的余额，关闭时从余额中扣除该额度。
  static const includeShanghaiOverdraft = 'include_shanghai_overdraft';

  /// 「莫奈取色（动态取色）」开关（'true' / 'false'；缺省视为开启）。
  /// 开启后主题色跟随系统壁纸取色（Android 12+ Dynamic Color）；
  /// 关闭时使用应用内置固定主题色。
  static const monetEnabled = 'monet_enabled';
}

/// 应用设置持久化抽象：文本键值对（每行 key=value），不使用 JSON。
abstract class SettingsStore {
  /// 读取指定键；键或文件不存在时返回 null，读取失败时抛出异常。
  Future<String?> read(String key);

  /// 写入指定键（保留其余键）。
  Future<void> write(String key, String value);
}

/// 文件实现：应用私有文档目录下的 app_settings.txt。
class FileSettingsStore implements SettingsStore {
  static const fileName = 'app_settings.txt';
  Future<void> _writes = Future.value();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<String?> read(String key) async {
    await _writes;
    final file = await _file();
    if (!await file.exists()) return null;
    return parseSettingsText(await file.readAsString())[key];
  }

  @override
  Future<void> write(String key, String value) {
    final pending = _writes.then((_) => _write(key, value));
    // Keep later writes usable while returning this failure to the controller.
    _writes = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<void> _write(String key, String value) async {
    final file = await _file();
    final values = <String, String>{};
    if (await file.exists()) {
      values.addAll(parseSettingsText(await file.readAsString()));
    }
    values[key] = value;
    final buffer = StringBuffer();
    values.forEach((k, v) => buffer.writeln('$k=$v'));
    final staging = await file.parent.createTemp('settings-');
    final temporary = File('${staging.path}${Platform.pathSeparator}$fileName');
    try {
      await temporary.writeAsString(buffer.toString(), flush: true);
      // Same-filesystem rename publishes the complete file. On failure the
      // existing target is retained and the error remains visible to the user.
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
      await staging.delete();
    }
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
