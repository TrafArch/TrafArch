import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_card.dart';
import 'package:transit_card_analyzer/features/trips/trips_page.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

import 'support/published_reference_fixture.dart';

const _cardName = '北京交通卡（演示）';
const _cardNumber = '3199999900000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _PreviewBundle bundle;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    directory = Directory.systemTemp.createTempSync('trafarch-trips-preview-');
    bundle = _PreviewBundle(_stationFixture(directory));
  });
  tearDownAll(() => directory.deleteSync(recursive: true));
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return directory.path;
          }
          throw MissingPluginException(call.method);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  testWidgets('真实行程页保留钱包摘要并展示商务行程的出站余额', (tester) async {
    tester.view.physicalSize = const Size(430, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final app = AppDependencies(
      bundle: bundle,
      settingsStore: MemorySettingsStore(),
      database: database,
    );
    addTearDown(() async {
      app.dispose();
      await database.close();
    });

    // Inject a synthetic completed read through the real application callback.
    // This exercises analysis and TripsPage, not the NFC acquisition protocol.
    await tester.runAsync(() async {
      await app.init();
      await app.scan.onCompleted!(
        TransitReadOutcome(_previewCard()),
        'synthetic-trips-visual',
        DateTime(2026, 10, 27, 18, 12),
        () => true,
      );
    });
    expect(app.analysis!.wallet.cardNumber, _cardNumber);
    expect(app.analysis!.wallet.balanceFen, 8800);
    expect(
      app.analysis!.trips
          .singleWhere((trip) => trip.sequence == 43)
          .balanceAfterFen,
      8800,
    );
    expect(
      app.analysis!.trips
          .singleWhere((trip) => trip.sequence == 42)
          .balanceAfterFen,
      13800,
    );

    final output = Platform.environment['TRAFARCH_VISUAL_REVIEW_DIR'];
    String? font;
    if (output != null) {
      final iconFile = Platform.environment['TRAFARCH_VISUAL_ICON_FONT'];
      if (iconFile != null) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(
                ByteData.sublistView(File(iconFile).readAsBytesSync()),
              ),
            ))
            .load();
      }
      final fontFile = Platform.environment['TRAFARCH_VISUAL_FONT'];
      if (fontFile != null) {
        font = 'TripsPagePreview';
        await (FontLoader(font)..addFont(
              Future.value(
                ByteData.sublistView(File(fontFile).readAsBytesSync()),
              ),
            ))
            .load();
      }
    }

    final previewKey = GlobalKey();
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: font,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: brightness,
            ),
          ),
          home: RepaintBoundary(
            key: previewKey,
            child: Scaffold(body: TripsPage(app: app)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_cardName), findsOneWidget);
      expect(find.text(_cardNumber), findsOneWidget);
      expect(find.text(app.analysis!.wallet.balanceText!), findsOneWidget);
      expect(find.text('记录 3 条'), findsOneWidget);
      expect(find.text('行程信息提示 1'), findsOneWidget);
      expect(find.text('历史行程 1'), findsOneWidget);
      expect(find.text('沙河'), findsOneWidget);
      expect(find.text('草桥'), findsOneWidget);
      expect(find.text('大兴机场'), findsOneWidget);
      expect(find.text('商务座'), findsOneWidget);
      expect(find.textContaining('50.00'), findsOneWidget);
      expect(find.text('行程后余额 ¥88.00'), findsOneWidget);
      expect(find.textContaining('行程后余额 ¥138.00'), findsNothing);
      expect(find.textContaining('-¥0.00'), findsNothing);
      final cards = tester
          .widgetList<TripEntryCard>(find.byType(TripEntryCard))
          .toList();
      expect(cards, hasLength(2));
      final complete = cards
          .singleWhere((card) => card.journey!.state == JourneyState.completed)
          .journey!;
      expect(complete.balanceAfterText, '¥88.00');
      expect(complete.seatLabel, '商务座');
      expect(complete.duration, const Duration(minutes: 37));
      final pending = cards
          .singleWhere((card) => card.journey!.state == JourneyState.inProgress)
          .journey!;
      expect(pending.balanceAfterText, isNull);
      expect(pending.amountText, isNull);
      expect(
        tester.getBottomRight(find.byType(TripEntryCard).last).dy,
        lessThanOrEqualTo(1300),
      );
      expect(tester.takeException(), isNull);

      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await rendered.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final target = File('$output/trips-page-${brightness.name}.png');
            await target.parent.create(recursive: true);
            await target.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            rendered.dispose();
          }
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

