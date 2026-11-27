import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/internal_preview_app.dart';
import 'package:transit_card_analyzer/features/updates/update_prompt.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/gallery_scroll.dart';

void main() {
  testWidgets('样例直接进入 2.x，重建后保留预测性返回偏好', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemorySettingsStore();
    final toggle = find.widgetWithText(SwitchListTile, '预测性返回手势');

    Future<void> openPreviewSettings() async {
      await tester.pumpWidget(InternalPreviewApp(previewSettingsStore: store));
      await tester.pumpAndSettle();
      final gallery = tester.widget<GalleryApp>(find.byType(GalleryApp));
      expect(gallery.liveApp, isNull);
      expect(find.byType(UpdatePrompt), findsNothing);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        toggle,
        250,
        scrollable: galleryVerticalScroll(),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('备用界面', skipOffstage: false), findsNothing);
    }

    await openPreviewSettings();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.values[SettingsKeys.galleryPredictiveBackEnabled], 'false');
    await tester.pumpWidget(const SizedBox.shrink());

    await openPreviewSettings();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });
}
