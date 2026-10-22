import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

// Literal source pairs: M0.J/K/L/M.a. Times straddle the original m763q
// cutoff; these are controlled synthetic records, not captured device traffic.
void main() {
  for (final (terminal, expected) in const [
    ('0000000220000001', '963'),
    ('0000000224000002', 'M292'),
    ('0000000231010001', 'M437'),
    ('0000000231020001', '83'),
  ]) {
    test('Shenzhen historical terminal $terminal reaches paired trip', () {
      expect(_line(city: '5840', terminal: terminal), expected);
    });
  }

  test('Shenzhen historical name retains the original contained route', () {
    // m764r parses field[0:4] as hexadecimal: 0x0015 = 21 -> current route 2.
    // M292 contains "2", so original m1288J0 contains() keeps M292.
    expect(
      _line(
        city: '5840',
        terminal: '0000000224000002',
        field: '00150000000000',
      ),
      'M292',
    );
  });

  test(
    'Shenzhen 0020 current route replaces non-contained historical name',
    () {
      // 0x0020 = 32 -> current route 3; M292 does not contain "3".
      expect(
        _line(
          city: '5840',
          terminal: '0000000224000002',
          field: '00200000000000',
        ),
        '3',
      );
    },
  );

  test('Shenzhen current route replaces an unrelated historical route', () {
    expect(
      _line(
        city: '5840',
        terminal: '0000000220000001',
        field: '00160000000000',
      ),
      '2',
    );
  });

  test('Shenzhen history stops exactly at its source epoch boundary', () {
    expect(
      _line(city: '5840', terminal: '0000000220000001', epoch: 1735675200000),
      '0000',
    );
  });

  test(
    'Shenzhen history cannot leak through another terminal prefix or city',
    () {
      expect(_line(city: '5840', terminal: '0000000320000001'), '0000');
      expect(_line(city: '1610', terminal: '0000000220000001'), isNot('963'));
    },
  );

  test('original subtype-one city exception reaches the bus decoder', () {
    expect(_line(city: '1380', app: 1, field: '00010000000000'), '1');
  });

  test('original bus prefix carrier 13 suppresses route-name fallback', () {
    expect(_line(city: '3610', field: '09990000002F00'), '0999');
  });
}

String? _line({
  required String city,
  String terminal = '0000000000000001',
  String field = '00000000000000',
  int app = 2,
  int epoch = 1735675199999,
}) {
  final time = DateTime.fromMillisecondsSinceEpoch(epoch);
  final record = TUnionTripRecord(
    typeCode: 6,
    terminalId: terminal,
    appTypeCode: app,
    lineStationCode: field,
    amountFen: 100,
    balanceFen: 10000,
    time: time,
    cityCode: city,
  );
  return AnalysisEngine(KnowledgeBase.empty())
      .analyze(
        ParsedCard(
          parserName: 'source caller bus regression',
          selectedAidHex: 'A000000632010105',
          info: const TUnionCardInfo(cityCode: '3910'),
          transactions: [
            TUnionTransaction(
              sequence: 1,
              overdraftLimitFen: 0,
              amountFen: 100,
              rawType: 9,
              terminalId: terminal.substring(4),
              time: time,
            ),
          ],
          transitProcessRecords: [
            TUnionProcessRecord(
              sfi: 0x1E,
              recordNumber: 1,
              recordName: 'synthetic bus',
              raw: const [],
              trip: record,
            ),
          ],
        ),
      )
      .trips
      .single
      .lineLabel;
}
