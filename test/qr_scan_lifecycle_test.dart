import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:transit_card_analyzer/features/qr/presentation/qr_scan_page.dart';

void main() {
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
}

class _Camera extends MobileScannerPlatform {
  final starting = Completer<MobileScannerViewAttributes>();
  int starts = 0;
  int stops = 0;
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
  }

  @override
  Future<void> dispose() async {}
}
