import 'package:url_launcher/url_launcher.dart';

import '../../../platform/browser/feedback_browser.dart';
import '../../../platform/storage/settings_store.dart';
import '../../../platform/storage/app_logger.dart';
import '../../../shared/application/owned_notifier.dart';
import '../../../shared/app_support.dart';

class SettingsController extends OwnedNotifier {
  SettingsController(
    this.store,
    this.logger, {
    this._browser = const MethodChannelFeedbackBrowser(),
  });
  final SettingsStore store;
  final AppLogger logger;
  final FeedbackBrowser _browser;
  final Map<String, bool> _values = {};
  final Map<String, int> _revisions = {};
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  String? persistenceError;
  bool openingFeedbackSurvey = false;
  String? feedbackBrowserError;

  /// 无可用浏览器时链接已自动复制到剪贴板，界面据此弹一次气泡提示。
  String? feedbackBrowserNotice;

  void clearFeedbackBrowserNotice() => feedbackBrowserNotice = null;

  bool get loggingEnabled => _values[SettingsKeys.loggingEnabled] ?? false;
  bool get autoSaveEnabled => _values[SettingsKeys.autoSaveEnabled] ?? false;
  bool get includeShanghaiOverdraft =>
      _values[SettingsKeys.includeShanghaiOverdraft] ?? false;
  bool get monetEnabled => _values[SettingsKeys.monetEnabled] ?? true;

  Future<bool> openFeedbackEmail(String address) async {
    try {
      return await launchUrl(
        Uri(scheme: 'mailto', path: address),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> openFeedbackQqGroup(String groupNumber, Uri joinUrl) async {
    final qqUrl = Uri(
      scheme: 'mqqapi',
      host: 'card',
      path: '/show_pslcard',
      queryParameters: {
        'src_type': 'internal',
        'version': '1',
        'uin': groupNumber,
        'card_type': 'group',
        'source': 'qrcode',
      },
    );
    // 直接启动 QQ；未安装或唤起失败时交给外部浏览器打开原邀请页。
    // 不先用 canLaunchUrl 查询，避免 Android 包可见性限制导致误判。
    for (final url in [qqUrl, joinUrl]) {
      if (disposed) return false;
      try {
        if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // 启动失败继续尝试网页，均不可用时由反馈页提示复制群号。
      }
    }
    return false;
  }

  Future<void> openPrivacyPolicy() =>
      _browser.open(Uri.parse(AppSupport.privacy));

  Future<void> openFeedbackSurvey(Uri url) async {
    if (disposed || openingFeedbackSurvey) return;
    openingFeedbackSurvey = true;
    feedbackBrowserError = null;
    notifyListeners();
    try {
      await _browser.open(url);
    } on FeedbackBrowserException catch (error) {
      if (disposed) return;
      if (error.copiedToClipboard) {
        // 链接已在浏览器层复制入剪贴板：不阻塞页面，仅提示气泡。
        feedbackBrowserNotice = error.message;
      } else {
        feedbackBrowserError = error.message;
      }
    } catch (_) {
      if (!disposed) feedbackBrowserError = '问卷暂时无法打开，请重试或复制问卷链接。';
    } finally {
      if (!disposed) {
        openingFeedbackSurvey = false;
        notifyListeners();
      }
    }
  }

  Future<void> initialize() => _initialization ??= () async {
    for (final key in [
      SettingsKeys.loggingEnabled,
      SettingsKeys.autoSaveEnabled,
      SettingsKeys.includeShanghaiOverdraft,
      SettingsKeys.monetEnabled,
    ]) {
      final revision = _revisions[key] ?? 0;
      try {
        final value = await store.read(key);
        if (disposed) return;
        // 未保存过的键保留 getter 的默认值，不能被 null 覆盖成 false。
        if (value != null && (_revisions[key] ?? 0) == revision) {
          _values[key] = value == 'true';
        }
      } catch (e) {
        if (!disposed) persistenceError = '$e';
      }
    }
    if (disposed) return;
    logger.enabled = loggingEnabled;
    notifyListeners();
  }();

  Future<void> setLoggingEnabled(bool value) async {
    if (disposed || value == loggingEnabled) return;
    // Record the closing marker while logging is still enabled. Queue the
    // opening marker after the setting takes effect, then flush both changes.
    if (!value) logger.log('== 日志记录已关闭 ==');
    final write = _set(SettingsKeys.loggingEnabled, value);
    if (value) logger.log('== 日志记录已开启 ==');
    await write;
    await logger.flush();
  }

  Future<void> setAutoSaveEnabled(bool value) =>
      _set(SettingsKeys.autoSaveEnabled, value);
  Future<void> setIncludeShanghaiOverdraft(bool value) =>
      _set(SettingsKeys.includeShanghaiOverdraft, value);
  Future<void> setMonetEnabled(bool value) =>
      _set(SettingsKeys.monetEnabled, value);

  Future<void> _set(String key, bool value) {
    if (disposed) return Future.value();
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    _values[key] = value;
    logger.enabled = loggingEnabled;
    notifyListeners();
    return _writes = _writes.then((_) async {
      try {
        await store.write(key, '$value');
        if (!disposed) persistenceError = null;
      } catch (e) {
        if (!disposed) persistenceError = '$e';
      }
      notifyListeners();
    });
  }
}
