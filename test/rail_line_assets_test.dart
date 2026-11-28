import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_rail_line_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Shanghai and Suzhou artwork matches the Fuzhou badge height', () async {
    final reference = await _paintedHeight('3910/3910_Line_4.svg');
    expect(reference, closeTo(24, .2));
    for (final city in ['2900', '3050']) {
      for (final line in ['01', '11']) {
        for (final suffix in ['', '_black']) {
          final asset = '$city/${city}_Line_$line$suffix.svg';
          expect(
            await _paintedHeight(asset),
            closeTo(reference, .4),
            reason: asset,
          );
        }
      }
    }
  });

  test('rail SVG manifest covers the supplied city artwork', () async {
    final manifest = jsonDecode(
      File('assets/Line_Icon/icons.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest.keys.toSet(), {
      '1000',
      '2900',
      '3050',
      '3910',
      '3930',
      '5810',
    });
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundled = assetManifest.listAssets().toSet();
    final catalog = await GalleryRailLineCatalog.load(rootBundle);

    final registered = <String>{};
    for (final city in manifest.entries) {
      final icons = (city.value as Map)['icons'] as Map<String, dynamic>;
      for (final entry in icons.entries) {
        final config = entry.value as List;
        final file = config[0] as String;
        expect(config[1] as num, greaterThan(0), reason: entry.key);
        expect(config[2] as num, greaterThan(0), reason: entry.key);
        final path = 'assets/Line_Icon/${city.key}/$file';
        final darkPath = catalog.icon(city.key, entry.key)?.darkPath;
        for (final asset in [path, ?darkPath]) {
          expect(bundled, contains(asset));
          expect(File(asset).existsSync(), isTrue, reason: asset);
          final source = File(asset).readAsStringSync();
          expect(source, isNot(contains('<style')), reason: asset);
          expect(source, isNot(contains('class=')), reason: asset);
          if (city.key == '2900') {
            expect(source, isNot(contains('<text')), reason: asset);
          }
          final viewBox = RegExp(r'viewBox="([^"]+)"').firstMatch(source);
          expect(viewBox, isNotNull, reason: asset);
          final dimensions = viewBox!
              .group(1)!
              .trim()
              .split(RegExp(r'\s+'))
              .map(double.parse)
              .toList(growable: false);
          expect(dimensions, hasLength(4), reason: asset);
          expect(dimensions[2], greaterThan(0), reason: asset);
          expect(dimensions[3], greaterThan(0), reason: asset);
          if (asset == path) {
            expect(
              config[1] as num,
              closeTo(dimensions[2], .001),
              reason: asset,
            );
            expect(
              config[2] as num,
              closeTo(dimensions[3], .001),
              reason: asset,
            );
          }
          registered.add(asset.replaceFirst('assets/Line_Icon/', ''));
        }
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
    expect(registered, hasLength(122));
    expect(
      registered,
      containsAll([
        '1000/1000_Line_01.svg',
        '1000/1000_Line_0A_5A.svg',
        '1000/Northeast_Loop_Line.svg',
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
    expect(catalog.tuCode('3050', '苏州市', 'tu'), '3050');
    for (final (code, lineNumbers) in [
      ('2900', List<int>.generate(18, (index) => index + 1)),
      ('3050', [1, 2, 3, 4, 5, 6, 7, 8, 11]),
    ]) {
      for (final number in lineNumbers) {
        final suffix = number.toString().padLeft(2, '0');
        final stem = 'assets/Line_Icon/$code/${code}_Line_$suffix';
        final icon = catalog.icon(code, '$number号线');
        expect(icon?.path, '$stem.svg');
        expect(icon?.darkPath, '${stem}_black.svg');
      }
    }
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
    final rmgCities = palette['rmgCities'] as Map<String, dynamic>;
    expect(rmgCities, hasLength(48));
    expect(
      rmgCities.values
          .map((city) => ((city as Map)['lines'] as List).length)
          .fold(0, (sum, count) => sum + count),
      542,
    );
    expect((cities['3910'] as Map)['colors']['滨海快线'], '#00ADBB');
    expect((cities['2900'] as Map)['colors']['4号线'], '#461D84');
    expect((cities['5810'] as Map)['colors']['APM线'], '#00B5E2');
    final shenzhen = cities['5840'] as Map<String, dynamic>;
    expect(
      shenzhen['sourceSha256'],
      'ef616414fc0c78ea9ae4c38e06f33b9cb819132ebf195381ff387bff25da18b5',
    );
    expect(shenzhen['colors'], {
      '1号线': '#00B140',
      '2号线': '#B94700',
      '3号线': '#00A9E0',
      '4号线': '#DA291C',
      '5号线': '#A05EB5',
      '6号线': '#00C7B1',
      '7号线': '#0033A0',
      '8号线': '#B94700',
      '9号线': '#7B6469',
      '10号线': '#F8779E',
      '11号线': '#672146',
      '坪山云巴1号线': '#1974D2',
    });
    expect((palette['cuToTu'] as Map)['2000'], '2900');
    expect((palette['cuToTu'] as Map)['5180'], '5840');

    final catalog = GalleryRailLineCatalog.fromJson(local, palette);
    expect(catalog.tuCode('3910', '福州市', 'tu'), '3910');
    expect(catalog.tuCode('2000', '上海', 'cu'), '2900');
    expect(catalog.tuCode('5180', '深圳', 'cu'), '5840');
    expect(catalog.lineKey('3910', 'F1'), '滨海快线');
    expect(catalog.lineKey('1000', '怀柔-密云线'), '怀密线');
    expect(
      catalog.icon('3910', '滨海快线')?.path,
      'assets/Line_Icon/3910/3910_Line_F1.svg',
    );
    expect(
      catalog.icon('1000', '18号线')?.path,
      'assets/Line_Icon/1000/1000_Line_12.svg',
    );
    for (final (name, suffix) in [
      ('浦江线', 'PJ'),
      ('磁浮线', '90'),
      ('机场联络线', '51'),
      ('市域机场线', '51'),
    ]) {
      final line = catalog.lineKey('2900', name);
      expect(
        catalog.icon('2900', line)?.path,
        'assets/Line_Icon/2900/2900_Line_$suffix.svg',
      );
    }
    expect(catalog.paletteColor('2900', '4号线')?.toARGB32(), 0xff461d84);
    expect(catalog.paletteColor('2900', '机场联络线')?.toARGB32(), 0xff236890);
    expect(catalog.paletteColor('5840', '4号线')?.toARGB32(), 0xffda291c);
    expect(catalog.paletteColor('5840', '8号线')?.toARGB32(), 0xffb94700);
    expect(catalog.paletteColor('5840', '8号线（原）')?.toARGB32(), 0xffe45dbf);
    expect(catalog.paletteColor('5840', '12号线')?.toARGB32(), 0xffa192b2);
    expect(catalog.paletteColor('5840', '6号线支线')?.toARGB32(), 0xff168773);

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

Future<double> _paintedHeight(String path) async {
  final info = await vg.loadPicture(
    SvgAssetLoader('assets/Line_Icon/$path'),
    null,
  );
  const samplesPerDp = 8.0;
  const sampleHeight = 192;
  final scale = sampleHeight / info.size.height;
  final recorder = ui.PictureRecorder();
  (ui.Canvas(recorder)..scale(scale)).drawPicture(info.picture);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      (info.size.width * scale).ceil(),
      sampleHeight,
    );
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    int? firstRow;
    var lastRow = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final alpha = pixels.getUint8((y * image.width + x) * 4 + 3);
        if (alpha >= 128) {
          firstRow ??= y;
          lastRow = y;
          break;
        }
      }
    }
    return firstRow == null ? 0 : (lastRow - firstRow + 1) / samplesPerDp;
  } finally {
    image?.dispose();
    picture.dispose();
    info.picture.dispose();
  }
}
