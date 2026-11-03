import 'package:flutter/material.dart';

enum GalleryElevation { flat, card, floating, modal }

abstract final class GalleryGeometry {
  static const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
}

abstract final class GalleryTypography {
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

@immutable
class GalleryPalette {
  const GalleryPalette(this.id, this.name, this.lightPrimary, this.darkPrimary);
  final String id, name;
  final Color lightPrimary, darkPrimary;
  static const values = [
    GalleryPalette('blue', '靛蓝', Color(0xff101d50), Color(0xffbcc8f0)),
    GalleryPalette('teal', '青绿', Color(0xff087f78), Color(0xff8ed2c5)),
    GalleryPalette('violet', '藤紫', Color(0xff7551a8), Color(0xffd1bbee)),
    GalleryPalette('rose', '蔷薇', Color(0xffa64470), Color(0xffedb9cd)),
    GalleryPalette('amber', '麦金', Color(0xff9e640a), Color(0xffe5c07b)),
  ];
  static GalleryPalette byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => values.first);
  ColorScheme scheme(bool dark) {
    final generated = ColorScheme.fromSeed(
      seedColor: lightPrimary,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return generated.copyWith(
      primary: dark ? darkPrimary : lightPrimary,
      onPrimary: dark ? const Color(0xff102c4d) : Colors.white,
      primaryContainer: id == 'blue'
          ? Color(dark ? 0xff2b3658 : 0xffe3e8ff)
          : generated.primaryContainer,
      onPrimaryContainer: id == 'blue'
          ? Color(dark ? 0xffdce3ff : 0xff101d50)
          : generated.onPrimaryContainer,
      secondary: Color(dark ? 0xff8ed2c5 : 0xff087f78),
      onSecondary: Color(dark ? 0xff003831 : 0xffffffff),
      secondaryContainer: Color(dark ? 0xff163d38 : 0xffdef3ec),
      onSecondaryContainer: Color(dark ? 0xffb4eddb : 0xff145747),
      tertiary: Color(dark ? 0xffe5c07b : 0xff9e640a),
      onTertiary: Color(dark ? 0xff3c2b0b : 0xffffffff),
      tertiaryContainer: Color(dark ? 0xff463820 : 0xffffedce),
      onTertiaryContainer: Color(dark ? 0xfff4d59b : 0xff76500d),
      surface: Color(dark ? 0xff0c1119 : 0xfff1f4f9),
      surfaceDim: Color(dark ? 0xff0c1119 : 0xffdee6f0),
      surfaceBright: Color(dark ? 0xff2e3e53 : 0xffffffff),
      surfaceContainerLowest: Color(dark ? 0xff101722 : 0xffe8eef6),
      surfaceContainerLow: Color(dark ? 0xff151e2b : 0xffffffff),
      surfaceContainer: Color(dark ? 0xff1b2636 : 0xffeef3f9),
      surfaceContainerHigh: Color(dark ? 0xff223047 : 0xfff7faff),
      surfaceContainerHighest: Color(dark ? 0xff101722 : 0xffe8eef6),
      onSurface: Color(dark ? 0xffe8eef7 : 0xff18263a),
      onSurfaceVariant: Color(dark ? 0xffa6b4c7 : 0xff58687c),
      outline: Color(dark ? 0xff75859c : 0xff748398),
      outlineVariant: Color(dark ? 0xff3d4e65 : 0xffcdd8e6),
      error: Color(dark ? 0xffffb4ab : 0xffba1a1a),
      onError: Color(dark ? 0xff690005 : 0xffffffff),
      errorContainer: Color(dark ? 0xff502126 : 0xffffe9e7),
      onErrorContainer: Color(dark ? 0xffffdad6 : 0xff8e1414),
    );
  }
}

@immutable
class GalleryCardFace {
  const GalleryCardFace(this.id, this.name, this.start, this.end);
  final String id, name;
  final Color start, end;
  Color get foreground => Colors.white;
  Color get secondaryForeground => const Color(0xfff7f9fc);
  static const values = [
    GalleryCardFace('blue', '海蓝', Color(0xff2463ad), Color(0xff153b67)),
    GalleryCardFace('teal', '青玉', Color(0xff187e80), Color(0xff17444a)),
    GalleryCardFace('graphite', '鸢紫', Color(0xff7564a5), Color(0xff3e355d)),
    GalleryCardFace('amber', '暖铜', Color(0xff9a6532), Color(0xff563a2a)),
  ];
  static GalleryCardFace byId(String id) =>
      values.firstWhere((p) => p.id == id, orElse: () => values.first);
}
