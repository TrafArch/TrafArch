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

  test('重庆一票制设施的三笔扣款各计一次乘行并显示设施名称', () {
    final summary = projectGalleryArchiveSpending(
      ArchiveHistoryResult(
        card: null,
        records: [
          _record(amount: 100, busLine: '703', civil: '2025-07-12T10:34:39'),
          _record(amount: 200, busLine: '704', civil: '2025-07-12T10:08:56'),
          _record(amount: 200, busLine: '704', civil: '2025-07-12T10:00:28'),
          _record(amount: 100, kind: ArchiveRecordKind.bus),
        ],
      ),
    );
    expect(summary.total, 500);
    expect(summary.rideCount, 3);
    expect(summary.entries.map((entry) => entry.record['title']), [
      '凯旋路电梯',
      '皇冠大扶梯',
      '皇冠大扶梯',
    ]);
    expect(
      summary.entries.map((entry) => entry.record['kind']),
      everyElement('facility'),
    );
    expect(summary.categories, {'其他': 500});
  });

  test('仅一票制设施保留标为上车的实际扣款', () {
    final summary = projectGalleryArchiveSpending(
      ArchiveHistoryResult(
        card: null,
        records: [
          _record(amount: 150, entry: true, busLine: '701'),
          _record(amount: 160, entry: true, busLine: '702'),
        ],
      ),
    );
    expect(summary.total, 150);
    expect(summary.rideCount, 1);
    expect(summary.entries.single.record['title'], '长江索道');
  });
}

ArchiveHistoryRecord _record({
  required int amount,
  String? currency = 'CNY',
  int? digits = 2,
  String? civil,
  String? busLine,
  bool consume = true,
  bool entry = false,
  ArchiveRecordKind kind = ArchiveRecordKind.transaction,
}) => ArchiveHistoryRecord(
  kind: kind,
  fields: {
    'amountFen': amount,
    'consume': consume,
    'isEntry': entry,
    if (busLine == null)
      'stationType': '地铁'
    else ...{
      'cityCode': '6900',
      'appTypeName': '公共汽电车',
      'lineLabel': busLine,
    },
    if (civil != null)
      'capturedTimes': {
        'time': {'civil': civil},
      },
  },
  context: ArchiveContext(currencyCode: currency, minorUnitDigits: digits),
  sources: const [],
);
