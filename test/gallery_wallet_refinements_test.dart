import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_balance_presentation.dart';
import 'package:transit_card_analyzer/gallery/gallery_controller.dart';
import 'package:transit_card_analyzer/gallery/gallery_data.dart';
import 'package:transit_card_analyzer/gallery/gallery_design.dart';
import 'package:transit_card_analyzer/gallery/gallery_theme.dart';

void main() {
  late GalleryController c;
  setUp(() {
    c = GalleryController(
      GalleryData(
        jsonDecode(File('assets/gallery/fixtures.json').readAsStringSync())
            as GalleryRecord,
      ),
    );
    c.monet = false;
    c.themeMode = ThemeMode.light;
  });
  tearDown(() => c.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(GalleryApp(controller: c));
    await tester.pumpAndSettle();
  }

  group('system gallery card faces', () {
    const channel = MethodChannel('transit_card_analyzer/qr_image');
    final imagePath = File('assets/icon/app_icon.png').absolute.path;
    final corruptPath = File('assets/gallery/fixtures.json').absolute.path;
    late List<MethodCall> calls;

    void mockPicker(Future<String?> Function() pick) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            expect(call.method, 'pickImage');
            expect(call.arguments, isNull);
            return pick();
          });
    }

    setUp(() => calls = []);
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> openFace(WidgetTester tester, GalleryCard card) async {
      c.showOverlay(GalleryOverlay.face, card: card);
      await tester.pumpAndSettle();
    }

    Future<void> mountFace(WidgetTester tester) async {
      c.navigate(GalleryPage.cards);
      await mount(tester);
      await openFace(tester, c.current);
    }

    // File reads and the engine codec must complete outside fake async time.
    Future<void> pickAndFinish(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('从相册选择图片'));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        do {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('正在打开相册…').evaluate().isEmpty) return;
        } while (DateTime.now().isBefore(deadline));
        fail('The gallery image operation did not finish');
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Uint8List seedImage(GalleryCard card) =>
        card.image = File(imagePath).readAsBytesSync();

    BoxDecoration faceDecoration(WidgetTester tester, GalleryCard card) =>
        tester
                .widget<Container>(find.byKey(ValueKey('card-face-${card.id}')))
                .decoration!
            as BoxDecoration;

    testWidgets(
      'selection stores PNG bytes and renders white text from memory',
      (tester) async {
        mockPicker(() async => imagePath);
        c.current.saved = true;
        await mountFace(tester);
        final card = c.current;
        expect(card.image, isNull);
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('face-title-${card.id}')))
              .style!
              .color,
          GalleryCardFace.byId(card.face).foreground,
        );
        await pickAndFinish(tester);
        expect(calls, hasLength(1));
        expect(card.image, isA<Uint8List>());
        expect(card.image!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final image = faceDecoration(tester, card).image!.image;
        expect(image, isA<MemoryImage>());
        expect((image as MemoryImage).bytes, same(card.image));
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('face-title-${card.id}')))
              .style!
              .color,
          Colors.white,
        );
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        final wallet = tester.widget<Container>(
          find.byKey(ValueKey('wallet-card-${card.id}')),
        );
        expect(
          ((wallet.decoration as BoxDecoration).image!.image as MemoryImage)
              .bytes,
          same(card.image),
        );
      },
    );

    testWidgets('another card selection leaves the first owned image intact', (
      tester,
    ) async {
      mockPicker(() async => imagePath);
      await mountFace(tester);
      final first = c.current;
      await pickAndFinish(tester);
      final firstImage = first.image!;
      final snapshot = Uint8List.fromList(firstImage);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      final second = c.cards.firstWhere((card) => card.id != first.id);
      await openFace(tester, second);
      // Even if the native picker reuses the same cache path, each card owns bytes.
      await pickAndFinish(tester);
      expect(calls, hasLength(2));
      expect(second.image, isNotNull);
      expect(identical(second.image, firstImage), isFalse);
      expect(first.image, same(firstImage));
      expect(first.image, orderedEquals(snapshot));
      second.image![0] ^= 0xff;
      expect(first.image, orderedEquals(snapshot));
      second.image![0] ^= 0xff;
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await openFace(tester, first);
      expect(
        (faceDecoration(tester, first).image!.image as MemoryImage).bytes,
        same(firstImage),
      );
    });

    testWidgets(
      'cancel keeps the existing image and allows another selection',
      (tester) async {
        final previous = seedImage(c.current);
        mockPicker(() async => null);
        await mountFace(tester);
        await pickAndFinish(tester);
        expect(c.current.image, same(previous));
        expect(find.text('从相册选择图片'), findsOneWidget);
        mockPicker(() async => imagePath);
        await pickAndFinish(tester);
        expect(calls, hasLength(2));
        expect(identical(c.current.image, previous), isFalse);
      },
    );

    for (final failure in ['corrupt', 'platform', 'missing']) {
      testWidgets('$failure preserves the existing image and can be retried', (
        tester,
      ) async {
        final previous = seedImage(c.current);
        mockPicker(() async {
          if (failure == 'platform') {
            throw PlatformException(code: 'picker_failed');
          }
          if (failure == 'missing') throw MissingPluginException();
          return corruptPath;
        });
        await mountFace(tester);
        await pickAndFinish(tester);
        expect(c.current.image, same(previous));
        expect(
          find.text(
            failure == 'missing'
                ? '当前平台不支持系统相册，请在 Android 上选择图片'
                : '无法读取所选图片，请选择其他图片重试',
          ),
          findsOneWidget,
        );
        mockPicker(() async => imagePath);
        await pickAndFinish(tester);
        expect(calls, hasLength(2));
        expect(identical(c.current.image, previous), isFalse);
        expect(find.textContaining('请在 Android'), findsNothing);
        expect(find.textContaining('无法读取所选图片'), findsNothing);
      });
    }

    testWidgets('oversized image keeps the existing card face', (tester) async {
      final directory = Directory.systemTemp.createTempSync('trafarch-face-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final oversized = File('${directory.path}/oversized.png');
      final handle = oversized.openSync(mode: FileMode.write);
      handle.truncateSync(20 * 1024 * 1024 + 1);
      handle.closeSync();
      final previous = seedImage(c.current);
      mockPicker(() async => oversized.path);
      await mountFace(tester);
      await pickAndFinish(tester);
      expect(c.current.image, same(previous));
      expect(find.text('图片过大，请选择小于 20 MB 的图片'), findsOneWidget);
      expect(find.text('从相册选择图片'), findsOneWidget);
    });

    testWidgets('pending selection disables repeats and timeout allows retry', (
      tester,
    ) async {
      final previous = seedImage(c.current);
      final pending = Completer<String?>();
      mockPicker(() => pending.future);
      await mountFace(tester);
      await tester.tap(find.text('从相册选择图片'));
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('正在打开相册…'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('正在打开相册…'));
      await tester.pump();
      expect(calls, hasLength(1));
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      await tester.pumpAndSettle();
      expect(c.current.image, same(previous));
      expect(find.text('相册选择超时，请重试'), findsOneWidget);
      pending.complete(null);
      await tester.pump();
      mockPicker(() async => imagePath);
      await pickAndFinish(tester);
      expect(calls, hasLength(2));
      expect(identical(c.current.image, previous), isFalse);
      expect(find.text('相册选择超时，请重试'), findsNothing);
    });

    for (final leave in ['close sheet', 'reset generation']) {
      testWidgets('$leave ignores a delayed picker result', (tester) async {
        final card = c.current;
        final previous = seedImage(card);
        final pending = Completer<String?>();
        mockPicker(() => pending.future);
        await mountFace(tester);
        final generation = c.generation;
        await tester.tap(find.text('从相册选择图片'));
        await tester.pump();
        if (leave == 'close sheet') {
          await tester.tap(find.text('完成'));
        } else {
          c.reset();
          expect(c.generation, greaterThan(generation));
        }
        await tester.pumpAndSettle();
        // Open a new face sheet before the old request returns.
        await openFace(tester, c.current);
        final currentImage = c.current.image;
        await tester.runAsync(() async {
          pending.complete(imagePath);
          // Drain real file IO so fake async cannot mask a stale update.
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();
        expect(card.image, same(previous));
        expect(c.current.image, same(currentImage));
        expect(find.text('从相册选择图片'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('restore default removes custom bytes and restores dark text', (
      tester,
    ) async {
      mockPicker(() async => imagePath);
      await mountFace(tester);
      await pickAndFinish(tester);
      c.update(() => c.current.face = 'amber');
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认卡面'));
      await tester.pumpAndSettle();
      expect(c.current.image, isNull);
      expect(c.current.face, 'blue');
      expect(faceDecoration(tester, c.current).image, isNull);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('face-title-shanghai')))
            .style!
            .color,
        GalleryCardFace.byId('blue').foreground,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('wallet text stays readable in every light and dark palette', (
    tester,
  ) async {
    c.navigate(GalleryPage.cards);
    await mount(tester);
    for (final palette in GalleryPalette.values) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        c.update(() {
          c.palette = palette.id;
          c.themeMode = mode;
        });
        await tester.pumpAndSettle();
        final panel = find.byKey(
          ValueKey('wallet-card-${c.savedCards.first.id}'),
        );
        final tokens = Theme.of(tester.element(panel))
            .extension<GalleryTokens>()!;
        final background =
            (tester.widget<Container>(panel).decoration! as BoxDecoration)
                .color!;
        for (final foreground in [tokens.text, tokens.muted]) {
          final a = foreground.computeLuminance() + .05;
          final b = background.computeLuminance() + .05;
          expect(
            a > b ? a / b : b / a,
            greaterThanOrEqualTo(4.5),
            reason: '${palette.id} $mode',
          );
        }
        expect(tokens.dark, mode == ThemeMode.dark);
        expect(find.text('尾号 ${c.savedCards.first.tail}'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'wallet aligns balances and keeps explanations below the divider',
    (tester) async {
      for (final (id, balance) in [
        ('usd-sample', r'USD $0.00'),
        ('mop-sample', 'MOP ¥-123,456.78'),
      ]) {
        c.cards.add(
          GalleryCard.fromJson({
            ...c.data.cards.first,
            'id': id,
            'saved': true,
            'name': id,
            'balance': balance,
          }),
        );
      }
      c.cards[1].rawBalance = '-1,234,567.89';
      final originalBalances = [for (final card in c.cards) card.rawBalance];
      c.navigate(GalleryPage.cards);
      await mount(tester);
      for (final width in [320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 2400);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          double? center;
          double? numberHeight;
          for (final card in c.savedCards) {
            final number = tester.getRect(
              find.byKey(ValueKey('wallet-number-${card.id}')),
            );
            expect(
              find.byKey(ValueKey('wallet-count-${card.id}')),
              findsNothing,
            );
            final divider = tester.getRect(
              find.byKey(ValueKey('wallet-divider-${card.id}')),
            );
            center ??= number.center.dx;
            numberHeight ??= number.height;
            expect(number.center.dx, closeTo(center, .1));
            expect(number.height, closeTo(numberHeight, .1));
            expect(number.bottom, lessThan(divider.top));
            final panel = find.byKey(ValueKey('wallet-card-${card.id}'));
            final metadata = find.descendant(
              of: panel,
              matching: find.text('${card.city} · ${card.type}'),
            );
            final when = find.descendant(
              of: panel,
              matching: find.text('最近读取 ${card.readDateLabel}'),
            );
            expect(metadata, findsOneWidget);
            expect(when, findsOneWidget);
            expect(tester.getTopLeft(metadata).dy, greaterThan(divider.bottom));
            expect(tester.getTopLeft(when).dy, greaterThan(divider.bottom));
            final tail = find.descendant(
              of: panel,
              matching: find.text('尾号 ${card.tail}'),
            );
            expect(tail, findsNothing);
            expect(
              tester.getRect(metadata).center.dy,
              closeTo(tester.getRect(when).center.dy, .1),
            );
            expect(
              find.descendant(
                of: panel,
                matching: find.textContaining(RegExp(r'\d{1,2}:\d{2}')),
              ),
              findsNothing,
            );
            expect(
              find.descendant(of: panel, matching: find.textContaining('••••')),
              findsNothing,
            );
            expect(find.textContaining('交联'), findsNothing);
            final label = tester.widget<Text>(
              find.byKey(ValueKey('wallet-currency-${card.id}')),
            );
            final value = GalleryBalancePresentation.parse(
              card.balance(c.includeOverdraft),
              currencyCode: card.currency?.name.toUpperCase(),
            );
            expect(label.data, value.currencyLabel);
            expect(
              find.byKey(ValueKey('card-thumbnail-${card.id}')),
              findsNothing,
            );
            final item = tester.getRect(
              find.byKey(ValueKey('wallet-card-${card.id}')),
            );
            expect(item.contains(number.center), isTrue);
            final footer = find.byKey(ValueKey('wallet-footer-${card.id}'));
            expect(item.contains(tester.getRect(footer).center), isTrue);
            final scroll = find.descendant(
              of: footer,
              matching: find.byType(Scrollable),
            );
            final position = tester.state<ScrollableState>(scroll).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            expect(
              tester.getRect(when).right,
              closeTo(tester.getRect(footer).right, .1),
            );
            expect(
              tester.getRect(footer).overlaps(tester.getRect(when)),
              isTrue,
            );
          }
          expect(tester.takeException(), isNull, reason: '$width / $scale');
        }
      }
      expect([for (final card in c.cards) card.rawBalance], originalBalances);
    },
  );

  testWidgets(
    'wallet uses themed panels, face badges and ghost menus with grouped actions',
    (tester) async {
      c.navigate(GalleryPage.cards);
      await mount(tester);
      final group = find.byKey(const ValueKey('main-action-group'));
      final tokens = Theme.of(tester.element(group))
          .extension<GalleryTokens>()!;
      expect(
        (tester.widget<DecoratedBox>(group).decoration as BoxDecoration).color,
        tokens.surface2,
      );
      expect(
        find.descendant(of: group, matching: find.byType(VerticalDivider)),
        findsOneWidget,
      );
      for (final card in c.savedCards) {
        final item = tester.widget<Container>(
          find.byKey(ValueKey('wallet-card-${card.id}')),
        );
        final decoration = item.decoration as BoxDecoration;
        expect(decoration.color, tokens.surface);
        expect(decoration.border, isNotNull);
        final badge = tester.widget<Container>(
          find
              .ancestor(
                of: find.byKey(
                  ValueKey(
                    'wallet-${card.type == '交通联合卡' ? 'tunion' : 'contactless'}-${card.id}',
                  ),
                ),
                matching: find.byType(Container),
              )
              .first,
        );
        final gradient =
            (badge.decoration as BoxDecoration).gradient! as LinearGradient;
        final face = GalleryCardFace.byId(card.face);
        expect(gradient.colors, [face.start, face.end]);
        expect(tester.getSize(find.byWidget(badge)), const Size(40, 40));
        if (card.type == '交通联合卡') {
          final logo = tester.widget<SvgPicture>(
            find.byKey(ValueKey('wallet-tunion-${card.id}')),
          );
          expect(
            (logo.bytesLoader as SvgAssetLoader).assetName,
            'assets/gallery/tunion-logo.svg',
          );
          expect(logo.colorFilter, isNull);
          expect(
            find.byKey(ValueKey('wallet-contactless-${card.id}')),
            findsNothing,
          );
        } else {
          final icon = tester.widget<Icon>(
            find.byKey(ValueKey('wallet-contactless-${card.id}')),
          );
          expect(icon.size, greaterThanOrEqualTo(32));
          expect(
            find.byKey(ValueKey('wallet-tunion-${card.id}')),
            findsNothing,
          );
        }
        final menu = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('${card.name} 管理'),
            matching: find.byType(IconButton),
          ),
        );
        expect(menu.style!.side!.resolve({}), BorderSide.none);
        expect(menu.style!.backgroundColor?.resolve({}), isNull);
      }
      await tester.tap(find.byTooltip('深圳通 管理'));
      await tester.pumpAndSettle();
      expect(c.page, GalleryPage.cards);
      expect(c.selectedCard.id, 'shenzhen');
      expect(c.overlay, GalleryOverlay.cardMenu);
      expect(find.text('重命名'), findsOneWidget);
      c.back();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('导出卡片记录'));
      await tester.pumpAndSettle();
      expect(c.overlay, GalleryOverlay.export);
    },
  );

  testWidgets(
    'card face keeps its fields separate for long and unknown money',
    (tester) async {
      c.openCard(c.current);
      await mount(tester);
      for (final width in [320.0, 360.0, 412.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = Size(width, 2400);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final balance in ['86.50', '-1,234,567.89', '—']) {
            c.update(() {
              c.current.rawBalance = balance;
              c.current.name = balance == '86.50'
                  ? '上海公共交通卡'
                  : '上海公共交通卡 交通联合纪念版';
            });
            await tester.pumpAndSettle();
            final face = tester.getRect(
              find.byKey(const ValueKey('card-face-shanghai')),
            );
            final title = tester.getRect(
              find.byKey(const ValueKey('face-title-shanghai')),
            );
            final tail = tester.getRect(
              find.byKey(const ValueKey('face-tail-shanghai')),
            );
            final amount = tester.getRect(
              find.byKey(
                ValueKey(
                  'face-${balance == '—' ? 'unknown' : 'number'}-shanghai',
                ),
              ),
            );
            for (final field in [title, tail, amount]) {
              expect(face.contains(field.topLeft), isTrue);
              expect(
                face.contains(field.bottomRight - const Offset(.01, .01)),
                isTrue,
              );
            }
            expect(amount.top, greaterThan(title.bottom));
            expect(tail.top, greaterThan(title.bottom));
            expect(amount.overlaps(tail), isFalse);
            expect(find.text('当前余额'), findsNothing);
            expect(find.textContaining('最近读取'), findsNothing);
            if (balance == '—') {
              expect(
                find.byKey(const ValueKey('face-currency-shanghai')),
                findsNothing,
              );
            } else {
              expect(find.text('CNY ¥'), findsOneWidget);
            }
            if (scale >= 1.5) expect(tail.top, greaterThan(amount.bottom));
            expect(
              tester.takeException(),
              isNull,
              reason: '$width / $scale / $balance',
            );
          }
        }
      }
    },
  );
}
