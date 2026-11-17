import 'dart:io';

import 'package:flutter/services.dart';

/// What the current device can do with MagicOS translucent components.
class TranslucencyCapability {
  const TranslucencyCapability({
    required this.supported,
    required this.nativeGlass,
  });

  static const none = TranslucencyCapability(
    supported: false,
    nativeGlass: false,
  );

  /// The system exposes the documented translucent switch.
  final bool supported;

  /// The bar may host the native `HnVisualEffectLayout` platform view. False
  /// on every non-Android host (including widget tests) so the Flutter
  /// material stays the only path there.
  final bool nativeGlass;
}

/// Probes whether the current device exposes MagicOS translucent components.
///
/// The bundled Translucent Component Kit ships as a native AAR; its glass
/// container can only wrap Android views. The 2.x bars therefore ask the
/// platform a read-only question and then either host the native platform view
/// or keep the Flutter material defined by `design.md`.
abstract class TranslucencyPlatform {
  static TranslucencyPlatform create() => Platform.isAndroid
      ? const AndroidTranslucencyPlatform()
      : const NoopTranslucencyPlatform();

  Future<TranslucencyCapability> probe();
}

class NoopTranslucencyPlatform implements TranslucencyPlatform {
  const NoopTranslucencyPlatform();

  @override
  Future<TranslucencyCapability> probe() async => TranslucencyCapability.none;
}

class AndroidTranslucencyPlatform implements TranslucencyPlatform {
  const AndroidTranslucencyPlatform();

  static const channel = MethodChannel('transit_card_analyzer/translucency');

  @override
  Future<TranslucencyCapability> probe() async {
    try {
      final reply = await channel.invokeMapMethod<String, Object?>(
        'getSupport',
      );
      if (reply?['supported'] != true) return TranslucencyCapability.none;
      return const TranslucencyCapability(supported: true, nativeGlass: true);
    } on MissingPluginException {
      return TranslucencyCapability.none;
    } on PlatformException {
      return TranslucencyCapability.none;
    }
  }
}
