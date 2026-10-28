import 'package:flutter/material.dart';

import 'trip_entry_card.dart';
import 'trip_entry_details.dart';
import 'trip_entry_presenter.dart';
import 'trip_filters.dart';
import 'journey_presentation.dart';

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
    this.journeyEvent,
  });

  final TripEntryInfo info;
  final S source;
  final TripModeFilter mode;
  final String dateText;
  final bool remote;
  final VoidCallback? onDiagnostics;
  final JourneyEvent<TripEntryInfo>? journeyEvent;
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
    final journeys = projectJourneys(
      widget.entries.map(
        (entry) =>
            entry.journeyEvent?.withPayload(entry) ??
            JourneyEvent(
              payload: entry,
              mode: entry.mode,
              role: JourneyEventRole.unknown,
              endpoint: JourneyEndpoint(
                line: entry.info.line,
                time: DateTime.tryParse(entry.info.timeText ?? ''),
                timeText: entry.info.timeText,
              ),
              amountText: entry.info.amountText,
            ),
      ),
    );
    final visible = journeys
        .where(
          (journey) =>
              (_sources.isEmpty ||
                  journey.events.any(
                    (event) => _sources.contains(event.payload.source),
                  )) &&
              (_modes.isEmpty || _modes.contains(journey.mode)),
        )
        .toList();
    final pending = visible
        .where((journey) => journey.state == JourneyState.inProgress)
        .toList();
    final history = visible
        .where(
          (journey) =>
              journey.state != JourneyState.inProgress &&
              journey.mode != TripModeFilter.other,
        )
        .toList();
    final other = visible
        .where(
          (journey) =>
              journey.state != JourneyState.inProgress &&
              journey.mode == TripModeFilter.other,
        )
        .toList();
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
        _section(context, '行程信息提示', pending),
        _section(context, '历史行程', history),
        if (other.isNotEmpty) _section(context, '其他记录', other),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              widget.entries.isEmpty ? '暂无记录' : '当前筛选条件下没有记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<JourneyPresentation<TripCardPresentation<S>>> journeys,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
          child: Text(
            '$title ${journeys.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final journey in journeys)
          TripEntryCard(
            info: journey.events.first.payload.info,
            remote: journey.events.any((event) => event.payload.remote),
            journey: journey.mode == TripModeFilter.other
                ? null
                : JourneyPresentation(
                    events: [
                      for (final event in journey.events)
                        event.withPayload(event.payload.info),
                    ],
                    mode: journey.mode,
                    state: journey.state,
                    cityLabel: journey.cityLabel,
                    start: journey.start,
                    end: journey.end,
                    duration: journey.duration,
                    amountText: journey.amountText,
                    balanceAfterText: journey.balanceAfterText,
                    seatLabel: journey.seatLabel,
                  ),
            onTap: () => _openJourney(context, journey),
          ),
      ],
    );
  }

  void _openJourney(
    BuildContext context,
    JourneyPresentation<TripCardPresentation<S>> journey,
  ) {
    void open(TripCardPresentation<S> entry) => showTripEntryDetails(
      context,
      entry.info,
      onDiagnostics: entry.onDiagnostics,
    );
    if (journey.events.length == 1) {
      open(journey.events.single.payload);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('行程记录', style: Theme.of(context).textTheme.titleLarge),
                for (final event in journey.events)
                  ListTile(
                    title: Text(event.payload.info.title),
                    subtitle: Text(
                      [
                        ?event.payload.info.timeText,
                        ?event.payload.info.subText,
                        if (event.role == JourneyEventRole.exit &&
                            journey.balanceAfterText != null)
                          '${event.mode == TripModeFilter.bus ? '下车' : '出站'}后余额 ${journey.balanceAfterText}',
                      ].join('\n'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      open(event.payload);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
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
