import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/archive_export_options.dart';

/// Selected-field imports are readable records, never fabricated NFC captures.
class ImportedArchiveRecords extends StatefulWidget {
  const ImportedArchiveRecords({super.key, required this.records});
  final List<Map<String, dynamic>> records;

  @override
  State<ImportedArchiveRecords> createState() => _ImportedArchiveRecordsState();
}

class _ImportedArchiveRecordsState extends State<ImportedArchiveRecords> {
  int _visible = 50;

  @override
  void didUpdateWidget(ImportedArchiveRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records)) _visible = 50;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) return const SizedBox.shrink();
    final labels = {
      for (final field in ArchiveExportField.values) field.key: field.label,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '导入记录 · ${widget.records.length} 条',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('来自 JSON 文件，仅显示文件提供的字段。'),
        ),
        for (final (index, record) in widget.records.take(_visible).indexed)
          Card(
            child: ExpansionTile(
              key: ValueKey(index),
              title: Text(_title(record, index)),
              subtitle: _route(record) == null ? null : Text(_route(record)!),
              children: [
                for (final entry in record.entries)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(labels[entry.key] ?? entry.key),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: SelectableText(_value(entry.value)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (_visible < widget.records.length)
          TextButton(
            onPressed: () => setState(() => _visible += 50),
            child: const Text('继续显示'),
          ),
      ],
    );
  }

  String _title(Map<String, dynamic> record, int index) {
    final time = record['time'] ?? record['entry_time'] ?? record['exit_time'];
    return time is String && time.isNotEmpty ? time : '记录 ${index + 1}';
  }

  String? _route(Map<String, dynamic> record) {
    final start = record['entry_station'];
    final end = record['exit_station'];
    if (start is String && end is String) return '$start → $end';
    return switch (record['station'] ?? start ?? end) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
  }

  String _value(Object? value) => switch (value) {
    null => '未提供',
    String() => value,
    num() || bool() => '$value',
    _ => jsonEncode(value),
  };
}