ParsedCard _previewCard() {
  final transactions = <TUnionTransaction>[
    for (final (sequence, hour, minute, amount, terminal) in const [
      (44, 18, 9, 0, '100056002301'),
      (43, 12, 44, 5000, '100058002702'),
      (42, 12, 7, 0, '100058001703'),
    ])
      TUnionTransaction(
        sequence: sequence,
        recordNumber: 45 - sequence,
        overdraftLimitFen: 0,
        amountFen: amount,
        rawType: 9,
        terminalId: terminal,
        time: DateTime(2026, 10, 27, hour, minute),
      ),
  ];
  return ParsedCard(
    parserId: CardParserIds.tunion,
    parserName: 'Synthetic TripsPage visual fixture',
    selectedAidHex: 'A000000632010105',
    info: const TUnionCardInfo(
      issuerId: '1122334455667788',
      applicationSerial: '0$_cardNumber',
      cityCode: '1000',
      balanceFen: 8800,
    ),
    transactionFileObserved: true,
    transactions: transactions,
    transitProcessRecords: [
      for (final transaction in transactions)
        TUnionProcessRecord(
          sfi: 0x1E,
          recordNumber: transaction.recordNumber!,
          recordName: 'synthetic matching cycle ${transaction.sequence}',
          raw: const [],
          trip: TUnionTripRecord(
            typeCode: transaction.sequence == 43 ? 4 : 3,
            terminalId: '0000${transaction.terminalId}',
            appTypeCode: 1,
            lineStationCode: '00000000000000',
            amountFen: transaction.amountFen,
            balanceFen: transaction.sequence == 42 ? 13800 : 8800,
            time: transaction.time,
            cityCode: '1000',
          ),
        ),
    ],
  );
}

// These terminal layouts are synthetic fixture data, not decoder evidence.
Uint8List _stationFixture(Directory directory) {
  final file = File('${directory.path}/preview-stations.sqlite');
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('''
CREATE TABLE regions(region_id INTEGER PRIMARY KEY, region_code TEXT,
  region_name TEXT, province TEXT, table_name TEXT, code_source TEXT);
CREATE TABLE region_beijing(station_id INTEGER PRIMARY KEY, transport_type TEXT,
  line_name TEXT, station_name TEXT, system_name TEXT, source_field TEXT,
  source_key TEXT, source_region_code TEXT, source_region_name TEXT,
  raw_value_json TEXT, confidence TEXT);
INSERT INTO regions VALUES(1,'1000','北京市','北京市','region_beijing','synthetic');
INSERT INTO region_beijing VALUES
  (1,'metro','昌平线','沙河','演示轨道','test.visual','1000560023','1000','北京市',NULL,'high'),
  (2,'metro','大兴机场线','大兴机场','演示轨道','test.visual','1000580027','1000','北京市',NULL,'high'),
  (3,'metro','大兴机场线','草桥','演示轨道','test.visual','1000580017','1000','北京市',NULL,'high');
''');
  } finally {
    db.close();
  }
  return file.readAsBytesSync();
}

class _PreviewBundle extends CachingAssetBundle {
  _PreviewBundle(Uint8List stations)
    : _published = publishTuFixture(stations, {
        'assets/data/tunion_card_prefixes.json': jsonEncode({
          'entries': [
            {
              'prefix': '31999999',
              'issuer': '01281000',
              'cardName': _cardName,
              'city': '北京市',
            },
          ],
        }),
        'assets/data/tunion_terminal_rules.json': jsonEncode({
          'rules': [
            {
              'id': 'synthetic-visual-beijing',
              'match': {'terminalPrefix': '1000'},
              'layout': {
                'cityCode': [0, 4],
                'lineCode': [4, 6],
                'stationCode': [6, 10],
              },
            },
          ],
        }),
      });

  final Map<String, Uint8List> _published;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _published[key];
    if (bytes == null) throw FlutterError('Preview asset missing: $key');
    return ByteData.sublistView(bytes);
  }
}
