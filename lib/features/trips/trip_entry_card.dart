import 'package:flutter/material.dart';

import 'trip_entry_presenter.dart';

class TripEntryCard extends StatelessWidget {
  final TripEntryInfo info;
  final bool remote;
  final VoidCallback onTap;
  const TripEntryCard({
    super.key,
    required this.info,
    required this.remote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      info.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final badge in info.badges) ...[
                    _TagBadge(text: badge, scheme: scheme),
                    const SizedBox(width: 4),
                  ],
                  if (remote)
                    _TagBadge(text: '异地用卡', tertiary: true, scheme: scheme),
                ],
              ),
              if (info.remoteCityText != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '受理城市：${info.remoteCityText}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (info.line != null) ...[
                const SizedBox(height: 4),
                Text(
                  info.line!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (info.timeText != null) ...[
                const SizedBox(height: 6),
                Text(
                  info.timeText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (info.amountText != null)
                    Text(
                      info.amountText!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: info.isConsume ? scheme.error : scheme.primary,
                      ),
                    ),
                  if (info.subText != null)
                    Text(
                      info.subText!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  if (info.category != null)
                    Text(
                      info.category!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String text;
  final bool tertiary;
  final ColorScheme scheme;
  const _TagBadge({
    required this.text,
    required this.scheme,
    this.tertiary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tertiary
            ? scheme.tertiaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: tertiary
              ? scheme.onTertiaryContainer
              : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
