import 'package:flutter/material.dart';

import '../domain/models/card_application.dart';
import '../domain/models/card_field_summary.dart';
import '../domain/models/card_record.dart';
import '../domain/models/parse_issue.dart';
import 'tag_tree_view.dart';

/// 单个银行卡应用详情页：应用选择证据（FCI）、GPO（AIP / AFL）、
/// 记录标签树与解析异常；只读展示，不发起任何写卡 / 认证 / 交易操作。
/// 未知标签同样保留原始 HEX 展示（字典未收录不影响结果呈现）。
class ApplicationDetailPage extends StatelessWidget {
  final ParsedApplication application;

  const ApplicationDetailPage({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    final app = application;
    return Scaffold(
      appBar: AppBar(title: Text(app.application.displayLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _kv('应用标签', app.application.displayLabel),
          _kv('AID', app.application.aidHex),
          _kv('解析规则', app.parserId.toUpperCase()),
          _kv('选择状态', app.application.selected ? '已选择' : '未选择'),
          _kv('读取记录', '${app.records.length} 条'),
          if (app.summary.pan != null) ...[
            _kv('卡号 (PAN)', app.summary.pan!),
            _kv('卡号来源', '应用数据标签 ${app.summary.panSourceTag}'),
          ],
          const Divider(height: 28),
          _sectionTitle(context, '卡号与交易信息'),
          if (app.summary.isEmpty)
            _hint(context, '未读取到可识别的卡号/交易标签（记录为空或读取被访问条件拒绝）')
          else
            _summaryTable(context, app.summary),
          const Divider(height: 28),
          _sectionTitle(context, '应用选择 FCI 标签（${app.fciTags.length}）'),
          if (app.fciTags.isEmpty)
            _hint(context, '无 FCI 标签数据（选择响应未携带或未成功）')
          else
            TagTreeView(nodes: app.fciTags),
          const Divider(height: 28),
          _sectionTitle(context, 'GPO 处理选项标签（${app.gpoTags.length}）'),
          if (app.gpoHex.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              '响应原始值：${app.gpoHex}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 4),
          ],
          if (app.gpoTags.isEmpty)
            _hint(context, '无 GPO 标签数据（未读取或响应非 TLV 结构）')
          else
            TagTreeView(nodes: app.gpoTags),
          const Divider(height: 28),
          _sectionTitle(context, '应用记录（${app.records.length}）'),
          if (app.records.isEmpty)
            _hint(context, '未读取到可访问记录（文件不存在或读取被访问条件拒绝）')
          else
            for (final record in app.records) _recordTile(context, record),
          if (app.issues.isNotEmpty) ...[
            const Divider(height: 28),
            _sectionTitle(context, '读取与解析异常（${app.issues.length}）'),
            for (final issue in app.issues) _issueRow(context, issue),
          ],
        ],
      ),
    );
  }

  /// 关键信息表：左侧「中文名 [tag]」，右侧值（完整呈现，供本机读卡核对）。
  Widget _summaryTable(BuildContext context, CardFieldSummary s) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in s.fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    '${f.label}\n[${f.tag}]${f.sensitive ? ' · 敏感' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    f.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _recordTile(BuildContext context, CardRecord record) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('${record.sfiHex} · 记录 ${record.recordNumber}'),
      subtitle: Text(
        record.parseError ??
            '${record.tags.length} 个标签 · ${record.rawHex.length ~/ 2} 字节',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.outline),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: record.tags.isEmpty
              ? SelectableText(
                  record.rawHex,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : TagTreeView(nodes: record.tags),
        ),
      ],
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
}
