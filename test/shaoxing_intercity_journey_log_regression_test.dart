import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_application_display.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/features/transit_analysis/tunion_analysis_models.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/features/trips/trip_entry_presenter.dart';
import 'package:transit_card_analyzer/features/trips/trip_filters.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_adapter.dart';
import 'package:transit_card_analyzer/features/trips/trip_journey_evidence.dart';
import 'package:transit_card_analyzer/features/trips/trip_presentation_context.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_trip_matcher.dart';

// Exact successful record bodies from the LAST read in
// transit_card_log_20261104_160640.txt: 2026-11-04 16:06:30, Build 2122.
// The earlier 2026-10-30 session in that same exported log is not replayed.
// All 10 TU18, 18 TU1A and 30 TU1E records are retained, including the real
// zero-filled 1A bodies/headers, the two short 1A records and issuer custom data.
// Only the successful SW9000 bytes are omitted from these body constants.
// SELECT, public identity and holder information use explicitly synthetic
// envelopes below; no real public card number or holder identity is copied.
// This starts at CommonUnitTu. The preceding rejected PAY.APPY probes belong
// to local-card discovery and are outside this TU journey regression.
const _transactions = [
  '242A000000000000000941310188306220261104094123',
  '2429000000000000000941310143052920261104074947',
  '2428000000000000000941310143064520261104073732',
  '2427000000000000000941310190779720261104073226',
  '2426000000000000000941310623606720261104055831',
  '2425000000000000000941310623607220261103221109',
  '2424000000000000000941310614910820261103215717',
  '2423000000000000000941310614623420261103214641',
  '2422000000000000000941310614776820261103212209',
  '2421000000000000000941310614776320261103201554',
];
const _variableRecords = [
  '27017D0101003137393337353634023300337003493370FFFFFFFF03493370FFFFFFFF411230500000012141123050000011353050000001211A043050000011351501202611040749472026110409412300000000011100000000000005DC000000000000000000000000000000000000000000000000000000000000000000',
  '27027D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000086228680600000026110407373287',
  '27037D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27047D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27057D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27067D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27076D01010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27087D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27097D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '270A7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '270B7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '270C7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '270D1B010100000000000000000000000000000000000000000000000000',
  '270E7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '270F7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27107D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27117D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27127D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
];
const _cycles = [
  '0441310188306200000A1135150100000000000000000005DC20261104094123337003493370FFFFFFFF000000000000',
  '0341310143052900000A01211A0400000000000000000005DC20261104074947337003493370FFFFFFFF000000000000',
  '060000413101430645020000086200000000000000000005DC20261104073732337013493370FFFFFFFF000000000000',
  '040000413101907797010089000500000000000000000005DC20261104073226337003493370FFFFFFFF000000000000',
  '030000413106236067010003003500000000000000000005DC20261104055831331001663310FFFFFFFF000000000000',
  '040000413106236072010003003500000000000000000005DC20261103221109331001663310FFFFFFFF000000000000',
  '030000413106149108010005001900000000000000000005DC20261103215717331001663310FFFFFFFF000000000000',
  '040000413106146234010001001400000000000000000005DC20261103214641331001663310FFFFFFFF000000000000',
  '030000413106147768010004001400000000000000000005DC20261103212209331001663310FFFFFFFF000000000000',
  '040000413106147763010004001400000000000000000005DC20261103201554331001663310FFFFFFFF000000000000',
  '030000413106148031010002003300000000000000000005DC20261103192231331001663310FFFFFFFF000000000000',
  '040000413106147396010002003300000000000000000005DC20261103063045331001663310FFFFFFFF000000000000',
  '030000413106236067010003003500000000000000000005DC20261103054901331001663310FFFFFFFF000000000000',
  '040000413106147018010005001500000000000000000005DC20261102213600331001663310FFFFFFFF000000000000',
  '030000413101908032010089000100000000000000000005DC20261102203449337003493370FFFFFFFF000000000000',
  '040000413101908034010089000100000000000000000005DC20261102203411337003493370FFFFFFFF000000000000',
  '030000413106147238010002000500000000000000000005DC20261102201148331001663310FFFFFFFF000000000000',
  '040000413106147252010002000500000000000000000005DC20261102170703331001663310FFFFFFFF000000000000',
  '030000413106149018010001001800000000000000000005DC20261102162525331001663310FFFFFFFF000000000000',
  '040000413106148824010001001800000000000000000005DC20261102133552331001663310FFFFFFFF000000000000',
  '030000413106236067010003003500000000000000000005DC20261102130148331001663310FFFFFFFF000000000000',
  '040000413106234030010003003500000000000000000005DC20261102074159331001663310FFFFFFFF000000000000',
  '030000413101908195010089001000000000000000000005DC20261102060753337003493370FFFFFFFF000000000000',
  '060000413101882361020000080700000000000000000005DC20261101164047337013493370FFFFFFFF000000000000',
  '040000413101908075010089001000000000000000000005DC20261101163709337003493370FFFFFFFF000000000000',
  '030000413101945458010088002200000000000000000005DC20261101155420337003493370FFFFFFFF000000000000',
  '060000413100768256020001905200000000000000000005DC20261101154149337013493370FFFFFFFF000000000000',
  '060000413101266414020001005200000000000000000005DC20261101144144337013493370FFFFFFFF000000000000',
  '040000413101945673010087003200000000000000000005DC20261101141522337003493370FFFFFFFF000000000000',
  '030000413101908163010089001000000000000000000005DC20261101135303337003493370FFFFFFFF000000000000',
];
const _typeCodes = [
  0x04,
  0x03,
  0x06,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x04,
  0x03,
  0x06,
  0x04,
  0x03,
  0x06,
  0x06,
  0x04,
  0x03,
];
const _appTypes = [
  0x0A,
  0x0A,
  0x02,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x02,
  0x01,
  0x01,
  0x02,
  0x02,
  0x01,
  0x01,
];
const _cities = [
  '3370',
  '3370',
  '3370',
  '3370',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3370',
  '3370',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3310',
  '3370',
  '3370',
  '3370',
  '3370',
  '3370',
  '3370',
  '3370',
  '3370',
];
const _acquirers = [
  '03493370FFFFFFFF',
  '03493370FFFFFFFF',
  '13493370FFFFFFFF',
  '03493370FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '03493370FFFFFFFF',
  '03493370FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '01663310FFFFFFFF',
  '03493370FFFFFFFF',
  '13493370FFFFFFFF',
  '03493370FFFFFFFF',
  '03493370FFFFFFFF',
  '13493370FFFFFFFF',
  '13493370FFFFFFFF',
  '03493370FFFFFFFF',
  '03493370FFFFFFFF',
];
const _managementResponse =
    '0000015633003370000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009000';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late ScanPresentation view;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'trafarch-shaoxing-intercity-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    expect(reference.knowledge!.loadIssues, isEmpty);
    view = await _read(reference);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('绍兴城际真实末轮读取保留10条交易18条1A及30条1E原文和原分类', () {
    expect(view.parsedCard!.info.balanceFen, 1500);
    expect(view.parsedCard!.transactionFileObserved, isTrue);
    expect(view.parsedCard!.transactions, hasLength(10));
    expect(
      view.parsedCard!.transactions.map((record) => record.rawHex),
      _transactions,
    );
    expect(view.analysis!.trips, hasLength(10));
    final variables = view.transitProcessRecords
        .where((record) => record.sfi == 0x1A)
        .toList();
    expect(variables, hasLength(18));
    expect(
      variables.map((record) => _compact(record.rawHex)),
      _variableRecords,
    );
    expect(variables.map((record) => record.recordNumber), [
      for (var i = 1; i <= 18; i++) i,
    ]);
    expect(variables.map((record) => record.raw.length), [
      128,
      128,
      128,
      128,
      128,
      128,
      112,
      128,
      128,
      128,
      128,
      128,
      30,
      128,
      128,
      128,
      128,
      128,
    ]);
    final cycles = view.transitProcessRecords
        .where((record) => record.sfi == 0x1E)
        .toList();
    expect(cycles, hasLength(30));
    expect(cycles.map((record) => _compact(record.rawHex)), _cycles);
    expect(cycles.map((record) => record.recordNumber), [
      for (var i = 1; i <= 30; i++) i,
    ]);
    expect(cycles.every((record) => record.recordNumberIsReliable), isTrue);
    expect(view.cycleProcessTrips.map((record) => record.typeCode), _typeCodes);
    expect(
      view.cycleProcessTrips.map((record) => record.appTypeCode),
      _appTypes,
    );
    expect(view.cycleProcessTrips.map((record) => record.cityCode), _cities);
    expect(
      view.cycleProcessTrips.map((record) => record.acquirerId),
      _acquirers,
    );
    expect(
      view.cycleProcessTrips.map((record) => record.amountFen),
      everyElement(0),
    );
    expect(
      view.cycleProcessTrips.map((record) => record.balanceFen),
      everyElement(1500),
    );
    expect(_civil(view.cycleProcessTrips[0].time), '2026/11/4 9:41:23');
    expect(_civil(view.cycleProcessTrips[1].time), '2026/11/4 7:49:47');
    // The actual 1A record has the same times but different city/terminal
    // namespaces. Do not rewrite it to manufacture agreement with the 1E pair.
    final rail = view.railTransitRecord!;
    expect(rail.rawHex, _variableRecords.first);
    expect(rail.statusCode, 2);
    expect(rail.entryCityCode, '3300');
    expect(rail.exitCityCode, '3370');
    expect(_civil(rail.entryTime), '2026/11/4 7:49:47');
    expect(_civil(rail.exitTime), '2026/11/4 9:41:23');
    expect(rail.entryTerminalId, '3050000001211A04');
    expect(rail.exitTerminalId, '3050000011351501');
    expect(view.cycleProcessTrips[1].terminalId, '4131014305290000');
    expect(view.cycleProcessTrips[0].terminalId, '4131018830620000');
  });

  test('app0A城际进出站在真实完整行程流中组成已完成轨道行程及零票价', () {
    _expectIntercityJourney(_liveJourneys(view, reference));
    // Presentation is a projection; neither protocol bytes nor application
    // classes may be changed to make this zero-fare ride pair.
    expect(view.cycleProcessTrips.map((record) => record.rawHex), _cycles);
    expect(
      view.cycleProcessTrips.map((record) => record.appTypeCode),
      _appTypes,
    );
  });

  test('stage及完整JSON恢复保留末轮10条交易18条1A和30条1E证据', () async {
    final saved = await _saveAndRestore(view);
    _expectSnapshotEvidence(CardSessionSnapshot.decode(saved.encoded)!);
    for (final history in [saved.history, saved.restoredHistory]) {
      expect(history.batches, hasLength(1));
      expect(history.batches.single.decoded.rawJson, saved.encoded);
      final snapshot = history.batches.single.decoded.snapshot!;
      _expectSnapshotEvidence(snapshot);
      expect(
        snapshot.encode() == saved.encoded,
        isTrue,
        reason: 'Decoding must retain the complete persisted JSON text',
      );
      expect(
        history.records.where(
          (record) => record.kind == ArchiveRecordKind.transaction,
        ),
        hasLength(10),
      );
      expect(
        history.records.where(
          (record) => record.kind == ArchiveRecordKind.process,
        ),
        hasLength(30),
      );
    }
  });

  test('已保存档案与完整JSON恢复显示同一个app0A已完成城际行程', () async {
    final saved = await _saveAndRestore(view);
    for (final history in [saved.history, saved.restoredHistory]) {
      final before = jsonEncode([
        for (final record in history.records) record.fields,
      ]);
      final projection = presentArchiveTrips(
        history.records,
        batches: history.batches,
        onDiagnostics: (_) {},
      );
      expect(projection.transactionCount, 10);
      _expectIntercityJourney(projection.journeys);
      expect(
        jsonEncode([for (final record in history.records) record.fields]),
        before,
      );
      expect(history.batches.single.decoded.rawJson, saved.encoded);
      _expectSnapshotEvidence(history.batches.single.decoded.snapshot!);
    }
  });

  test('无0x18时真实1A与30条物理1E仍完成城际行程并识别跨城市终点', () {
    _expectIntercityJourney(
      _liveJourneys(view, reference, includeTransactions: false),
    );
    final capture = _syntheticCapture(
      view,
      rails: [view.railTransitRecord!],
      cycles: view.cycleProcessTrips,
    );
    final history = _syntheticHistory([capture]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    expect(projection.transactionCount, 0);
    _expectIntercityJourney(projection.journeys);
    expect(
      history.batches.single.decoded.rawJson == capture.encode(),
      isTrue,
      reason: 'Process-only projection must not rewrite its capture',
    );
  });

  test('异时同POS的展示关联不得吞掉真实城际1E时间端点', () {
    // Synthetic negative: reuse the real latest 0x18 POS/amount/direction but
    // move its civil time forward one minute. A stale displayProcessKey alone
    // must not let that transaction represent the real 09:41:23 exit. The
    // correct 1A and all physical 1E records remain exactly as captured.
    final original = view.analysis!.trips.first;
    final syntheticTransaction = TransitTrip(
      time: DateTime(2026, 11, 4, 9, 42, 23),
      amountFen: original.amountFen,
      overdraftLimitFen: original.overdraftLimitFen,
      isConsume: original.isConsume,
      typeName: original.typeName,
      isCompositeConsume: original.isCompositeConsume,
      sequence: original.sequence,
      terminalId: original.terminalId,
      location: original.location,
      cityName: original.cityName,
      cityCode: original.cityCode,
      lineLabel: original.lineLabel,
      resolvedBusLineLabel: original.resolvedBusLineLabel,
      stationLabel: original.stationLabel,
      stationType: original.stationType,
      appTypeName: '城际铁路',
      balanceAfterFen: original.balanceAfterFen,
      balanceAfterIsRecorded: original.balanceAfterIsRecorded,
      rideStatusName: original.rideStatusName,
      rideStatusSource: original.rideStatusSource,
      isEntry: original.isEntry,
      displayProcessKey: cycleDisplayKey(view.cycleProcessTrips.first),
      stationConfidence: original.stationConfidence,
      rawHex: '${_transactions.first.substring(0, 32)}20261104094223',
      currency: original.currency,
    );
    expect(syntheticTransaction.terminalId, original.terminalId);
    expect(syntheticTransaction.matchedProcessTrip, isNull);
    expect(syntheticTransaction.isEntry, isFalse);
    expect(syntheticTransaction.amountFen, 0);
    _expectIntercityJourney(
      _liveJourneys(
        view,
        reference,
        transactionOverride: [syntheticTransaction],
      ),
    );
    final capture = _syntheticCapture(
      view,
      trips: [syntheticTransaction],
      rails: [view.railTransitRecord!],
      cycles: view.cycleProcessTrips,
    );
    final history = _syntheticHistory([capture]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    _expectIntercityJourney(projection.journeys);
    expect(
      history.batches.single.decoded.rawJson == capture.encode(),
      isTrue,
      reason: 'Rejecting a stale display link must preserve the capture',
    );
  });

  test('缺少或重复1E及重复1A时不吞掉原1A进站侧', () {
    final rail = view.railTransitRecord!;
    final cycles = view.cycleProcessTrips;
    // These multiplicity perturbations are synthetic boundaries, not extra
    // APDU responses claimed to exist in the source log.
    final cases = [
      (
        name: 'missing 1E',
        rails: [rail],
        cycles: <TUnionTripRecord>[],
        count: 1,
      ),
      (
        name: 'duplicate 1E',
        rails: [rail],
        cycles: [...cycles, cycles[1]],
        count: 1,
      ),
      (name: 'duplicate 1A', rails: [rail, rail], cycles: cycles, count: 2),
    ];
    for (final variant in cases) {
      final stream = buildTripStream(
        trips: const [],
        rails: variant.rails,
        processTrips: variant.cycles,
      );
      expect(
        stream.whereType<RailRecordEntry>().where((side) => side.isEntry),
        hasLength(variant.count),
        reason: variant.name,
      );
      final capture = _syntheticCapture(
        view,
        rails: variant.rails,
        cycles: variant.cycles,
      );
      final history = _syntheticHistory([capture]);
      final projection = presentArchiveTrips(
        history.records,
        batches: history.batches,
        onDiagnostics: (_) {},
      );
      final entries = projection.journeys
          .expand((journey) => journey.events)
          .where(
            (event) =>
                event.payload.source == ArchiveRecordKind.rail &&
                event.role == JourneyEventRole.entry,
          );
      expect(entries, hasLength(variant.count), reason: variant.name);
      expect(
        history.batches.single.decoded.rawJson == capture.encode(),
        isTrue,
        reason: '${variant.name}: ambiguity must not rewrite original evidence',
      );
    }
  });

  for (final change in {
    '时间': {0x43: '20261104074948'},
    '机构': {0x13: '03493371FFFFFFFF'},
    '城市': {0x0F: '3310'},
    '金额': {0x57: '00000001'},
  }.entries) {
    test('1A${change.key}与1E冲突时实时及档案均保留1A侧', () {
      // Alter exactly one source-field byte range in a COPY of the real 1A.
      // The altered capture is explicitly synthetic; all other fields and
      // the production protocol decoder remain real.
      final bytes = _hex(_variableRecords.first);
      for (final field in change.value.entries) {
        final replacement = _hex(field.value);
        bytes.setRange(field.key, field.key + replacement.length, replacement);
      }
      final rail = const TUnionProcessParser().parseRailTransit(1, bytes)!;
      final stream = buildTripStream(
        trips: const [],
        rails: [rail],
        processTrips: view.cycleProcessTrips,
      );
      expect(
        stream.whereType<RailRecordEntry>().where((side) => side.isEntry),
        hasLength(1),
      );
      final capture = _syntheticCapture(
        view,
        rails: [rail],
        cycles: view.cycleProcessTrips,
      );
      final history = _syntheticHistory([capture]);
      final projection = presentArchiveTrips(
        history.records,
        batches: history.batches,
        onDiagnostics: (_) {},
      );
      expect(
        projection.journeys
            .expand((journey) => journey.events)
            .where(
              (event) =>
                  event.payload.source == ArchiveRecordKind.rail &&
                  event.role == JourneyEventRole.entry,
            ),
        hasLength(1),
      );
      expect(
        history.batches.single.decoded.snapshot!.rails.single.rawHex,
        rail.rawHex,
      );
      expect(view.railTransitRecord!.rawHex, _variableRecords.first);
    });
  }

  test('不同读取批次的1A和1E即使逐字段相符也不折叠档案1A侧', () {
    final railOnly = _syntheticCapture(
      view,
      rails: [view.railTransitRecord!],
      cycles: const [],
    );
    final processOnly = _syntheticCapture(
      view,
      rails: const [],
      cycles: view.cycleProcessTrips,
    );
    final history = _syntheticHistory([railOnly, processOnly]);
    final projection = presentArchiveTrips(
      history.records,
      batches: history.batches,
      onDiagnostics: (_) {},
    );
    final railEvents = projection.journeys
        .expand((journey) => journey.events)
        .where((event) => event.payload.source == ArchiveRecordKind.rail);
    expect(railEvents, hasLength(2));
    expect(railEvents.map((event) => event.role).toSet(), {
      JourneyEventRole.entry,
      JourneyEventRole.exit,
    });
    expect(
      projection.entries.where(
        (entry) => entry.source == ArchiveRecordKind.rail,
      ),
      hasLength(2),
    );
    expect(
      history.batches.every(
        (batch) =>
            batch.decoded.rawJson ==
            [
              railOnly,
              processOnly,
            ][int.parse(batch.id.substring('synthetic-'.length))].encode(),
      ),
      isTrue,
      reason: 'Cross-batch alias checks must preserve both capture payloads',
    );
  });
}

void _expectIntercityJourney<T>(Iterable<JourneyPresentation<T>> journeys) {
  // The verified 1A side aliases may fold into the app0A 1E presentation.
  // Original evidence stays separate in the capture even though the complete
  // stream must not show another entry for this already completed ride.
  final reported = journeys
      .where(
        (journey) => journey.events.any(
          (event) =>
              _civil(event.endpoint.time) == '2026/11/4 7:49:47' ||
              _civil(event.endpoint.time) == '2026/11/4 9:41:23',
        ),
      )
      .toList();
  expect(
    reported,
    hasLength(1),
    reason: 'Do not show a duplicate 1A entry after exit',
  );
  final matches = journeys
      .where(
        (journey) => journey.events.any(
          (event) =>
              event.railAppTypeCode == 0x0A &&
              _civil(event.endpoint.time) == '2026/11/4 7:49:47',
        ),
      )
      .toList();
  expect(
    matches,
    hasLength(1),
    reason: 'The observed app0A entry must belong to one completed rail ride',
  );
  final journey = matches.single;
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.state, JourneyState.completed);
  expect(_civil(journey.start?.time), '2026/11/4 7:49:47');
  expect(_civil(journey.end?.time), '2026/11/4 9:41:23');
  expect(journey.start?.line, '绍兴城际');
  expect(journey.start?.station, '钱清');
  expect(journey.end?.line, '宁波城际');
  expect(journey.end?.station, '宁波');
  expect(journey.isCrossCity, isTrue);
  expect(journey.cityLabel, isNull);
  expect(journey.duration, const Duration(hours: 1, minutes: 51, seconds: 36));
  expect(_compact(journey.amountText), anyOf('¥0.00', '-¥0.00'));
  final intercity = journey.events
      .where((event) => event.railAppTypeCode == 0x0A)
      .toList();
  expect(intercity.map((event) => event.role).toSet(), {
    JourneyEventRole.entry,
    JourneyEventRole.exit,
  });
  expect(intercity.map((event) => event.cityCode).toSet(), {'3370'});
}

