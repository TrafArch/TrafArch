import 'package:flutter/material.dart';

import 'trip_entry_presenter.dart';

/// The sheet receives the same projection as the tapped row.
void showTripEntryDetails(
  BuildContext context,
  TripEntryInfo info, {
  VoidCallback? onDiagnostics,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            info.title,
            style: Theme.of(sheetContext).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '记录来源：${info.sourceLabel}',
            style: Theme.of(sheetContext).textTheme.bodySmall
                ?.copyWith(color: Theme.of(sheetContext).colorScheme.outline),
          ),
          if (info.remoteCityText != null) ...[
            const SizedBox(height: 4),
            Text(
              '异地用卡 · 受理城市：${info.remoteCityText}',
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(sheetContext).colorScheme.tertiary,
              ),
            ),
          ],
          if (info.related != null) ...[
            const SizedBox(height: 4),
            Text(
              '关联来源：${info.related}',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          for (final field in info.fields)
            TripDetailRow(label: field.$1, value: field.$2),
          const SizedBox(height: 14),
          if (onDiagnostics != null)
            TextButton.icon(
              onPressed: onDiagnostics,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('诊断与原始证据'),
            )
          else ...[
            Text(
              '原始数据（HEX）',
              style: Theme.of(sheetContext).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SelectableText(
              info.rawHex == null ? '未保留原始字节' : groupTripHex(info.rawHex!),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

class TripDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const TripDetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
