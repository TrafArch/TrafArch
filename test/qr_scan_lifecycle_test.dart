import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:transit_card_analyzer/features/qr/presentation/qr_scan_page.dart';
import 'package:transit_card_analyzer/app/theme/app_theme.dart';

void main() {
  testWidgets('浅色主题进入黑色扫码页后导航图标变白，返回后恢复', (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = _Camera()..starting.complete(_Camera.attributes);
    MobileScannerPlatform.instance = camera;
    addTearDown(() => MobileScannerPlatform.instance = previous);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemUiOverlayStyle(
            Theme.of(context).scaffoldBackgroundColor,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const QrScanPage()),
                ),
                child: const Text('扫码'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Map<dynamic, dynamic> style() =>
        calls
                .lastWhere(
                  (call) =>
                      call.method == 'SystemChrome.setSystemUIOverlayStyle',
                )
                .arguments
            as Map<dynamic, dynamic>;
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.dark');
    await tester.tap(find.text('扫码'));
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.light');
    expect(style()['statusBarIconBrightness'], 'Brightness.light');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(style()['systemNavigationBarIconBrightness'], 'Brightness.dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('扫码前后台快速切换和权限启动中暂停均恢复相机', (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = _Camera();
    MobileScannerPlatform.instance = camera;
    addTearDown(() => MobileScannerPlatform.instance = previous);
    await tester.pumpWidget(const MaterialApp(home: QrScanPage()));
    await tester.pump();
    expect(camera.starts, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    camera.starting.complete(_Camera.attributes);
    await tester.pump();
    await tester.pump();
    expect(camera.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.starts, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('扫码返回等待相机关闭，失败留在原页并可重试', (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = _Camera()..starting.complete(_Camera.attributes);
    MobileScannerPlatform.instance = camera;
    addTearDown(() => MobileScannerPlatform.instance = previous);
    bool? released;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<List<int>>(
                MaterialPageRoute(
                  builder: (_) =>
                      QrScanPage(onReleased: (value) => released = value),
                ),
              ),
              child: const Text('扫码'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('扫码'));
    await tester.pumpAndSettle();
    expect(camera.starts, 1);
    final stop = camera.stopping = Completer<void>();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(camera.stops, 1);
    expect(released, isNull);
    expect(find.byType(QrScanPage), findsOneWidget);

    stop.completeError(StateError('close failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('相机尚未确认关闭'), findsOneWidget);
    expect(find.byType(QrScanPage), findsOneWidget);
    expect(released, isNull);
    camera.stopping = null;
    await tester.tap(find.text('重试相机'));
    await tester.pumpAndSettle();
    expect(camera.stops, 2);
    expect(released, isTrue);
    expect(find.byType(QrScanPage), findsNothing);
  });

  testWidgets('相机权限启动尚未完成时返回，等待启动与关闭后才离开', (tester) async {
    final previous = MobileScannerPlatform.instance;
    final camera = _Camera();
    MobileScannerPlatform.instance = camera;
    addTearDown(() => MobileScannerPlatform.instance = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<List<int>>(
                MaterialPageRoute(builder: (_) => const QrScanPage()),
              ),
              child: const Text('扫码'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('扫码'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(camera.starts, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(QrScanPage), findsOneWidget);
    expect(camera.stops, 0);
    camera.starting.complete(_Camera.attributes);
    await tester.pumpAndSettle();
    expect(camera.stops, 1);
    expect(find.byType(QrScanPage), findsNothing);
  });
}

class _Camera extends MobileScannerPlatform {
  final starting = Completer<MobileScannerViewAttributes>();
  int starts = 0;
  int stops = 0;
  Completer<void>? stopping;
  static const attributes = MobileScannerViewAttributes(
    cameraDirection: CameraFacing.back,
    currentTorchMode: TorchState.off,
    size: Size(640, 480),
  );
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    return starts == 1 ? starting.future : attributes;
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopping?.future;
  }

  @override
  Future<void> dispose() async {}
}
