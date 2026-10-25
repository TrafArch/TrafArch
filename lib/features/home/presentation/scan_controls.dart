import 'package:flutter/material.dart';

/// Acquisition controls only render state and invoke commands owned by HomePage.
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.scanning,
    required this.progress,
    required this.statusText,
    required this.buttonLabel,
    required this.onScanCard,
  });
  final bool scanning;
  final int? progress;
  final String statusText, buttonLabel;
  final VoidCallback onScanCard;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.contactless,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '请将卡片贴近手机背面',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(statusText, textAlign: TextAlign.center),
          if (scanning) ...[
            const SizedBox(height: 16),
            ReadProgressBar(
              value: progress == null ? null : progress! / 100,
              percent: progress,
            ),
          ],
          if (!scanning) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onScanCard,
              icon: const Icon(Icons.nfc),
              label: Text(buttonLabel),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 读卡进度条：等待贴卡 / 进度未知时为不确定进度动画，识读到卡片后
/// 按 [percent] 展示真实百分比。
class ReadProgressBar extends StatelessWidget {
  const ReadProgressBar({super.key, this.value, this.percent});

  /// 0.0–1.0；null 表示进度未知（不确定进度动画）。
  final double? value;

  /// 百分比文案；null 时不展示。
  final int? percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              semanticsLabel: '读卡进度',
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        if (percent != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
