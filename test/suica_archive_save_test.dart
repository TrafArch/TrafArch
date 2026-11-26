import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/memory/memory_platform.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

import 'support/test_database.dart';

FelicaReadOutcome _read({
  String? idm = '0102030405060708',
  int? balance = 900,
  bool history = true,
  bool complete = true,
}) => FelicaReadOutcome(
  FelicaScanResult(
    cardType: 'suica',
    displayName: 'Suica',
    cardProductType: FelicaCardType.suica,
    idm: idm,
    scannedAt: DateTime(2026, 11, 16),
    wallets: [
      FelicaWallet(
        walletId: 'suica',
        kind: FelicaWalletKind.suicaJpy,
        name: 'Suica',
        currency: 'JPY',
        fractionDigits: 0,
        balanceMinorUnits: balance,
        readState: balance == null
            ? FelicaWalletReadState.failed
            : FelicaWalletReadState.success,
      ),
    ],
    statuses: [
      FelicaReadStatus(
        stage: 'Suica 历史记录',
        state: complete ? FelicaReadState.success : FelicaReadState.failed,
        message: 'test',
      ),
    ],
    transactions: history
        ? [
            const SuicaRecordParser()
                .parseBlock(
                  blockNumber: 0,
                  bytes: [
                    0x16,
                    1,
                    0,
                    0,
                    0x33,
                    0x54,
                    1,
                    1,
                    1,
                    3,
                    0x84,
                    3,
                    0,
                    0,
                    2,
                    0,
                  ],
                )
                .toTransaction(),
          ]
        : [],
  ),
);

AppDependencies _app(AppDatabase database, {_Memory? memory}) {
  final app = AppDependencies(
    database: database,
    memoryPlatform: memory ?? _Memory(),
    bundle: MissingTestAssets(),
    settingsStore: MemorySettingsStore(),
    logger: AppLogger(store: MemoryLogStore()),
  );
  addTearDown(() {
    if (!app.disposed) app.dispose();
  });
  return app;
}

Future<void> _complete(
  AppDependencies app,
  FelicaReadOutcome outcome,
  String attempt,
  DateTime time,
) async {
  app.scan.outcome = outcome;
  await app.scan.onCompleted!(outcome, attempt, time, () => true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Suica saves integer yen, frozen journeys and explicit identity across reopen and backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trafarch-suica-archive-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/archive.sqlite');
    final db = AppDatabase(NativeDatabase(file));
    var closed = false;
    addTearDown(() async {
      if (!closed) await db.close();
    });
    final app = _app(db);
    await app.init();
    await _complete(app, _read(), 'suica-one', DateTime(2026, 11, 16, 10));
    final pending = app.pendingCardSave;
    expect(pending, isNotNull);
    expect(pending!.fingerprint, 'felica:suica:idm:0102030405060708');
    expect(pending.cardNumber, isNull);
    expect(pending.balanceFen, 900);
    final snapshot = CardSessionSnapshot.decode(pending.sessionDataJson!)!;
    expect(snapshot.context.minorUnitDigits, 0);
    expect(snapshot.context.currencyCode, 'JPY');
    expect((snapshot.extensions['suica'] as Map)['records'], hasLength(1));
    expect(await app.acceptPendingSave('suica-one'), isTrue);
    final saved = (await app.cardRepository.getAllCards()).single;
    await app.cardRepository.renameCard(saved.id, '日本旅行');
    await _complete(
      app,
      _read(balance: null, history: false, complete: false),
      'partial',
      DateTime(2026, 11, 16, 11),
    );
    expect(app.pendingCardSave!.balanceFen, isNull);
    expect(app.pendingCardSave!.transactionCount, isNull);
    expect(await app.acceptPendingSave('partial'), isTrue);
    app.dispose();
    await db.close();
    closed = true;
    final reopened = AppDatabase(NativeDatabase(file));
    var reopenedClosed = false;
    addTearDown(() async {
      if (!reopenedClosed) await reopened.close();
    });
    final repository = CardRepository(reopened);
    final cards = await repository.getAllCards();
    expect(cards, hasLength(1));
    expect(cards.single.customName, '日本旅行');
    expect(cards.single.balanceFen, 900);
    expect(cards.single.cardNumber, isNull);
    final history = await ArchiveHistory(repository).load(cards.single.id);
    expect(history.balanceText, 'JP￥900');
    expect(history.batches, hasLength(2));
    final documents = await repository.exportDocuments();
    await reopened.close();
    reopenedClosed = true;
    final target = CardRepository(testDatabase());
    await target.importDocuments(documents);
    final imported = (await target.getAllCards()).single;
    final importedHistory = await ArchiveHistory(target).load(imported.id);
    expect(importedHistory.balanceText, 'JP￥900');
    expect(
      importedHistory.batches.map((b) => b.decoded.rawJson),
      history.batches.map((b) => b.decoded.rawJson),
    );
  });

  test(
    'invalid or absent IDm cannot create a Suica archive identity',
    () async {
      final app = _app(testDatabase());
      await app.init();
      for (final idm in [
        null,
        '',
        '0000000000000000',
        '0102',
        '010203040506070Z',
        'XX0102030405060708',
      ]) {
        app.archive.clearSession();
        await _complete(
          app,
          _read(idm: idm),
          'invalid',
          DateTime(2026, 11, 16),
        );
        expect(app.pendingCardSave, isNull, reason: '$idm');
      }
    },
  );

  test('different IDm creates separate cards and successful empty history observes zero', () async {
    final app = _app(testDatabase());
    await app.init();
    for (final idm in ['0102030405060708', '0102030405060709']) {
      await _complete(
        app,
        _read(idm: idm, history: false),
        idm,
        DateTime(2026, 11, 16),
      );
      expect(app.pendingCardSave, isNotNull);
      expect(app.pendingCardSave!.transactionCount, 0);
      expect(await app.acceptPendingSave(idm), isTrue);
    }
    expect(await app.cardRepository.getAllCards(), hasLength(2));
  });
}

class _Memory implements MemoryPlatform {
  String? text;
  @override
  void listen(Future<bool> Function(bool kill) handler) {}
  @override
  void dispose() {}
  @override
  Future<String?> readRecovery() async => text;
  @override
  Future<void> clearRecovery() async {
    text = null;
  }

  @override
  Future<void> writeRecovery(String content) async {
    text = content;
  }
}
