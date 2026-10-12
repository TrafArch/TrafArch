import 'package:flutter/material.dart';
import '../../core/app_info.dart';
import '../../state/app_state.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  final AppState app;
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
    // 在线同步状态说明（开关开启后展示在页面中，随 AppState 通知刷新）
    final String syncStatus;
    final Color syncStatusColor;
    if (app.syncingData) {
      syncStatus = '正在从在线源拉取读卡识途站点数据…';
      syncStatusColor = scheme.outline;
    } else if (app.syncError != null) {
      syncStatus = '更新失败：${app.syncError}';
      syncStatusColor = scheme.error;
    } else if (app.syncReport != null) {
      syncStatus = app.syncReport!;
      syncStatusColor = scheme.primary;
    } else if (app.usingOnlineData) {
      syncStatus = '当前使用在线数据（已保存到本地，重启后继续生效）；'
          '再次更新将整体覆盖';
      syncStatusColor = scheme.primary;
    } else {
      syncStatus = '点击右侧按钮获取最新站点数据'
          '（从 GitHub 主源拉取读卡识途公开数据；'
          '拉取后保存到本地，重启后继续生效）';
      syncStatusColor = scheme.outline;
    }
    // 日志导出状态说明（随 AppState 通知刷新）
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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.cloud_download_outlined),
              title: const Text('开启在线拉取数据'),
              subtitle: Text(
                app.onlineFetchEnabled
                    ? '已开启：可在下方在线更新站点数据'
                        '（拉取后取代预制数据并保存到本地；'
                        '关闭开关会清除在线数据）'
                    : '默认停用：使用应用内预制站点数据'
                        '（读卡识途公开快照，开箱即用）',
              ),
              value: app.onlineFetchEnabled,
              onChanged: (value) => app.setOnlineFetchEnabled(value),
            ),
          ),
          if (app.onlineFetchEnabled)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_sync_outlined, color: syncStatusColor),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        syncStatus,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: syncStatusColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: app.syncingData
                          ? null
                          : () => app.syncTripreaderData(),
                      child: Text(app.syncingData ? '更新中…' : '在线更新'),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.article_outlined),
                  title: const Text('启用运行日志'),
                  subtitle: Text(
                    app.loggingEnabled
                        ? '已开启：记录读卡与解析过程，便于排查问题'
                        : '默认停用：不写入新的运行日志（已记录内容仍可导出）',
                  ),
                  value: app.loggingEnabled,
                  onChanged: (value) => app.setLoggingEnabled(value),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导出日志'),
                  subtitle: Text(
                    logStatus,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: logStatusColor),
                  ),
                  trailing: app.exportingLog
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: app.exportingLog ? null : () => app.exportLog(),
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              subtitle: Text('版本 ${AppInfo.version}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}