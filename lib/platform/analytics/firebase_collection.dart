import 'package:flutter/services.dart';

abstract final class FirebaseCollection {
  static const _channel = MethodChannel('transit_card_analyzer/analytics');

  static Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') == true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setCollectionEnabled', enabled);
}
