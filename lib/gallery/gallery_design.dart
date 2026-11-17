import 'package:flutter/material.dart';

import 'gallery_color_engine.dart';

enum GalleryElevation { flat, card, floating, modal }

abstract final class GalleryGeometry {
  static const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
}

abstract final class GalleryTypography {
  static const feedback = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );
  static const amount = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
  );
  static const hero = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w600,
  );
  // 卡片详情展开态余额（spec 2.2 §12：display-balance 30px Semibold）。
  static const balance = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w600,
  );
  static const stat = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w600,
  );
  static const lead = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );
  static const page = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );
  static const card = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 15,
    height: 23 / 15,
    fontWeight: FontWeight.w400,
  );
  static const field = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 14,
    height: 21 / 14,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
  );
  static const caption = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
  );
  static const button = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
  );
  static const navigation = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
  );
  static const theme = TextTheme(
    displaySmall: hero,
    headlineMedium: page,
    titleLarge: section,
    titleMedium: card,
    titleSmall: label,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button,
    labelMedium: label,
    labelSmall: caption,
  );
}

/// Journey tickets follow the user's reference rather than the general type scale.
abstract final class GalleryJourneyTypography {
  static const date = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
  );
  static const time = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w400,
  );
  // 单向公交仅记录上车，时间与常规时间同为三号 16dp 且不加粗。
  static const oneWayTime = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w400,
  );
  static const station = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w400,
  );
  static const mode = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w400,
  );
  static const city = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );
  static const amount = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w400,
  );
  static const line = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );
}

@immutable
class GalleryPalette {
  const GalleryPalette(this.id, this.name);
  final String id, name;
  static final values = [
    for (final spec in GalleryThemeSpec.values)
      GalleryPalette(spec.id, spec.name),
  ];
  static GalleryPalette byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => values.first);
  GalleryThemeSpec get spec => GalleryThemeSpec.byId(id);
  GallerySchemeTokens tokens(bool dark) => spec.tokens(dark);
  Color get lightPrimary => spec.light.primary;
  Color get darkPrimary => spec.tokens(true).primary;
  ColorScheme scheme(bool dark) =>
      buildGalleryColorScheme(tokens(dark), dark: dark);
}

/// Card image scrim parameters. Light and dark are tuned independently so the
/// light-theme face stays translucent while the dark-theme look is unchanged
/// (spec 2.5 §4).
@immutable
class GalleryCardImageStyle {
  const GalleryCardImageStyle({
    required this.overlayAlpha,
    required this.textGradientAlpha,
  });
  static const light = GalleryCardImageStyle(
    overlayAlpha: .36,
    textGradientAlpha: .10,
  );
  static const dark = GalleryCardImageStyle(
    overlayAlpha: .60,
    textGradientAlpha: 0,
  );

  /// Uniform scrim over the whole image.
  final double overlayAlpha;

  /// Extra scrim at the top and bottom edges where card text sits; fades to
  /// zero across the middle so the photo keeps its original colour there.
  final double textGradientAlpha;
}

@immutable
class GalleryCardFace {
  const GalleryCardFace(this.id, this.name, this.start, this.end);
  final String id, name;
  final Color start, end;
  static const imageForeground = Colors.white;
  static const imageSecondaryForeground = Color(0xfff7f9fc);
  Color get foreground => const Color(0xff18263a);
  Color get secondaryForeground => const Color(0xff304057);

  /// The more saturated end of the preset gradient is the card's Monet seed
  /// until the user supplies a photo of their own.
  Color get seed => end;
  static const values = [
    GalleryCardFace('blue', '海蓝', Color(0xffc4dff7), Color(0xff8fb8e1)),
    GalleryCardFace('teal', '青玉', Color(0xffb9e5d9), Color(0xff82c7bd)),
    GalleryCardFace('graphite', '鸢紫', Color(0xffdccff0), Color(0xffb7a2d6)),
    GalleryCardFace('amber', '暖铜', Color(0xfff2d7b5), Color(0xffd9ad83)),
  ];
  static GalleryCardFace byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => values.first);
}
