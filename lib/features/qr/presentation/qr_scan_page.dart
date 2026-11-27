import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/qr_barcode_payload.dart';
import '../../../shared/presentation/adaptive_layout.dart';

/// 保留二进制载荷，通过 Navigator.pop 返回原始字节而非解码文本。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key, this.onReleased});
  final ValueChanged<bool>? onReleased;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );

  /// 防止 onDetect 连续多帧回调重复触发返回。
  bool _handled = false;
  bool _cameraWanted = true;
  bool _finishing = false;
  bool _stopFailed = false;
  List<int>? _pendingPayload;
  Object? _cameraError;
  Future<void> _cameraWork = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraWanted =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;
    _syncCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cameraWanted = state == AppLifecycleState.resumed;
    _syncCamera();
  }

  void _syncCamera() {
    // Serialize stop/start when focus changes rapidly during fold or multiwindow.
    _cameraWork = _cameraWork.then((_) async {
      if (!mounted || _handled) return;
      try {
        if (_stopFailed || !_cameraWanted) await _stopCamera();
        if (_cameraWanted) {
          await _controller.start();
          if (!_cameraWanted && !_handled) await _stopCamera();
        }
        if (mounted && _cameraError != null) {
          setState(() => _cameraError = null);
        }
      } on Object catch (error) {
        // A lost camera may fail stop as well as start. Keep the operation queue
        // usable and provide a retry instead of leaving an unhandled Future.
        if (mounted) setState(() => _cameraError = error);
      }
    });
  }

  Future<void> _stopCamera() async {
    try {
      if (_stopFailed) {
        if (Platform.isAndroid) {
          await const MethodChannel(
            'dev.steenbakker.mobile_scanner/scanner/method',
          ).invokeMethod<void>('stop', {'force': true});
        } else {
          await MobileScannerPlatform.instance.stop();
        }
      } else {
        await _controller.stop();
      }
      _stopFailed = false;
    } catch (_) {
      _stopFailed = true;
      rethrow;
    }
  }

  Future<void> _releaseAfterUnmount(ValueChanged<bool>? callback) async {
    var closed = false;
    try {
      await _cameraWork;
      await _stopCamera();
      closed = true;
    } catch (_) {
      closed = false;
    } finally {
      try {
        await _controller.dispose();
      } catch (_) {
        closed = false;
      }
      callback?.call(closed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseAfterUnmount(widget.onReleased));
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final payload = qrPayloadOfBarcodes(capture.barcodes);
    if (!_handled && payload != null && payload.isNotEmpty) {
      unawaited(_finish(payload));
    }
  }

  Future<void> _finish(List<int>? payload) async {
    if (_finishing || !mounted) return;
    setState(() {
      _finishing = true;
      _handled = true;
      _pendingPayload = payload;
      _cameraError = null;
    });
    try {
      await _cameraWork;
      await _stopCamera();
      if (mounted) Navigator.of(context).pop<List<int>>(payload);
    } catch (_) {
      if (mounted) {
        setState(() {
          _finishing = false;
          _cameraError = '相机尚未确认关闭，请重试。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: true,
      ),
      child: PopScope<List<int>>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_finish(null));
        },
        child: FoldSafePage(
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              leading: BackButton(
                onPressed: _finishing ? null : () => _finish(null),
              ),
              title: const Text('扫描乘车码（JT/T 1179）'),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: '闪光灯',
                  onPressed: _handled ? null : () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on_outlined),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) =>
                        _ScanErrorView(error: error, onRetry: _syncCamera),
                    overlayBuilder: (context, constraints) =>
                        const _ScanOverlay(),
                  ),
                  if (_cameraError case final error?)
                    ColoredBox(
                      color: Colors.black,
                      child: _ScanErrorView(
                        error: error,
                        onRetry: _handled
                            ? () => _finish(_pendingPayload)
                            : _syncCamera,
                      ),
                    ),
                  if (_finishing)
                    const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: '正在关闭相机',
                      ),
                    ),
                  const Positioned(
                    left: 24,
                    right: 24,
                    bottom: 48,
                    child: Text(
                      '将乘车码二维码对准取景框',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 取景框遮罩：中间透明方框，便于对准二维码。
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide * 0.7;
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 相机 / 权限错误占位：提示从相册导入兜底。
class _ScanErrorView extends StatelessWidget {
  const _ScanErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                '相机不可用：$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('重试相机')),
              const Text(
                '请检查相机权限后重试。也可用系统相机拍下二维码后，'
                '返回扫码页点击「从相册导入」进行识别',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
