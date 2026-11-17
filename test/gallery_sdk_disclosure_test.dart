import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  testWidgets('第三方 SDK 披露列出荣耀通透控件信息', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
    controller.showOverlay(GalleryOverlay.sdkDisclosure);
    await tester.pumpAndSettle();

    expect(find.text('Translucent Component Kit'), findsOneWidget);
    expect(find.text('荣耀终端股份有限公司'), findsOneWidget);
    expect(find.text('不涉及'), findsNWidgets(2));
    expect(find.textContaining('sdk-privacy-policy'), findsOneWidget);
    expect(find.textContaining('sdk-security-compliance'), findsOneWidget);
  });
}
