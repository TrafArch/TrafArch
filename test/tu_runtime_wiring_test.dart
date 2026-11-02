import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_region_live_source.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_bus_location.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tu_station_repository.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/tu_lookup_service.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_engine.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  late Database db;
  late TuStationRepository repository;
  late KnowledgeBase knowledge;

  setUpAll(() {
    db = sqlite3.open(
      'assets/data/TrafArch_Database_TU.sqlite',
      mode: OpenMode.readOnly,
    );
    repository = TuStationRepository(db);
    knowledge = KnowledgeBase(
      cities: CityTable.fromInfos(const [
        CityInfo(code: '1610', name: '太原'),
        CityInfo(code: '3310', name: '杭州'),
        CityInfo(code: '3610', name: '合肥'),
        CityInfo(code: '3910', name: '福州'),
        CityInfo(code: '4520', name: '青岛'),
        CityInfo(code: '6510', name: '成都'),
      ]),
      issuers: IssuerTable.fromJson(const {}),
      terminalRules: TerminalRuleSet.fromJson(const {}),
      stationCodes: StationCodeTable.empty.withLive(
        TuRegionLiveSource(repository),
      ),
      tuStations: repository,
      tuLookup: TuLookupService(repository),
    );
  });

  tearDownAll(() => db.close());

  test('Shenzhen compatibility POS resolves without rewriting its key', () {
    final trip = _analyze(
      knowledge,
      cityCode: '5840',
      terminalId: '0000000262016000',
      field: '00000000000000',
    );
    expect(trip.lineLabel, '4号线');
    expect(trip.stationLabel, '深圳北站');
    expect(trip.stationConfidence, StationMatchConfidence.exact);
    final match = knowledge.tuLookup!.resolveShenzhenTerminal(
      city: '5840',
      terminal: '0000000262016000',
    );
    expect(match.entry!.sourceKey, '518062016');
    expect(match.entry!.sourceField, 'M0.y.b');
    final provenance = db.select(
      "SELECT copy_role FROM all_records WHERE region_code='5840' "
      "AND source_key='518062016'",
    );
    expect(provenance, hasLength(1));
    expect(provenance.single['copy_role'], isNot('native'));
  });

  test('Shenzhen operator prefixes preserve dated bus route decoding', () {
    final hit = resolveTunionBusLocation(
      stations: knowledge.stationCodes,
      cityCode: '5840',
      field: '00150000000000',
      context: TunionBusDecodeContext(
        terminalId: '0000000224000002',
        carrierCode: 1,
        transactionTime: DateTime.fromMillisecondsSinceEpoch(1735675199999),
      ),
    );
    expect(hit.lineLabel, 'M292');
    expect(hit.match.entry!.sourceKey, '518024');
  });

  test('packaged Chengdu terminal layout is used by the trip engine', () {
    final trip = _analyze(
      knowledge,
      cityCode: '6510',
      terminalId: '6510000000000000',
      field: '00001021000000',
    );
    expect(trip.lineLabel, '10号线');
    expect(trip.stationLabel, '太平园');
    expect(trip.stationConfidence, StationMatchConfidence.exact);
  });

  test('packaged Fuzhou process layout is used by the trip engine', () {
    final trip = _analyze(
      knowledge,
      cityCode: '3910',
      terminalId: '3910000000000000',
      field: '00010011000000',
    );
    expect(trip.lineLabel, '1号线');
    expect(trip.stationLabel, '象峰');
  });

  test('packaged Qingdao conflicting line labels stay ambiguous in the trip engine', () {
    final trip = _analyze(
      knowledge,
      cityCode: '4520',
      terminalId: '4520000011210000',
      field: '00000000000000',
    );
    expect(trip.stationConfidence, StationMatchConfidence.ambiguous);
    expect(trip.lineLabel, isNull);
    expect(trip.stationLabel, isNot('苗岭路'));
    expect(trip.matchedProcessTrip!.terminalId, '4520000011210000');
  });

  test('packaged Hefei process terminal hits M0.S.a exactly', () {
    final trip = _analyze(
      knowledge,
      cityCode: '3610',
      terminalId: '0000413106085352',
      field: '00000101000000',
    );
    expect(trip.stationLabel, '铜陵新村');
    expect(trip.stationConfidence, StationMatchConfidence.exact);
  });

  test('packaged Taiyuan basic terminal resolves the rail station', () {
    final time = DateTime(2026, 10, 20, 12);
    final trip = AnalysisEngine(knowledge)
        .analyze(
          ParsedCard(
            parserName: 'tu runtime wiring',
            selectedAidHex: 'A000000632010105',
            info: const TUnionCardInfo(cityCode: '1610'),
            transactions: [
              TUnionTransaction(
                sequence: 1,
                overdraftLimitFen: 0,
                amountFen: 100,
                rawType: 9,
                terminalId: '413180000003',
                time: time,
              ),
            ],
          ),
        )
        .trips
        .single;
    expect(trip.lineLabel, '2号线');
    expect(trip.stationLabel, '龙兴街');
    expect(trip.stationConfidence, StationMatchConfidence.exact);
  });

  test('packaged Hangzhou terminal alias resolves through M0.s.a', () {
    final time = DateTime(2026, 10, 20, 12);
    final trip = AnalysisEngine(knowledge)
        .analyze(
          ParsedCard(
            parserName: 'tu runtime wiring',
            selectedAidHex: 'A000000632010105',
            info: const TUnionCardInfo(cityCode: '3310'),
            transactions: [
              TUnionTransaction(
                sequence: 1,
                overdraftLimitFen: 0,
                amountFen: 100,
                rawType: 9,
                terminalId: '413101784816',
                time: time,
              ),
            ],
          ),
        )
        .trips
        .single;
    expect(trip.lineLabel, '4号线');
    expect(trip.stationLabel, '市民中心');
  });
}

TransitTrip _analyze(
  KnowledgeBase knowledge, {
  required String cityCode,
  required String terminalId,
  required String field,
}) {
  final time = DateTime(2026, 10, 20, 12);
  final trip = TUnionTripRecord(
    typeCode: 6,
    terminalId: terminalId,
    appTypeCode: 1,
    lineStationCode: field,
    amountFen: 100,
    balanceFen: 10000,
    time: time,
    cityCode: cityCode,
  );
  return AnalysisEngine(knowledge)
      .analyze(
        ParsedCard(
          parserName: 'tu runtime wiring',
          selectedAidHex: 'A000000632010105',
          info: const TUnionCardInfo(),
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
              trip: trip,
            ),
          ],
        ),
      )
      .trips
      .single;
}
