import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 致谢页：鸣谢读卡识途（Trip Reader）公开数据源。
class AcknowledgementsPage extends StatelessWidget {
  const AcknowledgementsPage({super.key});

  /// 读卡识途公开数据源项目地址（数据以 CC BY 4.0 许可开放）。
  static const String tripReaderDataUrl =
      'https://github.com/domosekai/tripreader-data';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('致谢')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.volunteer_activism_outlined,
                size: 56,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '本应用的城市站点数据（含应用内预制快照与在线更新数据）来自'
            '读卡识途（Trip Reader）项目公开发布的数据集，'
            '由其作者与数据贡献者们共同采集、维护。在此致以诚挚的感谢！',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('读卡识途数据源'),
              subtitle: const Text(tripReaderDataUrl),
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: '复制项目地址',
                onPressed: () => _copyUrl(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '数据以 CC BY 4.0（知识共享署名 4.0 国际）许可协议开放使用。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _copyUrl(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: tripReaderDataUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('项目地址已复制到剪贴板')),
    );
  }
}