import 'package:flutter/material.dart';
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../core/ui_constants.dart';
import '../../state/app_state.dart';
import '../settings/settings_action_button.dart';

/// 行程页：展示最近一次读卡解析出的行程数据，包括交易行程列表、
/// 0x1A 城市轨道进出站记录与 0x1A 公共汽电车上下车记录。
class TripsPage extends StatelessWidget {
  final AppState app;
  const TripsPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: const Text('行程'),
              actions: [SettingsActionButton(app: app)],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  12, 12, 12, UiConstants.floatingNavBarClearance,
                ),
                child: _TripsBody(app: app),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsBody extends StatelessWidget {
  final AppState app;
  const _TripsBody({required this.app});

  @override
  Widget build(BuildContext context) {
    if (app.parsing) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final analysis = app.analysis;
    final trips = analysis?.trips ?? const <TransitTrip>[];
    final railRecord = app.railTransitRecord;
    final busRecord = app.busTransitRecord;
    final hasData = trips.isNotEmpty || railRecord != null || busRecord != null;

    if (!hasData) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.directions_transit_outlined),
          title: const Text('暂无行程数据'),
          subtitle: Text(
            app.lastResult == null
                ? '读取卡片后在这里展示解析出的行程记录'
                : '本次读取未解析到行程记录',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analysis != null) ...[
          _SessionHeader(analysis: analysis, app: app),
          const SizedBox(height: 12),
        ],
        if (trips.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '交易行程（${trips.length} 条）',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          for (final trip in trips) _TripCard(trip: trip, app: app),
        ],
        if (railRecord != null) ...[
          const SizedBox(height: 8),
          _RailRecordCard(record: railRecord, app: app),
        ],
        if (busRecord != null) ...[
          const SizedBox(height: 8),
          _BusRecordCard(record: busRecord, app: app),
        ],
      ],
    );
  }
}

/// 本次读卡会话摘要：卡片名称、余额与交易条数。
class _SessionHeader extends StatelessWidget {
  final CardAnalysisResult analysis;
  final AppState app;
  const _SessionHeader({required this.analysis, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final identity = analysis.identity;
    final wallet = analysis.wallet;
    final prefix = app.cardPrefixOf(wallet.cardNumber);
    final cardName = prefix?.cardName ??
        identity.cardFamily ??
        identity.operatorName ??
        '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cardName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wallet.cardNumber ?? '—',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  wallet.balanceText ?? '—',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${analysis.trips.length} 条行程',
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条交易行程卡片。
class _TripCard extends StatelessWidget {
  final TransitTrip trip;
  final AppState app;
  const _TripCard({required this.trip, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRemote = app.isRemoteUse(trip.cityCode);

    final statusName = trip.rideStatusName;
    final titleParts = <String>[
      statusName ?? trip.typeName,
      if (trip.stationLabel != null) trip.stationLabel!,
      '序号 ${trip.sequence}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titleParts.join(' · '),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isRemote) _RemoteBadge(scheme: scheme),
              ],
            ),
            if (trip.lineLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                trip.lineLabel!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              trip.timeText,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  trip.amountText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: trip.isConsume ? scheme.error : scheme.primary,
                  ),
                ),
                if (trip.balanceAfterText != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '余额 ${trip.balanceAfterText}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
                if (trip.appTypeName != null) ...[
                  const Spacer(),
                  Text(
                    trip.appTypeName!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 0x1A 记录 1：城市轨道交通进出站记录卡片。
class _RailRecordCard extends StatelessWidget {
  final TransitRecord record;
  final AppState app;
  const _RailRecordCard({required this.record, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRemote = app.isRemoteUse(record.exitCityCode);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '城市轨道交通 · 进出站记录',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isRemote) _RemoteBadge(scheme: scheme),
              ],
            ),
            const SizedBox(height: 8),
            _kvRow(context, '交易状态', record.statusName),
            if (record.entryTime != null)
              _kvRow(context, '进站时间', _fmtDateTime(record.entryTime!)),
            if (record.exitTime != null)
              _kvRow(context, '出站时间', _fmtDateTime(record.exitTime!)),
            if (record.entryStationId != null)
              _kvRow(context, '进站站点', record.entryStationId!),
            if (record.exitStationId != null)
              _kvRow(context, '出站站点', record.exitStationId!),
            if (record.entryBalanceFen != null)
              _kvRow(
                context,
                '进站余额',
                '¥${(record.entryBalanceFen! / 100).toStringAsFixed(2)}',
              ),
            if (record.exitAmountFen != null)
              _kvRow(
                context,
                '出站金额',
                '¥${(record.exitAmountFen! / 100).toStringAsFixed(2)}',
              ),
          ],
        ),
      ),
    );
  }
}

/// 0x1A 记录 2：公共汽电车上下车记录卡片。
class _BusRecordCard extends StatelessWidget {
  final BusTransitRecord record;
  final AppState app;
  const _BusRecordCard({required this.record, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRemote = app.isRemoteUse(record.exitCityCode);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '公共汽电车 · 上下车记录',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isRemote) _RemoteBadge(scheme: scheme),
              ],
            ),
            const SizedBox(height: 8),
            _kvRow(context, '交易状态', record.statusName),
            if (record.entryTime != null)
              _kvRow(context, '上车时间', _fmtDateTime(record.entryTime!)),
            if (record.exitTime != null)
              _kvRow(context, '下车时间', _fmtDateTime(record.exitTime!)),
            if (record.transactionAmountFen != null)
              _kvRow(
                context,
                '交易金额',
                '¥${(record.transactionAmountFen! / 100).toStringAsFixed(2)}',
              ),
            if (record.mileage != null)
              _kvRow(context, '乘车里程', '${record.mileage} 站'),
            _kvRow(context, '方向', record.directionName),
          ],
        ),
      ),
    );
  }
}

/// 异地用卡标识徽章。
class _RemoteBadge extends StatelessWidget {
  final ColorScheme scheme;
  const _RemoteBadge({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '异地用卡',
        style: TextStyle(
          fontSize: 11,
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

Widget _kvRow(BuildContext context, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );

String _fmtDateTime(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}
