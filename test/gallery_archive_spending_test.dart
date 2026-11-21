import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/gallery/gallery_archive_spending.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_spending.dart';

void main() {
  test('only captured debits count, and missing dates cannot enter trends', () {
    final history = ArchiveHistoryResult(
      card: null,
      records: [
        _record(amount: 125, civil: '2026-11-21T23:45:00'),
        _record(amount: 275),
        _record(amount: 500, consume: false),
        _record(amount: 500, entry: true),
        _record(amount: 500, kind: ArchiveRecordKind.process),
        _record(amount: 500, currency: null),
        _record(amount: 500, digits: null),
      ],
    );
    final all = projectGalleryArchiveSpending(history);
    expect(all.currency, GalleryCurrency.cny);
    expect(all.total, 400);
    expect(all.datedTotal, 125);
    expect(all.undatedCount, 1);
    expect(all.rideCount, 2);
    expect(all.daily, {DateTime.utc(2026, 11, 21): 125});
    final ranged = projectGalleryArchiveSpending(
      history,
      selection: GallerySpendingSelection.between(
        DateTime(2026, 11, 21),
        DateTime(2026, 11, 21),
      ),
    );
    expect(ranged.total, 125);
    expect(ranged.dailyAverage, 125);
  });

  test('totals do not mix independently captured currencies', () {
    final mixed = projectGalleryArchiveSpending(
      ArchiveHistoryResult(
        card: null,
        records: [
          _record(amount: 200),
          _record(amount: 120, currency: 'JPY', digits: 0),
        ],
      ),
    );
    expect(mixed.currency, isNull);
    expect(mixed.entries, isEmpty);
    expect(mixed.format(mixed.total), '暂不可用');
  });
}

ArchiveHistoryRecord _record({
  required int amount,
  String? currency = 'CNY',
  int? digits = 2,
  String? civil,
  bool consume = true,
  bool entry = false,
  ArchiveRecordKind kind = ArchiveRecordKind.transaction,
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: {
    'amountFen': amount,
    'consume': consume,
    'isEntry': entry,
    'stationType': '地铁',
    if (civil != null)
      'capturedTimes': {
        'time': {'civil': civil},
      },
  },
  context: ArchiveContext(currencyCode: currency, minorUnitDigits: digits),
  sources: const [],
);
