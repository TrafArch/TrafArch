import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_dependencies.dart';
import '../data/app_database.dart';
import '../domain/card_name_extension.dart';
import '../domain/archive_export_options.dart';

/// Import is available even when the card list is empty.
class ArchiveTransferButtons extends StatefulWidget {
  const ArchiveTransferButtons({super.key, required this.app});
  final AppDependencies app;

  @override
  State<ArchiveTransferButtons> createState() => _ArchiveTransferButtonsState();
}

class _ArchiveTransferButtonsState extends State<ArchiveTransferButtons> {
  bool _interacting = false;

  Future<void> _import() async {
    if (_interacting || widget.app.archiveTransfer.busy) return;
    setState(() => _interacting = true);
    try {
      final preview = await widget.app.archiveTransfer.pickImport();
      if (!mounted || preview == null) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入卡片 JSON'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.name),
                const SizedBox(height: 12),
                Text(preview.summary),
                const SizedBox(height: 12),
                Text(
                  preview.isPartial
                      ? '文件中的字段将作为导入记录保存；未包含的内容保持未知。'
                      : '相同卡片的历史记录将合并，已有的自定义名称保留。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await widget.app.archiveTransfer.confirmImport(preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：新增 ${result.insertedCards} 张卡片，合并 ${result.mergedCards} 张卡片；'
            '新增 ${result.addedBatches} 个读取批次、${result.addedRecords} 条导入记录。',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：${_errorText(error)}')));
      }
    } finally {
      if (mounted) setState(() => _interacting = false);
    }
  }

  Future<void> _export() async {
    if (_interacting || widget.app.archiveTransfer.busy) return;
    setState(() => _interacting = true);
    try {
      await exportArchiveJson(context, widget.app);
    } finally {
      if (mounted) setState(() => _interacting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app.archiveTransfer,
    builder: (context, _) {
      final busy = _interacting || widget.app.archiveTransfer.busy;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '导入卡片 JSON',
            onPressed: busy ? null : _import,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: '导出卡片 JSON',
            onPressed: busy ? null : _export,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      );
    },
  );
}

Future<void> exportArchiveJson(
  BuildContext context,
  AppDependencies app, {
  SavedCard? card,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已保存：$name')));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：${_errorText(error)}')));
    }
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
      content: SizedBox(
        width: 440,
        height: fullBackup ? 220 : MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.cardName == null ? '导出：全部已保存卡片' : '导出：${widget.cardName}',
            ),
            const SizedBox(height: 12),
            SegmentedButton<ArchiveExportMode>(
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
              const Expanded(
                child: SingleChildScrollView(
                  child: Text('保存卡片名称、全部历史记录和原始读取数据，可用于恢复卡片档案。'),
                ),
              )
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
              Expanded(
                child: ListView(
                  children: [
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
                ),
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
