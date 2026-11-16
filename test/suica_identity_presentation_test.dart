import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/archive/domain/pending_card_save.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/home/presentation/felica_summary_panel.dart';
import 'package:transit_card_analyzer/features/home/presentation/pending_save_presenter.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

import 'support/test_database.dart';

const _idm = '0123456789ABCDEF';
const _fingerprint = 'felica:suica:idm:$_idm';
const _suica = CardArchiveIdentity(
  cardType: CardTypes.suica,
  officialName: 'Suica',
);

void main() {
  testWidgets('live Suica identity distinguishes selectable IDm from JE', (
    tester,
  ) async {
    await _pump(
      tester,
      FelicaSummaryPanel(
        felica: FelicaScanResult(
          cardType: 'suica',
          displayName: 'Suica',
          cardProductType: FelicaCardType.suica,
          idm: _idm,
          scannedAt: DateTime(2026, 11, 16),
        ),
      ),
    );
    _expectSuicaIdentity();
    expect(find.text('IDm'), findsNothing);
  });

  testWidgets('save dialog identifies Suica without a missing card number', (
    tester,
  ) async {
    await _pump(
      tester,
      SaveCardDialog(
        pending: PendingCardSave(
          fingerprint: _fingerprint,
          identity: _suica,
          sessionDataJson: _snapshot(),
        ),
      ),
    );
    _expectSuicaIdentity();
    expect(find.text('未读取到卡号'), findsNothing);
    expect(find.text('卡号'), findsNothing);
  });

  testWidgets(
    'saved Suica shows frozen IDm and retains real balance failures',
    (tester) async {
      await _pumpDetail(tester, snapshot: _snapshot());
      _expectSuicaIdentity(showReadExplanation: false);
      expect(find.text('卡面编号（手工填写）'), findsNothing);
      expect(find.text('填写卡面编号'), findsOneWidget);
      expect(find.text('卡号未提供'), findsNothing);
      expect(find.textContaining('卡号未读到'), findsNothing);
      expect(find.textContaining('余额未读到'), findsOneWidget);
    },
  );

  testWidgets('legacy Suica can display a verified fingerprint IDm', (
    tester,
  ) async {
    await _pumpDetail(tester);
    _expectSuicaIdentity(showReadExplanation: false);
    expect(find.text('卡号未提供'), findsNothing);
  });

  testWidgets(
    'conflicting captured IDm is not silently presented as identity',
    (tester) async {
      await _pumpDetail(tester, snapshot: _snapshot(idm: 'FEDCBA9876543210'));
      expect(find.text('卡片标识（IDm）'), findsOneWidget);
      expect(find.textContaining('标识不一致'), findsOneWidget);
      expect(find.text(_idm), findsNothing);
      expect(find.text('FEDCBA9876543210'), findsNothing);
      expect(find.text('卡号未提供'), findsNothing);
      expect(find.text('填写卡面编号'), findsNothing);
      expect(find.textContaining('无法确认档案身份'), findsOneWidget);
    },
  );

  testWidgets('malformed Suica fingerprint does not become an IDm', (
    tester,
  ) async {
    await _pumpDetail(tester, fingerprint: 'felica:suica:idm:1234');
    expect(find.text('卡片标识（IDm）'), findsOneWidget);
    expect(find.text('1234'), findsNothing);
    expect(find.text('IDm 未读取'), findsOneWidget);
    expect(find.text('填写卡面编号'), findsNothing);
    expect(find.textContaining('无法确认档案身份'), findsOneWidget);
  });

  testWidgets(
    'wallet conditionally shows manual number beside IDm at narrow large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final db = testDatabase();
      final app = AppDependencies(
        database: db,
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await tester.runAsync(
        () => app.cardRepository.saveIdentity(
          fingerprint: _fingerprint,
          identity: _suica,
          sessionDataJson: _snapshot(),
          balanceFen: 900,
          currencyCode: 'JPY',
        ),
      );
      await _pump(tester, CardsPage(app: app), scroll: false, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('IDm'), findsWidgets);
      expect(find.textContaining(_idm), findsOneWidget);
      expect(find.text('卡号未提供'), findsNothing);
      expect(find.textContaining('JP￥900'), findsOneWidget);
      expect(find.text('卡面编号（手工填写）'), findsNothing);
      expect(find.text('卡面编号（IDi）'), findsNothing);
      await tester.runAsync(() async {
        final card = (await app.cardRepository.getAllCards()).single;
        await app.cardRepository.setSuicaManualNumber(
          card.id,
          'JE123456789012345',
        );
      });
      await tester.pumpAndSettle();
      expect(find.text(_idm), findsOneWidget);
      expect(find.text('卡面编号（手工填写）'), findsOneWidget);
      expect(find.text('JE123 4567 8901 2345'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final card = (await app.cardRepository.getAllCards()).single;
        await app.cardRepository.setSuicaManualNumber(card.id, null);
      });
      await tester.pumpAndSettle();
      expect(find.text(_idm), findsOneWidget);
      expect(find.text('卡面编号（手工填写）'), findsNothing);
      expect(find.text('JE123 4567 8901 2345'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary transit cards retain card number missing diagnostics', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      identity: const CardArchiveIdentity(cardType: CardTypes.chinaTunion),
      fingerprint: 'tunion::12345678',
      snapshot: _snapshot(),
    );
    expect(find.text('卡号未提供'), findsOneWidget);
    expect(find.textContaining('卡号未读到'), findsOneWidget);
    expect(find.text('卡片标识（IDm）'), findsNothing);
    expect(find.text('卡面编号（IDi）'), findsNothing);
    expect(find.text('填写卡面编号'), findsNothing);
  });

  testWidgets('wallet checks IDm conflicts across every archived capture', (
    tester,
  ) async {
    final app = AppDependencies(
      database: testDatabase(),
      bundle: MissingTestAssets(),
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    await tester.runAsync(() async {
      await app.cardRepository.saveIdentity(
        fingerprint: _fingerprint,
        identity: _suica,
        sessionDataJson: _snapshot(idm: 'FEDCBA9876543210'),
        readAt: DateTime(2026, 11, 15),
      );
      await app.cardRepository.saveIdentity(
        fingerprint: _fingerprint,
        identity: _suica,
        sessionDataJson: _snapshot(),
        readAt: DateTime(2026, 11, 16),
      );
    });
    await _pump(tester, CardsPage(app: app), scroll: false);
    expect(find.textContaining('标识不一致'), findsOneWidget);
    expect(find.textContaining(_idm), findsNothing);
  });

  testWidgets('unsupported manual metadata remains visible as unavailable', (
    tester,
  ) async {
    for (final metadata in <Object?>[
      {
        'version': 2,
        'source': 'user',
        'value': 'JE123456789012345',
        'updatedAt': 1,
      },
      {'version': 1, 'source': 'user', 'value': 123, 'updatedAt': 1},
      null,
    ]) {
      final repository = await _pumpDetail(
        tester,
        snapshot: _snapshot(),
        cardExtensions: {'suicaManualNumber': metadata},
      );
      expect(find.textContaining('当前版本无法编辑'), findsOneWidget);
      expect(find.textContaining('原始资料已保留'), findsOneWidget);
      expect(find.text('填写卡面编号'), findsNothing);
      expect(find.text('修改卡面编号'), findsNothing);
      expect(find.text('卡面编号（手工填写）'), findsNothing);
      expect(
        (await repository.exportDocuments())
            .single
            .cardExtensions['suicaManualNumber'],
        metadata,
      );
    }
  });

  testWidgets('manual printed number can be saved, edited and cleared', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final repository = await _pumpDetail(tester, snapshot: _snapshot());
    await tester.tap(find.text('填写卡面编号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'je123 4567 8901 2345');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('卡面编号（手工填写）'), findsOneWidget);
    _expectSuicaIdentity(showReadExplanation: false);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText && widget.data == 'JE123 4567 8901 2345',
      ),
      findsOneWidget,
    );
    expect(find.text('已观察卡号'), findsNothing);
    expect((await repository.getAllCards()).single.cardNumber, isNull);
    final document = (await repository.exportDocuments()).single;
    expect(document.cardExtensions['suicaManualNumber'], isA<Map>());
    await tester.tap(find.byTooltip('复制卡面编号'));
    await tester.pumpAndSettle();
    expect(clipboardText, 'JE123456789012345');

    await tester.tap(find.text('修改卡面编号'));
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, 'JE123 4567 8901 2345');
    await tester.enterText(find.byType(TextFormField), 'JE987 6543 2109 8765');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('JE987 6543 2109 8765'), findsOneWidget);

    await tester.tap(find.text('修改卡面编号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('卡面编号（手工填写）'), findsNothing);
    _expectSuicaIdentity(showReadExplanation: false);
    expect(find.text('填写卡面编号'), findsOneWidget);
    expect(
      ((await repository.exportDocuments())
              .single
              .cardExtensions['suicaManualNumber']
          as Map)['value'],
      isNull,
    );
  });

  testWidgets(
    'invalid manual number is rejected without changing captured IDm',
    (tester) async {
      final repository = await _pumpDetail(tester, snapshot: _snapshot());
      await tester.tap(find.text('填写卡面编号'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), _idm);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('2 位字母和 15 位数字'), findsOneWidget);
      expect((await repository.getAllCards()).single.cardNumber, isNull);
      expect(
        (await repository.exportDocuments()).single.cardExtensions.containsKey(
          'suicaManualNumber',
        ),
        isFalse,
      );
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      _expectSuicaIdentity(showReadExplanation: false);
    },
  );
  testWidgets('Suica manual entry remains usable at 320dp and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpDetail(tester, snapshot: _snapshot(), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('填写卡面编号'));
    await tester.tap(find.text('填写卡面编号'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'JE123456789012345');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('卡面编号（手工填写）'), findsOneWidget);
    expect(find.text('JE123 4567 8901 2345'), findsOneWidget);
  });
}

