import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'survey_page.dart';

/// 反馈页：提供 QQ 群与问卷两种反馈渠道。
class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  /// 用户反馈 QQ 群号。
  static const String qqGroupNumber = '1106608008';

  /// QQ 加群链接（应用内 WebView 直接打开加群页）。
  static const String qqGroupJoinUrl = 'https://qm.qq.com/q/I8Ba9gEise';

  /// 反馈问卷地址（飞书问卷，应用内 WebView 直接打开）。
  static const String surveyUrl =
      'https://kajolno1.feishu.cn/share/base/form/shrcnHyB4j9cSYWcxpGrezjeg1e';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('反馈')),
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
                Icons.forum_outlined,
                size: 56,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '使用中遇到问题，或对应用有任何建议？'
            '欢迎通过以下渠道反馈，你的意见对改进应用非常重要！',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('QQ 群'),
              subtitle: const Text('$qqGroupNumber\n点按即可打开加群页'),
              trailing: IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: '复制群号',
                onPressed: () => _copyQqGroup(context),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const SurveyPage(title: '加入 QQ 群', url: qqGroupJoinUrl),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const SurveyPage(title: '反馈问卷', url: surveyUrl),
                ),
              ),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('填写反馈问卷'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '问卷将在应用内直接打开',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyQqGroup(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: qqGroupNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('QQ 群号已复制到剪贴板')));
  }
}
