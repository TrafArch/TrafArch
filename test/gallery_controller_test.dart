import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_spending.dart';

void main() {
  GallerySpendingSummary weeklySummary(
    GalleryCurrency? currency,
    Iterable<GalleryRecord> records,
  ) => GallerySpendingSummary(
    currency,
    records,
    selection: GallerySpendingSelection.forPeriod(
      GallerySpendingPeriod.week,
      GalleryController.clock,
    ),
  );
  late GalleryController c;
  setUp(() {
    final json = jsonDecode(
      File('assets/gallery/fixtures.json').readAsStringSync(),
    ) as GalleryRecord;
    c = GalleryController(GalleryData(json));
  });
  tearDown(() => c.dispose());

  test('design snapshot is complete and QR time is deterministic', () {
    expect(c.data.scenes.length, 52);
    expect(c.data.scenes.map((s) => s.id).toSet().length, 52);
    expect(c.savedCards.map((c) => c.id), ['shenzhen', 'suica', 'octopus']);
    expect(c.data.json['qrValid']['raw'].length, 335);
    expect(c.data.json['qrValid']['certificate'].length, 117);
    expect(
      c.data.json['qrValid']['generation'],
      GalleryController.clock.millisecondsSinceEpoch ~/ 1000,
    );
    final systems = c.data.knowledge['systems'] as Map;
    expect(systems['tu']['regions'].length, 41);
    expect(systems['tu']['entries'], 7658);
    expect(systems['cu']['regions'].length, 7);
    expect(systems['cu']['entries'], 1732);
  });

  test(
    'all 52 scene commands restore isolated deterministic session state',
    () {
      for (final scene in c.data.scenes) {
        c.current.name = '此前会话修改';
        c.includeOverdraft = true;
        c.applyScene(scene);
        expect(c.sceneId, scene.id);
        expect(c.current.name, isNot('此前会话修改'));
        expect(c.includeOverdraft, isFalse);
        expect(c.cards.length, 4);
        expect(c.qr.busy, isFalse);
        expect(c.selectedCard.id, 'shanghai');
      }
    },
  );

  testWidgets(
    'read, save, rename, card face and delete share the same in-memory card',
    (tester) async {
      c.read();
      c.read(); // No duplicate acquisition.
      await tester.pump(const Duration(milliseconds: 1600));
      expect(c.hasRead, isTrue);
      expect(c.current.saved, isFalse);
      c.save('通勤卡');
      expect(c.savedCards.length, 4);
      c.openCard(c.current);
      c.rename('上海通勤');
      c.update(() => c.selectedCard.face = 'teal');
      expect(c.current.name, '上海通勤');
      expect(c.current.face, 'teal');
      c.deleteCard();
      expect(c.current.saved, isFalse);
      expect(c.page, GalleryPage.cards);
      c.reset();
      expect(c.current.name, '上海公共交通卡');
      expect(c.savedCards.length, 3);
    },
  );

  testWidgets('failed reread preserves previous results and balance', (
    tester,
  ) async {
    c.read();
    await tester.pump(const Duration(milliseconds: 1600));
    c.save('保留名称');
    c.read(fail: true);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(c.readState, GalleryReadState.failed);
    expect(c.hasRead, isTrue);
    expect(c.current.name, '保留名称');
    expect(c.current.balance(false), '¥78.50');
  });

  testWidgets('QR navigation cancels NFC simulation and late callbacks', (
    tester,
  ) async {
    c.read();
    c.navigate(GalleryPage.qr);
    await tester.pump(const Duration(seconds: 2));
    expect(c.hasRead, isFalse);
    expect(c.readState, GalleryReadState.unread);
    c.qr.open('camera');
    c.qr.acquire('valid');
    c.back();
    await tester.pump(const Duration(seconds: 1));
    expect(c.qr.result, isNull);
    expect(c.qr.view, 'inspect');
    expect(c.hasRead, isFalse);
  });

  testWidgets(
    'QR keeps results on cancellation and unrecognized image, clears only QR',
    (tester) async {
      c.read();
      await tester.pump(const Duration(milliseconds: 1600));
      c.save('模拟卡片');
      c.navigate(GalleryPage.qr);
      c.qr.open('gallery');
      c.qr.acquire('valid');
      await tester.pump(const Duration(milliseconds: 700));
      final previous = c.qr.result;
      c.qr.open('gallery');
      c.qr.acquire('expired');
      c.qr.cancel();
      await tester.pump(const Duration(milliseconds: 800));
      expect(c.qr.result, same(previous));
      c.qr.open('gallery');
      c.qr.acquire('no-code');
      await tester.pump(const Duration(milliseconds: 700));
      expect(c.qr.result, same(previous));
      expect(c.qr.raw.length, 335);
      c.qr.clear();
      expect(c.qr.result, isNull);
      expect(c.current.saved, isTrue);
      expect(c.hasRead, isTrue);
    },
  );

  testWidgets('scene switch and reset invalidate all pending work', (
    tester,
  ) async {
    c.read();
    c.qr.open('gallery');
    c.qr.acquire('valid');
    c.applyScene(c.data.scenes.firstWhere((s) => s.id == 'home-unknown'));
    await tester.pump(const Duration(seconds: 2));
    expect(c.current.unknownBalance, isTrue);
    expect(c.qr.result, isNull);
    c.reset();
    expect(c.hasRead, isFalse);
    expect(c.current.balance(false), '¥78.50');
  });

  testWidgets(
    'auto save and allowance are reversible without changing source values',
    (tester) async {
      c.setAutoSave(true);
      c.read();
      await tester.pump(const Duration(milliseconds: 1600));
      expect(c.current.saved, isTrue);
      final raw = c.current.rawBalance;
      final originalTrips = jsonEncode(c.trips);
      for (var i = 0; i < 10; i++) {
        c.update(() => c.includeOverdraft = !c.includeOverdraft);
      }
      expect(c.current.balance(false), '¥78.50');
      expect(c.current.balance(true), '¥86.50');
      expect(c.cards[1].balance(false), '¥31.20');
      expect(c.current.rawBalance, raw);
      expect(jsonEncode(c.trips), originalTrips);
      c.current.rawBalance = '5.00';
      expect(c.current.balance(false), '¥-3.00');
      c.current.rawBalance = '—';
      expect(c.current.balance(false), '暂不可用');
    },
  );

  test('filters operate on trip source and mode without mutating data', () {
    c.applyScene(c.data.scenes.firstWhere((s) => s.id == 'main-trips'));
    expect(c.filteredTrips.length, 5);
    c.source = '0x1E 过程';
    expect(c.filteredTrips.length, 2);
    c.mode = '公共汽电车';
    expect(c.filteredTrips, isEmpty);
    expect(c.trips.length, 6);
  });

  test('weekly samples keep explicit CNY, JPY and HKD currencies', () {
    for (final sample in [
      (GalleryCurrency.cny, '−¥1,234.56', 123456, '¥1,234.56'),
      (GalleryCurrency.jpy, '−1,234 JPY', 1234, '1,234 JPY'),
      (GalleryCurrency.hkd, '−HK\$1,234.56', 123456, 'HK\$1,234.56'),
    ]) {
      final summary = weeklySummary(sample.$1, [
        {'isoDate': '2026-10-26', 'amount': sample.$2, 'kind': 'rail'},
        {'isoDate': '2026-11-01', 'amount': sample.$2, 'kind': 'bus'},
        {'isoDate': '2026-10-25', 'amount': sample.$2, 'kind': 'rail'},
        {'isoDate': '2026-11-02', 'amount': sample.$2, 'kind': 'rail'},
        {'amount': sample.$2, 'kind': 'rail'},
        {'isoDate': '2026-10-27', 'amount': '—', 'kind': 'rail'},
        {'isoDate': '2026-10-27', 'amount': '+¥20.00', 'kind': 'rail'},
        {'isoDate': '2026-10-27', 'amount': '−EUR2.00', 'kind': 'rail'},
      ]);
      expect(summary.rideCount, 2);
      expect(summary.buckets.map((bucket) => bucket.amount).toList(), [
        sample.$3,
        0,
        0,
        0,
        0,
        0,
        sample.$3,
      ]);
      expect(summary.total, sample.$3 * 2);
      expect(summary.categories, {'轨道交通': sample.$3, '公共汽电车': sample.$3});
      expect(summary.format(sample.$3), sample.$4);
    }
    expect(GalleryCurrency.jpy.debit('−1.23 JPY'), isNull);
    expect(GalleryCurrency.cny.debit('−HK\$2.00'), isNull);
  });

  test('weekly snapshot does not invent dates or an unknown currency', () {
    final original = jsonEncode(c.data.json);
    expect(weeklySummary(c.current.currency, c.ledger(c.current)).total, 1200);
    for (final card in c.cards.where(
      (card) => card.id == 'suica' || card.id == 'octopus',
    )) {
      final weekly = weeklySummary(card.currency, c.ledger(card));
      expect(weekly.rideCount, 0);
      expect(weekly.total, 0);
      expect(weekly.format(0), card.id == 'suica' ? '0 JPY' : 'HK\$0.00');
    }
    final unknown = weeklySummary(null, [
      {'isoDate': '2026-10-27', 'amount': '−¥2.00', 'kind': 'bus'},
    ]);
    expect(unknown.format(0), '暂不可用');
    expect(unknown.categories, isEmpty);
    expect(jsonEncode(c.data.json), original);
  });

  test('logs and export remain previews with no card data in UI logs', () {
    c.navigate(GalleryPage.settings);
    expect(c.logs, isEmpty);
    c.setLogs(true);
    c.navigate(GalleryPage.cards);
    c.showOverlay(GalleryOverlay.rename, card: c.cards[1]);
    c.rename('私人名称');
    c.export(log: true);
    expect(c.exportText, contains('logging-enabled'));
    expect(c.exportText, isNot(contains('私人名称')));
    expect(c.exportText, isNot(contains('3100 0000')));
    c.setLogs(false);
    final count = c.logs.length;
    c.navigate(GalleryPage.home);
    expect(c.logs.length, count);
    c.reset();
    expect(c.themeMode, ThemeMode.system);
  });
}
