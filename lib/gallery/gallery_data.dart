import 'dart:convert';

import 'package:flutter/services.dart';

typedef GalleryRecord = Map<String, dynamic>;

/// A frozen design snapshot. This loader never opens production reference DBs.
class GalleryData {
  GalleryData(this.json);

  final GalleryRecord json;

  static Future<GalleryData> load() async {
    // This bounded UI fixture is decoded in the owning isolate. Avoid spawning
    // a transient decode isolate while the previous application is disposing.
    final bytes = await rootBundle.load('assets/gallery/fixtures.json');
    return GalleryData(
      jsonDecode(
        utf8.decode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      ) as GalleryRecord,
    );
  }

  List<GalleryRecord> records(String key) =>
      (json[key] as List).cast<GalleryRecord>();

  List<GalleryRecord> get cards => records('cards');
  List<GalleryRecord> get trips => records('trips');
  List<GalleryRecord> get footprints => records('footprints');
  GalleryRecord get knowledge => json['knowledge'] as GalleryRecord;
  GalleryRecord get raw => json['raw'] as GalleryRecord;
  GalleryRecord get expert => json['expert'] as GalleryRecord;
  GalleryRecord get palettes => json['palettes'] as GalleryRecord;

  List<GalleryScene> get scenes => (json['scenes'] as List)
      .map((row) => GalleryScene.fromList(row as List))
      .toList(growable: false);

  List<GalleryRecord> ledger(String cardId) =>
      ((json['ledgers'] as GalleryRecord)[cardId] as List? ?? [])
          .cast<GalleryRecord>();
}

class GalleryScene {
  GalleryScene(
    this.id,
    this.group,
    this.name,
    this.query,
    this.variant,
    this.width,
  );

  factory GalleryScene.fromList(List<dynamic> row) => GalleryScene(
    row[0] as String,
    row[1] as String,
    row[2] as String,
    (row[3] as Map).cast<String, dynamic>(),
    row.length > 4 ? row[4] as String? : null,
    row.length > 5 ? row[5] as int? : null,
  );

  final String id;
  final String group;
  final String name;
  final GalleryRecord query;
  final String? variant;
  final int? width;
}

class GalleryCard {
  GalleryCard.fromJson(GalleryRecord json)
    : id = json['id'] as String,
      saved = json['saved'] as bool,
      name = json['name'] as String,
      tail = json['tail'] as String,
      pan = json['pan'] as String,
      rawBalance = json['balance'] as String,
      city = json['city'] as String,
      type = json['type'] as String,
      valid = json['valid'] as String,
      when = json['when'] as String,
      count = json['count'] as String,
      face = json['face'] as String,
      // Explicit applications win over the frozen sample's known identity.
      // A user-editable name is never evidence of a card's brand or protocol.
      applications = List.unmodifiable(
        (json['applications'] as List?)?.cast<String>() ??
            switch (json['id']) {
              'shanghai' => ['tu', 'cu'],
              'suica' => ['suica'],
              'octopus' => ['octopus'],
              _ => switch (json['type']) {
                '交通联合卡' => ['tu'],
                '城市一卡通' || '城市一卡通卡' => ['cu'],
                _ => <String>[],
              },
            },
      );

  final String id;
  bool saved;
  String name;
  final String tail;
  final String pan;
  String rawBalance;
  final String city;
  final String type;
  final String valid;
  final String when;
  final String count;
  final List<String> applications;
  String face;
  Uint8List? image;

  /// Display precision only; the original captured label remains unchanged.
  String get readDateLabel {
    final date = when
        .replaceFirst(
          RegExp(
            r'\s*T?\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?$',
          ),
          '',
        )
        .trim();
    return date.isEmpty ? '日期未记录' : date;
  }

  // These currencies belong to the frozen samples, not inferred real cards.
  GalleryCurrency? get currency => switch (id) {
    'shanghai' || 'shenzhen' => GalleryCurrency.cny,
    'suica' => GalleryCurrency.jpy,
    'octopus' => GalleryCurrency.hkd,
    _ => null,
  };

  bool get unknownBalance => !RegExp(r'\d').hasMatch(rawBalance);

  String balance(bool includeOverdraft) {
    if (unknownBalance) return '暂不可用';
    if (id != 'shanghai') {
      return RegExp(r'^-?[\d,.]+$').hasMatch(rawBalance)
          ? '¥$rawBalance'
          : rawBalance;
    }
    final value = double.tryParse(rawBalance.replaceAll(',', ''));
    if (value == null) return rawBalance;
    final fen = (value * 100).round() - (includeOverdraft ? 0 : 800);
    return '¥${formatGalleryMoney(fen)}';
  }
}

enum GalleryCurrency {
  cny(100, '元'),
  jpy(1, '日元'),
  hkd(100, '港元');

  const GalleryCurrency(this.scale, this.unit);
  final int scale;
  final String unit;

  String format(int amount) => switch (this) {
    cny => '¥${formatGalleryMoney(amount)}',
    jpy => '${formatGalleryMoney(amount * 100).split('.').first} JPY',
    hkd => 'HK\$${formatGalleryMoney(amount)}',
  };

  /// Only explicit debits in this sample's currency count as spending.
  int? debit(String value) {
    final pattern = switch (this) {
      cny => r'^[−-]¥([\d,]+(?:\.\d{1,2})?)$',
      jpy => r'^[−-]([\d,]+) JPY$',
      hkd => r'^[−-]HK\$([\d,]+(?:\.\d{1,2})?)$',
    };
    final number = RegExp(pattern).firstMatch(value)?.group(1);
    if (number == null) return null;
    final parts = number.replaceAll(',', '').split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    return whole * scale +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }
}

class GalleryWeeklySpending {
  GalleryWeeklySpending(this.currency, Iterable<GalleryRecord> records) {
    if (currency == null) return;
    for (final row in records) {
      final text = row['isoDate'] as String? ?? '';
      final date = DateTime.tryParse(text);
      if (date == null || date.toIso8601String().split('T').first != text) {
        continue;
      }
      final day = date.difference(DateTime(2026, 10, 26)).inDays;
      if (day < 0 || day > 6) continue;
      final amount = currency!.debit(row['amount'] as String? ?? '');
      if (amount == null) continue;
      days[day] += amount;
      final category = switch (row['kind']) {
        'rail' => '轨道交通',
        'bus' => '公共汽电车',
        _ => '其他',
      };
      categories.update(
        category,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
      count++;
    }
  }

  final GalleryCurrency? currency;
  final List<int> days = List<int>.filled(7, 0);
  final Map<String, int> categories = {};
  int count = 0;
  int get total => days.fold(0, (sum, value) => sum + value);
  String format(int amount) => currency?.format(amount) ?? '暂不可用';
}

String formatGalleryMoney(int fen) {
  final absolute = fen.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '${fen < 0 ? '-' : ''}$whole.${(absolute % 100).toString().padLeft(2, '0')}';
}

String galleryHex(List<dynamic> bytes) => bytes
    .map((b) => (b as int).toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');
