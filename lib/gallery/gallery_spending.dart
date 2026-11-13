import 'gallery_data.dart';

enum GallerySpendingPeriod { all, week, month, year, custom }

/// Calendar days are UTC values, so DST never changes a range's day count.
DateTime galleryCalendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

DateTime? galleryRecordedDate(GalleryRecord record) {
  final text = record['isoDate'];
  if (text is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    return null;
  }
  final parsed = DateTime.tryParse('${text}T00:00:00Z');
  return parsed != null && parsed.toIso8601String().startsWith('${text}T')
      ? parsed
      : null;
}

class GallerySpendingSelection {
  const GallerySpendingSelection.all()
    : period = GallerySpendingPeriod.all,
      start = null,
      end = null;

  GallerySpendingSelection.between(DateTime first, DateTime last)
    : period = GallerySpendingPeriod.custom,
      start = galleryCalendarDay(first),
      end = galleryCalendarDay(last) {
    if (end!.isBefore(start!)) throw ArgumentError('End precedes start');
  }

  const GallerySpendingSelection._(this.period, this.start, this.end);

  factory GallerySpendingSelection.forPeriod(
    GallerySpendingPeriod period,
    DateTime reference,
  ) {
    final day = galleryCalendarDay(reference);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return switch (period) {
      GallerySpendingPeriod.all => const GallerySpendingSelection.all(),
      GallerySpendingPeriod.week => GallerySpendingSelection._(
        period,
        monday,
        monday.add(const Duration(days: 6)),
      ),
      GallerySpendingPeriod.month => GallerySpendingSelection._(
        period,
        DateTime.utc(day.year, day.month),
        DateTime.utc(day.year, day.month + 1, 0),
      ),
      GallerySpendingPeriod.year => GallerySpendingSelection._(
        period,
        DateTime.utc(day.year),
        DateTime.utc(day.year, 12, 31),
      ),
      GallerySpendingPeriod.custom => GallerySpendingSelection.between(
        day,
        day,
      ),
    };
  }

  final GallerySpendingPeriod period;
  final DateTime? start, end;

  GallerySpendingSelection shift(int direction) {
    if (start == null) return this;
    return switch (period) {
      GallerySpendingPeriod.month => GallerySpendingSelection.forPeriod(
        period,
        DateTime.utc(start!.year, start!.month + direction),
      ),
      GallerySpendingPeriod.year => GallerySpendingSelection.forPeriod(
        period,
        DateTime.utc(start!.year + direction),
      ),
      GallerySpendingPeriod.week => GallerySpendingSelection.forPeriod(
        period,
        start!.add(Duration(days: 7 * direction)),
      ),
      GallerySpendingPeriod.custom => GallerySpendingSelection.between(
        start!.add(
          Duration(days: (end!.difference(start!).inDays + 1) * direction),
        ),
        end!.add(
          Duration(days: (end!.difference(start!).inDays + 1) * direction),
        ),
      ),
      GallerySpendingPeriod.all => this,
    };
  }

  bool contains(DateTime? date) =>
      period == GallerySpendingPeriod.all ||
      date != null && !date.isBefore(start!) && !date.isAfter(end!);
}

class GallerySpendingEntry {
  const GallerySpendingEntry(this.record, this.date, this.amount, this.index);
  final GalleryRecord record;
  final DateTime? date;
  final int amount, index;
  String get category => switch (record['kind']) {
    'rail' => '轨道交通',
    'bus' => '公共汽电车',
    _ => '其他',
  };
}

typedef GallerySpendingBucket = ({DateTime date, String label, int amount});

/// The aggregation a trend bar represents; it follows the selected range.
enum GallerySpendingBucketUnit { day, month, year }

