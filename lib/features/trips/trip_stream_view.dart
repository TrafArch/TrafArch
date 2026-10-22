import 'package:flutter/material.dart';

import '../transit_analysis/tunion_analysis_models.dart';
import 'trip_entry_presenter.dart';
import 'trip_cards_view.dart';
import 'trip_presentation_context.dart';
import 'trip_filters.dart';
import '../../app/app_dependencies.dart';

/// 行程流统一展示组件（当前读取会话）：
/// - 统一统计口径：交易笔数 / 过程事件数 / 实际行程数，0x1E 不重复计入消费；
/// - 日期分组、交通方式与记录来源筛选；
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
          cityNameOf: app.cityUnionDetected ? app.cuCityNameOf : app.cityNameOf,
          resolveStationMatch: app.resolveStationMatch,
          resolveCycleStationMatch: app.resolveCycleStationMatch,
          resolveLineName: app.resolveLineName,
          resolveBusLocation: app.resolveBusLocation,
        );
    final entries = <TripCardPresentation<TripSourceFilter>>[];
    for (final group in groupTripsByDate(stream)) {
      for (final entry in group.entries) {
        final remote = isRemote(tripCityCode(entry));
        entries.add(
          TripCardPresentation(
            info: describeTripEntry(entry, display, remote: remote),
            source: tripSourceOf(entry),
            mode: tripModeOf(entry),
            dateText: group.dateText,
            remote: remote,
          ),
        );
      }
    }
    return TripCardsView(
      entries: entries,
      sourceLabels: tripSourceLabels,
      summaryText: summarizeTripStream(stream).summaryText,
    );
  }
}
