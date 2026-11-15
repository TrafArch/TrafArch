import 'package:flutter/material.dart';

import 'gallery_color_engine.dart';
import 'gallery_data.dart';
import 'gallery_design.dart';

@immutable
class GalleryTokens extends ThemeExtension<GalleryTokens> {
  const GalleryTokens({
    required this.scheme,
    this.dynamic = false,
    this.success,
    this.warning,
    this.elevationDarkness,
  });
  final ColorScheme scheme;
  final bool dynamic;
  final Color? success, warning;
  final double? elevationDarkness;
  double get _depth => elevationDarkness ?? (dark ? 1 : 0);
  double _shadowAlpha(double light, double dark) =>
      light + (dark - light) * _depth;
  bool get dark => scheme.brightness == Brightness.dark;
  Color get bg => scheme.surface;
  Color get surface => scheme.surfaceContainerLow;
  Color get surface2 => scheme.surfaceContainerHighest;
  Color get segmentTrack => Color.lerp(surface, surface2, .25)!;
  Color get dockedNavigationSurface => Color.lerp(surface, surface2, .25)!;
  Color get raised => scheme.surfaceContainerHigh;
  Color get feedbackSurface => Color.lerp(surface, raised, .35)!;
  Color get successContainer =>
      Color.alphaBlend(ok.withValues(alpha: .12), surface);
  Color get onSuccessContainer => ok;
  Color get text => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get line => scheme.outlineVariant;
  Color get outline => scheme.outline;
  Color get tone => scheme.primaryContainer;
  Color get onTone => scheme.onPrimaryContainer;
  Color get action => scheme.primary;
  Color get onAction => scheme.onPrimary;
  Color get shanghaiLineOne =>
      Color.lerp(const Color(0xffc92135), const Color(0xffffb3b9), _depth)!;
  Color get onShanghaiLineOne =>
      Color.lerp(const Color(0xffffffff), const Color(0xff650012), _depth)!;
  Color get secondary => scheme.secondary;
  Color get secondaryContainer => scheme.secondaryContainer;
  Color get onSecondaryContainer => scheme.onSecondaryContainer;
  Color get accent => scheme.tertiary;
  Color get accentContainer => scheme.tertiaryContainer;
  Color get onAccentContainer => scheme.onTertiaryContainer;
  Color get control => scheme.primary;
  Color get thumb => scheme.onPrimary;
  Color get danger => scheme.error;
  Color get dangerContainer => scheme.errorContainer;
  Color get onDangerContainer => scheme.onErrorContainer;
  Color get _textSurface => dark ? raised : surface2;
  Color get ok =>
      success ??
      GalleryColorEngine.readable(GallerySemantic.success, _textSurface);
  Color get warn =>
      warning ??
      GalleryColorEngine.readable(GallerySemantic.warning, _textSurface);
  Color get info =>
      GalleryColorEngine.readable(GallerySemantic.info, _textSurface);

  /// Data visualization palette, separate from the UI theme colors (spec 2.2
  /// §5). Category mapping is stable: rail -> data-1, bus -> data-2, other ->
  /// data-3, regardless of the active theme.
  List<Color> get dataPalette =>
      GalleryColorEngine.dataPalette(scheme.primary, dark: dark);
  Color get data1 => dataPalette[0];
  Color get data2 => dataPalette[1];
  Color get data3 => dataPalette[2];
  Color get data4 => dataPalette[3];
  Color get data5 => dataPalette[4];
  Color get chartTrack =>
      GalleryColorEngine.chartTrack(scheme.primary, dark: dark);
  Color get chartSurface => surface;

  /// Trip line badges keep their pre-2.2 colors and do not follow the new
  /// color engine (user exception). Shanghai line 1 keeps its own red below.
  Color get tripBadgeRail =>
      dark ? const Color(0xff2b3658) : const Color(0xffe3e8ff);
  Color get tripBadgeOnRail =>
      dark ? const Color(0xffdce3ff) : const Color(0xff101d50);
  Color get tripBadgeBus =>
      dark ? const Color(0xffbcc8f0) : const Color(0xff101d50);
  Color get tripBadgeOnBus => dark ? const Color(0xff102c4d) : Colors.white;

