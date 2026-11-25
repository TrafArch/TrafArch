import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void mockGalleryWallpaper(WidgetTester tester, Color? Function() seed) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (call) async {
    expect(call.method, DynamicColorPlugin.methodName);
    final color = seed();
    return color == null ? null : (Int32List(65)..[4] = color.toARGB32());
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null);
  });
}