void _expectSnapshotEvidence(CardSessionSnapshot snapshot) {
  expect(snapshot.trips, hasLength(10));
  expect(snapshot.trips.map((record) => record.rawHex), _transactions);
  expect(snapshot.processTrips, hasLength(30));
  expect(snapshot.processTrips.map((record) => record.rawHex), _cycles);
  expect(snapshot.processTrips.map((record) => record.typeCode), _typeCodes);
  expect(snapshot.processTrips.map((record) => record.appTypeCode), _appTypes);
  expect(snapshot.processTrips.map((record) => record.cityCode), _cities);
  expect(snapshot.processTrips.map((record) => record.acquirerId), _acquirers);
  expect(
    snapshot.processTrips.map((record) => record.amountFen),
    everyElement(0),
  );
  expect(
    snapshot.processTrips.map((record) => record.balanceFen),
    everyElement(1500),
  );
  final variables = snapshot.rawEvidence
      .where(
        (record) =>
            record['kind'] == 'tu_process_record' && record['sfi'] == 0x1A,
      )
      .toList();
  expect(variables, hasLength(18));
  expect(
    variables.map((record) => _compact(record['rawHex'] as String?)),
    _variableRecords,
  );
  expect(variables.map((record) => record['recordNumber']), [
    for (var i = 1; i <= 18; i++) i,
  ]);
  final cycles = snapshot.rawEvidence
      .where(
        (record) =>
            record['kind'] == 'tu_process_record' && record['sfi'] == 0x1E,
      )
      .toList();
  expect(cycles, hasLength(30));
  expect(
    cycles.map((record) => _compact(record['rawHex'] as String?)),
    _cycles,
  );
  expect(cycles.map((record) => record['recordNumber']), [
    for (var i = 1; i <= 30; i++) i,
  ]);
  expect(snapshot.rails, hasLength(1));
  expect(snapshot.rails.single.rawHex, _variableRecords.first);
  expect(snapshot.rails.single.entryCityCode, '3300');
  expect(snapshot.rails.single.exitCityCode, '3370');
}

