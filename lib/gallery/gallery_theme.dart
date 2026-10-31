import 'package:flutter/material.dart';

import 'gallery_data.dart';

@immutable
class GalleryTokens extends ThemeExtension<GalleryTokens> {
  const GalleryTokens({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.text,
    required this.muted,
    required this.line,
    required this.tone,
    required this.onTone,
    required this.action,
    required this.onAction,
    required this.control,
    required this.thumb,
    required this.outline,
  });
  final bool dark;
  final Color bg, surface, surface2, text, muted, line;
  final Color tone, onTone, action, onAction, control, thumb, outline;
  Color get ok => dark ? const Color(0xff4bd08b) : const Color(0xff178a56);
  Color get warn => dark ? const Color(0xffe8b04b) : const Color(0xffa66a12);
  Color get danger => const Color(0xfff06464);

  static GalleryTokens from(GalleryData data, bool dark, String palette) {
    final roles =
        ((data.palettes[palette] as GalleryRecord)[dark ? 'dark' : 'light']
                as List)
            .map(
              (value) => Color(
                int.parse((value as String).replaceFirst('#', 'ff'), radix: 16),
              ),
            )
            .toList();
    return GalleryTokens(
      dark: dark,
      bg: Color(dark ? 0xff0a0d12 : 0xfff2f4f8),
      surface: Color(dark ? 0xff12171f : 0xffffffff),
      surface2: Color(dark ? 0xff171d27 : 0xfff7f9fc),
      text: Color(dark ? 0xfff1f5fb : 0xff15212c),
      muted: Color(dark ? 0xff93a0b4 : 0xff5e6b78),
      line: Color(dark ? 0x16ffffff : 0x1515212c),
      tone: roles[0],
      onTone: roles[1],
      action: roles[2],
      onAction: roles[3],
      control: roles[4],
      thumb: roles[5],
      outline: roles[6],
    );
  }

  ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: onTone,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: onTone,
          onPrimary: bg,
          surface: surface,
          onSurface: text,
          secondaryContainer: tone,
          onSecondaryContainer: onTone,
          outline: outline,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'sans-serif',
      extensions: [this],
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 14.5, height: 1.5, color: text),
        bodySmall: TextStyle(fontSize: 12, height: 1.6, color: muted),
      ),
      iconTheme: IconThemeData(color: muted, size: 20),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? control : surface2,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? thumb : muted,
        ),
      ),
    );
  }

  @override
  GalleryTokens copyWith() => this;
  @override
  GalleryTokens lerp(covariant GalleryTokens? other, double t) =>
      other == null || t < .5 ? this : other;
}
