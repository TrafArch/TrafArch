import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/gallery/gallery_app.dart';
import 'package:transit_card_analyzer/gallery/gallery_preferences.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/gallery_scroll.dart';
import 'support/test_database.dart';

const _idm = '0102030405060708';
const _fingerprint = 'felica:suica:idm:$_idm';
const _otherIdm = '0102030405060709';
final _readAt = DateTime(2026, 11, 21, 10, 42);
const _manualField = '卡面编号（手工填写）';
const _fillNumber = '填写卡面编号';
const _editNumber = '修改卡面编号';
const _extension = 'suicaManualNumber';

void main() {
  testWidgets('saved Suica keeps only its own printed number across sessions', (
    tester,
  ) async {
    _size(tester);
    final database = testDatabase();
    // Open and seed Drift before the widget starts watching the archive in fake
    // time. The test fixture, not either AppDependencies instance, owns the DB.
    final other = await _runIo(tester, 'seed the other Suica', () async {
      final repository = CardRepository(database);
      final card = await _seed(
        repository,
        fingerprint: 'felica:suica:idm:$_otherIdm',
        name: '另一张 Suica',
        capturedIdm: _otherIdm,
      );
      await repository.setSuicaManualNumber(card.id, 'CD111122223333444');
      return card;
    });

    final firstApp = await _mount(tester, database);
    final repository = firstApp.cardRepository;
    await tester.tap(find.widgetWithText(TextButton, '开始读取'));
    await _waitFor(tester, () => !firstApp.scanning, 'NFC read did not finish');
    expect(firstApp.hasCompletedRead, isTrue, reason: '${firstApp.error}');
    expect(firstApp.pendingCardSave, isNull);
    await _waitFor(
      tester,
      () => find.text('已自动保存').evaluate().isNotEmpty,
      'the home result did not receive the saved archive projection',
    );
    final saved = (await _runIo(
      tester,
      'load saved cards',
      repository.getAllCards,
    )).singleWhere((card) => card.cardFingerprint == _fingerprint);
    final before = await _archiveRows(tester, repository, saved);
    expect(before.card!.cardNumber, isNull);
    expect(before.batches, isNotEmpty);
    // The current read now owns the same ID used by the wallet's saved card.
    expect(find.byKey(ValueKey('card-face-${saved.id}')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await _navigateWallet(tester, [saved, other]);
    await _openInformation(tester, saved);
    expect(find.text(_manualField), findsOneWidget);
    expect(find.text('未填写'), findsOneWidget);
    expect(find.text(_idm), findsNothing);

    await _openEditor(tester, _fillNumber);
    await tester.enterText(
      find.byType(TextFormField),
      ' je000 1234 5678 9012 ',
    );
    await _saveNumber(tester, 'JE000 1234 5678 9012');
    expect(find.text('JE000 1234 5678 9012'), findsOneWidget);
    final firstSaved = await _archiveRows(tester, repository, saved);
    expect(
      firstSaved.cardExtensions[_extension],
      containsPair('value', 'JE000123456789012'),
    );

    await _openEditor(tester, _editNumber);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'JE000 1234 5678 9012',
    );
    await tester.enterText(find.byType(TextFormField), 'JE 1234');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 2 位英文字母和 15 位数字，可带空格'), findsOneWidget);
    final afterInvalid = await _archiveRows(tester, repository, saved);
    expect(afterInvalid.cardExtensions, firstSaved.cardExtensions);
    await tester.enterText(find.byType(TextFormField), 'AB123456789012345');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('JE000 1234 5678 9012'), findsOneWidget);
    final afterCancel = await _archiveRows(tester, repository, saved);
    expect(afterCancel.cardExtensions, firstSaved.cardExtensions);

    await _openEditor(tester, _editNumber);
    await tester.enterText(find.byType(TextFormField), 'AB123456789012345');
    await _saveNumber(tester, 'AB123 4567 8901 2345');
    await _unmount(tester);
    firstApp.dispose();
    await tester.pump();

    // Reload the saved projection in a fresh Gallery session. The disk reopen
    // is exercised by suica_manual_number_test.dart outside widget fake time.
    final secondApp = await _mount(tester, database);
    expect(secondApp.hasCompletedRead, isFalse);
    await _navigateWallet(tester, [saved, other]);
    await _openInformation(tester, saved);
    expect(find.text('AB123 4567 8901 2345'), findsOneWidget);
    await _openEditor(tester, _editNumber);
    await tester.enterText(find.byType(TextFormField), '');
    await _saveNumber(tester, '未填写');
    expect(find.text('AB123 4567 8901 2345'), findsNothing);
    expect(find.text(_fillNumber), findsOneWidget);
    expect(find.text('未填写'), findsOneWidget);
    expect(find.text(_idm), findsNothing);

    final cleared = await _archiveRows(tester, secondApp.cardRepository, saved);
    expect(cleared.cardExtensions[_extension], containsPair('value', null));
    expect(cleared.card!.id, saved.id);
    expect(cleared.card!.cardFingerprint, _fingerprint);
    expect(cleared.card!.cardNumber, isNull);
    expect(cleared.card!.lastReadAt, before.card!.lastReadAt);
    expect(cleared.card!.sessionDataJson, before.card!.sessionDataJson);
    expect(
      cleared.batches.map((batch) => batch.payloadJson),
      before.batches.map((batch) => batch.payloadJson),
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await _openInformation(tester, other);
    expect(find.text('CD111 1222 2333 3444'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('only Suica archives with a confirmed identity offer editing', (
    tester,
  ) async {
    _size(tester);
    final database = testDatabase();
    final repository = CardRepository(database);
    final cards = await _runIo(
      tester,
      'seed archives without an editable Suica identity',
      () async => [
        await _seed(
          repository,
          fingerprint: 'tunion:issuer:1234567',
          cardType: CardTypes.chinaTunion,
          name: 'Suica 名称不等于卡种',
        ),
        await _seed(
          repository,
          fingerprint: 'legacy:suica:unverified',
          name: '旧版 Suica 档案',
          capturedIdm: _idm,
        ),
        await _seed(
          repository,
          fingerprint: _fingerprint,
          name: '存在冲突的 Suica 档案',
          capturedIdm: _otherIdm,
        ),
      ],
    );
    await _mount(tester, database);
    await _navigateWallet(tester, cards);
    for (final (index, card) in cards.indexed) {
      await _openInformation(tester, card);
      expect(find.text(_fillNumber), findsNothing);
      expect(find.text(_editNumber), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.text(_manualField),
        index == 0 ? findsNothing : findsOneWidget,
      );
      if (index != 0) {
        expect(find.text('无法确认档案身份，暂不能编辑卡面编号。'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
    await _unmount(tester);
  });
}

Future<SavedCard> _seed(
  CardRepository repository, {
  required String fingerprint,
  required String name,
  String cardType = CardTypes.suica,
  String? capturedIdm,
}) async {
  await repository.saveIdentity(
    fingerprint: fingerprint,
    identity: CardArchiveIdentity(cardType: cardType, officialName: name),
    balanceFen: 1000,
    currencyCode: cardType == CardTypes.suica ? 'JPY' : 'CNY',
    sessionDataJson: CardSessionSnapshot(
      extensions: {
        if (capturedIdm != null) 'suica': {'version': 1, 'idm': capturedIdm},
      },
    ).encode(),
    readAt: _readAt.subtract(const Duration(days: 1)),
  );
  return (await repository.getAllCards()).singleWhere(
    (card) => card.cardFingerprint == fingerprint,
  );
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 892);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppDependencies> _mount(
  WidgetTester tester,
  AppDatabase database,
) async {
  final nfc = _SuicaReader();
  final app = AppDependencies(
    database: database,
    bundle: MissingTestAssets(),
    settingsStore: MemorySettingsStore({SettingsKeys.autoSaveEnabled: 'true'}),
    logger: AppLogger(store: MemoryLogStore()),
    channel: nfc,
    felicaChannel: nfc,
  );
  final preferences = GalleryPreferences(faceStore: _EmptyFaceStore());
  addTearDown(() {
    if (!app.disposed) app.dispose();
    preferences.dispose();
  });
  await _runIo(tester, 'initialize app dependencies', () async {
    await app.init();
    return app;
  });
  expect(app.autoSaveEnabled, isTrue);
  await tester.pumpWidget(GalleryApp(liveApp: app, preferences: preferences));
  await _waitFor(
    tester,
    () => find.byKey(const ValueKey('nav-cards')).evaluate().isNotEmpty,
    'Gallery did not mount',
  );
  await tester.pumpAndSettle();
  return app;
}

Future<T> _runIo<T extends Object>(
  WidgetTester tester,
  String operation,
  Future<T> Function() action,
) async {
  final result = await tester.runAsync(
    () => action().timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(operation),
    ),
  );
  return result!;
}

Future<ArchiveRows> _archiveRows(
  WidgetTester tester,
  CardRepository repository,
  SavedCard card,
) => _runIo(
  tester,
  'load archive rows',
  () => repository.getArchiveRows(card.id),
);

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  const step = Duration(milliseconds: 20);
  await tester.pump();
  // Give real async work a turn and advance the widget clock separately. In
  // particular, do not pumpAndSettle while the NFC progress UI can keep ticking.
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Finder _walletCard(SavedCard card) =>
    find.byKey(ValueKey('wallet-card-${card.id}'));

Future<void> _navigateWallet(
  WidgetTester tester,
  Iterable<SavedCard> cards,
) async {
  await tester.tap(find.byKey(const ValueKey('nav-cards')));
  await _waitFor(
    tester,
    () => cards.any((card) => _walletCard(card).evaluate().isNotEmpty),
    'the wallet did not receive its archive projection',
  );
  await tester.pumpAndSettle();
}

Future<void> _openInformation(WidgetTester tester, SavedCard card) async {
  final walletCard = _walletCard(card);
  if (walletCard.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      walletCard,
      160,
      scrollable: galleryVerticalScroll(),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(walletCard);
  await tester.pumpAndSettle();
  await tester.tap(find.text('卡片信息'));
  await tester.pumpAndSettle();
  expect(find.text('完整卡号'), findsOneWidget);
}

Future<void> _openEditor(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextButton, label));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _saveNumber(WidgetTester tester, String projectedNumber) async {
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await _waitFor(
    tester,
    () =>
        find.byType(AlertDialog).evaluate().isEmpty &&
        find.text(projectedNumber).evaluate().isNotEmpty,
    'the dialog did not close and publish the saved number: $projectedNumber',
  );
  await tester.pumpAndSettle();
}

class _EmptyFaceStore implements GalleryFaceStore {
  @override
  Future<GalleryFaceSnapshot?> read(String cardId) async => null;

  @override
  Future<void> write(String cardId, GalleryFaceSnapshot snapshot) async {}

  @override
  Future<void> delete(String cardId) async {}
}

class _SuicaReader implements NfcChannel, FelicaChannel {
  static const _idmBytes = [1, 2, 3, 4, 5, 6, 7, 8];
  static const _system = [0, 3];
  static const _history = [
    0x16,
    1,
    0,
    2,
    0x35,
    0x70,
    1,
    2,
    1,
    3,
    0xE8,
    3,
    0,
    0,
    1,
    0,
  ];

  @override
  Future<NfcScanResult?> scanOnce() async => NfcScanResult(
    uid: _idm,
    technologies: const ['NfcF'],
    isoDepConnected: false,
    felicaConnected: true,
    nfcFSystemCode: '0003',
    timestamp: _readAt,
  );

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<int>> transceive(List<int> frame) async {
    final payload = switch (frame[1]) {
      0 => [1, ..._idmBytes, ...List<int>.filled(8, 0), ..._system],
      0x0C => [0x0D, ..._idmBytes, 1, ..._system],
      0x02 => [0x03, ..._idmBytes, 1, 0, 0],
      0x06 => _readBlocks(frame),
      _ => throw StateError('Unexpected FeliCa command'),
    };
    return [payload.length + 1, ...payload];
  }

  List<int> _readBlocks(List<int> frame) {
    final countOffset = 11 + frame[10] * 2;
    final count = frame[countOffset];
    return [
      0x07,
      ..._idmBytes,
      0,
      0,
      count,
      for (var i = 0; i < count; i++)
        ...(frame[countOffset + 2 + i * 2] == 0
            ? _history
            : List<int>.filled(16, 0)),
    ];
  }
}