/// A read-only projection of retained debits. No inferred dates or currencies.
class GallerySpendingSummary {
  GallerySpendingSummary(
    this.currency,
    Iterable<GalleryRecord> records, {
    this.selection = const GallerySpendingSelection.all(),
  }) {
    var index = 0;
    for (final record in records) {
      final position = index++;
      if (record['kind'] == 'event') continue;
      final amount = currency?.debit(record['amount'] as String? ?? '');
      if (amount == null || amount <= 0) continue;
      final date = galleryRecordedDate(record);
      if (date == null) undatedCount++;
      if (!selection.contains(date)) continue;
      final entry = GallerySpendingEntry(record, date, amount, position);
      entries.add(entry);
      total += amount;
      if (record['kind'] == 'rail' || record['kind'] == 'bus') rideCount++;
      categories.update(
        entry.category,
        (sum) => sum + amount,
        ifAbsent: () => amount,
      );
      if (date != null) {
        datedTotal += amount;
        daily.update(date, (sum) => sum + amount, ifAbsent: () => amount);
      }
    }
    entries.sort((a, b) {
      if (a.date == null && b.date != null) return 1;
      if (a.date != null && b.date == null) return -1;
      final date = a.date == null ? 0 : b.date!.compareTo(a.date!);
      if (date != 0) return date;
      if (a.date != null) {
        final time = (b.record['time'] as String? ?? '').compareTo(
          a.record['time'] as String? ?? '',
        );
        if (time != 0) return time;
      }
      return a.index.compareTo(b.index);
    });
    final dates = daily.keys.toList()..sort();
    firstDay = selection.start ?? (dates.isEmpty ? null : dates.first);
    lastDay = selection.end ?? (dates.isEmpty ? null : dates.last);
  }

  final GalleryCurrency? currency;
  final GallerySpendingSelection selection;
  final entries = <GallerySpendingEntry>[];
  final categories = <String, int>{};
  final daily = <DateTime, int>{};
  int total = 0, datedTotal = 0, rideCount = 0, undatedCount = 0;
  late final DateTime? firstDay, lastDay;

  int? get dailyAverage => firstDay == null
      ? null
      : (datedTotal / (lastDay!.difference(firstDay!).inDays + 1)).round();

  String format(int value) => currency?.format(value) ?? '暂不可用';

  GallerySpendingBucketUnit get bucketUnit {
    if (firstDay == null) return GallerySpendingBucketUnit.day;
    if (selection.period == GallerySpendingPeriod.year) {
      return GallerySpendingBucketUnit.month;
    }
    final span = lastDay!.difference(firstDay!).inDays + 1;
    if (span > 366) return GallerySpendingBucketUnit.year;
    if (span > 31) return GallerySpendingBucketUnit.month;
    return GallerySpendingBucketUnit.day;
  }

  List<GallerySpendingBucket> get buckets {
    if (firstDay == null || currency == null) return [];
    final unit = bucketUnit;
    DateTime key(DateTime date) => switch (unit) {
      GallerySpendingBucketUnit.year => DateTime.utc(date.year),
      GallerySpendingBucketUnit.month => DateTime.utc(date.year, date.month),
      GallerySpendingBucketUnit.day => date,
    };
    final amounts = <DateTime, int>{};
    for (final entry in daily.entries) {
      amounts.update(
        key(entry.key),
        (sum) => sum + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    final result = <GallerySpendingBucket>[];
    var date = key(firstDay!);
    final end = key(lastDay!);
    while (!date.isAfter(end)) {
      result.add((
        date: date,
        label: switch (unit) {
          GallerySpendingBucketUnit.year => '${date.year}年',
          GallerySpendingBucketUnit.month => '${date.year}/${date.month}',
          GallerySpendingBucketUnit.day =>
            selection.period == GallerySpendingPeriod.week
                ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday -
                      1]
                : '${date.month}/${date.day}',
        },
        amount: amounts[date] ?? 0,
      ));
      date = switch (unit) {
        GallerySpendingBucketUnit.year => DateTime.utc(date.year + 1),
        GallerySpendingBucketUnit.month => DateTime.utc(date.year, date.month + 1),
        GallerySpendingBucketUnit.day => date.add(const Duration(days: 1)),
      };
    }
    return result;
  }
}
