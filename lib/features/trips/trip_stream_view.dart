import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import '../transit_analysis/balance_interpretation.dart';
import 'trip_entry_presenter.dart';
import 'trip_cards_view.dart';
import 'trip_presentation_context.dart';
import 'trip_filters.dart';
import '../../app/app_dependencies.dart';
import 'trip_journey_adapter.dart';
import 'trip_journey_evidence.dart';

/// 行程流统一展示组件（当前读取会话）：
/// - 分别统计交易笔数与过程事件数，0x1E 不重复计入消费；
/// - 完整行程投影后按交通方式与记录来源筛选；
/// - 单条详情：记录来源（0x18 / 0x1E / 0x1A）、关联证据、站点匹配置信、
///   原始十六进制（0x18 交易明细保持行程流与统计的主干来源）。
class TripStreamView extends StatelessWidget {
  const TripStreamView({
    super.key,
    required this.stream,
    required this.app,
    required this.isRemote,
    this.presentationContext,
  });

  final List<TripEntry> stream;
  final AppDependencies app;
  final TripPresentationContext? presentationContext;
  final bool Function(String? cityCode) isRemote;

  @override
  Widget build(BuildContext context) {
    final display =
        presentationContext ??
        TripPresentationContext(
          currency: app.cardCurrency,
          balanceDisplay: app.balanceDisplay,
          cityNameOf: app.cityUnionDetected ? app.cuCityNameOf : app.cityNameOf,
          resolveStationMatch: app.resolveStationMatch,
          resolveCycleStationMatch: app.resolveCycleStationMatch,
          resolveLineName: app.resolveLineName,
          resolveBusLocation: app.resolveBusLocation,
        );
    final entries = <TripCardPresentation<TripSourceFilter>>[];
    final parsed = app.parsedCard;
    final allowProcessBalance =
        parsed != null &&
        BalanceInterpretation.fromParsedCard(
              parsed,
              metadataCurrency: display.currency.code,
            ).semantics ==
            BalanceSemantics.direct;
    final evidence = buildLiveJourneyEvidence(
      stream: stream,
      processRecords: app.transitProcessRecords,
      rails: {
        ?app.railTransitRecord,
        for (final record in app.transitProcessRecords) ?record.railTransit,
      },
      buses: {
        ?app.busTransitRecord,
        for (final record in app.transitProcessRecords) ?record.busTransit,
      },
    );
    for (final group in groupTripsByDate(stream)) {
      for (final entry in group.entries) {
        final remote = isRemote(tripCityCode(entry));
        final info = describeTripEntry(entry, display, remote: remote);
        final journeyEvent = describeJourneyEvent(
          entry,
          display,
          info,
          applicationRecordId: evidence[entry]?.applicationRecordId,
          processPositions: evidence[entry]?.processPositions ?? const {},
          allowProcessBalance: allowProcessBalance,
        );
        entries.add(
          TripCardPresentation(
            info: info,
            source: tripSourceOf(entry),
            mode: journeyEvent.mode,
            dateText: group.dateText,
            remote: remote,
            journeyEvent: journeyEvent,
          ),
        );
      }
    }
    final stats = summarizeTripStream(stream);
    return TripCardsView(
      entries: entries,
      sourceLabels: tripSourceLabels,
      summaryText:
          '交易 ${stats.transactionCount} 笔（消费 ${stats.consumeCount}） · '
          '过程事件 ${stats.processEventCount} 条',
    );
  }
}
