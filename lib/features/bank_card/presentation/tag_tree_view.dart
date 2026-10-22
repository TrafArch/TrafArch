import 'package:flutter/material.dart';

import '../../../protocols/bank/domain/models/tlv_node.dart';

/// 标签树递归展示：已知标签给含义与（脱敏）解码值，未知标签保留原始 HEX。
class TagTreeView extends StatelessWidget {
  final List<TlvNode> nodes;
  const TagTreeView({super.key, required this.nodes});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final node in nodes) _tile(context, node)],
  );

  Widget _tile(BuildContext context, TlvNode node) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${node.tagHex}] ${node.description ?? '未知标签'}',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (node.decodedValue != null)
            Text(
              '${node.masked ? '脱敏值' : '解码值'}：${node.decodedValue}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Text(
            '原始(${node.length}B)：${node.rawValueHex}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.outline),
          ),
          if (node.children.isNotEmpty) TagTreeView(nodes: node.children),
        ],
      ),
    );
  }
}
