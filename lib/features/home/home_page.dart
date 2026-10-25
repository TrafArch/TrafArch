import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../shared/presentation/ui_constants.dart';
import '../../app/app_info.dart';
import '../../app/app_dependencies.dart';
import 'presentation/pending_save_presenter.dart';
import 'presentation/scan_controls.dart';
import '../qr/presentation/qr_action_button.dart';
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
              actions: [
                QrActionButton(app: app),
                SettingsActionButton(app: app),
              ],
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
                    ScanControls(
                      scanning: scanning,
                      progress: app.readProgress,
                      statusText: _statusText,
                      buttonLabel: _buttonLabel,
                      onScanCard: () {
                        if (widget.active && !scanning) app.scanOnce();
                      },
                    ),
                    const SizedBox(height: 12),
                    // 最近扫描：NFC 卡片与银行卡只读分析。
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