// Explicit synthetic envelopes for presentation-boundary negatives. The
// decoded real source bodies are reused; duplication, omission and splitting
// into capture batches are test inputs, not claims about additional log data.
CardSessionSnapshot _syntheticCapture(
  ScanPresentation view, {
  List<TransitTrip> trips = const [],
  required List<TransitRecord> rails,
  required List<TUnionTripRecord> cycles,
}) => CardSessionSnapshot(
  parseVersion: kTripParseVersion,
  cardCityCode: view.cardCityCode,
  context: const ArchiveContext(
    systemId: 'tunion',
    applicationId: 'A000000632010105',
    currencyCode: 'CNY',
    minorUnitDigits: 2,
    clockBasis: 'device-local-card-time-unverified',
  ),
  trips: trips,
  rails: rails,
  processTrips: cycles,
  rawEvidence: [
    for (final rail in rails)
      {
        'kind': 'tu_process_record',
        'sfi': 0x1A,
        'recordNumber': 1,
        'recordNumberIsReliable': true,
        'rawHex': rail.rawHex,
      },
    for (final cycle in cycles)
      {
        'kind': 'tu_process_record',
        'sfi': 0x1E,
        'recordNumber': view.cycleProcessTrips.indexOf(cycle) + 1,
        'recordNumberIsReliable': true,
        'rawHex': cycle.rawHex,
      },
  ],
  recordProvenance: {
    // As ArchiveController.stage does for a fresh capture, freeze names using
    // the production capture function. Archived projection then consumes this
    // saved display, without looking up old captures against a runtime DB.
    for (final (index, rail) in rails.indexed)
      'rails[$index]': {
        'sfi': 0x1A,
        'recordNumber': 1,
        'rawHex': rail.rawHex,
        'capturedDisplay': captureRailApplicationDisplay(view.knowledge, rail),
      },
    for (final (index, cycle) in cycles.indexed)
      'cycle[$index]': {
        'sfi': 0x1E,
        'recordNumber': view.cycleProcessTrips.indexOf(cycle) + 1,
        'recordNumberIsReliable': true,
        'rawHex': cycle.rawHex,
        'capturedDisplay': captureProcessDisplay(view.knowledge, cycle),
      },
  },
);

