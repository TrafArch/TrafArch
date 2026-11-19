import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_record_count.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_identity.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/domain/pending_card_save.dart';
import 'package:transit_card_analyzer/features/archive/presentation/card_detail_page.dart';
import 'package:transit_card_analyzer/features/cards/cards_page.dart';
import 'package:transit_card_analyzer/features/home/presentation/pending_save_presenter.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/felica/models/amusement_ic_data.dart';
import 'package:transit_card_analyzer/shared/presentation/amusement_ic_summary.dart';

import 'support/test_database.dart';

const _code = '50101234567890123456';
const _groupedCode = '5010 1234 5678 9012 3456';
const _idm = '012E3A4B5C6D7E8F';
const _fingerprint = 'felica:amusement_ic:access-code:$_code';
const _identity = CardArchiveIdentity(
  cardType: 'amusement_ic',
  officialName: 'Amusement IC（Aime）',
  issuerName: 'Aime',
  identificationSource: CardIdentificationSources.parserOnly,
);
const _data = AmusementIcData(
  accessCode: _code,
  issuer: 'Aime',
  dataFormatCode: 0x0078,
  idBlockHex: '012E3A4B5C6D7E8F0078000000000000',
  spad0Hex: '893D691806ECCFEF90C8773D41EEE231',
);

String _snapshot({bool malformed = false, AmusementIcData data = _data}) =>
    CardSessionSnapshot(
      context: const ArchiveContext(
        systemId: 'felica_amusement_ic',
        applicationId: 'felica-system:88B4/service:000B',
        observedFields: {
          'cardNumber': false,
          'balanceFen': false,
          'transactionCount': false,
        },
      ),
      extensions: {
        'amusementIc': {
          'version': malformed ? 99 : 1,
          'identityKind': 'amusement-ic-access-code',
          'idm': _idm,
          'data': data.toJson(),
        },
      },
    ).encode();

