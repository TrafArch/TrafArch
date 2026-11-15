import 'dart:math' as math;

import 'package:flutter/material.dart';

/// OKLCH color engine shared by the five preset themes and Monet extraction
/// (TrafArch spec 2.2, Part II). Presets and wallpaper seeds run through the
/// same pipeline: seed validation -> theme tokens -> dynamic data palette.
abstract final class GalleryColorEngine {
  static const _white = Color(0xffffffff);

  /// sRGB transfer -> linear.
  static double _toLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  static double _toSrgb(double c) =>
      c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

  static ({double l, double c, double h}) oklch(Color color) {
    final r = _toLinear(color.r),
        g = _toLinear(color.g),
        b = _toLinear(color.b);
    final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    final lc = math.pow(l, 1 / 3).toDouble(),
        mc = math.pow(m, 1 / 3).toDouble(),
        sc = math.pow(s, 1 / 3).toDouble();
    final ll = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc;
    final a = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc;
    final bb = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc;
    final c = math.sqrt(a * a + bb * bb);
    var h = math.atan2(bb, a) * 180 / math.pi;
    if (h < 0) h += 360;
    return (l: ll, c: c, h: h);
  }

  static Color _fromLinear(double r, double g, double b) => Color.from(
    alpha: 1,
    red: _toSrgb(r).clamp(0.0, 1.0),
    green: _toSrgb(g).clamp(0.0, 1.0),
    blue: _toSrgb(b).clamp(0.0, 1.0),
  );

  static Color _raw(double l, double c, double h) {
    final rad = h * math.pi / 180;
    final a = c * math.cos(rad), b = c * math.sin(rad);
    final lc = l + 0.3963377774 * a + 0.2158037573 * b;
    final mc = l - 0.1055613458 * a - 0.0638541728 * b;
    final sc = l - 0.0894841775 * a - 1.2914855480 * b;
    final ll = lc * lc * lc, mm = mc * mc * mc, ss = sc * sc * sc;
    return _fromLinear(
      4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
      -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
      -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss,
    );
  }

