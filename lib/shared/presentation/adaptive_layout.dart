import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';

/// Folded/unfolded layouts follow the active window's size. A crease or its
/// posture never creates a separate book/tabletop layout, including in routes
/// and modal overlays. Keep only display features that physically cover pixels.
class FoldableDisplayScope extends StatelessWidget {
  const FoldableDisplayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        displayFeatures: mediaQuery.displayFeatures
            .where(
              (feature) =>
                  feature.type != DisplayFeatureType.fold &&
                  feature.bounds.shortestSide > 0,
            )
            .toList(),
      ),
      child: child,
    );
  }
}

/// One reading surface stays in a usable sub-screen when a hinge separates
/// the window. Place around a whole page, before AppBar/SafeArea add insets.
class FoldSafePage extends StatelessWidget {
  const FoldSafePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => FoldableDisplayScope(
    child: DisplayFeatureSubScreen(
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: constraints.biggest),
          child: child,
        ),
      ),
    ),
  );
}