  /// Keep scene callers compatible; runtime design data is independent of fixtures.
  /// Monet seeds share the preset engine for surfaces, tint and the data
  /// palette. The OS core palette is already UI-safe upstream, so its primary
  /// label pair is preserved as the action color rather than re-clamped.
  static GalleryTokens from(
    GalleryData data,
    bool dark,
    String palette, {
    ColorScheme? dynamicScheme,
  }) => GalleryTokens(
    scheme: dynamicScheme != null
        ? buildGalleryScheme(
            dynamicScheme.primary,
            dark: dark,
            actionOverride: dynamicScheme.primary,
            onActionOverride: dynamicScheme.onPrimary,
          )
        : GalleryPalette.byId(palette).scheme(dark),
    dynamic: dynamicScheme != null,
  );

  Color get _shadow => Color.alphaBlend(
    action.withValues(alpha: .12),
    Color.lerp(const Color(0xff152d4a), const Color(0xff00030a), _depth)!,
  );
  Border? get floatingNavigationBorder => _depth == 0
      ? null
      : Border.all(color: line.withValues(alpha: line.a * _depth));
  List<BoxShadow> get floatingNavigationShadows => _depth == 1
      ? const []
      : [
          BoxShadow(
            color: _shadow.withValues(alpha: .16 * (1 - _depth)),
            offset: const Offset(0, 2),
            blurRadius: 10,
          ),
          BoxShadow(
            color: _shadow.withValues(alpha: .14 * (1 - _depth)),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ];
  List<BoxShadow> shadows(GalleryElevation level) => switch (level) {
    GalleryElevation.flat => const [],
    GalleryElevation.card => [
      BoxShadow(
        color: _shadow.withValues(alpha: _shadowAlpha(.07, .18)),
        offset: const Offset(0, 2),
        blurRadius: 8,
      ),
    ],
    GalleryElevation.floating => [
      BoxShadow(
        color: _shadow.withValues(alpha: _shadowAlpha(.14, .32)),
        offset: const Offset(0, 3),
        blurRadius: 8,
      ),
      BoxShadow(
        color: _shadow.withValues(alpha: _shadowAlpha(.17, .40)),
        offset: const Offset(0, 12),
        blurRadius: 28,
      ),
    ],
    GalleryElevation.modal => [
      BoxShadow(
        color: _shadow.withValues(alpha: _shadowAlpha(.16, .35)),
        offset: const Offset(0, 6),
        blurRadius: 18,
      ),
      BoxShadow(
        color: _shadow.withValues(alpha: _shadowAlpha(.20, .50)),
        offset: const Offset(0, 20),
        blurRadius: 48,
      ),
    ],
  };

  ThemeData theme() {
    final feedback = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) return Colors.transparent;
      if (states.contains(WidgetState.focused)) {
        return action.withValues(alpha: .12);
      }
      if (states.contains(WidgetState.hovered)) {
        return action.withValues(alpha: .04);
      }
      return Colors.transparent;
    });
    final flatButton = ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: feedback,
      splashFactory: NoSplash.splashFactory,
      textStyle: WidgetStatePropertyAll(GalleryTypography.button),
    );
    final actionButton = flatButton.copyWith(
      shape: const WidgetStatePropertyAll(GalleryGeometry.buttonShape),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'sans-serif',
      extensions: [this],
      textTheme: GalleryTypography.theme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      iconTheme: IconThemeData(color: muted, size: 20),
      dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      textButtonTheme: TextButtonThemeData(style: actionButton),
      filledButtonTheme: FilledButtonThemeData(style: actionButton),
      outlinedButtonTheme: OutlinedButtonThemeData(style: actionButton),
      elevatedButtonTheme: ElevatedButtonThemeData(style: actionButton),
      iconButtonTheme: IconButtonThemeData(style: flatButton),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        overlayColor: feedback,
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
  GalleryTokens copyWith({
    ColorScheme? scheme,
    bool? dynamic,
    Color? success,
    Color? warning,
    double? elevationDarkness,
  }) => GalleryTokens(
    scheme: scheme ?? this.scheme,
    dynamic: dynamic ?? this.dynamic,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    elevationDarkness: elevationDarkness ?? this.elevationDarkness,
  );
  @override
  GalleryTokens lerp(covariant GalleryTokens? other, double t) => other == null
      ? this
      : GalleryTokens(
          scheme: ColorScheme.lerp(scheme, other.scheme, t),
          dynamic: t < .5 ? dynamic : other.dynamic,
          success: Color.lerp(ok, other.ok, t),
          warning: Color.lerp(warn, other.warn, t),
          elevationDarkness: _depth + (other._depth - _depth) * t,
        );
}
