import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_record_context.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';

void main() {
  test('source city aliases only rewrite the derived acquirer city', () {
    expect(normalizeTunionAcquirerCity('1160'), '2220');
    expect(normalizeTunionAcquirerCity('2140'), '3020');
    expect(normalizeTunionAcquirerCity('6500'), '7310');
    expect(normalizeTunionAcquirerCity('7100'), '7910');
    expect(normalizeTunionAcquirerCity('5230', rawCity36: 5930), '6020');
    expect(normalizeTunionAcquirerCity('5230', rawCity36: 5929), '5230');
    expect(normalizeTunionAcquirerCity('3910'), '3910');
    expect(normalizeTunionAcquirerCity(null), isNull);
  });

  test('paired rail normalizes the source Dalian city alias before lookup', () {
    final time = DateTime(2026, 10, 20, 12);
    final knowledge = KnowledgeBase.fromJsonStrings(
      stationCodes: StationCodeTable.fromDatasets([
        const StationDataset(
          file: 'source alias regression',
          cityCode: '2220',
          kind: 'metro',
          codes: {
            '22200801': StationCodeEntry(
              code: '22200801',
              sourceKey: '22200801',
              sourceField: 'M0.i0.a',
              line: '12号线',
              station: '河口',
            ),
          },
        ),
      ]),
    );
    final process = TUnionTripRecord(
      typeCode: 6,
      terminalId: '0000000000000001',
      appTypeCode: 1,
      lineStationCode: '08010000000000',
      amountFen: 100,
      balanceFen: 10000,
      time: time,
      cityCode: '1160',
    );
    final trip = AnalysisEngine(knowledge)
        .analyze(
          ParsedCard(
            parserName: 'source alias regression',
            selectedAidHex: 'A000000632010105',
            info: const TUnionCardInfo(cityCode: '3910'),
            transactions: [
              TUnionTransaction(
                sequence: 1,
                overdraftLimitFen: 0,
                amountFen: 100,
                rawType: 9,
                terminalId: '000000000001',
                time: time,
              ),
            ],
            transitProcessRecords: [
              TUnionProcessRecord(
                sfi: 0x1E,
                recordNumber: 1,
                recordName: 'synthetic 1E',
                raw: const [],
                trip: process,
              ),
            ],
          ),
        )
        .trips
        .single;
    expect(trip.stationLabel, '河口');
    expect(trip.cityCode, '2220');
    expect(trip.matchedProcessTrip!.cityCode, '1160');
  });
  // Literal route/date boundary from the original Shanghai m764r branch.
  // These are synthetic transaction records, not newly captured card data.
  for (final (epoch, label) in [
    (1572033599999, '835'),
    (1572033600000, '71 T2'),
  ]) {
    test('paired Shanghai bus keeps transaction date $epoch -> $label', () {
      final time = DateTime.fromMillisecondsSinceEpoch(epoch);
      final record = TUnionTripRecord(
        typeCode: 6,
        terminalId: '0000000000000001',
        appTypeCode: 2,
        lineStationCode: '08350000000000',
        amountFen: 100,
        balanceFen: 10000,
        time: time,
        cityCode: '2900',
      );
      final card = ParsedCard(
        parserName: 'synthetic city integration',
        selectedAidHex: 'A000000632010105',
        info: const TUnionCardInfo(cityCode: '3910'),
        transactions: [
          TUnionTransaction(
            sequence: 1,
            overdraftLimitFen: 0,
            amountFen: 100,
            rawType: 9,
            terminalId: '000000000001',
            time: time,
          ),
        ],
        transitProcessRecords: [
          TUnionProcessRecord(
            sfi: 0x1E,
            recordNumber: 1,
            recordName: 'synthetic 1E',
            raw: const [],
            trip: record,
          ),
        ],
      );
      final trip = AnalysisEngine(KnowledgeBase.empty())
          .analyze(card)
          .trips
          .single;
      expect(trip.lineLabel, label);
      expect(trip.cityCode, '2900');
      expect(trip.matchedProcessTrip?.lineStationCode, '08350000000000');
    });
  }

  test('unknown industry cannot run rail matching', () {
    final raw = <int>[
      6,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
      0xFE,
      8,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      100,
      0,
      0,
      0,
      0,
      0x20,
      0x26,
      0x10,
      0x20,
      0x12,
      0,
      0,
      0x22,
      0x20,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ];
    final record = const TUnionProcessParser().parseCycleTrip(raw)!;
    expect(record.appTypeLabel, isNull);
    // An absent label must remain unknown even if the field resembles a rail key.
    expect(record.isCityRail, isFalse);
    expect(record.rawHex, isNotNull);
  });

  test(
    'paired 1A rail uses the same full station and line as its own card',
    () {
      final time = DateTime(2026, 10, 20, 12);
      final knowledge = KnowledgeBase.fromJsonStrings(
        stationCodes: StationCodeTable.fromDatasets([
          const StationDataset(
            file: 'synthetic rail regression',
            cityCode: '1000',
            kind: 'metro',
            codes: {
              '100000050102': StationCodeEntry(
                code: '100000050102',
                sourceKey: '100000050102',
                sourceField: 'M0.i0.a',
                line: 'test line',
                station: 'full station',
              ),
            },
          ),
        ]),
      );
      final result = AnalysisEngine(knowledge).analyze(
        ParsedCard(
          parserName: 'synthetic 1A',
          selectedAidHex: 'A000000632010105',
          info: const TUnionCardInfo(cityCode: '3910'),
          transactions: [
            TUnionTransaction(
              sequence: 1,
              overdraftLimitFen: 0,
              amountFen: 0,
              rawType: 9,
              terminalId: '000000000001',
              time: time,
            ),
          ],
          transitProcessRecords: [
            TUnionProcessRecord(
              sfi: 0x1A,
              recordNumber: 1,
              recordName: 'synthetic rail',
              raw: const [],
              railTransit: TransitRecord(
                statusCode: 1,
                entryCityCode: '1000',
                entryStationId: '0000000000000102',
                entryLineCode: 5,
                entryTime: time,
                entryAmountFen: 0,
              ),
            ),
          ],
        ),
      );
      final trip = result.trips.single;
      expect(trip.stationLabel, 'full station');
      expect(trip.lineLabel, 'test line');
      expect(trip.stationConfidence, StationMatchConfidence.exact);
      expect(trip.cityCode, '1000');
    },
  );
}
