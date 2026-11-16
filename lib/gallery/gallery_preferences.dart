import 'package:flutter/foundation.dart';

/// The host supplies persistence. Gallery itself never opens files or databases.
class GalleryPreferences extends ChangeNotifier {
  GalleryPreferences({this.readEnabled, this.writeEnabled});

  final Future<bool> Function()? readEnabled;
  final Future<void> Function(bool)? writeEnabled;
  bool enabled = true;
  bool loading = false;
  String? error;
  bool _readFailed = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void>? _writes;

  Future<void> load() async {
    if (_disposed || loading || readEnabled == null) return;
    loading = true;
    final revision = _revision;
    notifyListeners();
    try {
      final value = await readEnabled!();
      if (!_disposed && revision == _revision) {
        enabled = value;
        error = null;
        _readFailed = false;
      }
    } catch (_) {
      if (!_disposed && revision == _revision) {
        error = '无法读取返回手势偏好，当前使用默认设置。';
        _readFailed = true;
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setEnabled(bool value) {
    if (_disposed) return Future.value();
    enabled = value;
    final revision = ++_revision;
    _readFailed = false;
    error = null;
    notifyListeners();
    return _writes = (_writes ?? Future<void>.value()).then((_) async {
      try {
        await writeEnabled?.call(value);
        if (!_disposed && revision == _revision) error = null;
      } catch (_) {
        if (!_disposed && revision == _revision) {
          error = '返回手势偏好未保存，当前选择仅在本次会话生效。';
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> retry() => _readFailed ? load() : setEnabled(enabled);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
