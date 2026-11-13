import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shared/presentation/adaptive_layout.dart';

/// Geometry belongs to the current Flutter window, never the physical display.
@immutable
class GalleryWindowLayout {
  GalleryWindowLayout(MediaQueryData media) : bounds = _largestPane(media);

  static const readingWidth = 720.0;
  final Rect bounds;

  static Rect _largestPane(MediaQueryData media) {
    final panes = DisplayFeatureSubScreen.subScreensInBounds(
      Offset.zero & media.size,
      DisplayFeatureSubScreen.avoidBounds(media),
    ).where((rect) => !rect.isEmpty).toList();
    panes.sort((a, b) {
      final area = (b.width * b.height).compareTo(a.width * a.height);
      if (area != 0) return area;
      final left = a.left.compareTo(b.left);
      return left != 0 ? left : a.top.compareTo(b.top);
    });
    return panes.isEmpty ? Offset.zero & media.size : panes.first;
  }
}

/// Keep Navigator, its barriers, and all route overlays in the same sub-screen.
/// The wrapper and child keep their identity when the window changes shape.
class GalleryWindow extends StatelessWidget {
  const GalleryWindow({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => FoldableDisplayScope(
    child: Builder(
      builder: (context) {
        final media = MediaQuery.of(context);
        final rect = GalleryWindowLayout(media).bounds;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            rect.left,
            rect.top,
            media.size.width - rect.right,
            media.size.height - rect.bottom,
          ),
          child: MediaQuery(
            data: media.removeDisplayFeatures(rect).copyWith(size: rect.size),
            child: SizedBox.expand(
              key: const ValueKey('gallery-safe-window'),
              child: child,
            ),
          ),
        );
      },
    ),
  );
}

class GalleryReadingSurface extends StatelessWidget {
  const GalleryReadingSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: GalleryWindowLayout.readingWidth,
      ),
      child: child,
    ),
  );
}

/// Root coordinate space: Scaffold handles IME; only remaining safe area is added.
@immutable
class GalleryNavigationLayout {
  GalleryNavigationLayout(MediaQueryData media, {required this.docked})
    : safeBottom = math.max(
        0,
        media.viewPadding.bottom - media.viewInsets.bottom,
      ),
      extraHeight = math.max(0, media.textScaler.scale(14) / 14 - 1) * 20,
      _safeTop = math.max(media.padding.top, media.viewPadding.top),
      _titleRow = math.max(44.0, media.textScaler.scale(32)),
      _compactTitle =
          media.size.height - math.max(media.padding.top, media.viewPadding.top) <
          480;
  final bool docked;
  final double safeBottom, extraHeight;
  final double _safeTop, _titleRow;
  final bool _compactTitle;
  double get contentHeight => (docked ? 65 : 62) + extraHeight;
  double get gap => docked ? (safeBottom > 0 ? 8 : 0) : 18;
  double get bottomSpace => safeBottom + gap;
  double get occupiedHeight => contentHeight + bottomSpace;
  double get listBottom => occupiedHeight + 16;
  double get toastBottom => occupiedHeight + 12;

  /// Feedback sits just below the page title band, not over the title itself.
  double feedbackTop({required bool mainPage}) {
    final headerPadding = mainPage ? (_compactTitle ? 16.0 : 32.0) : 26.0;
    return _safeTop + _titleRow + headerPadding + 8;
  }
}
