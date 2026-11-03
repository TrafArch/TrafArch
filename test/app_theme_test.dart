import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/theme/app_theme.dart';

void main() {
  test('关闭莫奈取色时回落到图标蓝而非旧的内置青绿', () {
    expect(AppTheme.seedColor, const Color(0xFF4E7098));

    for (final scheme in [AppTheme.fallbackLight, AppTheme.fallbackDark]) {
      final hue = HSLColor.fromColor(scheme.primary).hue;
      // 图标灰蓝的色相在 214° 附近（旧的内置青绿 teal 为 174°）。
      expect(hue, inInclusiveRange(195, 260));
    }

    expect(AppTheme.fallbackLight.brightness, Brightness.light);
    expect(AppTheme.fallbackDark.brightness, Brightness.dark);
    expect(AppTheme.light(null).colorScheme, same(AppTheme.fallbackLight));
    expect(AppTheme.dark(null).colorScheme, same(AppTheme.fallbackDark));
  });
}
