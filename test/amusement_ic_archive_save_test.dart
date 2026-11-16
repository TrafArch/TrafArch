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

const _code = '50101234567890123456';
FelicaReadOutcome _read({
  String? code = _code,
  String? issuer = 'Aime',
  String? idm = '0102030405060708',
  FelicaCardType type = FelicaCardType.amusementIc,
}) => FelicaReadOutcome(
  FelicaScanResult(
    cardType: 'amusement_ic',
    displayName: 'Amusement IC（Aime）',
    cardProductType: type,
    idm: idm,
    systemCodes: const [0x88B4],
    amusementIc: AmusementIcData(
      accessCode: code,
      issuer: issuer,
      dataFormatCode: 0x0078,
      idBlockHex: '01020304050607080078000000000000',
      spad0Hex: '893D691806ECCFEF90C8773D41EEE231',
    ),
    statuses: const [
      FelicaReadStatus(
        stage: 'Amusement IC Access Code',
        state: FelicaReadState.success,
        message: 'fixture',
      ),
    ],
    scannedAt: DateTime(2026, 11, 16),
  ),
);

AppDependencies _app(AppDatabase db, {_Memory? memory, bool autoSave = false}) {
  final app = AppDependencies(
    database: db,
    memoryPlatform: memory ?? _Memory(),
    bundle: MissingTestAssets(),
    settingsStore: MemorySettingsStore({
      SettingsKeys.autoSaveEnabled: '$autoSave',
    }),
    logger: AppLogger(store: MemoryLogStore()),
  );
  addTearDown(() {
    if (!app.disposed) app.dispose();
  });
  return app;
}

Future<void> _complete(
  AppDependencies app,
  FelicaReadOutcome result,
  String id, {
  int hour = 10,
}) async {
  app.archive.clearSession();
  app.scan.outcome = result;
  await app.scan.onCompleted!(
    result,
    id,
    DateTime(2026, 11, 16, hour),
    () => true,
  );
}

Map _data(String raw) =>
    (CardSessionSnapshot.decode(raw)!.extensions['amusementIc'] as Map)['data']
        as Map;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AIC code and brand survive file reopen, repeat reads, rename and backup',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'trafarch-aic-archive-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/archive.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      var closed = false;
      addTearDown(() async {
        if (!closed) await db.close();
      });
      final app = _app(db);
      await app.init();
      await _complete(app, _read(), 'first');
      final pending = app.pendingCardSave;
      expect(pending, isNotNull);
      expect(pending!.fingerprint, 'felica:amusement_ic:access-code:$_code');
      expect(pending.cardNumber, isNull);
      expect(pending.balanceFen, isNull);
      expect(pending.currencyCode, isNull);
      expect(pending.transactionCount, isNull);
      expect(pending.identity.issuerName, 'Aime');
      final frozen = CardSessionSnapshot.decode(pending.sessionDataJson!)!;
      expect(frozen.context.currencyCode, isNull);
      expect(frozen.context.minorUnitDigits, isNull);
      expect(_data(pending.sessionDataJson!)['accessCode'], _code);
      expect(_data(pending.sessionDataJson!)['issuer'], 'Aime');
      expect(await app.acceptPendingSave('first'), isTrue);
      final saved = (await app.cardRepository.getAllCards()).single;
      await app.cardRepository.renameCard(saved.id, '我的音游卡');
      await _complete(app, _read(idm: '1112131415161718'), 'second', hour: 11);
      expect(await app.acceptPendingSave('second'), isTrue);
      // A failed read cannot erase the previous successful code or brand.
      await _complete(app, _read(code: null), 'missing-code', hour: 12);
      expect(app.pendingCardSave, isNull);
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
      expect(cards.single.customName, '我的音游卡');
      expect(cards.single.issuerName, 'Aime');
      expect(cards.single.cardNumber, isNull);
      expect(cards.single.balanceFen, isNull);
      expect(_data(cards.single.sessionDataJson!)['accessCode'], _code);
      final history = await ArchiveHistory(repository).load(cards.single.id);
      expect(history.batches, hasLength(2));
      expect(
        history.batches.map((b) => _data(b.decoded.rawJson)['accessCode']),
        everyElement(_code),
      );
      final documents = await repository.exportDocuments();
      await reopened.close();
      reopenedClosed = true;
      final importedRepo = CardRepository(testDatabase());
      await importedRepo.importDocuments(documents);
      final imported = (await importedRepo.getAllCards()).single;
      final importedHistory = await ArchiveHistory(importedRepo)
          .load(imported.id);
      expect(imported.customName, '我的音游卡');
      expect(imported.issuerName, 'Aime');
      expect(
        importedHistory.batches.map((b) => b.decoded.rawJson),
        history.batches.map((b) => b.decoded.rawJson),
      );
    },
  );

  test('AIC automatic saving respects stable code instead of RF IDm', () async {
    final app = _app(testDatabase(), autoSave: true);
    await app.init();
    await _complete(app, _read(idm: null), 'auto-first');
    expect(app.pendingCardSave, isNull);
    expect(await app.cardRepository.getAllCards(), hasLength(1));
    await _complete(
      app,
      _read(idm: '1112131415161718'),
      'auto-repeat',
      hour: 11,
    );
    expect(await app.cardRepository.getAllCards(), hasLength(1));
    await _complete(
      app,
      _read(code: '50101234567890123457'),
      'auto-other',
      hour: 12,
    );
    expect(await app.cardRepository.getAllCards(), hasLength(2));
  });

  test('AIC recovery retains pending code and brand and saves only on confirmation', () async {
    final db = testDatabase();
    final memory = _Memory();
    final app = _app(db, memory: memory);
    await app.init();
    await _complete(app, _read(), 'recover');
    expect(await app.handleMemoryPressure(true), isTrue);
    app.dispose();
    final restored = _app(db, memory: memory, autoSave: true);
    await restored.init();
    expect(await restored.cardRepository.getAllCards(), isEmpty);
    expect(restored.recoveredCapture?.canSave, isTrue);
    expect(
      _data(restored.recoveredCapture!.snapshotJson!)['accessCode'],
      _code,
    );
    expect(restored.recoveredCapture!.pending!.identity.issuerName, 'Aime');
    await restored.saveRecoveredCapture();
    final saved = (await restored.cardRepository.getAllCards()).single;
    expect(_data(saved.sessionDataJson!)['issuer'], 'Aime');
    expect(_data(saved.sessionDataJson!)['accessCode'], _code);
  });

  test(
    'unidentified AIC or incomplete code and brand cannot create archive',
    () async {
      final app = _app(testDatabase(), autoSave: true);
      await app.init();
      for (final read in [
        _read(type: FelicaCardType.unknown),
        _read(issuer: null),
        _read(issuer: ''),
        for (final code in <String?>[
          null,
          '',
          '0' * 20,
          '123',
          '5010123456789012345X',
          '01234567890123456789',
        ])
          _read(code: code),
      ]) {
        await _complete(app, read, 'invalid');
        expect(app.pendingCardSave, isNull);
      }
      expect(await app.cardRepository.getAllCards(), isEmpty);
    },
  );
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
  Future<void> clearRecovery() async => text = null;
  @override
  Future<void> writeRecovery(String content) async => text = content;
}
