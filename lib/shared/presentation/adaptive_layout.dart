import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import 'ui_constants.dart';

/// Main tabs reserve space for the floating navigation at every window size;
/// standalone list/detail routes only need ordinary content padding.
class AdaptiveWindowScope extends InheritedWidget {
  const AdaptiveWindowScope({
    super.key,
    required this.hasFloatingNavigation,
    required super.child,
  });

  final bool hasFloatingNavigation;

  static double bottomClearanceOf(BuildContext context) =>
      context
              .dependOnInheritedWidgetOfExactType<AdaptiveWindowScope>()
              ?.hasFloatingNavigation ==
          false
      ? 24
      : UiConstants.floatingNavBarClearance;

  @override
  bool updateShouldNotify(AdaptiveWindowScope oldWidget) =>
      hasFloatingNavigation != oldWidget.hasFloatingNavigation;
}

/// Bounds the reading surface without changing the identity of its child.
/// Put scrollable content inside this widget, so its viewport is also bounded.
class AdaptiveContent extends StatelessWidget {
  const AdaptiveContent({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// One reading surface stays in a usable sub-screen when a hinge separates
/// the window. Place around a whole page, before AppBar/SafeArea add insets.
class FoldSafePage extends StatelessWidget {
  const FoldSafePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DisplayFeatureSubScreen(
    child: LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: constraints.biggest),
        child: child,
      ),
    ),
  );
}

/// Inline supporting content shares one scroll on compact windows. Wrap keeps
/// both subtrees mounted while switching between stacked and side-by-side.
class AdaptiveSupportingContent extends StatelessWidget {
  const AdaptiveSupportingContent({
    super.key,
    required this.primary,
    required this.secondary,
  });

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final split = constraints.maxWidth >= 840;
      final width = split
          ? (constraints.maxWidth - 24) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          SizedBox(width: width, child: primary),
          SizedBox(width: width, child: secondary),
        ],
      );
    },
  );
}

/// List/detail equivalent of Android's adaptive pane scaffold. Both panes stay
/// mounted; narrowing a selected detail never resets its stream/filters/scroll.
/// A separating vertical fold defines the pane bounds, even below 840dp.
class AdaptiveListDetail extends StatelessWidget {
  const AdaptiveListDetail({
    super.key,
    required this.list,
    required this.detail,
    required this.hasSelection,
    this.onBackToList,
  });

  final Widget list;
  final Widget detail;
  final bool hasSelection;
  final VoidCallback? onBackToList;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final window = Offset.zero & size;
      Rect? hinge;
      for (final feature in MediaQuery.displayFeaturesOf(context)) {
        if ((feature.type == DisplayFeatureType.hinge ||
                feature.state == DisplayFeatureState.postureHalfOpened) &&
            feature.bounds.height >= size.height &&
            feature.bounds.left >= 280 &&
            size.width - feature.bounds.right >= 320) {
          hinge = feature.bounds;
          break;
        }
      }
      // Horizontal tabletop folds, or narrow book panes, use a complete page
      // on one sub-screen rather than placing controls across the fold.
      final whole = DisplayFeatureSubScreen.subScreensInBounds(
        window,
        DisplayFeatureSubScreen.avoidBounds(MediaQuery.of(context))
            .where((bounds) => bounds != hinge),
      ).first;
      final split =
          hinge != null || (whole.width >= 840 && whole.height >= 480);
      final listWidth = math.min(360.0, whole.width * 0.4);
      final listRect = !split
          ? whole
          : Rect.fromLTRB(
              whole.left,
              whole.top,
              hinge?.left ?? whole.left + listWidth,
              whole.bottom,
            );
      final detailRect = !split
          ? whole
          : Rect.fromLTRB(
              hinge?.right ?? whole.left + listWidth + 1,
              whole.top,
              whole.right,
              whole.bottom,
            );
      Widget pane(String name, Rect rect, bool hidden, Widget child) =>
          Positioned.fromRect(
            key: ValueKey(name),
            rect: rect,
            child: Offstage(
              offstage: hidden,
              child: TickerMode(
                enabled: !hidden,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .removeDisplayFeatures(rect)
                      .copyWith(size: rect.size, displayFeatures: const []),
                  child: child,
                ),
              ),
            ),
          );
      return PopScope(
        canPop: split || !hasSelection,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !split && hasSelection) onBackToList?.call();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            pane('list', listRect, !split && hasSelection, list),
            if (split && hinge == null)
              Positioned(
                left: whole.left + listWidth,
                top: whole.top,
                height: whole.height,
                child: const VerticalDivider(width: 1),
              ),
            pane('detail', detailRect, !split && !hasSelection, detail),
          ],
        ),
      );
    },
  );
}
