import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_dart_decoder.dart';
import 'qr_image_picker.dart';

/// 二维码扫描页：读取二维码内的原始二进制数据（8 bit byte 模式），
/// 通过 [Navigator.pop] 返回 `List<int>`；返回（取消）时结果为 null。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );

  /// 防止 onDetect 连续多帧回调重复触发返回。
  bool _handled = false;

  /// 相册导入进行中（选图 / 图片识别），用于禁用按钮并展示进度。
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    _handleBarcodes(capture.barcodes);
  }

  /// 统一处理识别结果（相机流 / 相册图片共用）：
  /// 优先取原始二进制（JT/T 1179 为 8 bit byte 模式，文本值会损坏数据），
  /// 兜底按 ISO-8859-1 还原文本字节。
  void _handleBarcodes(List<Barcode> barcodes) {
    if (_handled || !mounted) return;
    for (final barcode in barcodes) {
      final raw = barcode.rawDecodedBytes;
      if (raw is DecodedBarcodeBytes && raw.bytes.isNotEmpty) {
        _finishWithPayload(raw.bytes.toList());
        return;
      }
      final text = barcode.rawValue;
      if (text != null && text.isNotEmpty) {
        try {
          _finishWithPayload(latin1.encode(text));
          return;
        } catch (_) {
          // 文本含非 ISO-8859-1 字符：忽略本次结果，继续扫描
        }
      }
    }
  }

  /// 统一返回解码字节（相机 / MLKit / 内置解码共用），仅生效一次。
  void _finishWithPayload(List<int> payload) {
    if (_handled || !mounted || payload.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop<List<int>>(payload);
  }

  /// 从相册导入：原生相册选图 → MLKit 识别；
  /// MLKit 不可用（无 Google Play 服务 / 无法联网 / 模型未下载）或未识别时，
  /// 降级为内置纯 Dart 解码。
  Future<void> _pickFromGallery() async {
    if (_handled || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await pickQrImageFromGallery();
      if (!mounted) return;
      if (path == null) return; // 用户取消

      var mlkitUnavailable = false;
      BarcodeCapture? capture;
      try {
        capture = await _controller.analyzeImage(
          path,
          formats: const [BarcodeFormat.qrCode],
        );
      } catch (_) {
        mlkitUnavailable = true;
      }
      if (!mounted) return;
      final barcodes = capture?.barcodes ?? const <Barcode>[];
      if (barcodes.isNotEmpty) {
        _handleBarcodes(barcodes);
        return;
      }

      final payload = await decodeQrFromImageFile(path);
      if (!mounted) return;
      if (payload != null && payload.isNotEmpty) {
        _finishWithPayload(payload);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mlkitUnavailable
                ? 'MLKit 不可用（Google Play 服务缺失或无法联网），内置解码也未识别到二维码'
                : '未在该图片中识别到二维码',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('从相册导入失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描乘车码（JT/T 1179）'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScanErrorView(error: error),
            overlayBuilder: (context, constraints) => const _ScanOverlay(),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '将乘车码二维码对准取景框，或从相册导入二维码图片',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _pickFromGallery,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(_busy ? '正在识别…' : '从相册导入'),
                ),
              ],
            ),
          ),
        ],
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

/// 相机 / 权限错误占位：提示改用「手动输入」兜底。
class _ScanErrorView extends StatelessWidget {
  const _ScanErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              '相机不可用：$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '请检查相机权限后重试。若因 Google Play 服务不可用或无法联网导致识别失效，'
              '可用系统相机拍下二维码后点击下方「从相册导入」，返回后也可手动输入',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),

          ],
        ),
      ),
    );
  }
}