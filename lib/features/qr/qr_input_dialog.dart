import 'package:flutter/material.dart';

/// 手动输入二维码数据对话框：确认时返回输入文本（HEX / Base64），
/// 取消时返回 null。
Future<String?> showQrInputDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const QrInputDialog(),
  );
}

/// 对话框本体：以 StatefulWidget 持有输入控制器，
/// 保证控制器在关闭动画结束后再释放。
class QrInputDialog extends StatefulWidget {
  const QrInputDialog({super.key});

  @override
  State<QrInputDialog> createState() => _QrInputDialogState();
}

class _QrInputDialogState extends State<QrInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('手动输入二维码数据'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '粘贴二维码原始数据的十六进制（如 80 12…）或 Base64 文本。'
            '仅含十六进制字符的内容优先按 HEX 解码。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'HEX / Base64',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('解析')),
      ],
    );
  }
}