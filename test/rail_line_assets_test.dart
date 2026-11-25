import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_rail_line_catalog.dart';

void main() {
  test('rail SVG manifest covers the supplied city artwork', () {
    final manifest = jsonDecode(
      File('assets/Line_Icon/icons.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest.keys.toSet(), {'3910', '3930', '5810'});

    final registered = <String>{};
    for (final city in manifest.entries) {
      final icons = (city.value as Map)['icons'] as Map<String, dynamic>;
      for (final entry in icons.entries) {
        final config = entry.value as List;
        final file = config[0] as String;
        expect(config[1] as num, greaterThan(0), reason: entry.key);
        expect(config[2] as num, greaterThan(0), reason: entry.key);
        final path = 'assets/Line_Icon/${city.key}/$file';
        expect(File(path).existsSync(), isTrue, reason: path);
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('<style')), reason: path);
        expect(source, isNot(contains('class=')), reason: path);
        registered.add('${city.key}/$file');
      }
    }

    final supplied = Directory('assets/Line_Icon')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .where((path) => path.endsWith('.svg'))
        .map((path) => path.replaceFirst('assets/Line_Icon/', ''))
        .toSet();
    expect(registered, supplied);
    expect(registered, hasLength(30));
    expect(
      registered,
      containsAll([
        '3910/3910_Line_4.svg',
        '3910/3910_Line_F1.svg',
        '3930/3930_Line6.svg',
        '5810/5810_Line_60.svg',
        '5810/5810_Line_68.svg',
      ]),
    );
    expect(
      File('assets/Line_Icon/3910/3910_Line_4.svg').readAsStringSync(),
      contains('fill="#ff7f41"'),
    );
    expect(
      File('assets/Line_Icon/3910/3910_Line_F1.svg').readAsStringSync(),
      contains('fill="#00ADB9"'),
    );
  });

  test('offline palette keeps verified mappings and its upstream license', () {
    final local = jsonDecode(
      File('assets/Line_Icon/icons.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final palette = jsonDecode(
      File('third_party/railmapgen_palette/tu_colors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(palette['revision'], '993a7d4dfa9277740f7a8952ed2b502309c45390');
    final cities = palette['cities'] as Map<String, dynamic>;
    expect((cities['3910'] as Map)['colors']['滨海快线'], '#00ADBB');
    expect((cities['2900'] as Map)['colors']['4号线'], '#461D84');
    expect((cities['5810'] as Map)['colors']['APM线'], '#00B5E2');
    expect((palette['cuToTu'] as Map)['2000'], '2900');

    final catalog = GalleryRailLineCatalog.fromJson(local, palette);
    expect(catalog.tuCode('3910', '福州市', 'tu'), '3910');
    expect(catalog.tuCode('2000', '上海', 'cu'), '2900');
    expect(catalog.lineKey('3910', 'F1'), '滨海快线');
    expect(
      catalog.icon('3910', '滨海快线')?.path,
      'assets/Line_Icon/3910/3910_Line_F1.svg',
    );
    expect(catalog.paletteColor('2900', '4号线')?.toARGB32(), 0xff461d84);

    final license = File('third_party/railmapgen_palette/GPL-3.0.txt')
        .readAsStringSync();
    expect(license, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(license, contains('Version 3, 29 June 2007'));
    expect(
      File('third_party/railmapgen_palette/README.md').readAsStringSync(),
      contains('https://github.com/railmapgen/rmg-palette'),
    );
  });
}
