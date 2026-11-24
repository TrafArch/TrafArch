import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Light-mode tokens for one preset theme (Monet Adaptive Canvas spec §3).
///
/// Presets keep their documented values instead of being regenerated from the
/// seed, so switching themes stays predictable. Dark mode is generated from the
/// same seed through [GalleryColorEngine.tokens] and never inverts these values.
@immutable
class GalleryLightTokens {
  const GalleryLightTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.primary,
    required this.primaryContainer,
    required this.outlineSoft,
    required this.outline,
    required this.outlineStrong,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color primary;
  final Color primaryContainer;
  final Color outlineSoft;
  final Color outline;
  final Color outlineStrong;
}

/// The full four-layer surface set plus the interaction and neutral roles that
/// custom components read through [GalleryTokens].
@immutable
class GallerySchemeTokens {
  const GallerySchemeTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.primary,
    required this.primaryContainer,
    required this.outlineSoft,
    required this.outline,
    required this.outlineStrong,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.mutedText,
    required this.onPrimary,
    required this.onPrimaryContainer,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color primary;
  final Color primaryContainer;
  final Color outlineSoft;
  final Color outline;
  final Color outlineStrong;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color mutedText;
  final Color onPrimary;
  final Color onPrimaryContainer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GallerySchemeTokens &&
          other.canvas == canvas &&
          other.surface == surface &&
          other.surfaceContainer == surfaceContainer &&
          other.surfaceContainerHigh == surfaceContainerHigh &&
          other.primary == primary &&
          other.primaryContainer == primaryContainer &&
          other.outlineSoft == outlineSoft &&
          other.outline == outline &&
          other.outlineStrong == outlineStrong &&
          other.onSurface == onSurface &&
          other.onSurfaceVariant == onSurfaceVariant &&
          other.mutedText == mutedText &&
          other.onPrimary == onPrimary &&
          other.onPrimaryContainer == onPrimaryContainer;

  @override
  int get hashCode => Object.hash(
    canvas,
    surface,
    surfaceContainer,
    surfaceContainerHigh,
    primary,
    primaryContainer,
    outlineSoft,
    outline,
    outlineStrong,
    onSurface,
    onSurfaceVariant,
    mutedText,
    onPrimary,
    onPrimaryContainer,
  );

  /// Compatibility path for tests and callers that only have a [ColorScheme].
  /// Production themes are built from [GalleryLightTokens] or the Monet
  /// generator so the three outline tiers stay distinct.
  factory GallerySchemeTokens.fromScheme(ColorScheme scheme) =>
      GallerySchemeTokens(
        canvas: scheme.surface,
        surface: scheme.surfaceContainerLow,
        surfaceContainer: scheme.surfaceContainer,
        surfaceContainerHigh: scheme.surfaceContainerHigh,
        primary: scheme.primary,
        primaryContainer: scheme.primaryContainer,
        outlineSoft: scheme.outlineVariant,
        outline: scheme.outline,
        outlineStrong: scheme.outline,
        onSurface: scheme.onSurface,
        onSurfaceVariant: scheme.onSurfaceVariant,
        mutedText: scheme.onSurfaceVariant,
        onPrimary: scheme.onPrimary,
        onPrimaryContainer: scheme.onPrimaryContainer,
      );

  GallerySchemeTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? primary,
    Color? primaryContainer,
    Color? outlineSoft,
    Color? outline,
    Color? outlineStrong,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? mutedText,
    Color? onPrimary,
    Color? onPrimaryContainer,
  }) => GallerySchemeTokens(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceContainer: surfaceContainer ?? this.surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
    primary: primary ?? this.primary,
    primaryContainer: primaryContainer ?? this.primaryContainer,
    outlineSoft: outlineSoft ?? this.outlineSoft,
    outline: outline ?? this.outline,
    outlineStrong: outlineStrong ?? this.outlineStrong,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    mutedText: mutedText ?? this.mutedText,
    onPrimary: onPrimary ?? this.onPrimary,
    onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
  );

  static GallerySchemeTokens lerp(
    GallerySchemeTokens a,
    GallerySchemeTokens b,
    double t,
  ) => GallerySchemeTokens(
    canvas: Color.lerp(a.canvas, b.canvas, t)!,
    surface: Color.lerp(a.surface, b.surface, t)!,
    surfaceContainer: Color.lerp(a.surfaceContainer, b.surfaceContainer, t)!,
    surfaceContainerHigh: Color.lerp(
      a.surfaceContainerHigh,
      b.surfaceContainerHigh,
      t,
    )!,
    primary: Color.lerp(a.primary, b.primary, t)!,
    primaryContainer: Color.lerp(a.primaryContainer, b.primaryContainer, t)!,
    outlineSoft: Color.lerp(a.outlineSoft, b.outlineSoft, t)!,
    outline: Color.lerp(a.outline, b.outline, t)!,
    outlineStrong: Color.lerp(a.outlineStrong, b.outlineStrong, t)!,
    onSurface: Color.lerp(a.onSurface, b.onSurface, t)!,
    onSurfaceVariant: Color.lerp(a.onSurfaceVariant, b.onSurfaceVariant, t)!,
    mutedText: Color.lerp(a.mutedText, b.mutedText, t)!,
    onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
    onPrimaryContainer: Color.lerp(
      a.onPrimaryContainer,
      b.onPrimaryContainer,
      t,
    )!,
  );
}

/// OKLCH color engine shared by the six preset themes and Monet extraction
/// (TrafArch Monet design). Presets and system seeds run through the same
/// surface pipeline: seed validation → surface tokens → Material scheme.
abstract final class GalleryColorEngine {
  static const _white = Color(0xffffffff);

  // Fixed neutrals (spec §7). Text roles are re-checked against the lightest
  // dark surface / darkest light surface before they are exposed.
  static const _lightOnSurface = Color(0xff202a35);
  static const _lightOnSurfaceVariant = Color(0xff65717e);
  static const _lightMutedText = Color(0xff89939d);
  static const _darkOnSurface = Color(0xffeef2f6);
  static const _darkOnSurfaceVariant = Color(0xffb1bcc7);
  static const _darkMutedText = Color(0xff8995a1);
  static const _darkOnPrimary = Color(0xff18212b);

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

  /// The documented preset tokens for light mode, plus the fixed neutrals.
  static GallerySchemeTokens preset(GalleryLightTokens light, Color seed) {
    final seedOklch = oklch(seed);
    return GallerySchemeTokens(
      canvas: light.canvas,
      surface: light.surface,
      surfaceContainer: light.surfaceContainer,
      surfaceContainerHigh: light.surfaceContainerHigh,
      primary: light.primary,
      primaryContainer: light.primaryContainer,
      outlineSoft: light.outlineSoft,
      outline: light.outline,
      outlineStrong: light.outlineStrong,
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightOnSurfaceVariant,
      mutedText: _lightMutedText,
      onPrimary: _white,
      onPrimaryContainer: readable(
        color(0.42, seedOklch.c, seedOklch.h),
        light.primaryContainer,
      ),
    );
  }

