import 'package:flutter/material.dart';
import '../../core/analysis/tunion_analysis_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../core/ui_constants.dart';
import '../../state/app_state.dart';
import '../settings/settings_action_button.dart';

/// 行程页：展示最近一次读卡解析出的行程数据，包括交易行程列表与
/// 0x1A 城市轨道进出站、公共汽电车上下车记录（按进 / 出（上 / 下）
/// 两侧拆为单条行程卡片，样式与 0x1E 行程一致）。
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
    // 交易明细（0x18）与 0x1A 过程记录（轨道进出站 / 公交上下车）合并为
    // 一条按时间倒序的行程流，0x1A 记录也作为其中一条行程记录出现。
    final stream = buildTripStream(trips, railRecord, busRecord);

    if (stream.isEmpty) {
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
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '行程记录（${stream.length} 条）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final entry in stream)
          switch (entry) {
            TransactionTripEntry(:final trip) =>
              _TripCard(trip: trip, app: app),
            RailRecordEntry(:final record, :final isEntry) =>
              _RailRecordTripCard(record: record, isEntry: isEntry, app: app),
            BusRecordEntry(:final record, :final isEntry) =>
              _BusRecordTripCard(record: record, isEntry: isEntry, app: app),
          },
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

/// 0x1A 记录 1 单侧行程（进站 / 出站）：与 0x1E 行程卡片同样式，
/// 站点查不到线路库时回退原始编码（不猜测）。
class _RailRecordTripCard extends StatelessWidget {
  final TransitRecord record;
  final bool isEntry;
  final AppState app;
  const _RailRecordTripCard({
    required this.record,
    required this.isEntry,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = app.cardCurrency.symbol;
    final time = isEntry ? record.entryTime : record.exitTime;
    final cityCode = isEntry ? record.entryCityCode : record.exitCityCode;
    final rawStation = isEntry ? record.entryStationId : record.exitStationId;
    final rawLine =
        (isEntry ? record.entryLineCode : record.exitLineCode)?.toString();
    final station = app.resolveStationName(cityCode, rawStation) ?? rawStation;
    final line = app.resolveLineName(cityCode, rawLine) ?? rawLine;
    final amountFen = isEntry ? record.entryAmountFen : record.exitAmountFen;
    final balanceFen = isEntry ? record.entryBalanceFen : null;
    final isRemote = app.isRemoteUse(cityCode);

    final titleParts = <String>[
      isEntry ? '进站' : '出站',
      if (station != null) station,
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
            if (line != null) ...[
              const SizedBox(height: 4),
              Text(
                line,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (time != null) ...[
              const SizedBox(height: 6),
              Text(
                _fmtTime(time),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (amountFen != null && amountFen > 0)
                  Text(
                    '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.error,
                    ),
                  ),
                if (balanceFen != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '余额 $symbol${(balanceFen / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
                const Spacer(),
                Text(
                  '城市轨道交通',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 0x1A 记录 2 单侧行程（上车 / 下车）：与 0x1E 行程卡片同样式；
/// 交易金额为整程一次性扣费，仅展示在下车侧，里程同侧展示。
class _BusRecordTripCard extends StatelessWidget {
  final BusTransitRecord record;
  final bool isEntry;
  final AppState app;
  const _BusRecordTripCard({
    required this.record,
    required this.isEntry,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final symbol = app.cardCurrency.symbol;
    final time = isEntry ? record.entryTime : record.exitTime;
    final cityCode = isEntry ? record.entryCityCode : record.exitCityCode;
    final rawStation =
        isEntry ? record.entryStationCode : record.exitStationCode;
    final rawLine = isEntry ? record.entryLineCode : record.exitLineCode;
    final station = app.resolveStationName(cityCode, rawStation) ?? rawStation;
    final line = app.resolveLineName(cityCode, rawLine);
    final amountFen = isEntry ? null : record.transactionAmountFen;
    final mileage = isEntry ? null : record.mileage;
    final isRemote = app.isRemoteUse(cityCode);

    final titleParts = <String>[
      isEntry ? '上车' : '下车',
      if (station != null) station,
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
            if (line != null) ...[
              const SizedBox(height: 4),
              Text(
                line,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (time != null) ...[
              const SizedBox(height: 6),
              Text(
                _fmtTime(time),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (amountFen != null && amountFen > 0)
                  Text(
                    '-$symbol${(amountFen / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.error,
                    ),
                  ),
                if (mileage != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '里程 $mileage 站',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
                const Spacer(),
                Text(
                  '公共汽电车',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
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

String _fmtTime(DateTime t) {
  String pad2(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad2(t.month)}-${pad2(t.day)} '
      '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
}