ArchiveHistoryResult _syntheticHistory(List<CardSessionSnapshot> captures) {
  const card = SavedCard(
    id: 'synthetic-intercity-boundary',
    cardFingerprint: 'synthetic-intercity-boundary',
    cardType: 'china_tunion',
    identificationSource: 'synthetic-test',
    createdAt: 1,
    updatedAt: 1,
  );
  return ArchiveHistory.project(
    ArchiveRows(
      card: card,
      batches: [
        for (final (index, capture) in captures.indexed)
          CardReadBatch(
            id: 'synthetic-$index',
            cardId: card.id,
            cardFingerprint: card.cardFingerprint,
            readAt: index + 1,
            parseVersion: capture.parseVersion,
            payloadJson: capture.encode(),
          ),
      ],
    ),
  );
}

List<JourneyPresentation<TripEntryInfo>> _liveJourneys(
  ScanPresentation view,
  ReferenceDataController reference, {
  bool includeTransactions = true,
  List<TransitTrip>? transactionOverride,
}) {
  // Match TripsPage: the real 1A rail/bus records participate in both the
  // stream and evidence builder, rather than an artificial TU1E-only stream.
  final rails = [?view.railTransitRecord];
  final buses = [?view.busTransitRecord];
  final stream = buildTripStream(
    trips:
        transactionOverride ??
        (includeTransactions ? view.analysis!.trips : const []),
    rails: rails,
    buses: buses,
    processTrips: view.cycleProcessTrips,
  );
  final evidence = buildLiveJourneyEvidence(
    stream: stream,
    processRecords: view.transitProcessRecords,
    rails: rails,
    buses: buses,
  );
  final display = TripPresentationContext(
    currency: view.cardCurrency,
    cityNameOf: reference.cityNameOf,
    resolveStationMatch: reference.resolveStationMatch,
    resolveCycleStationMatch: reference.resolveCycleStationMatch,
    resolveLineName: reference.resolveLineName,
    resolveBusLocation: reference.resolveBusLocation,
  );
  return projectJourneys([
    for (final entry in stream)
      describeJourneyEvent(
        entry,
        display,
        describeTripEntry(entry, display, remote: false),
        applicationRecordId: evidence[entry]?.applicationRecordId,
        processPositions: evidence[entry]?.processPositions ?? const {},
      ),
  ]);
}

