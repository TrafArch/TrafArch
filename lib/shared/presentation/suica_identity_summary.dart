import 'package:flutter/material.dart';

/// IDm is the local archive identity, distinct from the protected card IDi.
class SuicaIdentitySummary extends StatelessWidget {
  const SuicaIdentitySummary({
    super.key,
    this.idm,
    this.hasConflict = false,
    this.compact = false,
  });

  final String? idm;
  final bool hasConflict;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '卡片标识（IDm）',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        if (hasConflict)
          Text('已保存的卡片标识不一致', style: theme.textTheme.bodyMedium)
        else if (idm case final value?)
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          )
        else
          Text('IDm 未读取', style: theme.textTheme.bodyMedium),
        if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            '卡面编号（IDi）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'JE 等开头的卡面编号位于加密区，当前无法通过 NFC 读取。卡包使用 IDm 识别同一卡片。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}
