import 'package:flutter/material.dart';

import '../../../app/app_info.dart';
import '../../../app/app_dependencies.dart';
import '../../../app/beta_ui_scope.dart';
import 'about_page.dart';
import 'feedback_page.dart';
import '../../reference_data/presentation/knowledge_base_page.dart';

class SettingsPage extends StatefulWidget {
  final AppDependencies app;
  const SettingsPage({super.key, required this.app});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
      logStatus = '保存到手机「下载」目录（Download/transit_card_log_*.txt）';
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

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
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
                secondary: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('上海交通卡可透支余额'),
                subtitle: Text(
                  app.includeShanghaiOverdraft
                      ? '已开启：总余额包含固定的 8 元可透支额度，城市一卡通余额保持原值'
                      : '默认关闭：总余额和相关记录余额扣除 8 元，城市一卡通余额不重复扣除',
                ),
                value: app.includeShanghaiOverdraft,
                onChanged: (value) => app.setIncludeShanghaiOverdraft(value),
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
                  onChanged: beta.onChanged,
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
                      : '已关闭：使用应用内置固定主题色（青绿色）',
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
                          ? '已开启：记录读卡与解析过程，便于排查问题'
                          : '默认停用：不写入新的运行日志（开启后可导出）',
                    ),
                    value: app.loggingEnabled,
                    onChanged: (value) => app.setLoggingEnabled(value),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: app.loggingEnabled
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.download_outlined),
                                title: const Text('导出日志'),
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
                                    : () => app.exportLog(),
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
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
                  MaterialPageRoute(builder: (_) => FeedbackPage(app: app)),
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
    );
  }
}
