import 'package:flutter/material.dart';

import '../../protocols/transit/local/local_card_models.dart';
import 'local_card_trip_presenter.dart';
import 'trip_cards_view.dart';

/// 地方交通卡行程列表：把解析出的 [ApduRecord] 行程流适配到共享的
/// 票据式行程卡（与 TU / CU 同一 [TripCardsView] 与来源 / 方式筛选）。
///
/// 记录身份、来源与统计由调用方持有；本组件只做适配与展示。
class LocalCardTripList extends StatelessWidget {
  const LocalCardTripList({
    super.key,
    required this.trips,
    required this.currencySymbol,
    this.profile = LocalTripProfile.general,
    this.cityNameOf,
    this.isRemote,
    this.titlePrefix,
    this.initialFilters,
    this.onFiltersChanged,
    this.showHeader = true,
  });

  final List<ApduRecord> trips;
  final String currencySymbol;
  final LocalTripProfile profile;
  final String? Function(String?)? cityNameOf;
  final bool Function(ApduRecord)? isRemote;
  final String? titlePrefix;
  final List<String>? initialFilters;
  final ValueChanged<List<String>>? onFiltersChanged;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final trip in trips)
        describeLocalTrip(
          trip,
          currencySymbol: currencySymbol,
          profile: profile,
          cityName: trip.cityCode > 0
              ? cityNameOf?.call('${trip.cityCode}')
              : null,
          remote: isRemote?.call(trip) ?? false,
          titlePrefix: titlePrefix,
        ),
    ];
    return TripCardsView(
      entries: entries,
      sourceLabels: localTripSourceLabels,
      summaryText: showHeader
          ? '${switch (profile) {
              LocalTripProfile.lingnan => '岭南通',
              LocalTripProfile.shenzhen => '深圳通',
              LocalTripProfile.general => '地方交通卡',
            }} · ${trips.length} 条记录'
          : '记录 ${trips.length} 条',
      initialFilters: initialFilters,
      onFiltersChanged: onFiltersChanged,
    );
  }
}
