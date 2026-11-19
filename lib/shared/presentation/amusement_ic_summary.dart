import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../protocols/felica/models/amusement_ic_data.dart';

/// The same frozen Access Code fields are shown after a read and after restart.
/// IDm belongs to the surrounding card identity and is never a code fallback.
class AmusementIcSummary extends StatelessWidget {
  const AmusementIcSummary({
    super.key,
    required this.data,
    this.showRawAccessCode = true,
  });

  final AmusementIcData? data;
  // Live/read-recovery views retain their existing raw evidence presentation.
  // Saved card layouts use the grouped value once, while copying raw digits.
  final bool showRawAccessCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = data?.formattedAccessCode;
    final issuer = data?.issuer;
    final note = data?.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (issuer != null && issuer.isNotEmpty)
          _field(context, '发行品牌', SelectableText(issuer)),
        _field(
          context,
          'Access Code',
          formatted == null
              ? const Text('Access Code 未读取')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      formatted,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showRawAccessCode) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        data!.accessCode!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                    IconButton(
                      tooltip: '复制 Access Code',
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        await Clipboard.setData(
                          ClipboardData(text: data!.accessCode!),
                        );
                        if (messenger?.mounted == true) {
                          messenger!.showSnackBar(
                            const SnackBar(content: Text('已复制 Access Code')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
        ),
        if (note != null && note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(BuildContext context, String label, Widget value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: value),
      ],
    ),
  );
}
