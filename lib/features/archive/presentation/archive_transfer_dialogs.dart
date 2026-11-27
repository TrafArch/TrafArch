import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_dependencies.dart';
import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../domain/archive_export_options.dart';

typedef ArchiveTransferNotice = void Function(String message, bool failed);

Future<void> exportArchiveJson(
  BuildContext context,
  AppDependencies app, {
  SavedCard? card,
  ArchiveTransferNotice? onNotice,
}) async {
  if (app.archiveTransfer.busy) return;
  final options = await showArchiveExportDialog(
    context,
    cardName: card?.displayName,
  );
  if (!context.mounted || options == null) return;
  try {
    final name = await app.archiveTransfer.export(
      options: options,
      cardIds: card == null ? null : {card.id},
    );
    if (!context.mounted || name == null) return;
    _showNotice(context, onNotice, '已保存：$name');
  } catch (error) {
    if (context.mounted) {
      _showNotice(context, onNotice, '导出失败：${_errorText(error)}', failed: true);
    }
  }
}

void _showNotice(
  BuildContext context,
  ArchiveTransferNotice? callback,
  String message, {
  bool failed = false,
}) {
  if (callback != null) {
    callback(message, failed);
  } else {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

String _errorText(Object error) => switch (error) {
  FormatException() => error.message,
  PlatformException() => error.message ?? '文件操作未完成，请重试。',
  StateError() => error.message,
  _ => '文件操作未完成，请重试。',
};

Future<ArchiveExportOptions?> showArchiveExportDialog(
  BuildContext context, {
  String? cardName,
}) => showDialog<ArchiveExportOptions>(
  context: context,
  builder: (_) => _ArchiveExportDialog(cardName: cardName),
);

class _ArchiveExportDialog extends StatefulWidget {
  const _ArchiveExportDialog({this.cardName});
  final String? cardName;

  @override
  State<_ArchiveExportDialog> createState() => _ArchiveExportDialogState();
}

class _ArchiveExportDialogState extends State<_ArchiveExportDialog> {
  ArchiveExportMode _mode = ArchiveExportMode.selectedRecords;
  final _fields = Set<ArchiveExportField>.of(
    ArchiveExportOptions.defaultFields,
  );

  @override
  Widget build(BuildContext context) {
    final fullBackup = _mode == ArchiveExportMode.fullBackup;
    return AlertDialog(
      title: const Text('导出卡片 JSON'),
      scrollable: true,
      insetPadding: const EdgeInsets.all(16),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.cardName == null ? '导出：全部已保存卡片' : '导出：${widget.cardName}',
            ),
            const SizedBox(height: 12),
            SegmentedButton<ArchiveExportMode>(
              direction:
                  (MediaQuery.sizeOf(context).width - 80).clamp(0, 440) <
                      220 * MediaQuery.textScalerOf(context).scale(14) / 14
                  ? Axis.vertical
                  : Axis.horizontal,
              segments: const [
                ButtonSegment(
                  value: ArchiveExportMode.selectedRecords,
                  label: Text('选择字段'),
                ),
                ButtonSegment(
                  value: ArchiveExportMode.fullBackup,
                  label: Text('完整备份'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.single),
            ),
            const SizedBox(height: 12),
            if (fullBackup)
              const Text('保存卡片名称、全部历史记录和原始读取数据，可用于恢复卡片档案。')
            else ...[
              const Text('仅导出所选字段，每条记录一行，方便整理成表格。'),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () => _fields.addAll(ArchiveExportField.values),
                    ),
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () => setState(_fields.clear),
                    child: const Text('清空选择'),
                  ),
                  Text('已选 ${_fields.length} 项'),
                ],
              ),
              for (final field in ArchiveExportField.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(field.label),
                  value: _fields.contains(field),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _fields.add(field);
                    } else {
                      _fields.remove(field);
                    }
                  }),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: !fullBackup && _fields.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  ArchiveExportOptions(mode: _mode, fields: _fields),
                ),
          child: const Text('选择保存位置'),
        ),
      ],
    );
  }
}
