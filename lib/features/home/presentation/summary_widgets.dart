import 'package:flutter/material.dart';

List<Widget> summaryNameLine(BuildContext context, String name) => [
  Text(
    name,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w600),
  ),
  const SizedBox(height: 4),
  const Divider(height: 20),
];

Widget summaryField(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Widget summaryHint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.outline),
  ),
);
