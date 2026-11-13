import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_spending.dart';

void main() {
  GalleryRecord debit(
    String? day, {
    String amount = '−¥2.00',
    String kind = 'rail',
  }) => {'isoDate': ?day, 'kind': kind, 'amount': amount};

  test('all history includes undated spending without inventing dates', () {
    final rows = [
      debit('2026-10-01'),
      debit(null),
      debit('2026-10-03', kind: 'shop'),
      debit('2026-10-02', amount: '+¥20.00'),
      debit('2026-10-02', kind: 'event'),
    ];
    final original = jsonEncode(rows);
    final summary = GallerySpendingSummary(GalleryCurrency.cny, rows);
    expect(summary.total, 600);
    expect(summary.datedTotal, 400);
    expect(summary.rideCount, 2);
    expect(summary.dailyAverage, 133);
    expect(summary.undatedCount, 1);
    expect(summary.entries.last.date, isNull);
    expect(summary.categories, {'轨道交通': 400, '其他': 200});
    expect(summary.buckets.map((entry) => entry.amount), [200, 0, 200]);
    expect(jsonEncode(rows), original);
  });

  test(
    'date ranges include both boundaries and retain the original records',
    () {
      final rows = [
        debit('2026-10-01'),
        debit('2026-10-02'),
        debit('2026-10-03'),
        debit('2026-10-04'),
        debit(null),
      ];
      final summary = GallerySpendingSummary(
        GalleryCurrency.cny,
        rows,
        selection: GallerySpendingSelection.between(
          DateTime(2026, 10, 2),
          DateTime(2026, 10, 3),
        ),
      );
      expect(summary.total, 400);
      expect(summary.entries.map((entry) => entry.date!.day), [3, 2]);
      expect(summary.entries.first.record, same(rows[2]));
      expect(summary.dailyAverage, 200);
      expect(summary.undatedCount, 1);
      expect(
        () =>
            GallerySpendingSelection.between(DateTime(2026, 2), DateTime(2026)),
        throwsArgumentError,
      );
    },
  );

  test(
    'calendar navigation handles weeks, leap months, years and custom spans',
    () {
      final week = GallerySpendingSelection.forPeriod(
        GallerySpendingPeriod.week,
        DateTime(2027, 1, 1),
      );
      expect(week.start, DateTime.utc(2026, 12, 28));
      expect(week.end, DateTime.utc(2027, 1, 3));
      expect(week.shift(1).start, DateTime.utc(2027, 1, 4));
      final february = GallerySpendingSelection.forPeriod(
        GallerySpendingPeriod.month,
        DateTime(2028, 2, 29),
      );
      expect(february.end, DateTime.utc(2028, 2, 29));
      expect(february.shift(-1).end, DateTime.utc(2028, 1, 31));
      final year = GallerySpendingSelection.forPeriod(
        GallerySpendingPeriod.year,
        DateTime(2028, 2),
      );
      expect(year.shift(-1).end, DateTime.utc(2027, 12, 31));
      final custom = GallerySpendingSelection.between(
        DateTime(2026, 12, 30),
        DateTime(2027, 1, 2),
      ).shift(1);
      expect(custom.start, DateTime.utc(2027, 1, 3));
      expect(custom.end, DateTime.utc(2027, 1, 6));
    },
  );

  test('invalid dates and other currencies never become dated spending', () {
    final rows = [
      debit('2026-02-30'),
      debit('2026-10-27T00:00:00Z'),
      debit(null, amount: '−HK\$2.00'),
      debit('2026-10-27', amount: '—'),
    ];
    final summary = GallerySpendingSummary(GalleryCurrency.cny, rows);
    expect(summary.total, 400);
    expect(summary.undatedCount, 2);
    expect(summary.dailyAverage, isNull);
    expect(summary.buckets, isEmpty);
    expect(GallerySpendingSummary(null, rows).format(0), '暂不可用');
  });

  test('monthly and yearly buckets sum retained minor units accurately', () {
    final selection = GallerySpendingSelection.forPeriod(
      GallerySpendingPeriod.year,
      DateTime(2028),
    );
    final summary = GallerySpendingSummary(GalleryCurrency.hkd, [
      debit('2028-02-29', amount: '−HK\$10.60'),
      debit('2028-12-31', amount: '−HK\$1.01'),
    ], selection: selection);
    expect(summary.total, 1161);
    expect(summary.buckets.length, 12);
    expect(summary.buckets[1].amount, 1060);
    expect(summary.buckets.last.amount, 101);
    final years = GallerySpendingSummary(GalleryCurrency.jpy, [
      debit('2025-01-01', amount: '−157 JPY'),
      debit('2027-01-01', amount: '−180 JPY'),
    ]);
    expect(years.buckets.map((entry) => entry.amount), [157, 0, 180]);
    expect(years.format(years.total), '337 JPY');
  });

  test('undated frozen Suica and Octopus history remains visible in all', () {
    final data = GalleryData(
      jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
          as GalleryRecord,
    );
    final original = jsonEncode(data.json);
    expect(
      GallerySpendingSummary(GalleryCurrency.jpy, data.ledger('suica')).total,
      337,
    );
    expect(
      GallerySpendingSummary(GalleryCurrency.hkd, data.ledger('octopus')).total,
      1060,
    );
    expect(jsonEncode(data.json), original);
  });
}
