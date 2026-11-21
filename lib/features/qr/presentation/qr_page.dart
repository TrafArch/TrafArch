import 'package:flutter/material.dart';

import '../../../shared/presentation/adaptive_layout.dart';

import '../../../app/app_dependencies.dart';
import 'jt_t1179_qr_display.dart';
import 'qr_acquire.dart';
import 'qr_inspection_panel.dart';

class QrPage extends StatelessWidget {
  const QrPage({super.key, required this.app});

  final AppDependencies app;

  @override
  Widget build(BuildContext context) => FoldSafePage(
    child: Scaffold(
      appBar: AppBar(title: const Text('乘车码解析')),
      body: AdaptiveContent(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              QrReadContent(
                app: app,
                canPublish: () => ModalRoute.of(context)?.isCurrent ?? true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class QrReadContent extends StatelessWidget {
  const QrReadContent({
    super.key,
    required this.app,
    this.onNotice,
    this.canPublish,
  });
  final AppDependencies app;
  final void Function(String message, bool failed)? onNotice;
  final bool Function()? canPublish;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: app.qrAcquiring
                  ? null
                  : () => scanQrAndParse(
                      context,
                      app,
                      onNotice: onNotice,
                      canPublish: canPublish,
                    ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫描二维码'),
            ),
            OutlinedButton.icon(
              onPressed: app.qrAcquiring
                  ? null
                  : () => importQrFromGalleryAndParse(
                      context,
                      app,
                      onNotice: onNotice,
                      canPublish: canPublish,
                    ),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册导入'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (app.qrAcquiring) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],
        if (app.qrData == null && app.qrError == null && app.qrRaw == null)
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
                app.cardPrefixByIssuerId(app.qrData?.issuerIdText)?.cardName ??
                '未知',
            onClear: () {
              if (!app.qrAcquiring) app.clearQr();
            },
          ),
      ],
    ),
  );
}
