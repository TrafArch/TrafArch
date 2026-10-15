import 'package:flutter/material.dart';
import '../../core/nfc/nfc_scan_mixin.dart';
import '../../core/ui_constants.dart';
import '../../core/app_info.dart';
import '../../state/app_state.dart';
import '../card_archive/models/pending_card_save.dart';
import '../qr/qr_acquire.dart';
import '../settings/settings_action_button.dart';
import 'recent_scan_section.dart';

class HomePage extends StatefulWidget {
  final AppState app;
  final bool active;
  const HomePage({super.key, required this.app, required this.active});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with NfcScanMixin<HomePage> {
  /// 相册导入进行中（选图 / 图片识别），用于禁用按钮并展示进度。
  bool _qrImporting = false;

  /// 已弹出（或正在弹出）保存确认框的待保存结果：同一份读取结果只弹一次。
  PendingCardSave? _saveDialogFor;

  /// 已调度（或正在展示）自动保存提示：同一份提示只弹一次。
  bool _noticeScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_maybeShowSaveDialog);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowSaveDialog();
    });
  }

  @override
  void dispose() {
    widget.app.removeListener(_maybeShowSaveDialog);
    super.dispose();
  }

  @override
  AppState get app => widget.app;

  @override
  bool get isActive => widget.active;

  String get _statusText {
    if (app.parsing) return '已读到卡片，正在解析数据…';
    if (scanning) return '正在监听 NFC 标签…';
    if (error != null) return '读取失败，请点击下方按钮重试';
    if (app.lastBankCardResult != null) return '分析完成，再次读取请点击下方按钮';
    if (result != null) return '读取完成，再次读取请点击下方按钮';
    return '点击下方按钮开始读取卡片信息';
  }

  String get _buttonLabel {
    if (error != null) return '重试';
    if (result != null) return '再次读取';
    return '开始读取';
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      // 离开首页：停止读取，释放 NFC 资源
      stopScan();
    } else if (!oldWidget.active && widget.active) {
      // 切回首页：尚未成功读取过则自动恢复读取模式；
      // 成功读取过则保持空闲，需点击下方按钮再次读取；
      // 若存在未应答的待保存结果（离开首页期间产生的），此时补弹确认框
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          enterAutoScanIfNeeded();
          _maybeShowSaveDialog();
        }
      });
    }
  }

  /// 读取解析完成后弹出「是否保存」确认对话框：同一份待保存结果只弹一次；
  /// 页面不在前台时暂不弹出（切回首页时由 didUpdateWidget 补弹）。
  /// 开启「读取后自动保存」时不再弹确认框（已由 AppState 直接落库），
  /// 仅用 SnackBar 提示保存结果。
  void _maybeShowSaveDialog() {
    if (!mounted || !widget.active) return;
    if (app.autoSaveEnabled) {
      _saveDialogFor = null;
      final notice = app.autoSaveNotice;
      if (notice != null && !_noticeScheduled) {
        _noticeScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _noticeScheduled = false;
          if (!mounted) return;
          app.clearAutoSaveNotice();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(notice)),
          );
        });
      }
      return;
    }
    final pending = app.pendingCardSave;
    if (pending == null) {
      _saveDialogFor = null;
      return;
    }
    if (identical(pending, _saveDialogFor)) return;
    _saveDialogFor = pending;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSaveDialog(pending);
    });
  }

  /// 「是否保存卡片」确认框：展示卡片名称与卡号（点击遮罩不关闭）；
  /// 「保存」写入卡片列表（失败提示不中断），「不保存」/系统返回仅丢弃。
  Future<void> _showSaveDialog(PendingCardSave pending) async {
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存卡片'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('是否将本次读取的卡片保存到卡片列表？'),
              const SizedBox(height: 12),
              _pendingRow('卡片名称', pending.displayName),
              _pendingRow('卡号', pending.cardNumberText),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (save == true) {
      final ok = await app.acceptPendingSave();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('卡片保存失败')),
        );
      }
    } else {
      // 「不保存」与系统返回（null）均视为放弃本次保存
      app.declinePendingSave();
    }
  }

  Widget _pendingRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      )),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

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
    return SafeArea(
      top: false,
      child: CustomScrollView(
        cacheExtent: 300,
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(Icons.contactless,
                              size: 72,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            '请将卡片贴近手机背面',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _statusText,
                            textAlign: TextAlign.center,
                          ),
                          if (!scanning) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => startScan(),
                              icon: const Icon(Icons.nfc),
                              label: Text(_buttonLabel),
                            ),
                          ],
                          const SizedBox(height: 24),
                          const Divider(height: 1),
                          const SizedBox(height: 24),
                          Text(
                            '扫码读取乘车码',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            app.useGmsScanner
                                ? '支持 JT/T 1179 交通一卡通乘车码，可系统扫码或从相册导入'
                                : '支持 JT/T 1179 交通一卡通乘车码，可相机扫描或从相册导入',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => scanQrAndParse(context, app),
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('扫描二维码'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _qrImporting
                                    ? null
                                    : _importQrFromGallery,
                                icon: _qrImporting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons.photo_library_outlined),
                                label: Text(
                                    _qrImporting ? '正在识别…' : '从相册导入'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                  RepaintBoundary(
                    child: RecentScanSection(app: app),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}