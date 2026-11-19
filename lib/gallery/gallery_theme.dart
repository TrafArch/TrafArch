import 'package:flutter/material.dart';

import 'gallery_color_engine.dart';
import 'gallery_data.dart';
import 'gallery_design.dart';

@immutable
class GalleryTokens extends ThemeExtension<GalleryTokens> {
  GalleryTokens({
    required this.scheme,
    this.dynamic = false,
    this.success,
    this.warning,
    this.elevationDarkness,
    GallerySchemeTokens? roles,
  }) : roles = roles ?? GallerySchemeTokens.fromScheme(scheme);

  final ColorScheme scheme;

  /// Four-layer Canvas / Surface / Surface Container / Outline roles from the
  /// Monet Adaptive Canvas spec. Derived getters below keep the existing
  /// component vocabulary (`bg`, `surface2`, `raised`, `line`) compatible.
  final GallerySchemeTokens roles;
  final bool dynamic;
  final Color? success, warning;
  final double? elevationDarkness;
  double get _depth => elevationDarkness ?? (dark ? 1 : 0);
  double _shadowAlpha(double light, double dark) =>
      light + (dark - light) * _depth;
  bool get dark => scheme.brightness == Brightness.dark;

  /// Level 1: page background. Always the generated or preset Canvas.
  Color get canvas => roles.canvas;
  Color get bg => canvas;

  /// Level 2: content cards, dialogs and floating navigation.
  Color get surface => roles.surface;

  /// Level 3: secondary regions, selected states and auxiliary containers.
  Color get surface2 => roles.surfaceContainer;
  Color get surfaceContainer => roles.surfaceContainer;
  Color get surfaceContainerHigh => roles.surfaceContainerHigh;

  /// Level 4: borders and dividers. Three tiers stay distinct so callers can
  /// choose a soft divider or a structural outline without inventing colors.
  Color get line => roles.outlineSoft;
  Color get outlineSoft => roles.outlineSoft;
  Color get outline => roles.outline;
  Color get outlineStrong => roles.outlineStrong;

  /// Elevated content is still Surface in the new four-layer model; borders and
  /// shadows provide the separation instead of a second background color.
  Color get raised => roles.surface;
  Color get segmentTrack => Color.lerp(surface, surface2, .25)!;
  Color get dockedNavigationSurface => surface;
  Color get feedbackSurface => surface;
  Color get successContainer =>
      Color.alphaBlend(ok.withValues(alpha: .12), surface);
  Color get onSuccessContainer => ok;

  /// Neutrals are checked against the extreme surface once, so every component
  /// that paints text on Canvas, Surface or a container keeps 4.5:1.
  Color get _textSurface => roles.surfaceContainerHigh;
  Color get text => GalleryColorEngine.readable(roles.onSurface, _textSurface);
  Color get muted =>
      GalleryColorEngine.readable(roles.onSurfaceVariant, _textSurface);

  /// Decorative-only muted label (spec §7.1); never use for body text.
  Color get mutedText => roles.mutedText;

  /// Disabled labels use their own neutral instead of fading the active color.
  Color get disabledText =>
      dark ? const Color(0xff697582) : const Color(0xffa6afb8);

  /// Card-face semantic roles (spec 2.5 §3.2). Every list, detail and home
  /// card reads text through these instead of deciding by page.
  Color get cardSurface => surface;
  Color get cardTextPrimary => text;
  Color get cardTextSecondary => muted;
  Color get cardDivider => roles.outlineSoft;
  GalleryCardImageStyle get cardImageStyle =>
      dark ? GalleryCardImageStyle.dark : GalleryCardImageStyle.light;

  Color get tone => roles.primaryContainer;
  Color get onTone => roles.onPrimaryContainer;
  Color get action => roles.primary;
  Color get onAction => roles.onPrimary;
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

  /// Keep scene callers compatible; runtime design data is independent of
  /// fixtures. [monetSeed] is the current home card's effective seed; when it
  /// is null the user's preset (or Indigo by default) provides the tokens.
  static GalleryTokens from(
    GalleryData data,
    bool dark,
    String palette, {
    Color? monetSeed,
  }) => forPalette(palette, dark: dark, monetSeed: monetSeed);

  static GalleryTokens forPalette(
    String palette, {
    required bool dark,
    Color? monetSeed,
  }) {
    final preset = GalleryPalette.byId(palette);
    final roles = monetSeed != null
        ? GalleryColorEngine.tokens(monetSeed, dark: dark)
        : preset.tokens(dark);
    return GalleryTokens(
      scheme: buildGalleryColorScheme(roles, dark: dark),
      dynamic: monetSeed != null,
      roles: roles,
    );
  }

  /// Shadows stay neutral and restrained; they never tint the page with the
  /// action hue. Dark mode replaces light shadows with a 1dp border upstream.
  Color get _shadow =>
      Color.lerp(const Color(0xff14202e), const Color(0xff000000), _depth)!;
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
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabledText : null,
      ),
      textStyle: WidgetStatePropertyAll(GalleryTypography.button),
    );
    final actionButton = flatButton.copyWith(
      shape: const WidgetStatePropertyAll(GalleryGeometry.buttonShape),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
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
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: action, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
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
    GallerySchemeTokens? roles,
    bool? dynamic,
    Color? success,
    Color? warning,
    double? elevationDarkness,
  }) => GalleryTokens(
    scheme: scheme ?? this.scheme,
    roles: roles ?? this.roles,
    dynamic: dynamic ?? this.dynamic,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    elevationDarkness: elevationDarkness ?? this.elevationDarkness,
  );

  /// Value equality keeps ThemeData comparable across rebuilds. Without it,
  /// every controller notification yields a fresh ThemeExtension and
  /// MaterialApp restarts its theme cross-fade, rebuilding every
  /// Theme-dependent widget on each frame of a page transition.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GalleryTokens &&
          other.scheme == scheme &&
          other.roles == roles &&
          other.dynamic == dynamic &&
          other.success == success &&
          other.warning == warning &&
          other.elevationDarkness == elevationDarkness;

  @override
  int get hashCode =>
      Object.hash(scheme, roles, dynamic, success, warning, elevationDarkness);

  @override
  GalleryTokens lerp(covariant GalleryTokens? other, double t) => other == null
      ? this
      : GalleryTokens(
          scheme: ColorScheme.lerp(scheme, other.scheme, t),
          roles: GallerySchemeTokens.lerp(roles, other.roles, t),
          dynamic: t < .5 ? dynamic : other.dynamic,
          success: Color.lerp(ok, other.ok, t),
          warning: Color.lerp(warn, other.warn, t),
          elevationDarkness: _depth + (other._depth - _depth) * t,
        );
}
