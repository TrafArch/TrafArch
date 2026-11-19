import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/presentation/adaptive_layout.dart';
import '../../../shared/domain/archive_conflict_policy.dart';

import '../../../app/app_info.dart';
import '../../../app/app_dependencies.dart';
import '../../../app/beta_ui_scope.dart';
import 'about_page.dart';
import 'feedback_page.dart';
import 'diagnostic_export_dialog.dart';
import '../../reference_data/presentation/knowledge_base_page.dart';

class SettingsPage extends StatefulWidget {
  final AppDependencies app;
  const SettingsPage({super.key, required this.app});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _betaUiWarningOpen = false;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestBetaUiChange(bool enabled) async {
    final beta = BetaUiScope.maybeOf(context);
    if (beta == null || beta.enabled == enabled || _betaUiWarningOpen) return;
    if (!enabled) {
      beta.onChanged(false);
      return;
    }

    _betaUiWarningOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _BetaUiWarningDialog(),
      );
      if (confirmed == true && mounted) {
        BetaUiScope.maybeOf(context)?.onChanged(true);
      }
    } finally {
      _betaUiWarningOpen = false;
    }
  }

  Future<void> _pickArchiveConflictPolicy() async {
    final app = widget.app;
    final selected = await showDialog<ArchiveConflictPolicy>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('已经存在的记录'),
        children: [
          RadioGroup<ArchiveConflictPolicy>(
            groupValue: app.archiveConflictPolicy,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final policy in ArchiveConflictPolicy.values)
                  RadioListTile<ArchiveConflictPolicy>(
                    value: policy,
                    title: Text(policy.label),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ),
        ],
      ),
    );
    if (selected != null) await app.setArchiveConflictPolicy(selected);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final scheme = Theme.of(context).colorScheme;
    // 日志导出状态说明（随 AppDependencies 通知刷新）
    final String logStatus;
    final Color logStatusColor;
    if (app.exportingLog) {
      logStatus = '正在导出到下载目录…';
      logStatusColor = scheme.outline;
    } else if (app.logExportMessage != null) {
      logStatus = app.logExportMessage!;
      logStatusColor = app.logExportFailed ? scheme.error : scheme.primary;
    } else {
      logStatus = '选择读取记录，导出 JSON 到手机「下载」目录';
      logStatusColor = scheme.outline;
    }
    Widget section(String title, List<Widget> children) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
        ],
      );
    }

    return FoldSafePage(
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: SafeArea(
          top: false,
          child: AdaptiveContent(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (app.settings.persistenceError case final String message)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.error_outline, color: scheme.error),
                      title: const Text('设置未能保存或读取'),
                      subtitle: Text('当前选择可能仅在本次运行生效。$message'),
                    ),
                  ),
                section('读卡与数据', [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: const Text('已经存在的记录'),
                      subtitle: Text(app.archiveConflictPolicy.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickArchiveConflictPolicy,
                    ),
                  ),
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(Icons.save_outlined),
                      title: const Text('读取后自动保存'),
                      subtitle: Text(
                        app.autoSaveEnabled
                            ? '已开启：每次读卡解析成功后自动保存到卡片列表（无需手动确认）'
                            : '默认停用：读卡后弹出确认框，由你选择是否保存',
                      ),
                      value: app.autoSaveEnabled,
                      onChanged: (value) => app.setAutoSaveEnabled(value),
                    ),
                  ),
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('上海交通卡可透支余额'),
                      subtitle: Text(
                        app.includeShanghaiOverdraft
                            ? '已开启：总余额包含固定的 8 元可透支额度，城市一卡通余额保持原值'
                            : '默认关闭：总余额和相关记录余额扣除 8 元，城市一卡通余额不重复扣除',
                      ),
                      value: app.includeShanghaiOverdraft,
                      onChanged: (value) =>
                          app.setIncludeShanghaiOverdraft(value),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: const Text('知识库'),
                      subtitle: Text(app.knowledgeSummary),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => KnowledgeBasePage(app: app),
                        ),
                      ),
                    ),
                  ),
                ]),
                section('外观', [
                  if (BetaUiScope.maybeOf(context) case final beta?)
                    Card(
                      child: SwitchListTile(
                        secondary: const Icon(Icons.new_releases_outlined),
                        title: const Text('启用新界面（beta）'),
                        subtitle: const Text('预览全新界面与模拟数据，仅本次运行生效'),
                        value: beta.enabled,
                        onChanged: _requestBetaUiChange,
                      ),
                    ),
                  Card(
                    child: SwitchListTile(
                      secondary: const Icon(Icons.palette_outlined),
                      title: const Text('莫奈取色'),
                      subtitle: Text(
                        app.monetEnabled
                            ? '已开启（默认）：主题色跟随系统壁纸动态取色（需 Android 12 及以上，'
                                  '低版本系统自动回落到内置主题色）'
                            : '已关闭：使用应用内置固定主题色（蓝色）',
                      ),
                      value: app.monetEnabled,
                      onChanged: (value) => app.setMonetEnabled(value),
                    ),
                  ),
                ]),
                section('日志', [
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.article_outlined),
                          title: const Text('启用运行日志'),
                          subtitle: Text(
                            app.loggingEnabled
                                ? '已开启：等待贴卡时立即生效，读卡日志保存在本机，可能含卡片标识与行程信息'
                                : '默认停用：不写入新的运行日志，已有日志可在日志管理器中查看和导出',
                          ),
                          value: app.loggingEnabled,
                          onChanged: (value) => app.setLoggingEnabled(value),
                        ),
                        if (app.diagnostics.storageIssue
                            case final String issue)
                          ListTile(
                            leading: Icon(
                              Icons.warning_amber_outlined,
                              color: scheme.error,
                            ),
                            title: const Text('日志保存状态异常'),
                            subtitle: Text(issue),
                          ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.download_outlined),
                          title: const Text('日志管理器'),
                          subtitle: Text(
                            logStatus,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: logStatusColor),
                          ),
                          trailing: app.exportingLog
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: app.exportingLog
                              ? null
                              : () => showDiagnosticExportDialog(context, app),
                        ),
                      ],
                    ),
                  ),
                ]),
                section('关于', [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.feedback_outlined),
                      title: const Text('反馈'),
                      subtitle: const Text('QQ 群、邮箱与问卷反馈渠道'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FeedbackPage(app: app),
                        ),
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于'),
                      subtitle: Text('版本 ${AppInfo.version}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AboutPage(
                            updates: app.updates,
                            openPrivacyPolicy: app.openPrivacyPolicy,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BetaUiWarningDialog extends StatefulWidget {
  const _BetaUiWarningDialog();

  @override
  State<_BetaUiWarningDialog> createState() => _BetaUiWarningDialogState();
}

class _BetaUiWarningDialogState extends State<_BetaUiWarningDialog> {
  static const _waitSeconds = 10;
  int _remainingSeconds = _waitSeconds;
  late final Timer _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _waitSeconds - timer.tick;
      if (remaining <= 0) timer.cancel();
      setState(() => _remainingSeconds = remaining > 0 ? remaining : 0);
    });
  }

  @override
  void dispose() {
    _countdown.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onErrorContainer;
    final canConfirm = _remainingSeconds == 0;
    const emphasis = TextStyle(fontWeight: FontWeight.bold);
    return AlertDialog(
      scrollable: true,
      backgroundColor: scheme.errorContainer,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: foreground.withValues(alpha: 0.2)),
      ),
      icon: const Icon(Icons.warning_amber_rounded),
      iconColor: foreground,
      title: Text('新界面预览警告', style: TextStyle(color: foreground)),
      content: Text.rich(
        const TextSpan(
          children: [
            TextSpan(text: '新界面仅用于 '),
            TextSpan(text: 'UI预览', style: emphasis),
            TextSpan(text: '。页面操作仅作演示，卡片、余额和行程均为'),
            TextSpan(text: '模拟数据', style: emphasis),
            TextSpan(text: '。\n\n预览不会读取实体卡，也不会写入真实档案。'),
          ],
        ),
        style: TextStyle(color: foreground),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: foreground),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('不开启'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            disabledBackgroundColor: foreground.withValues(alpha: 0.12),
            disabledForegroundColor: foreground.withValues(alpha: 0.8),
          ),
          onPressed: canConfirm ? () => Navigator.pop(context, true) : null,
          child: Text(
            canConfirm ? '确认开启' : '确认开启（$_remainingSeconds 秒）',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
