import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'qr_input_dialog.dart';
import 'qr_scan_page.dart';

/// 相机扫描二维码 → 解析并写入 [app]，结果以 SnackBar 提示。
Future<void> scanQrAndParse(BuildContext context, AppState app) async {
  final bytes = await Navigator.of(context).push<List<int>>(
    MaterialPageRoute<List<int>>(builder: (_) => const QrScanPage()),
  );
  if (bytes == null || bytes.isEmpty || !context.mounted) return;
  _notifyResult(context, app.parseQrBytes(bytes));
}

/// 手动输入二维码数据（HEX / Base64）→ 解析并写入 [app]，结果以 SnackBar 提示。
Future<void> inputQrAndParse(BuildContext context, AppState app) async {
  final text = await showQrInputDialog(context);
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  _notifyResult(context, app.parseQrText(text));
}

void _notifyResult(BuildContext context, bool ok) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(ok ? '二维码解析成功' : '二维码解析失败，请查看二维码详情')),
  );
}