Future<ScanPresentation> _read(ReferenceDataController reference) async {
  // Synthetic public identity and holder data are the only identity envelope
  // used. The BCD card serial is fake but satisfies CommonUnitTu's TU IIN gate.
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, _hex('03493370FFFFFFFF'))
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, _hex('03100000000000000001'))
    ..setRange(20, 28, _hex('2026010120991231'));
  final responses = <String, List<int>>{
    // Minimal SELECT success envelopes are synthetic, not source FCI bytes.
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0960000': [...List<int>.filled(56, 0), 0x90, 0],
    '00B0970000': _hex(_managementResponse),
    '805C000204': _hex('000005DC9000'),
    '00B201C500': [..._hex(_transactions.join()), 0x90, 0],
    for (final (index, raw) in _variableRecords.indexed)
      '00B2${_byte(index + 1)}D400': [..._hex(raw), 0x90, 0],
    // Observed as logged: an invalid TU1E bulk body containing two 1A records
    // and SW6100. Transit policy does not follow 6100. The subsequent real
    // F4 requests must supply all 30 records; never substitute 6A86 here.
    '00B201F500': [
      ..._hex('${_variableRecords[0]}${_variableRecords[1]}'),
      0x61,
      0,
    ],
    for (final (index, raw) in _cycles.indexed)
      '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
    '00B21FF400': [0x6A, 0x83],
  };
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async {
        final key = command.map(_byte).join();
        final response = responses[key];
        if (response == null) {
          throw StateError('Unobserved APDU has no synthetic fallback: $key');
        }
        return response;
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  final card = await unit.read(info, records);
  expect(card, isNotNull);
  return ScanPresentation(TransitReadOutcome(card!), reference.knowledge!);
}

