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
      face = json['face'] as String;

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
  String face;
  String? image;

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