Future<String> _save(
  CardRepository repository, {
  bool malformed = false,
  AmusementIcData data = _data,
  CardArchiveIdentity identity = _identity,
}) async {
  await repository.saveIdentity(
    fingerprint: _fingerprint,
    identity: identity,
    sessionDataJson: _snapshot(malformed: malformed, data: data),
    readAt: DateTime(2026, 11, 16, malformed ? 12 : 11),
  );
  return (await repository.getAllCards()).single.id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'save dialog shows frozen AIC brand and code instead of missing transit card number',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SaveCardDialog(
              pending: PendingCardSave(
                pendingSaveId: 'aic-save',
                fingerprint: _fingerprint,
                identity: _identity,
                sessionDataJson: _snapshot(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Aime'), findsOneWidget);
      expect(find.text('Amusement IC ( Aime )'), findsOneWidget);
      expect(find.text(_code), findsNothing);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text('未读取到卡号'), findsNothing);
      expect(find.text('保存'), findsOneWidget);
    },
  );

  for (final narrow in [false, true]) {
    testWidgets(
      'saved AIC details expose frozen identity and copy raw code (${narrow ? 'narrow large text' : 'normal'})',
      (tester) async {
        final repository = CardRepository(testDatabase());
        late String cardId;
        await tester.runAsync(() async {
          cardId = await _save(repository);
          await repository.renameCard(cardId, '我的音游卡');
        });
        if (narrow) {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        final copied = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') copied.add(call.arguments);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
              child: child!,
            ),
            home: CardDetailPage(repository: repository, cardId: cardId),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的音游卡'), findsOneWidget);
        expect(find.text('Aime'), findsOneWidget);
        expect(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((text) => text.data),
          contains('Aime'),
        );
        expect(find.text('Amusement IC ( Aime )'), findsOneWidget);
        expect(find.text(_code), findsNothing);
        expect(find.text('Access Code'), findsOneWidget);
        expect(find.text(_groupedCode), findsOneWidget);
        expect(find.text(_idm), findsOneWidget);
        expect(find.text('已观察余额'), findsNothing);
        expect(find.textContaining('行程记录'), findsNothing);
        expect(find.textContaining('本次缺失'), findsNothing);
        await tester.ensureVisible(find.byTooltip('复制 Access Code'));
        await tester.tap(find.byTooltip('复制 Access Code'));
        await tester.pumpAndSettle();
        expect(copied, [
          {'text': _code},
        ]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'unknown newest AIC snapshot keeps the older frozen details and diagnostics',
    (tester) async {
      final repository = CardRepository(testDatabase());
      late String cardId;
      await tester.runAsync(() async {
        cardId = await _save(repository);
        await _save(repository, malformed: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: repository, cardId: cardId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_code), findsNothing);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text('Amusement IC ( Aime )'), findsOneWidget);
      expect(find.text('Aime'), findsWidgets);
      expect(find.textContaining('格式'), findsWidgets);
      final history = await tester.runAsync(
        () => ArchiveHistory(repository).load(cardId),
      );
      expect(history!.batches, hasLength(2));
      expect(history.batches.first.decoded.rawJson, contains('"version":99'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'card wallet uses frozen AIC name and grouped Access Code for old saved cards',
    (tester) async {
      final database = testDatabase();
      final app = AppDependencies(
        database: database,
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await tester.runAsync(() async {
        await app.init();
        await _save(app.cardRepository);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CardsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amusement IC ( Aime )'), findsOneWidget);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text('Access Code'), findsOneWidget);
      expect(find.text(_code), findsNothing);
      expect(find.text('Amusement IC（Aime）'), findsNothing);
      expect(find.text('未读取到卡号'), findsNothing);
      expect(find.text('卡号未提供'), findsNothing);
      expect(find.text('已保存 0 条'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brand in ['Banapassport', 'e-amusement pass', 'NESiCA']) {
    testWidgets('saved AIC uses the captured $brand in its default name', (
      tester,
    ) async {
      final repository = CardRepository(testDatabase());
      late String cardId;
      await tester.runAsync(() async {
        // Stale scalar identity must not override the brand in the valid capture.
        cardId = await _save(
          repository,
          data: AmusementIcData(accessCode: _code, issuer: brand),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: repository, cardId: cardId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amusement IC ( $brand )'), findsOneWidget);
      expect(find.text('Amusement IC（Aime）'), findsNothing);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.text(_code), findsNothing);
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((text) => text.data),
        contains(brand),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'wallet retains custom name and falls back to one older valid AIC capture',
    (tester) async {
      final app = AppDependencies(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      await tester.runAsync(() async {
        await app.init();
        final cardId = await _save(app.cardRepository);
        await _save(
          app.cardRepository,
          malformed: true,
          data: const AmusementIcData(
            accessCode: '30101234567890123456',
            issuer: 'NESiCA',
          ),
          identity: const CardArchiveIdentity(
            cardType: 'amusement_ic',
            officialName: 'Amusement IC（NESiCA）',
            issuerName: 'NESiCA',
          ),
        );
        await app.cardRepository.renameCard(cardId, '我的音游卡');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CardsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我的音游卡'), findsOneWidget);
      expect(find.text('Amusement IC ( Aime )'), findsOneWidget);
      expect(find.text(_groupedCode), findsOneWidget);
      expect(find.textContaining('NESiCA'), findsNothing);
      expect(find.textContaining('3010'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unrecoverable saved AIC shows unknown code instead of IDm or scalar brand',
    (tester) async {
      final app = AppDependencies(
        database: testDatabase(),
        bundle: MissingTestAssets(),
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(store: MemoryLogStore()),
      );
      addTearDown(app.dispose);
      late String cardId;
      await tester.runAsync(() async {
        await app.init();
        cardId = await _save(
          app.cardRepository,
          data: const AmusementIcData(issuer: 'Aime'),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CardsPage(app: app)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amusement IC ( 发行品牌未知 )'), findsOneWidget);
      expect(find.text('Access Code 未读取'), findsOneWidget);
      expect(find.text(_idm), findsNothing);
      expect(find.text(_groupedCode), findsNothing);
      expect(find.text('Amusement IC（Aime）'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: CardDetailPage(repository: app.cardRepository, cardId: cardId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amusement IC ( 发行品牌未知 )'), findsOneWidget);
      expect(find.text('Access Code 未读取'), findsOneWidget);
      expect(find.byTooltip('复制 Access Code'), findsNothing);
      expect(find.text(_idm), findsNothing);
      expect(find.text(_groupedCode), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('AIC summaries compare projected identity by value and include batch-only brand changes', () async {
    final database = testDatabase();
    final repository = CardRepository(database);
    final cardId = await _save(repository);
    final first = (await watchArchiveCardSummaries(repository).first).single;
    final replay = (await watchArchiveCardSummaries(repository).first).single;
    expect(replay, first);
    expect(replay.hashCode, first.hashCode);
    await database
        .into(database.cardReadBatches)
        .insert(
          CardReadBatch(
            id: 'new-brand',
            cardId: cardId,
            cardFingerprint: _fingerprint,
            readAt: DateTime(2026, 11, 16, 13).millisecondsSinceEpoch,
            parseVersion: 1,
            payloadJson: _snapshot(
              data: const AmusementIcData(
                accessCode: _code,
                issuer: 'Banapassport',
              ),
            ),
          ),
        );
    final changed = (await watchArchiveCardSummaries(repository).first).single;
    expect(changed.card, first.card);
    expect(changed.recordCount, first.recordCount);
    expect(changed, isNot(first));
  });

  testWidgets('missing AIC code offers no copy action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AmusementIcSummary(data: AmusementIcData(issuer: 'Aime')),
        ),
      ),
    );
    expect(find.text('Access Code 未读取'), findsOneWidget);
    expect(find.byTooltip('复制 Access Code'), findsNothing);
  });
}
