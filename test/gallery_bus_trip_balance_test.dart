import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';

void main() {
  late GalleryController controller;

  setUp(() {
    controller = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    controller.hasRead = true;
    controller.monet = false;
  });
  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester,
    GalleryRecord record, {
    required bool archived,
  }) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (archived) {
      controller.navigate(GalleryPage.cards);
      final card = controller.current;
      controller.liveLedgers = {
        card.id: [record],
      };
      controller.openCard(card);
    } else {
      controller.trips = [record];
      controller.navigate(GalleryPage.trips);
    }
    await tester.pumpWidget(GalleryApp(controller: controller));
    await tester.pumpAndSettle();
  }

  for (final archived in [false, true]) {
    final page = archived ? '卡片详情' : '行程';
    for (final (kind, oneWay, sub, balance) in const [
      ('有余额的单端公交', true, '交易后余额 ¥61.39', '¥61.39'),
      ('有余额的双端公交', false, '延安东路 → 静安寺', '¥64.27'),
      ('仅有记录余额的单端公交', true, '记录余额 ¥57.88', null),
    ]) {
      testWidgets('$page：$kind 仅在半模态展示交易后余额', (tester) async {
        await mount(tester, {
          'kind': 'bus',
          'title': '公交 71 路',
          'date': '今天',
          'isoDate': '2026-10-27',
          'time': '08:42',
          'entryTime': '08:07',
          'mode': '公共汽电车',
          'city': '上海',
          'source': '0x18 交易',
          'sub': sub,
          'oneWay': oneWay,
          'amount': '−¥2.47',
          'balanceAfter': ?balance,
        }, archived: archived);

        final ticket = find.byKey(
          ValueKey(oneWay ? 'trip-one-way' : 'trip-endpoints'),
        );
        expect(ticket, findsOneWidget);
        final expectedStops = oneWay ? ['未记录'] : ['延安东路', '静安寺'];
        for (final stop in expectedStops) {
          expect(
            find.descendant(of: ticket, matching: find.text(stop)),
            findsOneWidget,
          );
        }
        final expectedSummary = '公交 71 路，${expectedStops.join(' → ')}';
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(expectedSummary))),
          findsOneWidget,
        );
        for (final amount in ['¥2.47', '¥61.39', '¥64.27', '¥57.88']) {
          expect(find.textContaining(amount), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(amount))),
            findsNothing,
          );
        }
        if (!archived) {
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('trips-summary')),
              matching: find.text(controller.current.balance(false)),
            ),
            findsOneWidget,
          );
        }

        await tester.ensureVisible(ticket);
        await tester.pumpAndSettle();
        await tester.tap(ticket);
        await tester.pumpAndSettle();
        final sheet = find.byKey(const ValueKey('gallery-modal-surface'));
        expect(sheet, findsOneWidget);
        for (final value in ['交易后余额', balance ?? '未知', '−¥2.47']) {
          expect(
            find.descendant(of: sheet, matching: find.text(value)),
            findsOneWidget,
          );
        }
        expect(find.textContaining('¥57.88'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('轨道票面保留扣款，半模态保留对应余额', (tester) async {
    final record = {
      ...controller.trips.first,
      'amount': '−¥4.41',
      'balanceAfter': '¥85.12',
    };
    expect(record['kind'], 'rail');
    await mount(tester, record, archived: false);
    expect(find.text('−¥4.41'), findsOneWidget);
    expect(find.text('¥85.12'), findsNothing);
    final station = find.text('陆家嘴');
    await tester.ensureVisible(station);
    await tester.pumpAndSettle();
    await tester.tap(station);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('gallery-modal-surface'));
    expect(
      find.descendant(of: sheet, matching: find.text('¥85.12')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
