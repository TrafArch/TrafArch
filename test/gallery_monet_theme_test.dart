import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_color_engine.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_monet.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

void main() {
  test('six preset themes keep the documented light tokens', () {
    const expected = [
      (
        'blue',
        '靛蓝',
        0xff4e7098,
        0xfff3f7fb,
        0xffeaf1f8,
        0xffe3ecf5,
        0xff496b91,
        0xffe5edf7,
        0xffe4ebf2,
        0xffdce7f1,
        0xffc9d8e7,
      ),
      (
        'teal',
        '青绿',
        0xff568276,
        0xfff3f8f5,
        0xffeaf2ed,
        0xffe2eee7,
        0xff477365,
        0xffe4efe8,
        0xffe3ece6,
        0xffdce8e1,
        0xffc9dcd1,
      ),
      (
        'violet',
        '藤紫',
        0xff806c98,
        0xfff7f4f9,
        0xffefeaf4,
        0xffe8e1f0,
        0xff6e5a86,
        0xffebe5f1,
        0xffeae5ef,
        0xffe3dcea,
        0xffd7cde1,
      ),
      (
        'rose',
        '蔷薇',
        0xffa96878,
        0xfffaf5f6,
        0xfff3e9ec,
        0xffeedfe4,
        0xff925363,
        0xfff2e5e9,
        0xfff0e5e8,
        0xffe9dadf,
        0xffe2ccd3,
      ),
      (
        'amber',
        '麦金',
        0xffa18450,
        0xfff8f6f0,
        0xfff0ebdd,
        0xffeae2cc,
        0xff806637,
        0xffefe8d7,
        0xffeee9dc,
        0xffe5ddca,
        0xffdccfb4,
      ),
      (
        'mist',
        '雾灰',
        0xff687887,
        0xfff5f7f8,
        0xffebeff2,
        0xffe6ecef,
        0xff526675,
        0xffe8edf1,
        0xffe5eaed,
        0xffdde4e8,
        0xffcbd6dd,
      ),
    ];
    expect(GalleryThemeSpec.values, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i];
      final spec = GalleryThemeSpec.values[i];
      expect((spec.id, spec.name, spec.seed.toARGB32()), (e.$1, e.$2, e.$3));
      final light = spec.light;
      expect(light.canvas.toARGB32(), e.$4);
      expect(light.surface, const Color(0xffffffff));
      expect(light.surfaceContainer.toARGB32(), e.$5);
      expect(light.surfaceContainerHigh.toARGB32(), e.$6);
      expect(light.primary.toARGB32(), e.$7);
      expect(light.primaryContainer.toARGB32(), e.$8);
      expect(light.outlineSoft.toARGB32(), e.$9);
      expect(light.outline.toARGB32(), e.$10);
      expect(light.outlineStrong.toARGB32(), e.$11);
      expect(light.canvas, isNot(light.surface));
      expect(
        GalleryColorEngine.contrast(light.primary, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        GalleryColorEngine.oklch(light.canvas).c,
        lessThanOrEqualTo(.02),
        reason: '${spec.id} canvas must stay near-white',
      );
    }
  });

  test('dark tokens are generated independently from the same hue', () {
    for (final spec in GalleryThemeSpec.values) {
      final tokens = spec.tokens(true);
      final canvas = tokens.canvas.computeLuminance();
      final surface = tokens.surface.computeLuminance();
      final container = tokens.surfaceContainer.computeLuminance();
      final high = tokens.surfaceContainerHigh.computeLuminance();
      expect(canvas, greaterThan(.005), reason: '${spec.id} avoids pure black');
      expect(surface, greaterThan(canvas));
      expect(container, greaterThan(surface));
      expect(high, greaterThan(container));
      expect(
        GalleryColorEngine.contrast(tokens.onPrimary, tokens.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        GalleryColorEngine.contrast(
          tokens.onPrimaryContainer,
          tokens.primaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final seedHue = GalleryColorEngine.oklch(spec.seed).h;
      final canvasHue = GalleryColorEngine.oklch(tokens.canvas).h;
      final delta = (canvasHue - seedHue).abs();
      expect(
        delta < 8 || delta > 352,
        isTrue,
        reason: '${spec.id} keeps its hue in dark mode',
      );
    }
  });

  test('Monet surfaces stay restrained for vivid and extreme seeds', () {
    const seeds = [
      Color(0xff1e88e5), // blue
      Color(0xff2e7d32), // green
      Color(0xff7b1fa2), // purple
      Color(0xffd32f2f), // saturated red
      Color(0xfffbc02d), // saturated yellow
      Color(0xff101010), // almost black
      Color(0xfffafafa), // almost white
      Color(0xff808080), // neutral gray
    ];
    for (final seed in seeds) {
      for (final dark in [false, true]) {
        final tokens = GalleryColorEngine.tokens(seed, dark: dark);
        if (!dark) {
          expect(tokens.surface, const Color(0xffffffff));
        }
        expect(
          GalleryColorEngine.oklch(tokens.canvas).c,
          lessThanOrEqualTo(.026),
          reason: '$seed dark=$dark canvas chroma',
        );
        expect(
          GalleryColorEngine.contrast(tokens.onPrimary, tokens.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          GalleryColorEngine.contrast(
            tokens.onPrimaryContainer,
            tokens.primaryContainer,
          ),
          greaterThanOrEqualTo(4.5),
        );
        if (dark) {
          expect(tokens.canvas.computeLuminance(), greaterThan(.005));
        } else {
          expect(tokens.canvas.computeLuminance(), greaterThan(.85));
        }
      }
    }
  });

  test('image sampling finds a hue and rejects blank images', () {
    Uint8List pixels(int count, int r, int g, int b, [int a = 255]) {
      final data = Uint8List(count * 4);
      for (var i = 0; i < count; i++) {
        data[i * 4] = r;
        data[i * 4 + 1] = g;
        data[i * 4 + 2] = b;
        data[i * 4 + 3] = a;
      }
      return data;
    }

    final red = GalleryMonet.seedFromRgba(
      pixels(16, 220, 40, 40),
      width: 4,
      height: 4,
    );
    expect(red, isNotNull);
    final redHue = GalleryColorEngine.oklch(red!).h;
    expect(redHue, inInclusiveRange(15, 45));

    expect(
      GalleryMonet.seedFromRgba(pixels(16, 255, 255, 255), width: 4, height: 4),
      isNull,
    );
    expect(
      GalleryMonet.seedFromRgba(pixels(16, 0, 0, 0, 0), width: 4, height: 4),
      isNull,
    );

    final gray = GalleryMonet.seedFromRgba(
      pixels(16, 128, 128, 128),
      width: 4,
      height: 4,
    );
    expect(gray, isNotNull);
    expect(GalleryColorEngine.oklch(gray!).c, lessThan(.01));

    // A white field with a red subject must not average to pink/neutral.
    final mixed = pixels(32, 255, 255, 255);
    for (var i = 0; i < 6; i++) {
      mixed[i * 4] = 210;
      mixed[i * 4 + 1] = 35;
      mixed[i * 4 + 2] = 35;
    }
    final subject = GalleryMonet.seedFromRgba(mixed, width: 8, height: 4);
    expect(subject, isNotNull);
    expect(GalleryColorEngine.oklch(subject!).h, inInclusiveRange(10, 50));
  });

  test('monet seed selects generated tokens; null falls back to preset', () {
    final data = GalleryData(<String, dynamic>{});
    final preset = GalleryTokens.from(data, false, 'mist');
    expect(preset.dynamic, isFalse);
    expect(preset.roles.primary, GalleryThemeSpec.byId('mist').light.primary);

    final monet = GalleryTokens.from(
      data,
      false,
      'mist',
      monetSeed: const Color(0xff1e88e5),
    );
    expect(monet.dynamic, isTrue);
    expect(
      monet.roles.primary,
      GalleryColorEngine.tokens(const Color(0xff1e88e5), dark: false).primary,
    );
    expect(monet.canvas, isNot(preset.canvas));
    expect(GalleryPalette.values, hasLength(6));
  });
}
