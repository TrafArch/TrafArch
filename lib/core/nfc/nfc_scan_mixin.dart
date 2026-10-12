import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import 'nfc_models.dart';

mixin NfcScanMixin<T extends StatefulWidget> on State<T> {
  AppState get app;
  bool get isActive;
  bool get autoStartOnFirstFrame => true;

  /// 自动读取模式：本次运行尚未成功读取过任何卡片
  bool get inAutoReadMode => !app.autoScanConsumed;

  @override
  void initState() {
    super.initState();
    app.addListener(_onNfcChanged);
    // 打开应用（首次进入页面）即自动进入读取模式；
    // 成功读取过一次之后不再自动读取，由按钮手动触发
    if (autoStartOnFirstFrame && inAutoReadMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) enterAutoScanIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    app.removeListener(_onNfcChanged);
    super.dispose();
  }

  void _onNfcChanged() {
    if (mounted) setState(() {});
  }

  NfcScanResult? get result => app.lastResult;
  bool get scanning => app.scanning;
  String? get error => app.error;

  /// 自动读取模式：尚未成功读取过、页面可见且空闲时自动开始读取。
  /// 用于“打开应用自动读取”与“切回页面自动恢复读取”。
  void enterAutoScanIfNeeded() {
    if (!inAutoReadMode || !isActive || scanning) return;
    startScan();
  }

  Future<void> startScan() async {
    if (scanning || !isActive) return;
    await app.scanOnce();
  }

  Future<void> stopScan() async {
    await app.stop();
  }
}