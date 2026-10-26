import 'package:flutter/material.dart';

import '../../../app/app_info.dart';
import '../../updates/update_prompt.dart';
import '../../updates/update_service.dart';
import 'acknowledgements_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.updates,
    required this.openPrivacyPolicy,
    this.openUrl,
  });

  final Future<void> Function() openPrivacyPolicy;

  final UpdateService updates;
  final Future<bool> Function(Uri)? openUrl;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checking = false;
  bool _openingPrivacy = false;

  Future<void> _openPrivacyPolicy() async {
    if (_openingPrivacy) return;
    setState(() => _openingPrivacy = true);
    try {
      await widget.openPrivacyPolicy();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开隐私政策，请安装或启用 Edge 或 Chrome 后重试。')),
      );
    } finally {
      if (mounted) setState(() => _openingPrivacy = false);
    }
  }

  Future<void> _checkUpdates() async {
    if (_checking || !widget.updates.isConfigured) return;
    setState(() => _checking = true);
    try {
      final manifest = await widget.updates.checkNow();
      if (!mounted || manifest == null) return;
      setState(() => _checking = false);
      if (manifest.isNewerThan(widget.updates.currentBuild)) {
        await showUpdateDialog(context, manifest, openUrl: widget.openUrl);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂无更新')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 96,
                height: 96,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppInfo.appName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '版本 ${AppInfo.version}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (widget.updates.isConfigured) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _checkUpdates,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_outlined),
                label: Text(_checking ? '正在检查…' : '检查更新'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('作者'),
              subtitle: const Text(AppInfo.author),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: const Text('致谢'),
              subtitle: const Text('感谢读卡识途提供的公开数据源'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AcknowledgementsPage()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('开放源代码许可'),
              subtitle: const Text('查看本应用使用的开源软件与许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLicenses(context),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('隐私政策'),
              enabled: !_openingPrivacy,
              onTap: _openingPrivacy ? null : _openPrivacyPolicy,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppInfo.copyright,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  void _openLicenses(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LicensePage(
          applicationName: AppInfo.appName,
          applicationVersion: AppInfo.version,
          applicationIcon: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 40,
              height: 40,
              filterQuality: FilterQuality.high,
            ),
          ),
          applicationLegalese: AppInfo.copyright,
        ),
      ),
    );
  }
}
