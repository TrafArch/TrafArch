import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../shared/presentation/ui_constants.dart';

class ExpertField extends StatelessWidget {
  const ExpertField(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class ExpertHint extends StatelessWidget {
  const ExpertHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class ExpertHex extends StatelessWidget {
  const ExpertHex(this.hex, {super.key});
  final String hex;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: hex));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('原始数据已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Text(
        hex,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class ExpertHomeHint extends StatelessWidget {
  const ExpertHomeHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.home_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class ExpertTabBody extends StatelessWidget {
  const ExpertTabBody({
    super.key,
    required this.storageKey,
    required this.children,
    this.hasResult = true,
    this.showReadHint = true,
  });
  final String storageKey;
  final List<Widget> children;
  final bool hasResult, showReadHint;
  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey<String>(storageKey),
      scrollCacheExtent: const ScrollCacheExtent.pixels(200),
      padding: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        UiConstants.floatingNavBarClearance,
      ),
      children: [
        if (showReadHint && !hasResult)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '尚未读取，请先在首页放置票卡完成读取',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}
