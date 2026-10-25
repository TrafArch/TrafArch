import '../../../platform/storage/settings_store.dart';
import '../../../platform/storage/app_logger.dart';
import '../../../shared/application/owned_notifier.dart';

class SettingsController extends OwnedNotifier {
  SettingsController(this.store, this.logger);
  final SettingsStore store;
  final AppLogger logger;
  final Map<String, bool> _values = {};
  final Map<String, int> _revisions = {};
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  String? persistenceError;

  bool get loggingEnabled => _values[SettingsKeys.loggingEnabled] ?? false;
  bool get autoSaveEnabled => _values[SettingsKeys.autoSaveEnabled] ?? false;
  bool get monetEnabled => _values[SettingsKeys.monetEnabled] ?? true;

  Future<void> initialize() => _initialization ??= () async {
    for (final key in [
      SettingsKeys.loggingEnabled,
      SettingsKeys.autoSaveEnabled,
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
