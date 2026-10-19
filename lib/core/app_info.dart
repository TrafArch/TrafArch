/// 应用元信息，version/buildNumber 与 pubspec.yaml 的 version 字段保持同步。
class AppInfo {
  AppInfo._();

  /// 应用英文名称。
  static const String appNameEn = 'TrafArch';

  /// 应用中文名称（暂留空，待正式名称确定后补充）。
  static const String appNameZh = '';

  /// 当前展示用应用名称：中文名留空时回退为英文名。
  static String get appName => appNameZh.isEmpty ? appNameEn : appNameZh;

  static const String version = '1.0.1-beta.7';
  static const String buildNumber = '2051';
  static const String author = 'kajolno';
  static const String copyright = '© 2026 kajolno';
}