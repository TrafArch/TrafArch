import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import 'jt_t1179_qr_display.dart';
import 'qr_acquire.dart';
import 'qr_inspection_panel.dart';

class QrPage extends StatefulWidget {
  const QrPage({super.key, required this.app});

  final AppDependencies app;

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  bool _busy = false;

  Future<void> _acquire({required bool gallery}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (gallery) {
        await importQrFromGalleryAndParse(context, widget.app);
      } else {
        await scanQrAndParse(context, widget.app);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: const Text('乘车码解析')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: app,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _acquire(gallery: false),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('扫描二维码'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _acquire(gallery: true),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册导入'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              if (app.qrData == null &&
                  app.qrError == null &&
                  app.qrRaw == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    '尚未获取二维码\n扫描二维码或从相册导入，查看 JT/T 1179 乘车码读取信息',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                QrInspectionPanel(
                  qr: app.qrData,
                  error: app.qrError,
                  raw: app.qrRaw,
                  issuerName:
                      app
                          .cardPrefixByIssuerId(app.qrData?.issuerIdText)
                          ?.cardName ??
                      '未知',
                  onClear: app.clearQr,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