  /// Monet Adaptive Canvas generation (spec §4.3–§4.5).
  ///
  /// Light and dark are generated independently. Only the hue (and a capped
  /// amount of chroma) comes from the seed; surfaces never use the raw color.
  static GallerySchemeTokens tokens(Color seed, {required bool dark}) {
    final s = oklch(seed);
    final neutral = s.c < 0.008;

    double chroma(double factor, double min, double max) =>
        neutral ? 0 : (s.c * factor).clamp(min, max).toDouble();

    if (dark) {
      final primary = _darkPrimary(seed);
      final containerColor = color(0.30, math.min(s.c, 0.05), s.h);
      return GallerySchemeTokens(
        canvas: color(0.19, chroma(0.08, 0.006, 0.015), s.h),
        surface: color(0.23, chroma(0.08, 0.008, 0.018), s.h),
        surfaceContainer: color(0.26, chroma(0.12, 0.010, 0.020), s.h),
        surfaceContainerHigh: color(0.30, chroma(0.14, 0.010, 0.022), s.h),
        primary: primary,
        primaryContainer: containerColor,
        outlineSoft: color(0.355, chroma(0.08, 0.006, 0.014), s.h),
        outline: color(0.40, chroma(0.10, 0.008, 0.018), s.h),
        outlineStrong: color(0.48, chroma(0.12, 0.010, 0.020), s.h),
        onSurface: _darkOnSurface,
        onSurfaceVariant: _darkOnSurfaceVariant,
        mutedText: _darkMutedText,
        onPrimary: _darkOnPrimary,
        onPrimaryContainer: readable(
          color(0.85, s.c * 0.6, s.h),
          containerColor,
        ),
      );
    }

    final primary = actionFill(seed, dark: false);
    final containerColor = container(seed, dark: false).container;
    return GallerySchemeTokens(
      canvas: color(0.975, chroma(0.10, 0.006, 0.014), s.h),
      surface: _white,
      surfaceContainer: color(0.945, chroma(0.18, 0.010, 0.022), s.h),
      surfaceContainerHigh: color(0.925, chroma(0.20, 0.012, 0.026), s.h),
      primary: primary,
      primaryContainer: containerColor,
      outlineSoft: color(0.925, chroma(0.12, 0.006, 0.016), s.h),
      outline: color(0.890, chroma(0.12, 0.008, 0.018), s.h),
      outlineStrong: color(0.855, chroma(0.14, 0.010, 0.022), s.h),
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightOnSurfaceVariant,
      mutedText: _lightMutedText,
      onPrimary: _white,
      onPrimaryContainer: readable(color(0.42, s.c, s.h), containerColor),
    );
  }

  /// Dark actions are intentionally lighter than the seed so the fixed near-
  /// black label keeps 4.5:1 contrast without washing out the hue.
  static Color _darkPrimary(Color seed) {
    final s = oklch(seed);
    final neutral = s.c < 0.008;
    final base = color(
      0.72,
      neutral ? 0 : math.min(math.max(s.c * 0.55, 0.035), 0.10),
      s.h,
    );
    return _adjust(
      base,
      (c) => contrast(c, _darkOnPrimary) >= 4.5,
      increase: true,
    );
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

/// The six preset themes from the Monet Adaptive Canvas spec §3.
@immutable
class GalleryThemeSpec {
  const GalleryThemeSpec(this.id, this.name, this.seed, this.light);

  final String id, name;
  final Color seed;
  final GalleryLightTokens light;

  Color get primary => light.primary;
  Color get tint => light.primaryContainer;

  GallerySchemeTokens tokens(bool dark) => dark
      ? GalleryColorEngine.tokens(seed, dark: true)
      : GalleryColorEngine.preset(light, seed);

  static const indigo = GalleryThemeSpec(
    'blue',
    '靛蓝',
    Color(0xff4E7098),
    GalleryLightTokens(
      canvas: Color(0xffF3F7FB),
      surface: Color(0xFFFFFFFF),
      surfaceContainer: Color(0xffEAF1F8),
      surfaceContainerHigh: Color(0xffE3ECF5),
      primary: Color(0xff496B91),
      primaryContainer: Color(0xffE5EDF7),
      outlineSoft: Color(0xffE4EBF2),
      outline: Color(0xffDCE7F1),
      outlineStrong: Color(0xffC9D8E7),
    ),
  );

  static const values = [
    indigo,
    GalleryThemeSpec(
      'teal',
      '青绿',
      Color(0xff568276),
      GalleryLightTokens(
        canvas: Color(0xffF3F8F5),
        surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xffEAF2ED),
        surfaceContainerHigh: Color(0xffE2EEE7),
        primary: Color(0xff477365),
        primaryContainer: Color(0xffE4EFE8),
        outlineSoft: Color(0xffE3ECE6),
        outline: Color(0xffDCE8E1),
        outlineStrong: Color(0xffC9DCD1),
      ),
    ),
    GalleryThemeSpec(
      'violet',
      '藤紫',
      Color(0xff806C98),
      GalleryLightTokens(
        canvas: Color(0xffF7F4F9),
        surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xffEFEAF4),
        surfaceContainerHigh: Color(0xffE8E1F0),
        primary: Color(0xff6E5A86),
        primaryContainer: Color(0xffEBE5F1),
        outlineSoft: Color(0xffEAE5EF),
        outline: Color(0xffE3DCEA),
        outlineStrong: Color(0xffD7CDE1),
      ),
    ),
    GalleryThemeSpec(
      'rose',
      '蔷薇',
      Color(0xffA96878),
      GalleryLightTokens(
        canvas: Color(0xffFAF5F6),
        surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xffF3E9EC),
        surfaceContainerHigh: Color(0xffEEDFE4),
        primary: Color(0xff925363),
        primaryContainer: Color(0xffF2E5E9),
        outlineSoft: Color(0xffF0E5E8),
        outline: Color(0xffE9DADF),
        outlineStrong: Color(0xffE2CCD3),
      ),
    ),
    GalleryThemeSpec(
      'amber',
      '麦金',
      Color(0xffA18450),
      GalleryLightTokens(
        canvas: Color(0xffF8F6F0),
        surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xffF0EBDD),
        surfaceContainerHigh: Color(0xffEAE2CC),
        primary: Color(0xff806637),
        primaryContainer: Color(0xffEFE8D7),
        outlineSoft: Color(0xffEEE9DC),
        outline: Color(0xffE5DDCA),
        outlineStrong: Color(0xffDCCFB4),
      ),
    ),
    GalleryThemeSpec(
      'mist',
      '雾灰',
      Color(0xff687887),
      GalleryLightTokens(
        canvas: Color(0xffF5F7F8),
        surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xffEBEFF2),
        surfaceContainerHigh: Color(0xffE6ECEF),
        primary: Color(0xff526675),
        primaryContainer: Color(0xffE8EDF1),
        outlineSoft: Color(0xffE5EAED),
        outline: Color(0xffDDE4E8),
        outlineStrong: Color(0xffCBD6DD),
      ),
    ),
  ];

  static GalleryThemeSpec byId(String id) =>
      values.firstWhere((spec) => spec.id == id, orElse: () => indigo);
}

