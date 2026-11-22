import 'package:flutter/material.dart';

import '../../../shared/presentation/adaptive_layout.dart';

import '../../../app/app_info.dart';
import 'legal_document_links.dart';
import '../../updates/update_prompt.dart';
import '../../updates/update_service.dart';
import 'acknowledgements_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({
    super.key,
    required this.updates,
    required this.openWebLink,
    this.openUrl,
  });

  final Future<void> Function(Uri) openWebLink;

  final UpdateService updates;
  final Future<bool> Function(Uri)? openUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FoldSafePage(
      child: Scaffold(
        appBar: AppBar(title: const Text('关于')),
        body: SafeArea(
          top: false,
          child: AdaptiveContent(
            child: ListView(
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
                  '版本 ${AppInfo.version} (${AppInfo.displayBuildNumber})',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (updates.isConfigured) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: UpdateCheckButton(
                      service: updates,
                      openUrl: openUrl,
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
                      MaterialPageRoute(
                        builder: (_) => const AcknowledgementsPage(),
                      ),
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
                LegalDocumentLinks(openWebLink: openWebLink),
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
          ),
        ),
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
