import 'package:flutter/material.dart';

import 'trip_entry_presenter.dart';
import 'journey_presentation.dart';
import 'trip_filters.dart';

class TripEntryCard extends StatelessWidget {
  final TripEntryInfo info;
  final bool remote;
  final VoidCallback onTap;
  final JourneyPresentation<TripEntryInfo>? journey;
  const TripEntryCard({
    super.key,
    required this.info,
    required this.remote,
    required this.onTap,
    this.journey,
  });

  @override
  Widget build(BuildContext context) {
    if (journey case final ticket?) {
      return _JourneyTicket(journey: ticket, remote: remote, onTap: onTap);
    }
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

class _JourneyTicket extends StatelessWidget {
  const _JourneyTicket({
    required this.journey,
    required this.remote,
    required this.onTap,
  });
  final JourneyPresentation<TripEntryInfo> journey;
  final bool remote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bus = journey.mode == TripModeFilter.bus;
    final first = journey.events.first;
    final date =
        journey.start?.time ?? journey.end?.time ?? first.endpoint.time;
    final dateLabel = date == null
        ? '日期未知'
        : '${date.year}年${date.month}月${date.day}日';
    final city = journey.isCrossCity ? '' : journey.cityLabel ?? '地区未知';
    final mode = bus ? '公共汽电车' : '轨道交通';
    final amount = journey.state == JourneyState.inProgress
        ? null
        : journey.amountText;
    final end = journey.end;
    final start = journey.start;
    final complete = start != null && end != null;
    final seat = journey.seatLabel;
    final radius = BorderRadius.circular(22);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    bus ? Icons.directions_bus_outlined : Icons.subway_outlined,
                    color: scheme.primary,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$city$mode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (remote) ...[
                    _TagBadge(text: '异地用卡', tertiary: true, scheme: scheme),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    onPressed: onTap,
                    tooltip: '查看行程记录',
                    icon: const Icon(Icons.more_vert),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (complete)
                _JourneyEndpoints(
                  start: start,
                  end: end,
                  duration: journey.duration,
                  fareAdjustment: journey.startsWithFareAdjustment,
                )
              else if (start != null)
                _JourneyStop(endpoint: start, bus: bus)
              else if (end != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: _JourneyStop(endpoint: end, bus: bus, right: true),
                )
              else ...[
                Text(
                  first.endpoint.line ?? '线路未记录',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Single-charge buses intentionally have no invented endpoints.
                if (!(bus && journey.state == JourneyState.single)) ...[
                  if (first.endpoint.station != null ||
                      first.role == JourneyEventRole.fareAdjustment) ...[
                    const SizedBox(height: 6),
                    _JourneyStationLabel(
                      station: first.endpoint.station ?? '站点未记录',
                      style: theme.textTheme.titleMedium,
                      fareAdjustment:
                          first.role == JourneyEventRole.fareAdjustment,
                    ),
                  ],
                  if (first.endpoint.timeText case final time?) ...[
                    const SizedBox(height: 6),
                    Text(time, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 1,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TicketDivider(scheme.outlineVariant),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final footer = Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (journey.fareAdjustmentAmountText case final fare?)
                            Text('补票 $fare', style: theme.textTheme.bodySmall),
                          if (amount != null)
                            Text(
                              journey.startsWithFareAdjustment
                                  ? '出站 $amount'
                                  : amount,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (seat != null &&
                              journey.state != JourneyState.inProgress)
                            Text(seat, style: theme.textTheme.bodySmall),
                        ],
                      ),
                      if (amount != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            '行程后余额 ${journey.balanceAfterText ?? '未知'}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                  if (MediaQuery.textScalerOf(context).scale(14) > 22) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dateLabel, style: theme.textTheme.bodySmall),
                        if (amount != null || seat != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: footer,
                          ),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dateLabel, style: theme.textTheme.bodySmall),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: footer,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyEndpoints extends StatelessWidget {
  const _JourneyEndpoints({
    required this.start,
    required this.end,
    required this.duration,
    this.fareAdjustment = false,
  });
  final JourneyEndpoint start;
  final JourneyEndpoint end;
  final Duration? duration;
  final bool fareAdjustment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text, TextStyle? style, {bool right = false}) => Text(
      text,
      textAlign: right ? TextAlign.end : TextAlign.start,
      style: style,
    );
    final lineStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final stationStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    TableRow gap(double height) =>
        TableRow(children: List.generate(3, (_) => SizedBox(height: height)));
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(80),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            label(start.line ?? '', lineStyle),
            const SizedBox.shrink(),
            label(end.line ?? '', lineStyle, right: true),
          ],
        ),
        gap(5),
        TableRow(
          children: [
            _JourneyStationLabel(
              station: start.station ?? '站点未记录',
              style: stationStyle,
              fareAdjustment: fareAdjustment,
            ),
            const _JourneyArrow(duration: null),
            label(end.station ?? '站点未记录', stationStyle, right: true),
          ],
        ),
        gap(8),
        TableRow(
          children: [
            label(_journeyTimeText(start), theme.textTheme.titleMedium),
            _JourneyDuration(duration: duration),
            label(
              _journeyTimeText(end, startDate: start.time),
              theme.textTheme.titleMedium,
              right: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _JourneyStationLabel extends StatelessWidget {
  const _JourneyStationLabel({
    required this.station,
    required this.style,
    this.fareAdjustment = false,
  });

  final String station;
  final TextStyle? style;
  final bool fareAdjustment;

  @override
  Widget build(BuildContext context) {
    final stationText = Text(station, style: style);
    if (!fareAdjustment) return stationText;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(fit: FlexFit.loose, child: stationText),
        const SizedBox(width: 4),
        Text(
          '补票',
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            height: 1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _journeyTimeText(JourneyEndpoint endpoint, {DateTime? startDate}) {
  final time = endpoint.time;
  final dayOffset = startDate == null || time == null
      ? 0
      : DateTime.utc(time.year, time.month, time.day)
            .difference(
              DateTime.utc(startDate.year, startDate.month, startDate.day),
            )
            .inDays;
  final text = endpoint.timeText ?? '';
  return '$text${dayOffset > 0 ? '  +$dayOffset天' : ''}';
}

class _JourneyStop extends StatelessWidget {
  const _JourneyStop({
    required this.endpoint,
    required this.bus,
    this.right = false,
  });
  final JourneyEndpoint endpoint;
  final bool bus;
  final bool right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (endpoint.line case final line?)
          Text(
            line,
            textAlign: right ? TextAlign.end : TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 5),
        Text(
          endpoint.station ?? '站点未记录',
          textAlign: right ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (endpoint.timeText case final text?) ...[
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: right ? TextAlign.end : TextAlign.start,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ],
    );
  }
}

class _JourneyArrow extends StatelessWidget {
  const _JourneyArrow({required this.duration});
  final Duration? duration;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          key: const ValueKey('journey-arrow'),
          width: 72,
          height: 28,
          child: CustomPaint(painter: _TicketArrow(theme.colorScheme.primary)),
        ),
        if (duration != null) _JourneyDuration(duration: duration),
      ],
    );
  }
}

class _JourneyDuration extends StatelessWidget {
  const _JourneyDuration({required this.duration});
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = duration;
    String? label;
    if (value != null) {
      final hours = value.inHours;
      final minutes = value.inMinutes.remainder(60);
      label = hours > 0
          ? '$hours小时${minutes > 0 ? '$minutes分钟' : ''}'
          : value.inMinutes > 0
          ? '${value.inMinutes}分钟'
          : '${value.inSeconds}秒';
    }
    if (label == null) return const SizedBox.shrink();
    return Text(
      label,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _TicketArrow extends CustomPainter {
  const _TicketArrow(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    canvas.drawLine(Offset(3, y), Offset(size.width - 4, y), paint);
    canvas.drawLine(
      Offset(size.width - 13, y - 7),
      Offset(size.width - 4, y),
      paint,
    );
  }

  @override
  bool shouldRepaint(_TicketArrow oldDelegate) => oldDelegate.color != color;
}

class _TicketDivider extends CustomPainter {
  const _TicketDivider(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 9) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 5).clamp(0, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketDivider oldDelegate) => oldDelegate.color != color;
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
