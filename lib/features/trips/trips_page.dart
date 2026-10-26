import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import '../../shared/presentation/ui_constants.dart';
import '../../app/app_dependencies.dart';
import '../qr/presentation/qr_action_button.dart';
import '../settings/presentation/settings_action_button.dart';
import 'trip_stream_view.dart';
import 'cu_transaction_list.dart';

/// 行程页：展示最近一次读卡解析出的行程流（0x18 交易明细为主干，
/// 0x1A / 0x1E 过程记录逐条关联、确认重复合并、无法关联独立保留），
/// 统一统计口径与日期分组 / 来源筛选交互由 [TripStreamView] 提供。
class TripsPage extends StatelessWidget {
  final AppDependencies app;
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
              actions: [
                QrActionButton(app: app),
                SettingsActionButton(app: app),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  UiConstants.floatingNavBarClearance,
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
  final AppDependencies app;
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
    final rail = app.railTransitRecord;
    final bus = app.busTransitRecord;
    final cuTransactions = app.cityUnionTransactions;
    // 0x18 交易明细为主干，0x1A 按侧拆分、0x1E 未关联记录独立保留，
    // 合并为按时间倒序的行程流。
    final stream = buildTripStream(
      trips: trips,
      rails: [?rail],
      buses: [?bus],
      processTrips: app.cycleProcessTrips,
    );

    if (stream.isEmpty && cuTransactions.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.directions_transit_outlined),
          title: const Text('暂无行程数据'),
          subtitle: Text(
            app.lastResult == null ? '读取卡片后在这里展示解析出的行程记录' : '本次读取未解析到行程记录',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analysis != null) ...[
          _SessionHeader(
            analysis: analysis,
            app: app,
            recordCount: stream.length,
          ),
          const SizedBox(height: 12),
        ],
        if (stream.isNotEmpty)
          TripStreamView(stream: stream, app: app, isRemote: app.isRemoteUse),
        if (cuTransactions.isNotEmpty)
          CuTransactionList(transactions: cuTransactions),
      ],
    );
  }
}

/// 本次读卡会话摘要：卡片名称、余额与合并后可见记录总数。
class _SessionHeader extends StatelessWidget {
  final CardAnalysisResult analysis;
  final AppDependencies app;
  final int recordCount;
  const _SessionHeader({
    required this.analysis,
    required this.app,
    required this.recordCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final identity = analysis.identity;
    final wallet = analysis.wallet;
    final prefix = app.cardPrefixOf(wallet.cardNumber);
    final cardName =
        prefix?.cardName ?? identity.cardFamily ?? identity.operatorName ?? '—';

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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wallet.cardNumber ?? '—',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
                  '记录 $recordCount 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