  /// Reduce chroma until the color fits the sRGB gamut, then encode.
  static Color color(double l, double c, double h) {
    l = l.clamp(0.0, 1.0);
    var lo = 0.0, hi = c;
    for (var i = 0; i < 22; i++) {
      final mid = (lo + hi) / 2;
      final candidate = _raw(l, mid, h);
      final back = oklch(candidate);
      final inGamut =
          candidate.r >= 0 &&
          candidate.r <= 1 &&
          candidate.g >= 0 &&
          candidate.g <= 1 &&
          candidate.b >= 0 &&
          candidate.b <= 1 &&
          (back.c - mid).abs() < 0.004;
      if (inGamut) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return _raw(l, lo, h);
  }

  static double _luminance(Color color) {
    final r = _toLinear(color.r),
        g = _toLinear(color.g),
        b = _toLinear(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double contrast(Color a, Color b) {
    final la = _luminance(a), lb = _luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static Color _adjust(
    Color base,
    bool Function(Color) satisfied, {
    required bool increase,
  }) {
    final seed = oklch(base);
    var l = seed.l;
    var current = color(l, seed.c, seed.h);
    for (var i = 0; i < 90 && !satisfied(current); i++) {
      l = (l + (increase ? 0.01 : -0.01)).clamp(0.0, 1.0);
      current = color(l, seed.c, seed.h);
    }
    return current;
  }

  /// Nudge a foreground color's lightness until it reads on [background].
  /// Dark backgrounds lighten the text; light backgrounds darken it.
  static Color readable(Color base, Color background, {double target = 4.5}) {
    if (contrast(base, background) >= target) return base;
    final darken = _luminance(background) > 0.4;
    return _adjust(
      base,
      (c) => contrast(c, background) >= target,
      increase: !darken,
    );
  }

  /// A theme fill that carries white (light) or near-black (dark) label text.
  static Color actionFill(Color seed, {required bool dark}) {
    final seedOklch = oklch(seed);
    if (dark) {
      final label = color(0.20, seedOklch.c * 0.4, seedOklch.h);
      return _adjust(seed, (c) => contrast(label, c) >= 4.5, increase: true);
    }
    return _adjust(seed, (c) => contrast(_white, c) >= 4.5, increase: false);
  }

  static Color actionLabel(Color fill, {required bool dark}) {
    final seed = oklch(fill);
    return dark ? readable(color(0.20, seed.c * 0.4, seed.h), fill) : _white;
  }

  /// A pale container tinted by [base], paired with readable text in the spec.
  static ({Color container, Color onContainer}) container(
    Color base, {
    required bool dark,
  }) {
    final seed = oklch(base);
    final containerColor = dark
        ? color(0.30, math.min(seed.c, 0.05), seed.h)
        : color(0.93, math.min(seed.c, 0.035), seed.h);
    final onContainer = readable(
      dark ? color(0.85, seed.c * 0.6, seed.h) : color(0.42, seed.c, seed.h),
      containerColor,
    );
    return (container: containerColor, onContainer: onContainer);
  }

  // Data palette hue offsets and lightness/chroma targets, calibrated against
  // the Indigo reference (spec 2.2 §5). Other themes and Monet seeds rotate
  // these offsets around their own hue instead of copying the reference HEX.
  static const _dataOffsets = [20.6, -63.8, 181.7, 126.5, 43.3];
  static const _dataTargets = [
    (0.53, 0.10),
    (0.66, 0.067),
    (0.75, 0.105),
    (0.68, 0.088),
    (0.67, 0.083),
  ];

  static List<Color> dataPalette(Color seed, {required bool dark}) {
    final hue = oklch(seed).h;
    return [
      for (var i = 0; i < _dataOffsets.length; i++)
        color(
          dark ? math.min(0.80, _dataTargets[i].$1 + 0.13) : _dataTargets[i].$1,
          dark ? _dataTargets[i].$2 * 0.85 : _dataTargets[i].$2,
          (hue + _dataOffsets[i] + 360) % 360,
        ),
    ];
  }

  static Color chartTrack(Color seed, {required bool dark}) {
    final hue = oklch(seed).h;
    return dark ? color(0.30, 0.02, hue) : color(0.92, 0.016, hue);
  }
}

/// The five preset themes (spec 2.2 §2). Indigo keeps the app-icon anchor.
@immutable
class GalleryThemeSpec {
  const GalleryThemeSpec(
    this.id,
    this.name,
    this.primary,
    this.tint,
    this.dark,
  );
  final String id, name;
  final Color primary, tint, dark;

  static const indigo = GalleryThemeSpec(
    'blue',
    '靛蓝',
    Color(0xff4E7098),
    Color(0xffD5E4F1),
    Color(0xff344B68),
  );
  static const values = [
    indigo,
    GalleryThemeSpec(
      'teal',
      '青绿',
      Color(0xff4F8F87),
      Color(0xffDCEFEA),
      Color(0xff315F5A),
    ),
    GalleryThemeSpec(
      'violet',
      '藤紫',
      Color(0xff8275A8),
      Color(0xffE9E3F2),
      Color(0xff51466F),
    ),
    GalleryThemeSpec(
      'rose',
      '蔷薇',
      Color(0xffB87583),
      Color(0xffF4E3E7),
      Color(0xff794653),
    ),
    GalleryThemeSpec(
      'amber',
      '麦金',
      Color(0xffB58A4A),
      Color(0xffF4EBD8),
      Color(0xff72562E),
    ),
  ];

  static GalleryThemeSpec byId(String id) =>
      values.firstWhere((spec) => spec.id == id, orElse: () => indigo);
}

/// Shared neutral surfaces (spec 2.2 §3). Dark mode uses its own surface
/// ladder rather than inverting the light values (spec 2.2 §21).
abstract final class GalleryNeutrals {
  static const lightCanvas = Color(0xffF7F8FA);
  static const lightCard = Color(0xffFFFFFF);
  static const lightSecondary = Color(0xffF0F2F5);
  static const lightTertiary = Color(0xffE9EDF2);
  static const lightBorder = Color(0xffE3E7EC);
  static const lightBorderStrong = Color(0xffCDD4DD);
  static const lightText = Color(0xff29313D);
  static const lightTextSecondary = Color(0xff66717F);

  static const darkCanvas = Color(0xff0C1119);
  static const darkCard = Color(0xff151E2B);
  static const darkSecondary = Color(0xff1B2636);
  static const darkTertiary = Color(0xff101722);
  static const darkRaised = Color(0xff223047);
  static const darkBorder = Color(0xff3D4E65);
  static const darkBorderStrong = Color(0xff75859C);
  static const darkText = Color(0xffE8EEF7);
  static const darkTextSecondary = Color(0xffA6B4C7);
}

/// Global semantic colors (spec 2.2 §6), independent of the theme hue.
abstract final class GallerySemantic {
  static const success = Color(0xff4E9A75);
  static const warning = Color(0xffD5A04E);
  static const error = Color(0xffC66C72);
  static const info = Color(0xff6288BB);
}

/// Build a full Material scheme from a theme seed through the shared engine.
/// Presets pass their documented tint/dark anchors; Monet passes only a seed.
ColorScheme buildGalleryScheme(
  Color seed, {
  required bool dark,
  Color? tint,
  Color? darkAnchor,
  Color? actionOverride,
  Color? onActionOverride,
}) {
  final primary =
      actionOverride ?? GalleryColorEngine.actionFill(seed, dark: dark);
  final tone = dark
      ? GalleryColorEngine.container(seed, dark: true)
      : (
          container:
              tint ?? GalleryColorEngine.container(seed, dark: false).container,
          onContainer:
              darkAnchor ??
              GalleryColorEngine.container(seed, dark: false).onContainer,
        );
  final surface2 = dark
      ? GalleryNeutrals.darkTertiary
      : GalleryNeutrals.lightTertiary;
  // Text must read on the extreme surface: the darkest light surface, or the
  // lightest dark surface (dark mode does not invert the light ladder).
  final textSurface = dark
      ? GalleryNeutrals.darkRaised
      : GalleryNeutrals.lightTertiary;
  final error = GalleryColorEngine.readable(GallerySemantic.error, textSurface);
  final errorPair = GalleryColorEngine.container(
    GallerySemantic.error,
    dark: dark,
  );
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: primary,
    onPrimary:
        onActionOverride ?? GalleryColorEngine.actionLabel(primary, dark: dark),
    primaryContainer: tone.container,
    onPrimaryContainer: tone.onContainer,
    // Secondary/tertiary stay the established teal/amber UI accents; chart
    // categories use the separate data palette instead of these roles.
    secondary: Color(dark ? 0xff8ed2c5 : 0xff087f78),
    onSecondary: Color(dark ? 0xff003831 : 0xffffffff),
    secondaryContainer: Color(dark ? 0xff163d38 : 0xffdef3ec),
    onSecondaryContainer: Color(dark ? 0xffb4eddb : 0xff145747),
    tertiary: Color(dark ? 0xffe5c07b : 0xff9e640a),
    onTertiary: Color(dark ? 0xff3c2b0b : 0xffffffff),
    tertiaryContainer: Color(dark ? 0xff463820 : 0xffffedce),
    onTertiaryContainer: Color(dark ? 0xfff4d59b : 0xff76500d),
    error: error,
    onError: dark ? const Color(0xff690005) : Colors.white,
    errorContainer: errorPair.container,
    onErrorContainer: errorPair.onContainer,
    surface: dark ? GalleryNeutrals.darkCanvas : GalleryNeutrals.lightCanvas,
    onSurface: dark ? GalleryNeutrals.darkText : GalleryNeutrals.lightText,
    onSurfaceVariant: GalleryColorEngine.readable(
      dark
          ? GalleryNeutrals.darkTextSecondary
          : GalleryNeutrals.lightTextSecondary,
      textSurface,
    ),
    outline: dark
        ? GalleryNeutrals.darkBorderStrong
        : GalleryNeutrals.lightBorderStrong,
    outlineVariant: dark
        ? GalleryNeutrals.darkBorder
        : GalleryNeutrals.lightBorder,
    surfaceDim: dark ? GalleryNeutrals.darkCanvas : const Color(0xffdee6f0),
    surfaceBright: dark ? GalleryNeutrals.darkRaised : Colors.white,
    surfaceContainerLowest: dark
        ? GalleryNeutrals.darkTertiary
        : const Color(0xffe8eef6),
    surfaceContainerLow: dark
        ? GalleryNeutrals.darkCard
        : GalleryNeutrals.lightCard,
    surfaceContainer: dark
        ? GalleryNeutrals.darkSecondary
        : GalleryNeutrals.lightSecondary,
    surfaceContainerHigh: dark
        ? GalleryNeutrals.darkRaised
        : GalleryNeutrals.lightSecondary,
    surfaceContainerHighest: surface2,
  );
}