void _expectSuicaIdentity({bool showReadExplanation = true}) {
  expect(find.text('卡片标识（IDm）'), findsOneWidget);
  expect(
    find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == _idm,
    ),
    findsOneWidget,
  );
  expect(
    find.text('卡面编号（IDi）'),
    showReadExplanation ? findsOneWidget : findsNothing,
  );
  expect(
    find.textContaining('无法通过 NFC 读取'),
    showReadExplanation ? findsOneWidget : findsNothing,
  );
}

String _snapshot({String idm = _idm}) => CardSessionSnapshot(
  context: const ArchiveContext(
    systemId: 'felica',
    applicationId: 'suica',
    currencyCode: 'JPY',
    minorUnitDigits: 0,
    observedFields: {
      'cardNumber': false,
      'balanceFen': false,
      'currencyCode': false,
      'transactionCount': false,
    },
  ),
  extensions: {
    'suica': {
      'version': 1,
      'idm': idm,
      'historyObserved': false,
      'records': <Object>[],
    },
  },
).encode();

Future<void> _pump(
  WidgetTester tester,
  Widget widget, {
  bool scroll = true,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: scroll ? SingleChildScrollView(child: widget) : widget,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CardRepository> _pumpDetail(
  WidgetTester tester, {
  String fingerprint = _fingerprint,
  String? snapshot,
  CardArchiveIdentity identity = _suica,
  double textScale = 1,
  Map<String, dynamic>? cardExtensions,
}) async {
  final repository = CardRepository(testDatabase());
  await tester.runAsync(
    () => repository.saveIdentity(
      fingerprint: fingerprint,
      identity: identity,
      sessionDataJson: snapshot,
    ),
  );
  final card = (await repository.getAllCards()).single;
  if (cardExtensions != null) {
    await tester.runAsync(() async {
      final original = (await repository.exportDocuments()).single;
      await repository.importDocuments([
        original.copyWith(cardExtensions: cardExtensions),
      ]);
    });
  }
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CardDetailPage(repository: repository, cardId: card.id),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}
