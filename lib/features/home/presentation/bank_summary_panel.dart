import 'package:flutter/material.dart';

import '../../../protocols/bank/domain/models/bank_card_result.dart';
import '../../../protocols/bank/domain/models/card_application.dart';
import '../../../protocols/bank/domain/models/parse_issue.dart';
import '../../bank_card/presentation/application_detail_page.dart';

import 'summary_widgets.dart';
import 'result_labels.dart';

class BankSummaryPanel extends StatelessWidget {
  const BankSummaryPanel({
    super.key,
    required this.bank,
    this.detailed = false,
  });
  final BankCardResult bank;
  final bool detailed;
  BankCardResult get result => bank;
  @override
  Widget build(BuildContext context) => detailed
      ? _details(context)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _bankPanel(context, bank),
        );
  List<Widget> _bankPanel(BuildContext context, BankCardResult bank) {
    return [
      ...summaryNameLine(context, '银行卡（EMV / PBOC）'),
      summaryField(context, '协议族', bankFamilyText(bank.protocolFamily)),
      summaryField(context, '结果状态', bankStatusText(bank)),
      if (bank.applications.isEmpty)
        summaryHint(context, '未解析到应用：${bankEmptyReason(bank)}')
      else ...[
        const SizedBox(height: 4),
        for (final application in bank.applications)
          _bankApplicationTile(context, application),
      ],
      if (bank.issues.isNotEmpty)
        summaryHint(context, '读取与解析异常 ${bank.issues.length} 项（明细见应用详情）'),
    ];
  }

  Widget _bankApplicationTile(
    BuildContext context,
    ParsedApplication application,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = application.application.selected;
    final expiry = application.summary.expiry;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.credit_score : Icons.credit_card_off,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(application.application.displayLabel),
      subtitle: Text(
        'AID ${application.application.aidHex}'
        ' · 记录 ${application.records.length} 条'
        '${expiry == null ? '' : '\n有效期 $expiry'}'
        '${application.issues.isEmpty ? '' : ' · 异常 ${application.issues.length} 项'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ApplicationDetailPage(application: application),
        ),
      ),
    );
  }

  Widget _details(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('协议族', bankFamilyText(bank.protocolFamily)),
        _kv('结果状态', bankStatusText(bank, detailed: true)),
        _kv('解析器版本', result.parserVersion),
        _kv('分析时间', _fmtTime(result.analyzedAt)),
        _kv('应用数量', '${result.applications.length}'),
        _kv('APDU 步骤', '${result.traces.length}'),
        const Divider(height: 28),
        _sectionTitle(context, '应用列表（${result.applications.length}）'),
        if (result.applications.isEmpty)
          _hint(context, '未解析到应用：${bankEmptyReason(bank)}')
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
        'AID ${app.application.aidHex}'
        '${app.summary.panTail == null ? '' : '  ·  卡号尾号 ****${app.summary.panTail}'}\n'
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
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Widget _hint(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
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
