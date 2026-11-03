import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Root coordinate space: Scaffold handles IME; only remaining safe area is added.
@immutable
class GalleryNavigationLayout {
  GalleryNavigationLayout(MediaQueryData media, {required this.docked})
    : safeBottom = math.max(
        0,
        media.viewPadding.bottom - media.viewInsets.bottom,
      ),
      extraHeight = math.max(0, media.textScaler.scale(14) / 14 - 1) * 20;
  final bool docked;
  final double safeBottom, extraHeight;
  double get contentHeight => (docked ? 64 : 62) + extraHeight;
  double get gap => docked ? (safeBottom > 0 ? 8 : 0) : 18;
  double get bottomSpace => safeBottom + gap;
  double get occupiedHeight => contentHeight + bottomSpace;
  double get listBottom => occupiedHeight + 16;
  double get toastBottom => occupiedHeight + 12;
}