/// Global semantic colors (spec §7.3), independent of the theme hue. Dark mode
/// derives readable variants through [GalleryColorEngine.readable].
abstract final class GallerySemantic {
  static const success = Color(0xff347864);
  static const warning = Color(0xff9A6A25);
  static const error = Color(0xffB45353);
  static const info = Color(0xff4F7098);
}

/// Build a full Material scheme from the four-layer tokens. `surface` is the
/// Canvas; white content cards live in `surfaceContainerLow`, matching the
/// existing Gallery role mapping.
ColorScheme buildGalleryColorScheme(
  GallerySchemeTokens tokens, {
  required bool dark,
}) {
  final textSurface = tokens.surfaceContainerHigh;
  final error = GalleryColorEngine.readable(GallerySemantic.error, textSurface);
  final errorPair = GalleryColorEngine.container(
    GallerySemantic.error,
    dark: dark,
  );
  return ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    primaryContainer: tokens.primaryContainer,
    onPrimaryContainer: tokens.onPrimaryContainer,
    secondary: tokens.primary,
    onSecondary: tokens.onPrimary,
    secondaryContainer: tokens.primaryContainer,
    onSecondaryContainer: tokens.onPrimaryContainer,
    tertiary: tokens.primary,
    onTertiary: tokens.onPrimary,
    tertiaryContainer: tokens.primaryContainer,
    onTertiaryContainer: tokens.onPrimaryContainer,
    error: error,
    onError: dark ? const Color(0xff2b0b0b) : Colors.white,
    errorContainer: errorPair.container,
    onErrorContainer: errorPair.onContainer,
    surface: tokens.canvas,
    onSurface: GalleryColorEngine.readable(tokens.onSurface, textSurface),
    onSurfaceVariant: GalleryColorEngine.readable(
      tokens.onSurfaceVariant,
      textSurface,
    ),
    outline: tokens.outlineStrong,
    outlineVariant: tokens.outlineSoft,
    surfaceDim: dark ? tokens.canvas : tokens.surfaceContainerHigh,
    surfaceBright: dark ? tokens.surfaceContainerHigh : tokens.surface,
    surfaceContainerLowest: dark ? tokens.canvas : tokens.surface,
    surfaceContainerLow: tokens.surface,
    surfaceContainer: tokens.surfaceContainer,
    surfaceContainerHigh: tokens.surfaceContainerHigh,
    surfaceContainerHighest: tokens.surfaceContainerHigh,
  );
}
