import 'dart:io';

import 'package:flutter/services.dart';

abstract class MemoryPlatform {
  static MemoryPlatform create() =>
      Platform.isAndroid ? AndroidMemoryPlatform() : NoopMemoryPlatform();
  void listen(Future<bool> Function(bool kill) handler);
  void dispose();
  Future<String?> readRecovery();
  Future<void> writeRecovery(String content);
  Future<void> clearRecovery();
}

class NoopMemoryPlatform implements MemoryPlatform {
  @override
  void listen(Future<bool> Function(bool kill) handler) {}
  @override
  void dispose() {}
  @override
  Future<String?> readRecovery() async => null;
  @override
  Future<void> writeRecovery(String content) async {
    throw UnsupportedError('Memory recovery requires Android');
  }

  @override
  Future<void> clearRecovery() async {}
}

/// Recovery bytes are stored by Android in noBackupFilesDir, never SQLite.
class AndroidMemoryPlatform implements MemoryPlatform {
  static const channel = MethodChannel('transit_card_analyzer/memory');

  @override
  void listen(Future<bool> Function(bool kill) handler) {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onMemoryPressure') throw MissingPluginException();
      final args = call.arguments;
      if (args is! Map || args['kill'] is! bool) return false;
      final expires = args['expiresAtMillis'];
      if (expires is! int || DateTime.now().millisecondsSinceEpoch >= expires) {
        return false;
      }
      return handler(args['kill'] as bool);
    });
  }

  @override
  void dispose() => channel.setMethodCallHandler(null);
  @override
  Future<String?> readRecovery() =>
      channel.invokeMethod<String>('readRecovery');
  @override
  Future<void> writeRecovery(String content) =>
      channel.invokeMethod<void>('writeRecovery', {'content': content});
  @override
  Future<void> clearRecovery() => channel.invokeMethod<void>('clearRecovery');
}
