import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/app_shell.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/app/navigation/recovery_route_observer.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  // 读卡完成后弹出的保存卡片对话框是 DialogRoute（非 PageRoute）。历史上
  // 观察器以 PageRoute 为泛型，RouteObserver.didPop 的 `route is R` 判定不
  // 成立，壳页收不到 didPopNext，底栏卡在隐藏态、只剩"回到顶部"圆钮。
  for (final size in [const Size(390, 800), const Size(1182, 836)]) {
    testWidgets('窗口 $size 关闭保存对话框后底栏带过渡动画回显', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppDependencies(
        database: testDatabase(),
        settingsStore: MemorySettingsStore(),
        bundle: MissingTestAssets(),
        channel: _NoopNfcChannel(),
      );
      await tester.runAsync(app.init);
      final observer = RecoveryRouteObserver(app);
      final bar = BottomBarController();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: AppShell(
            app: app,
            routeObserver: observer,
            bottomBarController: bar,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final restingTop = tester.getTopLeft(find.byType(FloatingNavBar)).dy;
      expect(bar.isVisible, isTrue);

      // 模拟读卡结果出现前底栏已被滚出屏幕：只剩"回到顶部"圆钮。
      bar.hide();
      await tester.pumpAndSettle();
      expect(bar.isVisible, isFalse);
      final hiddenTop = tester.getTopLeft(find.byType(FloatingNavBar)).dy;
      expect(hiddenTop, greaterThan(restingTop));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        DialogRoute<void>(
          context: tester.element(find.byType(AppShell)),
          builder: (_) => const AlertDialog(title: Text('保存卡片')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存卡片'), findsOneWidget);

      navigator.pop();
      // 逐帧采样回显过程：必须走弹簧动画，而不是瞬间跳到终态。
      final frames = <double>[];
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        frames.add(tester.getTopLeft(find.byType(FloatingNavBar)).dy);
      }
      await tester.pumpAndSettle();

      expect(bar.isVisible, isTrue, reason: '关闭保存对话框后底栏卡在隐藏态');
      expect(tester.getTopLeft(find.byType(FloatingNavBar)).dy, restingTop);
      expect(
        frames.any((top) => top > restingTop + 0.5 && top < hiddenTop - 0.5),
        isTrue,
        reason: '关闭对话框后底栏应带过渡动画回显，实际采样：$frames',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      bar.dispose();
      app.dispose();
    });
  }
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}