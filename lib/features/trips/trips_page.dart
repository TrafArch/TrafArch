import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import '../../shared/presentation/adaptive_layout.dart';
import '../../shared/domain/remote_card_use.dart';
import '../../app/app_dependencies.dart';
import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/local/local_card_models.dart';
import '../qr/presentation/qr_action_button.dart';
import '../settings/presentation/settings_action_button.dart';
import 'trip_stream_view.dart';
import 'cu_transaction_list.dart';
import 'shanghai_mirrored_records.dart';
import 'local_card_trip_list.dart';
import '../recovery/recovery_result_panel.dart';

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
              child: AdaptiveContent(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    AdaptiveWindowScope.bottomClearanceOf(context),
                  ),
                  child: _TripsBody(app: app),
                ),
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
    if (app.recoveredCapture != null) return RecoveryResultPanel(app: app);
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
    // 地方交通卡（parserId=localCard：武汉通 / 北京互通卡 / 深圳通本地 /
    // 苏州苏薪·计次 / 天府通）的行程流水单独投影到同一票据式行程卡；
    // 岭南通 / 澳门通 / BMAC 各自有专属面板，TU 家族（含岭南通·交通联合 /
    // 深圳通交通联合版）已由分析链路接管，均不在此重复展示。
    final localTrips = app.parsedCard?.parserId == CardParserIds.localCard
        ? (app.localReadResult?.trips ?? const <ApduRecord>[])
        : const <ApduRecord>[];
    // 0x18 交易明细为主干，0x1A 按侧拆分、0x1E 未关联记录独立保留，
    // 合并为按时间倒序的行程流。
    final stream = buildTripStream(
      trips: trips,
      rails: [?rail],
      buses: [?bus],
      processTrips: app.cycleProcessTrips,
    );
    final cuRecords = partitionShanghaiMirroredRecords(
      parserId: stream.isEmpty ? null : app.parsedCard?.parserId,
      tunionTransactions: app.parsedCard?.transactions ?? const [],
      cityUnionTransactions: cuTransactions,
    );

    if (stream.isEmpty && cuTransactions.isEmpty && localTrips.isEmpty) {
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
        if (analysis != null || app.cityUnionDetected || localTrips.isNotEmpty) ...[
          _SessionHeader(
            analysis: analysis,
            app: app,
            recordCount: stream.length +
                cuRecords.independent.length +
                localTrips.length,
          ),
          const SizedBox(height: 12),
        ],
        if (stream.isNotEmpty)
          TripStreamView(stream: stream, app: app, isRemote: app.isRemoteUse),
        if (localTrips.isNotEmpty)
          LocalCardTripList(
            trips: localTrips,
            currencySymbol: app.cardCurrency.symbol,
            cityNameOf: app.cityNameOf,
            titlePrefix: app.localReadResult?.info.cardKindLabel,
            initialFilters: app.recoveryFilters['live:local'],
            onFiltersChanged: (values) =>
                app.recoveryFilters['live:local'] = values,
          ),
        if (cuTransactions.isNotEmpty)
          CuApplicationRecords(
            records: cuRecords,
            cityNameOf: app.cuCityNameOf,
            isRemote: (transaction) => isRemoteCardUse(
              app.cityUnionPublicInfo?.cityCode,
              transaction.regionCode,
            ),
            initialFilters: app.recoveryFilters['live:cu'],
            onFiltersChanged: (values) =>
                app.recoveryFilters['live:cu'] = values,
            currencySymbol: app.cardCurrency.symbol,
          ),
      ],
    );
  }
}

/// 本次读卡会话摘要：卡片名称、余额与合并后可见记录总数。
class _SessionHeader extends StatelessWidget {
  final CardAnalysisResult? analysis;
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
    final identity = analysis?.identity;
    final wallet = analysis?.wallet;
    final local = app.localReadResult;
    final isLocal = local != null;
    final cardNumber = app.cityUnionDetected
        ? app.lastIdentified?.cardNumber ??
              app.cityUnionPublicInfo?.cityCardNumber
        : isLocal
        ? (local.info.cardNumber.isEmpty ? null : local.info.cardNumber)
        : wallet?.cardNumber;
    final prefix = analysis == null ? null : app.cardPrefixOf(cardNumber);
    final cardName = app.cityUnionDetected
        ? app.lastIdentified?.displayName ?? '城市一卡通'
        : isLocal
        ? local.info.cardKindLabel
        : prefix?.cardName ??
              identity?.cardFamily ??
              identity?.operatorName ??
              '—';
    final balance =
        isLocal
            ? local.info.observedBalance
            : wallet?.balanceFen ??
                  (app.cityUnionDetected ? app.parsedCard?.info.balanceFen : null);

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
                    cardNumber ?? '—',
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
                  app.balanceDisplay.formatBalance(
                        balance,
                        symbol:
                            wallet?.currency.symbol ?? app.cardCurrency.symbol,
                      ) ??
                      '—',
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
