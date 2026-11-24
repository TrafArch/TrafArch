import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import '../../shared/presentation/adaptive_layout.dart';
import '../../shared/domain/remote_card_use.dart';
import '../../app/app_dependencies.dart';
import '../../protocols/transit/card_parser.dart';
import '../../protocols/transit/local/local_card_models.dart';
import '../../protocols/transit/tunion/tunion_cash_log.dart';
import '../qr/presentation/qr_action_button.dart';
import '../settings/presentation/settings_action_button.dart';
import 'trip_stream_view.dart';
import 'tunion_cash_log_view.dart';
import 'cu_transaction_list.dart';
import 'shanghai_mirrored_records.dart';
import 'local_card_trip_list.dart';
import 'local_card_trip_presenter.dart';
import '../recovery/recovery_result_panel.dart';
import 'suica_trip_list.dart';

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
                  child: CurrentTripsBody(app: app),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurrentTripsBody extends StatelessWidget {
  final AppDependencies app;
  final bool showSummary;
  const CurrentTripsBody({
    super.key,
    required this.app,
    this.showSummary = true,
  });

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
    if (app.suicaTrips.isNotEmpty) {
      return SuicaTripList(
        trips: app.suicaTrips,
        initialFilters: app.recoveryFilters['live:suica'],
        onFiltersChanged: (values) =>
            app.recoveryFilters['live:suica'] = values,
      );
    }
    final trips = analysis?.trips ?? const <TransitTrip>[];
    final rail = app.railTransitRecord;
    final bus = app.busTransitRecord;
    final cuTransactions = app.cityUnionTransactions;
    final cashLog = app.applications
        .map((application) => application.payload)
        .whereType<TUnionCashLog>()
        .firstOrNull;
    final cashCount =
        cashLog?.records.where((record) => record.isPurchase).length ?? 0;
    // 地方交通卡（parserId=localCard：武汉通 / 北京互通卡 / 深圳通本地 /
    // 苏州苏薪·计次 / 天府通）的行程流水单独投影到同一票据式行程卡；
    // TU 行程和本地钱包各有来源；双应用同时展示，不合并两边的记录。
    final parser = app.parsedCard?.parserId;
    final localProfile =
        parser == CardParserIds.lingnanTong ||
            parser == CardParserIds.lingnanTunion
        ? LocalTripProfile.lingnan
        : parser == CardParserIds.shenzhenTunion ||
              parser == CardParserIds.localCard &&
                  app.localReadResult?.info.isSZT == true
        ? LocalTripProfile.shenzhen
        : LocalTripProfile.general;
    final primaryLocal =
        parser == CardParserIds.localCard ||
            parser == CardParserIds.lingnanTong ||
            parser == CardParserIds.lingnanTunion ||
            parser == CardParserIds.shenzhenTunion
        ? app.localReadResult
        : null;
    final localApplications = {
      for (final application in app.applications)
        if (application.payload case final ReadResult wallet
            when application.confirmed && wallet.trips.isNotEmpty)
          application.appId: (
            wallet,
            localTripProfileOf({'profile': application.appId}),
          ),
    };
    // Older results carry a primary wallet instead of a per-application row.
    // An APPY + PAY.TICL summary can be a different ReadResult for the same purse.
    final primaryAppId = switch (primaryLocal?.info) {
      CardInfo(isLNT: true) || CardInfo(isYCT: true) => 'lingnan',
      CardInfo(isSZT: true) => 'shenzhen',
      CardInfo(isWHCTC: true) => 'wuhan',
      CardInfo(isSuxin: true) => 'suzhou_suxin',
      CardInfo(isCika: true) => 'suzhou_cika',
      CardInfo(isTFT: true) => 'tft',
      CardInfo(isBmac: true) || CardInfo(isBeijing: true) =>
        localApplications.containsKey('beijing') ? 'beijing' : 'df1001',
      CardInfo(isMacauPass: true) => 'macau',
      _ => null,
    };
    final localWallets = [
      ...localApplications.values,
      if (primaryLocal != null &&
          primaryLocal.trips.isNotEmpty &&
          !localApplications.containsKey(primaryAppId))
        (primaryLocal, localProfile),
    ];
    final localTripCount = localWallets.fold(
      0,
      (total, entry) => total + entry.$1.trips.length,
    );
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
      displayCardType: app.lastIdentified?.identity.cardType,
      tunionTransactions: app.parsedCard?.transactions ?? const [],
      cityUnionTransactions: cuTransactions,
    );

    final noRecords =
        stream.isEmpty &&
        cuTransactions.isEmpty &&
        localWallets.isEmpty &&
        cashCount == 0;
    final emptyRecords = Card(
      child: ListTile(
        leading: const Icon(Icons.directions_transit_outlined),
        title: const Text('暂无行程数据'),
        subtitle: Text(
          app.lastResult == null ? '读取卡片后在这里展示解析出的行程记录' : '本次读取未解析到行程记录',
        ),
      ),
    );
    if (noRecords && !app.isOctopusCard) {
      return emptyRecords;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSummary &&
            (app.isOctopusCard ||
                analysis != null ||
                app.cityUnionDetected ||
                localWallets.isNotEmpty)) ...[
          _SessionHeader(
            analysis: analysis,
            app: app,
            recordCount:
                stream.length +
                cuRecords.independent.length +
                localTripCount +
                cashCount,
          ),
          const SizedBox(height: 12),
        ],
        if (noRecords) emptyRecords,
        if (cashLog != null && cashCount > 0) TUnionCashLogView(log: cashLog),
        if (stream.isNotEmpty)
          TripStreamView(stream: stream, app: app, isRemote: app.isRemoteUse),
        for (final (wallet, profile) in localWallets)
          LocalCardTripList(
            trips: wallet.trips,
            profile: profile,
            currencySymbol: app.cardCurrency.symbol,
            cityNameOf: app.cityNameOf,
            titlePrefix: wallet.info.cardKindLabel,
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
    if (app.isOctopusCard) return _octopusSummary(context);
    final identity = analysis?.identity;
    final wallet = analysis?.wallet;
    final parsed = app.parsedCard;
    final local = app.localReadResult;
    final isLocal =
        local != null &&
        !CardParserIds.isTUnionFamily(parsed?.parserId) &&
        !app.cityUnionDetected;
    final cardNumber = app.cityUnionDetected
        ? app.lastIdentified?.cardNumber ??
              app.cityUnionPublicInfo?.cityCardNumber
        : isLocal
        ? local.info.displayCardNumber ??
              (local.info.cardNumber.isEmpty ? null : local.info.cardNumber)
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
    final balance = parsed?.primaryBalanceFen;
    final balanceText = isLocal && local.info.isCika
        ? local.info.observedRemainingTrips == null
              ? '剩余次数未知'
              : '剩余 ${local.info.observedRemainingTrips} 次'
        : app.balanceDisplay.formatBalance(
                balance,
                symbol: wallet?.currency.symbol ?? app.cardCurrency.symbol,
              ) ??
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
                  balanceText,
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

  Widget _octopusSummary(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cardName =
        app.lastIdentified?.displayName ??
        app.felicaResult?.displayName ??
        '八达通';
    final cardNumber =
        app.lastIdentified?.cardNumber ??
        app.parsedCard?.info.displayCardNumber ??
        app.felicaResult?.idm;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              cardName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cardNumber ?? '未读取到卡号',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              app.octopusBalanceText ?? '港币余额未读取',
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '记录 $recordCount 条',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            if (app.octopusReadNotice case final notice?) ...[
              const SizedBox(height: 10),
              Text(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
