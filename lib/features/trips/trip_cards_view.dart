import 'package:flutter/material.dart';

import 'trip_entry_card.dart';
import 'trip_entry_details.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';

/// A display projection: callers own record identity, context and statistics.
/// Both saved history and live trips use the same filters, cards and sheet.
class TripCardPresentation<S extends Enum> {
  const TripCardPresentation({
    required this.info,
    required this.source,
    required this.mode,
    required this.dateText,
    required this.remote,
    this.onDiagnostics,
  });

  final TripEntryInfo info;
  final S source;
  final TripModeFilter mode;
  final String dateText;
  final bool remote;
  final VoidCallback? onDiagnostics;
}

class TripCardsView<S extends Enum> extends StatefulWidget {
  const TripCardsView({
    super.key,
    required this.entries,
    required this.sourceLabels,
    required this.summaryText,
  });

  final List<TripCardPresentation<S>> entries;
  final Map<S, String> sourceLabels;
  final String summaryText;

  @override
  State<TripCardsView<S>> createState() => _TripCardsViewState<S>();
}

class _TripCardsViewState<S extends Enum> extends State<TripCardsView<S>> {
  final _sources = <S>{};
  final _modes = <TripModeFilter>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<TripCardPresentation<S>>>{};
    for (final entry in widget.entries) {
      if ((_sources.isEmpty || _sources.contains(entry.source)) &&
          (_modes.isEmpty || _modes.contains(entry.mode))) {
        groups.putIfAbsent(entry.dateText, () => []).add(entry);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.summaryText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _AnimatedTripFilter<S>(
                selection: _sources.isEmpty ? null : _sources.single,
                label: '来源',
                dropdownMenuEntries: [
                  DropdownMenuEntry<S?>(value: null, label: '全部来源'),
                  for (final entry in widget.sourceLabels.entries)
                    DropdownMenuEntry<S?>(value: entry.key, label: entry.value),
                ],
                onSelected: (next) => setState(() {
                  _sources
                    ..clear()
                    ..addAll(next == null ? <S>{} : {next});
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AnimatedTripFilter<TripModeFilter>(
                selection: _modes.isEmpty ? null : _modes.single,
                label: '方式',
                dropdownMenuEntries: [
                  const DropdownMenuEntry<TripModeFilter?>(
                    value: null,
                    label: '全部方式',
                  ),
                  for (final entry in tripModeLabels.entries)
                    DropdownMenuEntry<TripModeFilter?>(
                      value: entry.key,
                      label: entry.value,
                    ),
                ],
                onSelected: (next) => setState(() {
                  _modes
                    ..clear()
                    ..addAll(next == null ? <TripModeFilter>{} : {next});
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              widget.entries.isEmpty ? '暂无记录' : '当前筛选条件下没有记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              '${group.key} · ${group.value.length} 条',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in group.value)
            TripEntryCard(
              info: entry.info,
              remote: entry.remote,
              onTap: () => showTripEntryDetails(
                context,
                entry.info,
                onDiagnostics: entry.onDiagnostics,
              ),
            ),
        ],
      ],
    );
  }
}

class _AnimatedTripFilter<T extends Enum> extends StatefulWidget {
  const _AnimatedTripFilter({
    required this.selection,
    required this.label,
    required this.dropdownMenuEntries,
    required this.onSelected,
  });

  final T? selection;
  final String label;
  final List<DropdownMenuEntry<T?>> dropdownMenuEntries;
  final ValueChanged<T?> onSelected;

  @override
  State<_AnimatedTripFilter<T>> createState() => _AnimatedTripFilterState<T>();
}

class _AnimatedTripFilterState<T extends Enum>
    extends State<_AnimatedTripFilter<T>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final selected = widget.dropdownMenuEntries.firstWhere(
      (entry) => entry.value == widget.selection,
    );
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        animated: !reduceMotion,
        onOpen: () => setState(() => _open = true),
        onClose: () => setState(() => _open = false),
        style: MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
          maximumSize: WidgetStatePropertyAll(
            Size(constraints.maxWidth, double.infinity),
          ),
        ),
        menuChildren: [
          for (final entry in widget.dropdownMenuEntries)
            MenuItemButton(
              onPressed: () => widget.onSelected(entry.value),
              child: Text(entry.label),
            ),
        ],
        builder: (context, controller, child) => Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: InputDecorator(
              isFocused: _open,
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
                suffixIcon: AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOutCubic,
                  child: const Icon(Icons.arrow_drop_down),
                ),
              ),
              child: Text(
                selected.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
