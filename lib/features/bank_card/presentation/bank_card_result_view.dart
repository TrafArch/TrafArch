import 'package:flutter/material.dart';

import '../domain/models/bank_card_result.dart';
import '../domain/models/card_application.dart';
import '../domain/models/parse_issue.dart';
import 'application_detail_page.dart';

/// 银行卡只读分析结果视图（专家页「信息获取」页签内嵌展示）：
/// 概览字段 → 应用列表（AID / 选择状态 / 记录数）→ 解析异常；
/// 点击应用进入 [ApplicationDetailPage] 查看完整标签树。
/// 敏感标签按字典策略脱敏展示（如 PAN 仅保留末四位）。
class BankCardResultView extends StatelessWidget {
  final BankCardResult result;

  const BankCardResultView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('协议族', _familyText),
        _kv('结果状态', _statusText),
        _kv('解析器版本', result.parserVersion),
        _kv('分析时间', _fmtTime(result.analyzedAt)),
        _kv('应用数量', '${result.applications.length}'),
        _kv('APDU 步骤', '${result.traces.length}'),
        const Divider(height: 28),
        _sectionTitle(context, '应用列表（${result.applications.length}）'),
        if (result.applications.isEmpty)
          _hint(context, '未解析到应用：$_emptyReason')
        else
          for (final app in result.applications) _applicationTile(context, app),
        if (result.issues.isNotEmpty) ...[
          const Divider(height: 28),
          _sectionTitle(context, '读取与解析异常（${result.issues.length}）'),
          for (final issue in result.issues) _issueRow(context, issue),
        ],
      ],
    );
  }

  String get _familyText => result.protocolFamily == BankCardProtocolFamily.pboc
      ? 'PBOC（JR/T 0025 系列规则）'
      : 'EMV（通用规范规则）';

  String get _statusText => switch (result.status) {
        BankCardStatus.noCard => '未读到应用数据',
        BankCardStatus.enumerationFailed => '应用枚举失败（PPSE 不支持或访问受限）',
        BankCardStatus.partial => '部分解析成功（仅公开可读数据）',
        BankCardStatus.success => '解析完成',
      };

  String get _emptyReason {
    for (final issue in result.issues) {
      if (issue.stage == 'ppse') return issue.message;
    }
    return result.status == BankCardStatus.enumerationFailed
        ? '卡片未返回应用目录（PPSE），或读取被访问条件拒绝'
        : '未读到可展示的应用数据';
  }

  Widget _applicationTile(BuildContext context, ParsedApplication app) {
    final scheme = Theme.of(context).colorScheme;
    final selected = app.application.selected;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.credit_score : Icons.credit_card_off,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(app.application.displayLabel),
      subtitle: Text(
        'AID ${app.application.aidHex}\n'
        '${app.parserId.toUpperCase()} · FCI ${app.fciTags.length} 标签'
        ' · GPO ${app.gpoTags.length} 标签'
        ' · 记录 ${app.records.length} 条'
        '${app.issues.isEmpty ? '' : ' · 异常 ${app.issues.length} 项'}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ApplicationDetailPage(application: app),
        ),
      ),
    );
  }

  Widget _issueRow(BuildContext context, ParseIssue issue) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '[${issue.stage}] ${issue.code}：${issue.message}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  Widget _sectionTitle(BuildContext context, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Text(k)),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );

  static String _fmtTime(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    final sec = t.second.toString().padLeft(2, '0');
    return '${t.year}-$m-$d $h:$min:$sec';
  }
}