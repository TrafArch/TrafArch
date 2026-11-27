import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/shared/presentation/adaptive_layout.dart';

const _states = [
  ui.DisplayFeatureState.unknown,
  ui.DisplayFeatureState.postureFlat,
  ui.DisplayFeatureState.postureHalfOpened,
];

void main() {
  for (final horizontal in [false, true]) {
    testWidgets('完整页面忽略${horizontal ? '横向' : '竖向'}折痕及半折姿态，保留完整窗口和安全区', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 800);
      const insets = EdgeInsets.fromLTRB(24, 32, 16, 48);
      MediaQueryData? pageMedia;
      for (final state in _states) {
        // Some devices report a non-zero crease even though it covers no pixels.
        for (final thickness in [0.0, 20.0]) {
          final crease = horizontal
              ? Rect.fromLTWH(0, 390, 1000, thickness)
              : Rect.fromLTWH(490, 0, thickness, 800);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(1000, 800),
                  padding: insets,
                  viewPadding: insets,
                  displayFeatures: [
                    ui.DisplayFeature(
                      bounds: crease,
                      type: ui.DisplayFeatureType.fold,
                      state: state,
                    ),
                  ],
                ),
                child: FoldSafePage(
                  child: Builder(
                    builder: (context) {
                      pageMedia = MediaQuery.of(context);
                      return const SizedBox.expand(key: ValueKey('whole-page'));
                    },
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('whole-page'))),
            const Rect.fromLTWH(0, 0, 1000, 800),
          );
          expect(pageMedia!.size, const Size(1000, 800));
          expect(pageMedia!.padding, insets);
          expect(pageMedia!.displayFeatures, isEmpty);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
