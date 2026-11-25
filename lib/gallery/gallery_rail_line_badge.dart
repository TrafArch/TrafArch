part of 'gallery_app.dart';

class _GalleryRailLineCatalogScope extends InheritedWidget {
  const _GalleryRailLineCatalogScope({
    required this.catalog,
    required super.child,
  });

  final GalleryRailLineCatalog catalog;

  static GalleryRailLineCatalog? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GalleryRailLineCatalogScope>()
      ?.catalog;

  @override
  bool updateShouldNotify(_GalleryRailLineCatalogScope oldWidget) =>
      catalog != oldWidget.catalog;
}

class _GalleryRailLineBadge extends StatelessWidget {
  const _GalleryRailLineBadge({
    super.key,
    required this.line,
    this.cityCode,
    this.cityName,
    this.citySystem,
  });

  final String line;
  final String? cityCode;
  final String? cityName;
  final String? citySystem;

  Widget _label(Color background, Color foreground) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        line,
        style: GalleryJourneyTypography.line.copyWith(color: foreground),
      ),
    ),
  );

  Widget _coloredLabel(Color background) {
    final luminance = background.computeLuminance() + .05;
    final foreground = luminance / .05 >= 1.05 / luminance
        ? Colors.black
        : Colors.white;
    return _label(background, foreground);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    final neutral = _label(tokens.tripBadgeRail, tokens.tripBadgeOnRail);
    if (cityCode == null && cityName == null) return neutral;
    final catalog = _GalleryRailLineCatalogScope.of(context);
    if (catalog == null) return neutral;
    final code = catalog.tuCode(cityCode, cityName, citySystem);
    if (code == null) return neutral;
    final label = catalog.lineKey(code, line);
    Widget fallback() {
      final approved = catalog.approvedColor(code, label);
      if (approved != null) return _coloredLabel(approved);
      if (code == '2900' && label == '1号线') {
        return _label(tokens.shanghaiLineOne, tokens.onShanghaiLineOne);
      }
      final color = catalog.paletteColor(code, label);
      return color == null ? neutral : _coloredLabel(color);
    }

    final icon = catalog.icon(code, label);
    if (icon == null) return fallback();
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width = math.min(
          math.min(60 * scale, constraints.maxWidth),
          24 * scale * icon.aspectRatio,
        );
        final height = width / icon.aspectRatio;
        return Semantics(
          label: line,
          image: true,
          child: ExcludeSemantics(
            child: SvgPicture.asset(
              icon.path,
              width: width,
              height: height,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => fallback(),
            ),
          ),
        );
      },
    );
  }
}
