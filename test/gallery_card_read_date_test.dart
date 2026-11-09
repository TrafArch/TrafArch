import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  final data = GalleryData(
    jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
        as GalleryRecord,
  );
  test(
    'wallet read date removes clock precision without rewriting the source',
    () {
      for (final (original, expected) in [
        ('今天 09:41', '今天'),
        ('昨天 20:12', '昨天'),
        ('10月20日 18:03', '10月20日'),
        ('2026-11-09 09:41:05', '2026-11-09'),
        ('2026-11-09T09:41:05+08:00', '2026-11-09'),
        ('2026-11-09', '2026-11-09'),
        ('未记录', '未记录'),
        ('09:41', '日期未记录'),
        ('', '日期未记录'),
      ]) {
        final card = GalleryCard.fromJson({
          ...data.cards.first,
          'when': original,
        });
        expect(card.readDateLabel, expected);
        expect(card.when, original);
      }
    },
  );
}
