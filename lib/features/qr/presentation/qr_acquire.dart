import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../application/qr_acquisition.dart';
import 'qr_scan_page.dart';

/// Presentation coordinator: routes, parse-boundary handoff and notices.
/// System policy and image decoder cleanup belong to QrAcquisition.
Future<void> scanQrAndParse(BuildContext context, AppDependencies app) async {
  final result = await const QrAcquisition().scan(
    useSystemScanner: app.useGmsScanner,
    systemAvailable: app.gmsAvailable,
    openCamera: () async {
      if (!context.mounted) return null;
      return Navigator.of(context).push<List<int>>(
        MaterialPageRoute<List<int>>(builder: (_) => const QrScanPage()),
      );
    },
  );
  if (context.mounted) _present(context, app, result);
}

Future<void> importQrFromGalleryAndParse(
  BuildContext context,
  AppDependencies app,
) async {
  final result = await const QrAcquisition().gallery();
  if (context.mounted) _present(context, app, result);
}

void _present(
  BuildContext context,
  AppDependencies app,
  QrAcquisitionResult result,
) {
  final String message;
  switch (result) {
    case QrAcquisitionCancelled():
      return;
    case QrAcquisitionFailed():
      message = result.message;
    case AcquiredQrPayload():
      message = app.parseQrBytes(result.bytes)
          ? '二维码解析成功'
          : '二维码解析失败，请查看首页错误提示';
  }
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}
