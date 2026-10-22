import 'package:flutter/foundation.dart';

/// Async owners must discard late results and release resources after disposal.
abstract class OwnedNotifier extends ChangeNotifier {
  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
