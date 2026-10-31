/// 应用元信息；打包前从 pubspec.yaml 同步本次版本，打包后 pubspec 预留下次构建号。
class AppInfo {
  AppInfo._();

  /// 应用英文名称。
  static const String appNameEn = 'TrafArch';

  /// 应用中文名称（暂留空，待正式名称确定后补充）。
  static const String appNameZh = '';

  /// 当前展示用应用名称：中文名留空时回退为英文名。
  static String get appName => appNameZh.isEmpty ? appNameEn : appNameZh;

  static const String version = '1.0.2-beta.2';
  static const String buildNumber = '2114';
  static const String author = 'kajolno';
  static const String copyright = '© 2026 kajolno';
}
