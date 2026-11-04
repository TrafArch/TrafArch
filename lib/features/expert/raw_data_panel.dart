import 'package:flutter/material.dart';

import '../../protocols/transit/tunion/tunion_models.dart';
import 'expert_widgets.dart';
import '../../shared/diagnostics/raw_data_category.dart';

class RawDataPanel extends StatelessWidget {
  const RawDataPanel({
    super.key,
    required this.apduLog,
    required this.processRecords,
  });
  final List<String> apduLog;
  final List<TUnionProcessRecord> processRecords;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (apduLog.isEmpty)
        ExpertField('APDU', '暂无 APDU 记录')
      else
        // SELECT、GET BALANCE 在读取开始阶段。截取末尾会恰好隐藏
        // 排查余额和双应用所需的证据，必须按原顺序展示本次完整日志。
        for (final entry in apduLog)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_category(entry) case final category?)
                  Text(
                    category.label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ExpertHex(entry),
              ],
            ),
          ),
      if (processRecords.isNotEmpty) ...[
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '过程记录原始数据（0x1A / 0x1E）',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        for (final r in processRecords)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '0x${r.sfi.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                  ' · ${r.recordName} · ${r.raw.length} 字节',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
                Text(
                  classifyProcessRecord(r.sfi, r.recordNumber).label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                ExpertHex(r.rawHex),
              ],
            ),
          ),
      ],
    ],
  );

  RawDataCategory? _category(String entry) {
    if (!entry.startsWith('>> ')) return null;
    if (entry.startsWith('>> FeliCa ')) return RawDataCategory.felica;
    final command = entry
        .split('\n')
        .first
        .substring(3)
        .trim()
        .split(RegExp(r'\s+'));
    final bytes = <int>[];
    for (final value in command) {
      if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(value)) {
        return RawDataCategory.other;
      }
      bytes.add(int.parse(value, radix: 16));
    }
    return classifyRawCommand(bytes).category;
  }
}
