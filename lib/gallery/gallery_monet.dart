import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, instantiateImageCodec;

import 'package:flutter/material.dart';

import 'gallery_color_engine.dart';

/// Extracts a Monet seed from the current card face image.
///
/// The sampled image is decoded at a bounded width, so the histogram walks a
/// few thousand pixels instead of the full photo. Near-white and near-black
/// pixels are ignored, and hue buckets weighted by chroma keep a single strong
/// accent from being averaged away by a neutral background. When no usable
/// pixel remains (blank or fully transparent image) the caller falls back to
/// the preset theme.
abstract final class GalleryMonet {
  /// Bump when the sampling or normalization changes; cached seeds should be
  /// discarded when this value changes.
  static const algorithmVersion = 1;

  static Future<Color?> seedFromImage(Uint8List bytes) async {
    try {
      final codec = await instantiateImageCodec(
        bytes,
        targetWidth: 96,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ImageByteFormat.rawRgba,
          );
          if (data == null) return null;
          return seedFromRgba(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            width: frame.image.width,
            height: frame.image.height,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // Unknown codec, plugin or allocation failure: keep the previous theme.
      return null;
    }
  }

  /// Pure sampling entry point used by tests and by [seedFromImage].
  static Color? seedFromRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return null;
    }
    final buckets = List<_HueBucket>.generate(12, (_) => _HueBucket());
    for (var i = 0; i < width * height; i++) {
      final offset = i * 4;
      if (rgba[offset + 3] < 128) continue;
      final color = Color.from(
        alpha: 1,
        red: rgba[offset] / 255,
        green: rgba[offset + 1] / 255,
        blue: rgba[offset + 2] / 255,
      );
      final sample = GalleryColorEngine.oklch(color);
      if (sample.l > .97 || sample.l < .05) continue;
      final weight = .05 + sample.c * 8;
      final index = (sample.h / 30).floor() % 12;
      buckets[index].add(sample.l, sample.c, sample.h, weight);
    }

    _HueBucket? best;
    for (final bucket in buckets) {
      if (bucket.weight <= 0) continue;
      if (best == null || bucket.weight > best.weight) best = bucket;
    }
    if (best == null) return null;

    if (best.chroma < .008) {
      // Low-chroma images are valid: generate the neutral Mist-like canvas.
      return GalleryColorEngine.color(best.lightness.clamp(.45, .75), 0, 0);
    }
    return GalleryColorEngine.color(
      best.lightness.clamp(.38, .72),
      best.chroma.clamp(.02, .18),
      best.hue,
    );
  }
}

class _HueBucket {
  double weight = 0;
  double _lightness = 0;
  double _chroma = 0;
  double _x = 0;
  double _y = 0;

  void add(double lightness, double chroma, double hue, double weight) {
    this.weight += weight;
    _lightness += lightness * weight;
    _chroma += chroma * weight;
    final radians = hue * math.pi / 180;
    _x += math.cos(radians) * weight;
    _y += math.sin(radians) * weight;
  }

  double get lightness => _lightness / weight;
  double get chroma => _chroma / weight;
  double get hue {
    var degrees = math.atan2(_y, _x) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    return degrees;
  }
}
