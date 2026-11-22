import '../features/archive/application/archive_history.dart';
import '../features/archive/application/cu_archive_projection.dart';
import '../features/archive/presentation/shanghai_archive_mirrored_records.dart';
import '../features/trips/cu_trip_presenter.dart';
import '../features/trips/trip_filters.dart';
import 'gallery_data.dart';
import 'gallery_spending.dart';

GallerySpendingSummary projectGalleryArchiveSpending(
  ArchiveHistoryResult history, {
  GallerySpendingSelection selection = const GallerySpendingSelection.all(),
}) {
  final currencies = <(String, int)>{};
  final entries = <GallerySpendingEntry>[];
  void addDebit(
    int amount,
    String code,
    int digits,
    String? displayTime,
    String kind,
    String title,
  ) {
    if (amount <= 0 || !RegExp(r'^[A-Z]{3}$').hasMatch(code) || code == 'XXX') {
      return;
    }
    currencies.add((code, digits));
    final currency = _currency(code, digits);
    if (currency == null) return;
    final presentation = <String, dynamic>{
      'kind': kind,
      'title': title,
      if (displayTime != null && displayTime.length >= 16) ...{
        'isoDate': displayTime.substring(0, 10),
        'time': displayTime.substring(11, 16),
      },
      'amount': '−${currency.format(amount)}',
    };
    final date = galleryRecordedDate(presentation);
    if (date == null) presentation.remove('time');
    entries.add(
      GallerySpendingEntry(presentation, date, amount, entries.length),
    );
  }

  for (final record in history.records) {
    final fields = record.fields;
    final amount = fields['amountFen'];
    final code = record.context.currencyCode;
    final digits = record.context.minorUnitDigits;
    if (record.kind != ArchiveRecordKind.transaction ||
        fields['consume'] != true ||
        fields['isEntry'] == true ||
        amount is! int ||
        amount <= 0 ||
        code == null ||
        digits == null) {
      continue;
    }
    final times = fields['capturedTimes'];
    final capturedTime = times is Map ? times['time'] : null;
    final civil = capturedTime is Map ? capturedTime['civil'] : null;
    final timestamp = fields['time'];
    final offset = record.context.timeZoneOffsetMinutes;
    final String? displayTime;
    if (civil is String &&
        RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?$').hasMatch(civil)) {
      displayTime = civil;
    } else if (timestamp is int &&
        timestamp != 0 &&
        offset != null &&
        offset.abs() <= 1440 &&
        timestamp >= -8640000000000000 + 86400000 &&
        timestamp <= 8640000000000000 - 86400000) {
      final time = DateTime.fromMillisecondsSinceEpoch(
        timestamp + offset * 60000,
        isUtc: true,
      );
      displayTime = time.year > 0 && time.year <= 9999
          ? time.toIso8601String()
          : null;
    } else {
      displayTime = null;
    }
    addDebit(
      amount,
      code,
      digits,
      displayTime,
      switch (fields['stationType']) {
        '地铁' || '轨道' || '轨道交通' || '城市轨道交通' => 'rail',
        '公交' || '公共汽电车' => 'bus',
        _ => 'other',
      },
      fields['stationLabel'] is String
          ? fields['stationLabel'] as String
          : '消费',
    );
  }
  final cu = projectCuArchive(history);
  final independent = partitionShanghaiArchiveMirroredRecords(
    history: history,
    cityUnion: cu,
  ).independent;
  final contexts = {
    for (final batch in history.batches)
      batch.id: batch.decoded.snapshot?.context,
  };
  for (final transaction in independent) {
    final debit = transaction.interpretedAmountFen;
    final sources = cu.sources[transaction];
    if (debit == null ||
        debit >= 0 ||
        transaction.qingdaoMetro?.isEntry == true ||
        sources == null ||
        sources.isEmpty ||
        !sources.every((source) {
          final context = contexts[source.batchId];
          return context?.currencyCode == 'CNY' &&
              context?.minorUnitDigits == 2;
        })) {
      continue;
    }
    final trip = describeCuTrip(transaction);
    addDebit(
      -debit,
      'CNY',
      2,
      trip.journeyEvent?.endpoint.time?.toIso8601String(),
      switch (trip.mode) {
        TripModeFilter.rail => 'rail',
        TripModeFilter.bus => 'bus',
        _ => 'other',
      },
      transaction.locationLabel,
    );
  }
  final currency = currencies.length == 1
      ? _currency(currencies.single.$1, currencies.single.$2)
      : null;
  return GallerySpendingSummary.fromEntries(
    currency,
    entries,
    selection: selection,
  );
}

GalleryCurrency? _currency(String code, int digits) => switch ((code, digits)) {
  ('CNY', 2) => GalleryCurrency.cny,
  ('JPY', 0) => GalleryCurrency.jpy,
  ('HKD', 2) => GalleryCurrency.hkd,
  _ => null,
};
