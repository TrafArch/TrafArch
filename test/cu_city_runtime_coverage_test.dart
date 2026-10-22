import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/expert/city_union_panel.dart';
import 'package:transit_card_analyzer/features/reference_data/data/city_union_region_database.dart';
import 'package:transit_card_analyzer/features/reference_data/data/city_union_lookup_rules.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/region_db_store.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/cj_t331_wallet_local_consumption_parser.dart';

// Coverage uses the published CU package and its public runtime interfaces.
// Database rows are the independent oracle for preservation/reachability;
// no test-side terminal decoder, prefix ranking, or carrier inference is used.
// Literal legacy examples below also expose rules missing from that package.
// Flutter execution is reserved for the parent's integrated run (DLL lock).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const cities = [
    '1000',
    '1160',
    '2000',
    '2150',
    '2550',
    '3100',
    '3120',
    '3140',
    '3150',
    '5180',
    '6100',
  ];
  const stationCities = [
    '2000',
    '3100',
    '3120',
    '3140',
    '3150',
    '5180',
    '6100',
  ];
  late Directory temporary;
  late CityUnionRegionDatabaseContent content;
  late CityUnionRegionKnowledgeDb live;
  String? resolveName(
    String? terminal, {
    String? cityCode,
    int? decodedCarrierType,
    DateTime? transactionTime,
    bool busLookupEnabled = false,
  }) => content.terminalMatcher
      .match(
        terminal,
        cityCode: cityCode,
        decodedCarrierType: decodedCarrierType,
        transactionTime: transactionTime,
        busLookupEnabled: busLookupEnabled,
      )
      ?.displayLabel;

  setUpAll(() async {
    temporary = Directory.systemTemp.createTempSync('trafarch-cu-coverage-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => temporary.path);
    content = await CityUnionRegionDatabase.load();
    live = content.live!;
  });
  tearDownAll(() {
    content.live?.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    temporary.deleteSync(recursive: true);
  });

  for (final city in cities) {
    test(
      'CU $city packaged routes retain encoded keys through lookupRoute',
      () {
        final rows = live.db.select(
          'SELECT * FROM routes WHERE region_code=?',
          [city],
        );
        for (final row in rows) {
          for (final key in {
            row['line_key'] as String,
            row['line_code'] as String,
          }) {
            final result = live.lookupRoute(regionCode: city, lineCode: key);
            expect(result.status, isNot(ReferenceMatchStatus.unavailable));
            expect(
              result.candidates.any(
                (candidate) =>
                    candidate['source_field'] == row['source_field'] &&
                    candidate['line_key'] == row['line_key'] &&
                    candidate['line_code'] == row['line_code'] &&
                    candidate['line_number'] == row['line_number'] &&
                    candidate['value_json'] == row['value_json'],
              ),
              isTrue,
              reason: 'CU $city route $key lost its original signature',
            );
          }
        }
        // A named city with zero routes must not acquire another city's routes.
        expect(
          live.lookupRoute(regionCode: city, lineCode: 'FFFFFFFF').status,
          ReferenceMatchStatus.unknown,
        );
      },
    );

    test('CU $city exact prefix records remain queryable without becoming stations', () {
      final rows = live.db.select(
        'SELECT * FROM cu_prefix_dictionary WHERE region_code=?',
        [city],
      );
      for (final row in rows) {
        final result = live.lookupPrefix(
          regionCode: city,
          key: row['match_key'] as String,
        );
        expect(result.status, ReferenceMatchStatus.matched);
        expect(result.value!['record_kind'], row['record_kind']);
        expect(result.value!['value_json'], row['value_json']);
        expect(result.value!['source_field'], row['source_field']);
        final terminal = content.terminalMatcher.resolve(
          '${row['match_key']}00000000',
          CuLookupContext(regionCode: city),
        );
        if (row['record_kind'] == 'placeholder') {
          // The longest exact placeholder suppresses a broader readable prefix.
          final exact = content.terminalMatcher.resolve(
            row['match_key'] as String,
            CuLookupContext(regionCode: city),
          );
          expect(exact.status, ReferenceMatchStatus.unknown);
        } else {
          expect(
            terminal.status,
            ReferenceMatchStatus.matched,
            reason:
                'CU $city ${row['match_key']} ${row['record_kind']} is packaged',
          );
          expect(terminal.value!.displayLabel, isNotEmpty);
        }
      }
    });
  }

  for (final city in stationCities) {
    test('CU $city every indexed terminal resolves with its required carrier', () {
      final rows = live.db.select(
        'SELECT * FROM station_lookup WHERE region_code=?',
        [city],
      );
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final required = row['required_transaction_type'] as int;
        final context = CuLookupContext(
          regionCode: city,
          decodedCarrierType: required == -1 ? null : required,
        );
        final key = row['match_key'] as String;
        // Prefix entries must also work for a longer raw transaction terminal.
        final inputs = {
          key,
          if (row['match_mode'] == 'prefix') '${key}00000000',
        };
        for (final input in inputs) {
          final result = content.terminalMatcher.resolve(input, context);
          expect(
            result.status,
            ReferenceMatchStatus.matched,
            reason: 'CU $city $input carrier=$required: ${result.issue}',
          );
          final entry = result.value!;
          expect(
            (
              entry.sourceField,
              entry.sourceKey,
              entry.rawValueJson,
              entry.lineKey,
              entry.lineCode,
              entry.stationCode,
              entry.line,
              entry.station,
            ),
            (
              row['source_field'],
              row['source_key'],
              row['raw_value_json'],
              row['line_key'],
              row['line_code'],
              row['station_code'],
              row['line_name'],
              row['station_name'],
            ),
          );
          if (required != -1) {
            expect(
              live
                  .resolveTerminal(input, CuLookupContext(regionCode: city))
                  .status,
              ReferenceMatchStatus.unknown,
              reason:
                  'Missing carrier must not satisfy CU $city carrier=$required',
            );
            expect(
              live
                  .resolveTerminal(
                    input,
                    CuLookupContext(regionCode: city, decodedCarrierType: 6),
                  )
                  .status,
              ReferenceMatchStatus.unknown,
              reason: 'CJ/T331 instruction 06 is not decoded carrier $required',
            );
          }
        }
      }
    });

    test(
      'CU $city all packaged station names are reachable through LiveSource',
      () async {
        final expected = live.db
            .select(
              'SELECT line_name,station_name FROM stations WHERE region_code=?',
              [city],
            )
            .where((row) => (row['station_name'] as String).isNotEmpty)
            .map(
              (row) => jsonEncode([
                row['line_name'] == '' ? null : row['line_name'],
                row['station_name'],
              ]),
            )
            .toSet();
        final dataset = content.stationDatasets
            .where((item) => item.cityCode == city)
            .single;
        expect(dataset, isA<LiveRegionDataset>());
        final entries = await dataset.lazyEntries();
        expect(
          entries
              .map((entry) => jsonEncode([entry.line, entry.station]))
              .toSet(),
          expected,
        );
        // Browsing names is not evidence that a raw terminal can resolve them.
        expect(
          live
              .resolveTerminal(
                'FFFFFFFFFFFFFFFF',
                CuLookupContext(regionCode: city),
              )
              .status,
          ReferenceMatchStatus.unknown,
        );
      },
    );
  }

  for (final field in ['M0.J.a', 'M0.K.a', 'M0.L.a', 'M0.M.a']) {
    test(
      'CU 5180 $field every historical bus entry needs complete context',
      () {
        final before = DateTime.fromMillisecondsSinceEpoch(1735675199999);
        final rows = live.db.select(
          'SELECT * FROM bus_routes WHERE source_field=?',
          [field],
        );
        expect(rows, isNotEmpty);
        for (final row in rows) {
          final terminal = 'FFFFFFFF${row['terminal_suffix']}';
          final result = content.terminalMatcher.resolve(
            terminal,
            CuLookupContext(
              regionCode: '5180',
              decodedCarrierType: 1,
              transactionTime: before,
              busLookupEnabled: true,
            ),
          );
          expect(result.status, ReferenceMatchStatus.matched);
          expect(
            (
              result.value!.sourceKey,
              result.value!.sourceField,
              result.value!.line,
            ),
            (row['terminal_suffix'], row['source_field'], row['route_number']),
          );
          expect(result.value!.station, isNull);
          expect(
            result.value!.lineCode,
            isNull,
            reason: 'A bus display route is not an invented encoded line code',
          );
        }
        final terminal = 'FFFFFFFF${rows.first['terminal_suffix']}';
        for (final context in [
          CuLookupContext(
            regionCode: '5180',
            transactionTime: before,
            busLookupEnabled: true,
          ),
          CuLookupContext(
            regionCode: '5180',
            decodedCarrierType: 6,
            transactionTime: before,
            busLookupEnabled: true,
          ),
          const CuLookupContext(
            regionCode: '5180',
            decodedCarrierType: 1,
            busLookupEnabled: true,
          ),
          CuLookupContext(
            regionCode: '5180',
            decodedCarrierType: 1,
            transactionTime: before,
          ),
          CuLookupContext(
            regionCode: '5180',
            decodedCarrierType: 1,
            transactionTime: DateTime.fromMillisecondsSinceEpoch(1735675200000),
            busLookupEnabled: true,
          ),
          CuLookupContext(
            regionCode: '1000',
            decodedCarrierType: 1,
            transactionTime: before,
            busLookupEnabled: true,
          ),
        ]) {
          expect(
            content.terminalMatcher.resolve(terminal, context).status,
            ReferenceMatchStatus.unknown,
          );
        }
      },
    );
  }

  // Original L0.a0.m756j(mode=1) returns readable line/operator-only triples
  // using longest-prefix matching. These expose packaged != terminal runtime.
  for (final sample in [
    ('1000', '100004200001', '密云区'),
    ('2150', '2150030000030000', '1号线'),
    ('5180', '518020000000', '东部公交'),
  ]) {
    test(
      'CU ${sample.$1} original line-only prefix reaches terminal lookup',
      () {
        final result = content.terminalMatcher.resolve(
          sample.$2,
          CuLookupContext(regionCode: sample.$1),
        );
        expect(
          result.status,
          ReferenceMatchStatus.matched,
          reason: 'Original M0.y.b line evidence is already packaged',
        );
        expect(result.value!.line, sample.$3);
        expect(result.value!.station, anyOf(isNull, isEmpty));
      },
    );
  }

  // Original N0.a.a and the CU-to-TU name projection N0.e.a have historical
  // date rules. Expectations are literal source evidence, not current DB names.
  for (final sample in [
    ('2000', '2000110234', 1726862400000, '徐泾东', '国家会展中心'),
    ('3100', '331000090054', 1643140800000, '余杭高铁站', '临平南高铁站'),
    ('3140', '335000990001', 1643140800000, '余杭高铁站', '临平南高铁站'),
    ('3120', '337000870031', 1735502400000, '镜湖医院', '人民医院总院'),
  ]) {
    test(
      'CU ${sample.$1} ${sample.$2} uses the original historical date boundary',
      () {
        final terminals = live.db.select(
          'SELECT match_key,required_transaction_type FROM station_lookup '
          'WHERE region_code=? AND source_key=?',
          [sample.$1, sample.$2],
        );
        expect(
          terminals,
          isNotEmpty,
          reason: 'A historical-name test must use a real indexed CU terminal',
        );
        final row = terminals.first;
        final required = row['required_transaction_type'] as int;
        String? stationAt(int time) => content.terminalMatcher
            .resolve(
              row['match_key'] as String,
              CuLookupContext(
                regionCode: sample.$1,
                decodedCarrierType: required == -1 ? null : required,
                transactionTime: DateTime.fromMillisecondsSinceEpoch(time),
              ),
            )
            .value
            ?.station;
        expect(stationAt(sample.$3 - 1), sample.$4);
        expect(stationAt(sample.$3), sample.$5);
      },
    );
  }

  for (final sample in [
    ('2000', '2000260101', 13, '南桥汽车站'),
    ('5180', '518079001', 7, '坪山高铁站'),
  ]) {
    test(
      'CU ${sample.$1} original carrier ${sample.$3} is not labelled metro',
      () {
        final result = content.terminalMatcher.resolve(
          sample.$2,
          CuLookupContext(regionCode: sample.$1, decodedCarrierType: sample.$3),
        );
        expect(result.status, ReferenceMatchStatus.matched);
        expect(result.value!.station, sample.$4);
        expect(
          result.value!.kind,
          isNot('metro'),
          reason: 'Original L0.n.a carrier ${sample.$3} identifies BRT/tram',
        );
        expect(result.value!.type, isNot('地铁'));
      },
    );
  }

  test(
    'CU 5180 operator-only evidence can use a strictly gated historical route',
    () {
      final before = DateTime.fromMillisecondsSinceEpoch(1735675199999);
      final result = content.terminalMatcher.resolve(
        '518020000001',
        CuLookupContext(
          regionCode: '5180',
          decodedCarrierType: 1,
          transactionTime: before,
          busLookupEnabled: true,
        ),
      );
      expect(result.status, ReferenceMatchStatus.matched);
      expect(result.value!.line, '东部公交 · 963');
      expect(result.value!.station, isNull);
      expect(result.value!.sourceKey, '20000001');
      final facade = content.terminalMatcher.match(
        '518020000001',
        cityCode: '5180',
        decodedCarrierType: 1,
        transactionTime: before,
        busLookupEnabled: true,
      );
      expect(facade!.line, '东部公交 · 963');
      for (final context in [
        CuLookupContext(
          regionCode: '5180',
          transactionTime: before,
          busLookupEnabled: true,
        ),
        CuLookupContext(
          regionCode: '5180',
          decodedCarrierType: 6,
          transactionTime: before,
          busLookupEnabled: true,
        ),
        CuLookupContext(
          regionCode: '5180',
          decodedCarrierType: 1,
          transactionTime: before,
        ),
      ]) {
        final entry = content.terminalMatcher
            .resolve('518020000001', context)
            .value!;
        expect(entry.line, '东部公交');
        expect(entry.sourceKey, '518020');
      }
    },
  );

  for (final sample in [
    ('20240920', '120000', '徐泾东'),
    ('20240921', '040000', '国家会展中心'),
  ]) {
    testWidgets('CU panel passes original local time for ${sample.$3}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CityUnionPanel(
                files: [
                  const CjT331PublicInfo(
                    cityCode: '2000',
                    fields: [],
                    rawHex: '',
                  ),
                  _cuRecord('200011023400', sample.$1, sample.$2),
                ],
                resolveStationName: resolveName,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('电子钱包本地消费交易明细（0x18）'));
      await tester.pumpAndSettle();
      expect(find.textContaining(sample.$3), findsWidgets);
    });
  }

  testWidgets(
    'CU panel passes independently decoded Shenzhen carrier and explicit bus option',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CityUnionPanel(
                files: [
                  const CjT331PublicInfo(
                    cityCode: '5180',
                    fields: [],
                    rawHex: '',
                  ),
                  _cuRecord(
                    '000020000001',
                    '20241201',
                    '120000',
                    instruction: 0x09,
                  ),
                ],
                terminalProfile: CuLocalTerminalProfile.shenzhen,
                busLookupEnabled: true,
                resolveStationName: resolveName,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('电子钱包本地消费交易明细（0x18）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('东部公交 · 963'), findsOneWidget);
    },
  );

  test('CU terminal normalization requires an explicit recognized local-card profile', () {
    final standard = CityUnionLookupRules.identifyTerminal(
      '000030000001',
      cardCityCode: '1000',
    )!;
    expect(standard.terminal, '000030000001');
    expect(standard.carrier, isNull);
    final beijing = CityUnionLookupRules.identifyTerminal(
      '000030000001',
      cardCityCode: '1000',
      profile: CuLocalTerminalProfile.beijing,
    )!;
    expect(beijing.terminal, '1000000030000001');
    expect(beijing.carrier, 1);
    final suzhou = CityUnionLookupRules.identifyTerminal(
      '030000030001',
      profile: CuLocalTerminalProfile.suzhou,
    )!;
    expect(suzhou.terminal, '2150030000030001');
    expect(suzhou.carrier, 2);
    final chengdu = CityUnionLookupRules.identifyTerminal(
      '000100212401',
      profile: CuLocalTerminalProfile.chengdu,
    )!;
    expect(chengdu.terminal, '6100000100212401');
    expect(
      chengdu.carrier,
      isNull,
      reason:
          'Profile and instruction are not independent BRT carrier evidence',
    );
    final foreign = CityUnionLookupRules.identifyTerminal(
      '518020000001',
      cardCityCode: '2000',
    )!;
    expect(foreign.regionCode, '5180');
    expect(foreign.carrier, 1);
  });

  for (final instruction in [0x06, 0x09]) {
    testWidgets(
      'CU panel does not turn instruction $instruction into a carrier or invent missing time',
      (tester) async {
        final record = _cuRecord(
          '999999999999',
          '20240231',
          '120000',
          instruction: instruction,
        );
        int? receivedCarrier = -999;
        DateTime? receivedTime = DateTime.utc(2099);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CityUnionPanel(
                  files: [
                    const CjT331PublicInfo(
                      cityCode: '2000',
                      fields: [],
                      rawHex: '',
                    ),
                    record,
                  ],
                  resolveStationName:
                      (
                        terminal, {
                        cityCode,
                        decodedCarrierType,
                        transactionTime,
                        busLookupEnabled = false,
                      }) {
                        receivedCarrier = decodedCarrierType;
                        receivedTime = transactionTime;
                        return content.terminalMatcher
                            .match(
                              terminal,
                              cityCode: cityCode,
                              decodedCarrierType: decodedCarrierType,
                              transactionTime: transactionTime,
                              busLookupEnabled: busLookupEnabled,
                            )
                            ?.displayLabel;
                      },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('电子钱包本地消费交易明细（0x18）'));
        await tester.pumpAndSettle();
        expect(receivedCarrier, isNull);
        expect(receivedTime, isNull);
        expect(find.text('站点（终端解析）'), findsNothing);
      },
    );
  }
}

CjT331WalletLocalConsumption _cuRecord(
  String terminal,
  String date,
  String time, {
  int instruction = 0x06,
}) {
  List<int> bcd(String value) => [
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];
  return CjT331WalletLocalConsumptionParser.parseRecord([
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    instruction,
    ...bcd(terminal),
    ...bcd(date),
    ...bcd(time),
  ]);
}
