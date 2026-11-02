import 'package:flutter/material.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/app/navigation/app_shell.dart';
import 'package:transit_card_analyzer/app/navigation/floating_nav_bar.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  testWidgets('从扫码解析等子页面返回后底栏回到可见态', (tester) async {
    final app = AppDependencies(
      database: testDatabase(),
      settingsStore: MemorySettingsStore(),
      bundle: MissingTestAssets(),
      channel: _NoopNfcChannel(),
    );
    await tester.runAsync(app.init);
    final observer = RouteObserver<PageRoute<dynamic>>();
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

    // 模拟底栏在进入扫码页前已被滚出屏幕：只剩“回到顶部”圆钮。
    bar.hide();
    await tester.pumpAndSettle();
    expect(bar.isVisible, isFalse);
    final hiddenTop = tester.getTopLeft(find.byType(FloatingNavBar)).dy;
    expect(hiddenTop, greaterThan(restingTop));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('扫码解析'))),
      ),
    );
    await tester.pumpAndSettle();

    navigator.pop();
    // 逐帧采样回显过程：必须走弹簧动画，而不是瞬间跳到终态
    // （壳页被不透明路由覆盖时 Ticker 被静音，静音期间 elapsed 会跳变）。
    final frames = <double>[];
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(tester.getTopLeft(find.byType(FloatingNavBar)).dy);
    }
    await tester.pumpAndSettle();

    // 返回壳页后必须重新回显，而不是停在被隐藏的终态。
    expect(bar.isVisible, isTrue);
    expect(tester.getTopLeft(find.byType(FloatingNavBar)).dy, restingTop);
    // 至少有一帧停在隐藏位置与静止位置之间：说明回显带过渡帧。
    expect(
      frames.any((top) => top > restingTop + 0.5 && top < hiddenTop - 0.5),
      isTrue,
      reason: '返回壳页后底栏应带过渡动画回显，实际采样：$frames',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    bar.dispose();
    app.dispose();
  });
}

class _NoopNfcChannel implements NfcChannel {
  @override
  Future<NfcScanResult?> scanOnce() async => null;
  @override
  Future<void> stopScan() async {}
  @override
  Future<List<int>> transceive(List<int> apdu) async => const [0x6A, 0x82];
}
