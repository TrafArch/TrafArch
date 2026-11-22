import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/card_provider_registry.dart';

class CardProviderRegistryAsset {
  static const path = 'assets/data/card_provider_registry.json';

  static Future<CardProviderRegistry> load(AssetBundle bundle) async {
    try {
      return CardProviderRegistry.fromJson(
        jsonDecode(await bundle.loadString(path)),
      );
    } catch (_) {
      if (identical(bundle, rootBundle)) rethrow;
      return CardProviderRegistry.fromJson(
        jsonDecode(await rootBundle.loadString(path)),
      );
    }
  }
}
