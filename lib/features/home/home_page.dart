import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../shared/presentation/ui_constants.dart';
import '../../app/app_info.dart';
import '../../app/app_dependencies.dart';
import 'presentation/pending_save_presenter.dart';
import 'presentation/scan_controls.dart';
import '../qr/presentation/qr_acquire.dart';
import '../settings/presentation/settings_action_button.dart';
import 'recent_scan_section.dart';

class HomePage extends StatefulWidget {
  final AppDependencies app;
  final bool active;
  const HomePage({super.key, required this.app, required this.active});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 相册导入进行中（选图 / 图片识别），用于禁用按钮并展示进度。
  bool _qrImporting = false;

  AppDependencies get app => widget.app;
  bool get scanning => app.scanning;

  @override
  void initState() {
    super.initState();
    app.addListener(_refresh);
    _scheduleAutoScan();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _scheduleAutoScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && !app.autoScanConsumed && !scanning) {
        app.scanOnce();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_refresh);
      app.addListener(_refresh);
      _scheduleAutoScan();
    }
    if (oldWidget.active && !widget.active) {
      // stop() 会同步广播状态变更，而 didUpdateWidget 运行在 build 阶段，
      // 直接调用会让 app 的监听者（TripsPage / ExpertPage）在 build 中
      // setState 触发断言；挪到本帧结束后执行。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.stop();
      });
    } else if (!oldWidget.active && widget.active) {
      _scheduleAutoScan();
    }
  }

  @override
  void dispose() {
    app.removeListener(_refresh);
    super.dispose();
  }

  String get _statusText {
    if (app.parsing) return '已读到卡片，正在解析数据…';
    if (scanning) return '正在监听 NFC 标签…';
    if (app.error != null) return '读取失败，请点击下方按钮重试';
    if (app.lastBankCardResult != null) return '分析完成，再次读取请点击下方按钮';
    if (app.lastResult != null) return '读取完成，再次读取请点击下方按钮';
    return '点击下方按钮开始读取卡片信息';
  }

  String get _buttonLabel => app.error != null
      ? '重试'
      : app.lastResult != null
      ? '再次读取'
      : '开始读取';

  /// 从相册导入二维码：原生相册选图 → MLKit 识别 → 内置纯 Dart 解码兜底，
  /// 成功后解析并写入 [app]。
  Future<void> _importQrFromGallery() async {
    if (_qrImporting) return;
    setState(() => _qrImporting = true);
    try {
      await importQrFromGalleryAndParse(context, app);
    } finally {
      if (mounted) setState(() => _qrImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PendingSavePresenter(
      app: app,
      active: widget.active,
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(300),
          slivers: [
            SliverAppBar(
              pinned: true,
              title: Text(AppInfo.appName),
              actions: [SettingsActionButton(app: app)],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  UiConstants.floatingNavBarClearance,
                ),
                child: Column(
                  children: [
                    // 贴卡读取与乘车码获取合并为同一模块展示
                    ScanControls(
                      scanning: scanning,
                      progress: app.readProgress,
                      statusText: _statusText,
                      buttonLabel: _buttonLabel,
                      useGmsScanner: app.useGmsScanner,
                      importing: _qrImporting,
                      onScanCard: () {
                        if (widget.active && !scanning) app.scanOnce();
                      },
                      onScanQr: () => scanQrAndParse(context, app),
                      onImportGallery: _importQrFromGallery,
                    ),
                    if (app.qrError != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: const Text('二维码解析失败'),
                          subtitle: Text(app.qrError!),
                          trailing: TextButton(
                            onPressed: app.clearQr,
                            child: const Text('清除'),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 最近扫描：卡片（TU / CU / EMV-PBOC 自动切换）与
                    // 乘车码（内嵌展示，自动 / 手动切换）
                    RepaintBoundary(child: RecentScanSection(app: app)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
