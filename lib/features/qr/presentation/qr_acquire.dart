import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../application/qr_acquisition.dart';
import 'qr_scan_page.dart';

/// Presentation coordinator: routes, parse-boundary handoff and notices.
/// Acquisition and image decoder cleanup belong to QrAcquisition.
Future<void> scanQrAndParse(
  BuildContext context,
  AppDependencies app, {
  void Function(String message, bool failed)? onNotice,
  bool Function()? canPublish,
}) async {
  try {
    final acquired = await app.runQrAcquisition((isCurrent) async {
      bool active() => isCurrent() && canPublish?.call() != false;
      final result = await const QrAcquisition().scan(
        openCamera: () async {
          if (!context.mounted || !active()) return null;
          final released = Completer<bool>();
          final payload = await Navigator.of(context).push<List<int>>(
            MaterialPageRoute<List<int>>(
              builder: (_) => QrScanPage(onReleased: released.complete),
            ),
          );
          if (!await released.future) throw StateError('相机未确认关闭');
          return payload;
        },
      );
      if (context.mounted && active()) _present(context, app, result, onNotice);
    });
    if (!acquired &&
        context.mounted &&
        canPublish?.call() != false &&
        app.nfcReleaseFailed) {
      _showNotice(context, 'NFC 尚未关闭，无法启动相机。请重试。', true, onNotice);
    }
  } catch (_) {
    if (context.mounted && canPublish?.call() != false) {
      _showNotice(context, '相机操作未完成，请重试。', true, onNotice);
    }
  }
}

Future<void> importQrFromGalleryAndParse(
  BuildContext context,
  AppDependencies app, {
  void Function(String message, bool failed)? onNotice,
  bool Function()? canPublish,
}) async {
  final acquired = await app.runQrAcquisition((isCurrent) async {
    bool active() => isCurrent() && canPublish?.call() != false;
    if (!context.mounted || !active()) return;
    final result = await const QrAcquisition().gallery();
    if (context.mounted && active()) _present(context, app, result, onNotice);
  });
  if (!acquired &&
      context.mounted &&
      canPublish?.call() != false &&
      app.nfcReleaseFailed) {
    _showNotice(context, 'NFC 尚未关闭，无法打开相册。请重试。', true, onNotice);
  }
}

void _present(
  BuildContext context,
  AppDependencies app,
  QrAcquisitionResult result,
  void Function(String, bool)? onNotice,
) {
  final String message;
  final bool failed;
  switch (result) {
    case QrAcquisitionCancelled():
      return;
    case QrAcquisitionFailed():
      message = result.message;
      failed = true;
    case AcquiredQrPayload():
      failed = !app.parseQrBytes(result.bytes);
      message = !failed ? '二维码解析成功' : '二维码解析失败，请查看本页读取信息';
  }
  _showNotice(context, message, failed, onNotice);
}

void _showNotice(
  BuildContext context,
  String message,
  bool failed,
  void Function(String, bool)? callback,
) {
  if (callback != null) {
    callback(message, failed);
  } else {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }
}
