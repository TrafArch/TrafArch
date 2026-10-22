import 'package:flutter/material.dart';

/// Acquisition controls only render state and invoke commands owned by HomePage.
class ScanControls extends StatelessWidget {
  const ScanControls({
    super.key,
    required this.scanning,
    required this.progress,
    required this.statusText,
    required this.buttonLabel,
    required this.useGmsScanner,
    required this.importing,
    required this.onScanCard,
    required this.onScanQr,
    required this.onImportGallery,
  });
  final bool scanning, useGmsScanner, importing;
  final int? progress;
  final String statusText, buttonLabel;
  final VoidCallback onScanCard, onScanQr, onImportGallery;
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
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 24),
          Text('扫码读取乘车码', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            useGmsScanner
                ? '支持 JT/T 1179 交通一卡通乘车码，可系统扫码或从相册导入'
                : '支持 JT/T 1179 交通一卡通乘车码，可相机扫描或从相册导入',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onScanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫描二维码'),
              ),
              OutlinedButton.icon(
                onPressed: importing ? null : onImportGallery,
                icon: importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(importing ? '正在识别…' : '从相册导入'),
              ),
            ],
          ),
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
