import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const root = 'android/app/src/main/res';
  const densities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  for (final entry in densities.entries) {
    test(
      '${entry.key} launcher layers preserve themed cutouts and safe zone',
      () async {
        final layers = <String, ui.Image>{};
        try {
          for (final name in [
            'ic_launcher',
            'ic_launcher_background',
            'ic_launcher_foreground',
            'ic_launcher_monochrome',
          ]) {
            final codec = await ui.instantiateImageCodec(
              File('$root/mipmap-${entry.key}/$name.png').readAsBytesSync(),
            );
            layers[name] = (await codec.getNextFrame()).image;
            codec.dispose();
            final size = name == 'ic_launcher'
                ? entry.value
                : entry.value * 108 ~/ 48;
            expect(layers[name]!.width, size);
            expect(layers[name]!.height, size);
          }
          final foreground = layers['ic_launcher_foreground']!;
          final mono = layers['ic_launcher_monochrome']!;
          final fgBytes = (await foreground.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          final monoBytes = (await mono.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          final bgBytes = (await layers['ic_launcher_background']!.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          var opaque = 0;
          final size = mono.width;
          for (var y = 0; y < size; y++) {
            for (var x = 0; x < size; x++) {
              final offset = (y * size + x) * 4;
              final alpha = monoBytes.getUint8(offset + 3);
              expect(alpha, fgBytes.getUint8(offset + 3));
              expect(bgBytes.getUint8(offset + 3), 255);
              if (alpha > 128) {
                opaque++;
                final radius = math.sqrt(
                  math.pow(x + 0.5 - size / 2, 2) +
                      math.pow(y + 0.5 - size / 2, 2),
                );
                expect(radius * 108 / size, lessThanOrEqualTo(33));
                for (var channel = 0; channel < 3; channel++) {
                  expect(monoBytes.getUint8(offset + channel), greaterThanOrEqualTo(250));
                }
              }
            }
          }
          expect(opaque / (size * size), inExclusiveRange(0.05, 0.25));
          for (final point in [
            (0.6, 0.55),
            (0.369, 0.461),
            (0.5, 0.619),
            (0.0, 0.0),
          ]) {
            final offset =
                ((size * point.$2).floor() * size + (size * point.$1).floor()) *
                4;
            expect(monoBytes.getUint8(offset + 3), 0);
          }
        } finally {
          for (final image in layers.values) {
            image.dispose();
          }
        }
      },
    );
  }

  test('night launcher layers reuse the light geometry with the dark palette', () async {
    const darkBackground = [35, 48, 68];
    const darkForeground = [172, 193, 223];
    const lightForegroundColor = [78, 112, 152];
    for (final entry in densities.entries) {
      final size = entry.value * 108 ~/ 48;
      final lightPath = '$root/mipmap-${entry.key}';
      final nightPath = '$root/mipmap-night-${entry.key}';
      final layers = <String, ui.Image>{};
      try {
        for (final name in ['ic_launcher_background', 'ic_launcher_foreground']) {
          for (final (path, key) in [
            (lightPath, 'light_$name'),
            (nightPath, 'night_$name'),
          ]) {
            final codec = await ui.instantiateImageCodec(
              File('$path/$name.png').readAsBytesSync(),
            );
            layers[key] = (await codec.getNextFrame()).image;
            codec.dispose();
            expect(layers[key]!.width, size);
            expect(layers[key]!.height, size);
          }
        }
        final nightBackground = (await layers['night_ic_launcher_background']!
            .toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        final nightForeground = (await layers['night_ic_launcher_foreground']!
            .toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        final lightForeground = (await layers['light_ic_launcher_foreground']!
            .toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        for (var offset = 0; offset < size * size * 4; offset += 4) {
          expect(nightBackground.getUint8(offset + 3), 255);
          for (var channel = 0; channel < 3; channel++) {
            expect(
              nightBackground.getUint8(offset + channel),
              darkBackground[channel],
            );
          }
          final alpha = lightForeground.getUint8(offset + 3);
          expect(nightForeground.getUint8(offset + 3), alpha);
          if (alpha == 0) continue;
          for (var channel = 0; channel < 3; channel++) {
            final expected = darkForeground[channel];
            final actual = nightForeground.getUint8(offset + channel);
            if (alpha == 255) {
              expect(actual, expected);
            } else {
              // 低 alpha 像素在解码/反预乘后会有几个单位的舍入，
              // 因此只要求它已明显偏向暗色图形色而不是旧的亮色。
              expect(
                (actual - expected).abs(),
                lessThan((actual - lightForegroundColor[channel]).abs()),
              );
            }
          }
        }
      } finally {
        for (final image in layers.values) {
          image.dispose();
        }
      }
    }
  });

  test('both adaptive entries expose the monochrome layer', () {
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final xml = File('$root/mipmap-anydpi/$name.xml').readAsStringSync();
      expect(
        xml,
        contains(
          '<background android:drawable="@mipmap/ic_launcher_background"',
        ),
      );
      expect(
        xml,
        contains(
          '<foreground android:drawable="@mipmap/ic_launcher_foreground"',
        ),
      );
      expect(
        xml,
        contains(
          '<monochrome android:drawable="@mipmap/ic_launcher_monochrome"',
        ),
      );
    }
  });

  test('in-app branding uses the new palette', () async {
    final codec = await ui.instantiateImageCodec(
      File('assets/icon/app_icon.png').readAsBytesSync(),
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      expect(image.width, 512);
      expect(image.height, 512);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      expect(
        [for (var i = 0; i < 4; i++) bytes.getUint8(i)],
        [213, 228, 241, 255],
      );
    } finally {
      image.dispose();
    }
  });
}
