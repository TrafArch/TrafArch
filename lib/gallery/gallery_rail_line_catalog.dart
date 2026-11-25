import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GalleryRailLineCatalog {
  GalleryRailLineCatalog._(this._local, Map<String, dynamic> palette)
    : _cities = _jsonObject(palette['cities']),
      _cuToTu = _jsonObject(palette['cuToTu']) {
    for (final code in {..._cities.keys, ..._local.keys}) {
      final name =
          _jsonObject(_local[code])['name'] ??
          _jsonObject(_cities[code])['name'];
      if (name is! String) continue;
      final key = _cityKey(name);
      _names[key] = _names.containsKey(key) ? null : code;
    }
  }

  factory GalleryRailLineCatalog.empty() =>
      GalleryRailLineCatalog._(const {}, const {});

  factory GalleryRailLineCatalog.fromJson(
    Map<String, dynamic> local,
    Map<String, dynamic> palette,
  ) => GalleryRailLineCatalog._(local, palette);

  static final _numberedLine = RegExp(r'^([0-9]{1,3})\s*[号號]\s*[线線]$');
  static final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');
  final Map<String, dynamic> _local;
  final Map<String, dynamic> _cities;
  final Map<String, dynamic> _cuToTu;
  final _names = <String, String?>{};

  static Future<GalleryRailLineCatalog> load(AssetBundle bundle) async {
    final [local, palette] = await Future.wait([
      _read(bundle, 'assets/Line_Icon/icons.json'),
      _read(bundle, 'third_party/railmapgen_palette/tu_colors.json'),
    ]);
    return GalleryRailLineCatalog._(local, palette);
  }

  static Future<Map<String, dynamic>> _read(
    AssetBundle bundle,
    String path,
  ) async {
    try {
      return _jsonObject(jsonDecode(await bundle.loadString(path)));
    } on FlutterError {
      return const {};
    } on FormatException {
      return const {};
    }
  }

  String? tuCode(String? code, String? name, String? system) {
    final byName = name == null ? null : _names[_cityKey(name)];
    if (code == null) return byName;
    final byCode = system == 'cu' ? _cuToTu[code] : code;
    if (byCode is! String ||
        (!_cities.containsKey(byCode) && !_local.containsKey(byCode))) {
      return byName;
    }
    return byName != null && byName != byCode ? null : byCode;
  }

  String lineKey(String code, String label) {
    final text = label.trim().toUpperCase();
    final numbered = _numberedLine.firstMatch(text);
    if (numbered != null) return '${int.parse(numbered[1]!)}号线';
    final alias = _jsonObject(_jsonObject(_local[code])['aliases'])[text];
    return alias is String ? alias : text;
  }

  ({String path, double aspectRatio})? icon(String code, String line) {
    final config = _jsonObject(_jsonObject(_local[code])['icons'])[line];
    if (config case [final String file, final num width, final num height]
        when width > 0 && height > 0) {
      return (
        path: 'assets/Line_Icon/$code/$file',
        aspectRatio: width / height,
      );
    }
    return null;
  }

  Color? approvedColor(String code, String line) =>
      _color(_jsonObject(_local[code]), line);

  Color? paletteColor(String code, String line) =>
      _color(_jsonObject(_cities[code]), line);

  static Color? _color(Map<String, dynamic> city, String line) {
    final hex = _jsonObject(city['colors'])[line];
    return hex is String && _hexColor.hasMatch(hex)
        ? Color(0xff000000 | int.parse(hex.substring(1), radix: 16))
        : null;
  }

  static String _cityKey(String value) {
    final trimmed = value.trim();
    return trimmed.endsWith('市')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

Map<String, dynamic> _jsonObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