Future<
  ({
    String encoded,
    ArchiveHistoryResult history,
    ArchiveHistoryResult restoredHistory,
  })
>
_saveAndRestore(ScanPresentation view) async {
  // The only writable database is an isolated, ephemeral in-memory test DB.
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final repository = CardRepository(database);
  final controller = ArchiveController(
    repository,
    const MethodChannelLogExporter(),
    (_) {},
  );
  const attempt = 'synthetic-shaoxing-intercity-capture';
  try {
    controller.stage(view, attempt, DateTime(2026, 11, 4, 16, 6, 34), const []);
    expect(controller.pending, isNotNull);
    final stagedJson = controller.pending!.sessionDataJson!;
    _expectSnapshotEvidence(CardSessionSnapshot.decode(stagedJson)!);
    expect(await controller.accept(attempt), isTrue);
    final card = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(card.id);
    final encoded = history.batches.single.decoded.rawJson;
    _expectStagedContentPreserved(stagedJson, encoded);
    final rows = await repository.getArchiveRows(card.id);
    final restored = CardArchiveDocument.decode(
      CardArchiveDocument(
        card: rows.card!,
        batches: rows.batches,
        fieldObservationTimes: const {},
      ).encode(),
    );
    expect(
      restored.batches.single.payloadJson == encoded,
      isTrue,
      reason: 'Complete JSON export/restore must retain persisted capture text',
    );
    final restoredHistory = ArchiveHistory.project(
      ArchiveRows(card: restored.card, batches: restored.batches),
    );
    return (
      encoded: encoded,
      history: history,
      restoredHistory: restoredHistory,
    );
  } finally {
    controller.dispose();
    await database.close();
  }
}

