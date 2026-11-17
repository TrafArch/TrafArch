/// 应用元信息；打包前从 pubspec.yaml 同步本次版本，打包后 pubspec 预留下次构建号。
class AppInfo {
  AppInfo._();

  /// 应用英文名称。
  static const String appNameEn = 'TrafArch';

  /// 应用中文名称（暂留空，待正式名称确定后补充）。
  static const String appNameZh = '';

  /// 当前展示用应用名称：中文名留空时回退为英文名。
  static String get appName => appNameZh.isEmpty ? appNameEn : appNameZh;

  static const String version = '1.0.8-beta.2';
  static const String buildNumber = '4199';

  /// Flutter arm64 拆包追加到 Android versionCode 的 ABI 偏移。
  static const int _splitAbiVersionCodeOffset = 2000;

  /// 关于页展示的构建号：去掉 Android versionCode 中的 ABI 偏移。
  static String get displayBuildNumber {
    final versionCode = int.tryParse(buildNumber);
    if (versionCode == null || versionCode <= _splitAbiVersionCodeOffset) {
      return buildNumber;
    }
    return '${versionCode - _splitAbiVersionCodeOffset}';
  }

  /// Android 清单版本码：当前直接使用 4xxx 完整构建号。
  static String get androidVersionCode => buildNumber;
  static const String author = 'kajolno';
  static const String copyright = '© 2026 kajolno';
}