void _expectStagedContentPreserved(String stagedJson, String persistedJson) {
  final staged = jsonDecode(stagedJson) as Map<String, dynamic>;
  final persisted = jsonDecode(persistedJson) as Map<String, dynamic>;
  // CardRepository._capturePayload adds the scalar observation envelope and
  // its currency-observed flag during first persistence. This metadata is
  // expected; the captured records, raw evidence, context and provenance must
  // otherwise remain exactly the staged structure. Compare by field so a
  // failure reports one path rather than dumping the full transit history.
  final beforeFlags = (staged['context'] as Map)['observedFields'] as Map;
  final afterFlags = (persisted['context'] as Map)['observedFields'] as Map;
  if (!beforeFlags.containsKey('currencyCode')) {
    expect(
      afterFlags.remove('currencyCode'),
      isTrue,
      reason: 'Repository records the CNY currency observation',
    );
  }
  if (!staged.containsKey('observations')) {
    final observations = persisted.remove('observations') as Map;
    expect(observations['balanceFen'], 1500);
    expect(observations['currencyCode'], 'CNY');
    expect(observations['transactionCount'], 10);
  }
  _expectCapturedValue(persisted, staged, r'$');
}

void _expectCapturedValue(Object? actual, Object? expected, String path) {
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: path);
    final fields = actual as Map;
    expect(fields.keys.toSet(), expected.keys.toSet(), reason: path);
    for (final field in expected.entries) {
      _expectCapturedValue(
        fields[field.key],
        field.value,
        '$path.${field.key}',
      );
    }
  } else if (expected is List) {
    expect(actual, isA<List>(), reason: path);
    final values = actual as List;
    expect(values.length, expected.length, reason: path);
    for (var index = 0; index < expected.length; index++) {
      _expectCapturedValue(values[index], expected[index], '$path[$index]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

String? _compact(String? value) => value?.replaceAll(RegExp(r'\s+'), '');
String? _civil(DateTime? value) => value == null
    ? null
    : '${value.year}/${value.month}/${value.day} ${value.hour}:${value.minute}:${value.second}';
String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
