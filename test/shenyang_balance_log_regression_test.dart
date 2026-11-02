import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_controller.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_export_options.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_archive_document.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_record_presenter.dart';
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
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';
import 'package:transit_card_analyzer/platform/storage/log_exporter.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

// Exact successful record bodies from transit_card_log_20261030_192727.txt.
// SW bytes alone are omitted. Public identity, FCI, and holder information are
// excluded; the reader receives an explicitly SYNTHETIC serial below instead.
// The observed wallet is 1840 fen. The source log loses the tag at 1A record 10,
// before any 1E exchange. Do not invent process balances for this capture.
const _transactions = <String>[
  '0080000000000003E80212016080000120261025140329',
  '0247000000000001C20941310603401420261025140142',
  '0246000000000000000941310176116020261025132412',
  '0245000000000001C20941310603429120261025122525',
  '0244000000000000000941310603401020261025115651',
  '007F000000000003E80212016080000120261017200210',
  '02430000000000021C0941310603400020261017195355',
  '0242000000000000000941310176074120261017190722',
  '0241000000000000B40941310121748720261017141825',
  '007E000000000003E80212016080000120261017132819',
];
const _applications = <String>[
  '27017D010100000000000000000002221022101217221000000000121722100000000012172210000009331217221000000121221041310176116022104131060340142026102513241220261025140142000002BC00000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27027D01010000000000000000070200000000000000000000000000000000000000000000000000000000000000000000000000000000000001241011092410FFFFFFFF10040006040000303630353030000041310603221220260927165311000000C800000000000000000000000000000000000000000000000000000000',
  '27037D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27047D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27057D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27067D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27076D01010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27087D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
  '27097D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000',
];
// Exact successful bodies from the second, complete 19:51 reading in
// transit_card_log_20261030_195428.txt. It repeats the same transaction window
// and first nine 1A records above; only SW bytes are omitted. Card identity stays
// SYNTHETIC. The five observed Shenyang rail EP03/04 records encode money LE;
// the same capture's other rail and bus records continue to encode money BE.
const _completeApplications = <String>[
  ..._applications,
  '270A7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #10
  '270B7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #11
  '270C7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #12
  '270D1B010100000000000000000000000000000000000000000000000000', // 1A #13
  '270E7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #14
  '270F7D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #15
  '27107D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #16
  '27117D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #17
  '27127D0101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000', // 1A #18
];
const _completeCycles = <String>[
  '1622104131060340140100010079000300000001C2000003482026102514014222101217221000000000000002BC0000', // 1E #1
  '03221041310176116001000903A5000300000000000A0500002026102513241222101217221000000000000002BC0000', // 1E #2
  '160000413106034291010001008F000300000001C20000050A2026102512252522101217221000000000000002BC0000', // 1E #3
  '150000413106034010010001007900030000000000000006CC2026102511565122101217221000000000000002BC0000', // 1E #4
  '16000041310603400001000100790003000000021C000002E42026101719535522101217221000000000000002BC0000', // 1E #5
  '150000413101760741010001009F00030000000000000005002026101719072222101217221000000000000002BC0000', // 1E #6
  '0600004131012174870200030250000000000000B40000050020261017141825221012172210FFFFFFFF000000000000', // 1E #7
  '04221041310176201101000A041F0003001C020000E80300002026101713264722101217221000000000000002BC0000', // 1E #8
  '032210413106297251010003014D00030000000000E80300002026101711465122101217221000000000000002BC0000', // 1E #9
  '16000041310603429201000100790003000000021C000003E82026100714313722101217221000000000000002BC0000', // 1E #10
  '15000041310183646001000401B500030000000000000006042026100713390422101217221000000000000002BC0000', // 1E #11
  '0600004131018838640200020001000200000000640000060420261006161621272011192720FFFFFFFF000000000000', // 1E #12
  '0600004131010831360200410001000000000000550000066820261003180314249115092491FFFFFFFF000000000000', // 1E #13
  '060000413101083014020041000100000000000055000006BD20261003155243249115092491FFFFFFFF000000000000', // 1E #14
  '0600004131018837360200020001000200000000640000071220261002164242272011192720FFFFFFFF000000000000', // 1E #15
  '0600004131018839680200020001000200000000640000038E20261002151427272011192720FFFFFFFF000000000000', // 1E #16
  '060000413101883794020002000100020000000064000003F220261001132458272011192720FFFFFFFF000000000000', // 1E #17
  '0600004131018840360200020001000200000000640000045620261001114124272011192720FFFFFFFF000000000000', // 1E #18
  '062210413106335776023A0E01B5000000000000C8000005E620260927104523242011182420FFFFFFFF000000000000', // 1E #19
  '062210413101800028025D2A01B5000000000000C80000045620260925081906242011182420FFFFFFFF000000000000', // 1E #20
  '16221041310183644701000401B50003000000021C0000051E2026092421263022101217221000000000000002BC0000', // 1E #21
  '1522104131060339990100010079000300000000000000073A2026092420354922101217221000000000000002BC0000', // 1E #22
  '16221041310603399401000100790003000000021C000003522026091918141422101217221000000000000002BC0000', // 1E #23
  '03221041310183532001000A0415000300000000006E0500002026091917240322101217221000000000000002BC0000', // 1E #24
  '04221041310183531601000A0415000300B4000000220600002026091916181522101217221000000000000002BC0000', // 1E #25
  '152210413101760742010001009F00030000000000000006222026091916103622101217221000000000000002BC0000', // 1E #26
  '162210413101760732010001009F0003000000021C0000023A2026091915182422101217221000000000000002BC0000', // 1E #27
  '152210413106034008010001007900030000000000000004562026091914292822101217221000000000000002BC0000', // 1E #28
  '16221041310603401401000100790003000000021C000004562026091218463922101217221000000000000002BC0000', // 1E #29
  '152210413101760741010001009F00030000000000000006722026091218011922101217221000000000000002BC0000', // 1E #30
];
const _completeCycleAmounts = <int>[
  450, // 1E #1
  0, // 1E #2
  450, // 1E #3
  0, // 1E #4
  540, // 1E #5
  0, // 1E #6
  180, // 1E #7
  540, // 1E #8
  0, // 1E #9
  540, // 1E #10
  0, // 1E #11
  100, // 1E #12
  85, // 1E #13
  85, // 1E #14
  100, // 1E #15
  100, // 1E #16
  100, // 1E #17
  100, // 1E #18
  200, // 1E #19
  200, // 1E #20
  540, // 1E #21
  0, // 1E #22
  540, // 1E #23
  0, // 1E #24
  180, // 1E #25
  0, // 1E #26
  540, // 1E #27
  0, // 1E #28
  540, // 1E #29
  0, // 1E #30
];
const _completeCycleBalances = <int>[
  840, // 1E #1
  1290, // 1E #2
  1290, // 1E #3
  1740, // 1E #4
  740, // 1E #5
  1280, // 1E #6
  1280, // 1E #7
  1000, // 1E #8
  1000, // 1E #9
  1000, // 1E #10
  1540, // 1E #11
  1540, // 1E #12
  1640, // 1E #13
  1725, // 1E #14
  1810, // 1E #15
  910, // 1E #16
  1010, // 1E #17
  1110, // 1E #18
  1510, // 1E #19
  1110, // 1E #20
  1310, // 1E #21
  1850, // 1E #22
  850, // 1E #23
  1390, // 1E #24
  1570, // 1E #25
  1570, // 1E #26
  570, // 1E #27
  1110, // 1E #28
  1110, // 1E #29
  1650, // 1E #30
];

const _sequences = [128, 583, 582, 581, 580, 127, 579, 578, 577, 126];
const _balances = [1840, 840, 1290, 1290, 1740, 1740, 740, 1280, 1280, 1460];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late ReferenceDataController reference;
  late ScanPresentation view;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'trafarch-shenyang-balance-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    reference = ReferenceDataController(rootBundle);
    await reference.initialize();
    expect(reference.error, isNull);
    expect(reference.knowledge!.loadIssues, isEmpty);
    view = await _readObservedPrefix(reference);
  });

  tearDownAll(() {
    reference.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('沈阳日志掉卡前10条交易沿充值与消费混合账本重建全部余额', () {
    final card = view.parsedCard!;
    expect(card.info.balanceFen, 1840);
    expect(
      card.transactions.map((transaction) => transaction.sequence),
      _sequences,
    );
    expect(card.transactions.map((transaction) => transaction.recordNumber), [
      for (var i = 1; i <= 10; i++) i,
    ]);
    expect(
      card.transactions.map((transaction) => _clean(transaction.rawHex)),
      _transactions,
    );
    expect(
      card.transitProcessRecords.map((record) => _clean(record.rawHex)),
      _applications,
    );
    expect(card.transitProcessRecords.map((record) => record.recordNumber), [
      for (var i = 1; i <= 9; i++) i,
    ]);
    expect(
      card.transitProcessRecords.every((record) => record.sfi == 0x1A),
      isTrue,
    );
    expect(view.cycleProcessTrips, isEmpty);
    final trips = view.analysis!.trips;
    expect(trips.map((trip) => trip.sequence), _sequences);
    expect(trips.map((trip) => trip.balanceAfterFen), _balances);
    expect(trips.every((trip) => trip.balanceAfterIsRecorded == false), isTrue);
    expect(trips.singleWhere((trip) => trip.sequence == 579).amountFen, 540);
    expect(
      trips.singleWhere((trip) => trip.sequence == 579).balanceAfterFen,
      740,
    );
    // This 1A's recorded zero is retained but cannot replace the wallet ledger.
    expect(card.transitProcessRecords.first.railTransit!.entryBalanceFen, 0);
    expect(card.transitProcessRecords.first.railTransit!.exitAmountFen, 0);
  });

  test('沈阳日志经stage保存完整备份JSON历史详情及workflow JSON仍为7.40元', () async {
    final saved = await _saveAndRestore(view);
    final restored = CardSessionSnapshot.decode(saved.encoded)!;
    expect(restored.encode(), saved.encoded);
    expect(restored.trips.map((trip) => trip.sequence), _sequences);
    expect(restored.trips.map((trip) => trip.balanceAfterFen), _balances);
    expect(restored.trips.map((trip) => _clean(trip.rawHex)), _transactions);
    expect(restored.processTrips, isEmpty);
    expect(
      restored.rawEvidence
          .where((record) => record['kind'] == 'tu_process_record')
          .map((record) => _clean(record['rawHex'] as String?)),
      _applications,
    );
    expect(
      restored.rawEvidence
          .where((record) => record['kind'] == 'tu_transaction')
          .map((record) => _clean(record['rawHex'] as String?)),
      _transactions,
    );
    for (final history in [saved.history, saved.restoredHistory]) {
      final transactions = history.records
          .where((record) => record.kind == ArchiveRecordKind.transaction)
          .toList();
      final bySequence = {
        for (final record in transactions) record.fields['sequence']: record,
      };
      expect(bySequence.keys.toSet(), _sequences.toSet());
      for (final (index, sequence) in _sequences.indexed) {
        expect(
          archiveRecordBalanceFen(bySequence[sequence]!),
          _balances[index],
        );
        expect(archiveRecordBalanceIsRecorded(bySequence[sequence]!), isFalse);
        expect(
          _clean(bySequence[sequence]!.fields['rawHex'] as String?),
          _transactions[index],
        );
      }
      expect(history.batches.single.decoded.rawJson, saved.encoded);
      final before = jsonEncode([
        for (final record in history.records) record.fields,
      ]);
      final projection = presentArchiveTrips(
        history.records,
        onDiagnostics: (_) {},
      );
      expect(projection.transactionCount, 10);
      final target = projection.entries.singleWhere(
        (entry) => entry.info.title.endsWith('序号 579'),
      );
      expect(
        target.info.fields.map((field) => (field.$1, _clean(field.$2))),
        contains(('交易后余额', '¥7.40')),
      );
      expect(_clean(target.info.subText), '交易后余额¥7.40');
      final rows = projectArchiveRecords([history]);
      final exported = decodeArchiveRecords(
        encodeArchiveRecords(
          rows,
          fields: const {
            ArchiveExportField.source,
            ArchiveExportField.time,
            ArchiveExportField.amount,
            ArchiveExportField.balance,
            ArchiveExportField.terminal,
          },
          exportedAt: DateTime.utc(2026, 10, 30, 12),
        ),
      );
      final tuRows = exported.records
          .where((row) => row['source']!.startsWith('TU 0x18'))
          .toList();
      expect(tuRows, hasLength(10));
      expect(tuRows.map((row) => row['balance']), [
        '18.40',
        '8.40',
        '12.90',
        '12.90',
        '17.40',
        '17.40',
        '7.40',
        '12.80',
        '12.80',
        '14.60',
      ]);
      final targetRows = tuRows.where(
        (row) => row['terminal'] == '413106034000' && row['amount'] == '-5.40',
      );
      expect(targetRows, hasLength(1));
      expect(targetRows.single['balance'], '7.40');
      // The projection/export must not rewrite any captured record.
      expect(
        jsonEncode([for (final record in history.records) record.fields]),
        before,
      );
      expect(
        CardSessionSnapshot.decode(saved.encoded)!.encode(),
        saved.encoded,
      );
    }
  });

  test('沈阳完整读取30条1E同时保留EP小端与其他记录大端且不污染交易账本', () async {
    final complete = await _readObservedPrefix(reference, complete: true);
    final card = complete.parsedCard!;
    expect(card.info.balanceFen, 1840);
    expect(
      card.transactions.map((transaction) => _clean(transaction.rawHex)),
      _transactions,
    );
    expect(complete.analysis!.trips.map((trip) => trip.sequence), _sequences);
    expect(
      complete.analysis!.trips.map((trip) => trip.balanceAfterFen),
      _balances,
    );
    expect(
      complete.analysis!.trips.every(
        (trip) => trip.balanceAfterIsRecorded == false,
      ),
      isTrue,
    );
    final applications = card.transitProcessRecords
        .where((record) => record.sfi == 0x1A)
        .toList();
    expect(applications, hasLength(18));
    expect(
      applications.map((record) => _clean(record.rawHex)),
      _completeApplications,
    );
    final cycles = card.transitProcessRecords
        .where((record) => record.sfi == 0x1E)
        .toList();
    expect(cycles.map((record) => record.recordNumber), [
      for (var i = 1; i <= 30; i++) i,
    ]);
    _expectCompleteCycles(complete.cycleProcessTrips);
    final journeys = projectJourneys(_completeLiveEvents(complete, reference));
    _expectReportedEpJourney(_reportedEpJourney(journeys));
    _expectConfirmedWalletBalances(journeys);
  });

  test('沈阳完整读取经保存历史详情备份投影及workflow JSON仍保留正确EP金额余额', () async {
    final complete = await _readObservedPrefix(reference, complete: true);
    final saved = await _saveAndRestore(complete);
    final snapshot = CardSessionSnapshot.decode(saved.encoded)!;
    expect(snapshot.encode(), saved.encoded);
    expect(snapshot.trips.map((trip) => trip.balanceAfterFen), _balances);
    expect(snapshot.trips.map((trip) => _clean(trip.rawHex)), _transactions);
    _expectCompleteCycles(snapshot.processTrips);
    expect(
      snapshot.rawEvidence
          .where((record) => record['kind'] == 'tu_process_record')
          .map((record) => _clean(record['rawHex'] as String?)),
      [..._completeApplications, ..._completeCycles],
    );
    for (final history in [saved.history, saved.restoredHistory]) {
      final before = jsonEncode([
        for (final record in history.records) record.fields,
      ]);
      final projection = presentArchiveTrips(
        history.records,
        onDiagnostics: (_) {},
      );
      expect(projection.transactionCount, 10);
      final journeys = projectJourneys([
        for (final entry in projection.entries) entry.journeyEvent!,
      ]);
      _expectReportedEpJourney(_reportedEpJourney(journeys));
      _expectConfirmedWalletBalances(journeys);
      final exit = projection.entries.singleWhere(
        (entry) => _clean(entry.info.rawHex) == _completeCycles[7],
      );
      expect(exit.info.title, contains('长青桥'));
      expect(_clean(exit.info.amountText), '-¥5.40');
      expect(
        exit.info.fields.map((field) => (field.$1, _clean(field.$2))),
        contains(('记录余额', '¥10.00')),
      );
      final transaction = projection.entries.singleWhere(
        (entry) => entry.info.title.endsWith('序号 579'),
      );
      expect(_clean(transaction.info.subText), '交易后余额¥7.40');
      final exported = decodeArchiveRecords(
        encodeArchiveRecords(
          projectArchiveRecords([history]),
          fields: const {
            ArchiveExportField.source,
            ArchiveExportField.time,
            ArchiveExportField.amount,
            ArchiveExportField.balance,
            ArchiveExportField.terminal,
          },
          exportedAt: DateTime.utc(2026, 10, 30, 12),
        ),
      );
      final cycleRows = exported.records
          .where((row) => row['source'] == 'TU 0x1E')
          .toList();
      // The first seven cycles are already represented by their linked 0x18
      // transaction rows. Workflow rows fold those duplicate sources, while
      // the full snapshot above retains all thirty original cycle records.
      expect(cycleRows, hasLength(23));
      final exitRow = cycleRows.singleWhere(
        (row) => row['terminal'] == '2210413101762011',
      );
      expect(exitRow['amount'], '-5.40');
      expect(exitRow['balance'], '10.00');
      final entryRow = cycleRows.singleWhere(
        (row) => row['terminal'] == '2210413106297251',
      );
      expect(entryRow['amount'], isNull);
      expect(entryRow['balance'], '10.00');
      expect(
        jsonEncode([for (final record in history.records) record.fields]),
        before,
      );
      expect(history.batches.single.decoded.rawJson, saved.encoded);
      expect(
        CardSessionSnapshot.decode(saved.encoded)!.encode(),
        saved.encoded,
      );
    }
  });

  test('SIMULATED v11旧过程捕获仍保留当时金额和原始HEX不重新解析', () {
    // This is an explicitly synthetic archived capture, not the customer's
    // missing historical JSON. A parser upgrade must not rewrite it.
    final payload = jsonEncode({
      'v': 3,
      'parseVersion': 11,
      'context': const ArchiveContext(
        currencyCode: 'CNY',
        minorUnitDigits: 2,
      ).toJson(),
      'trips': [],
      'rails': [],
      'buses': [],
      'cycle': [
        {
          'typeCode': 4,
          'terminalId': '2210413101762011',
          'appTypeCode': 1,
          'lineStationCode': '000A041F000300',
          'amountFen': 469893120,
          'balanceFen': 3892510720,
          'time': DateTime(2026, 10, 17, 13, 26, 47).millisecondsSinceEpoch,
          'cityCode': '2210',
          'acquirerId': '1217221000000000',
          'rawHex': _completeCycles[7],
        },
      ],
      'rawEvidence': [],
      'recordProvenance': {},
      'syntheticEvidence': 'legacy cycle money preservation',
    });
    final snapshot = CardSessionSnapshot.decode(payload)!;
    expect(snapshot.encode(), payload);
    expect(snapshot.processTrips.single.amountFen, 469893120);
    expect(snapshot.processTrips.single.balanceFen, 3892510720);
    expect(snapshot.processTrips.single.rawHex, _completeCycles[7]);
  });

  test('SIMULATED旧异常余额捕获原文在恢复与完整备份中保留而不静默改写', () {
    // Synthetic corruption reproduction only. The user supplied an image and
    // APDU log, not the historical batch JSON that produced the large balance.
    // This test must not claim to reproduce the origin of that old capture.
    final payload =
        '  ${jsonEncode({
          'v': 3,
          'parseVersion': 8,
          'context': const ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2).toJson(),
          'trips': [
            {'time': DateTime(2026, 10, 17, 19, 53, 55).millisecondsSinceEpoch, 'amountFen': 540, 'consume': true, 'typeName': '复合消费', 'sequence': 579, 'terminalId': '413106034000', 'balanceAfterFen': 168099290, 'balanceAfterIsRecorded': false, 'currency': 'CNY', 'rawHex': _transactions[6]},
          ],
          'rails': [],
          'buses': [],
          'cycle': [],
          'rawEvidence': [],
          'recordProvenance': {},
          'syntheticEvidence': 'unknown legacy balance origin',
        })}\n';
    final snapshot = CardSessionSnapshot.decode(payload)!;
    expect(snapshot.encode(), payload);
    expect(snapshot.trips.single.balanceAfterFen, 168099290);
    const card = SavedCard(
      id: 'synthetic-old-balance-card',
      cardFingerprint: 'synthetic-old-balance-fingerprint',
      cardType: 'china_tunion',
      identificationSource: 'synthetic-test',
      createdAt: 1,
      updatedAt: 1,
    );
    final batch = CardReadBatch(
      id: 'synthetic-old-balance-batch',
      cardId: card.id,
      cardFingerprint: card.cardFingerprint,
      readAt: 1,
      parseVersion: 8,
      payloadJson: payload,
    );
    final restored = CardArchiveDocument.decode(
      CardArchiveDocument(
        card: card,
        batches: [batch],
        fieldObservationTimes: const {},
      ).encode(),
    );
    expect(restored.batches.single.payloadJson, payload);
    final history = ArchiveHistory.project(
      ArchiveRows(card: restored.card, batches: restored.batches),
    );
    expect(history.batches.single.decoded.rawJson, payload);
    expect(history.records.single.fields['balanceAfterFen'], 168099290);
    presentArchiveTrips(history.records, onDiagnostics: (_) {});
    projectArchiveRecords([history]);
    expect(history.batches.single.decoded.rawJson, payload);
    expect(history.records.single.fields['rawHex'], _transactions[6]);
  });
}

void _expectConfirmedWalletBalances<T>(List<JourneyPresentation<T>> journeys) {
  final events = journeys.expand((journey) => journey.events).toList();
  // Every 0x18 event must keep its independent confirmed balance, including
  // an entry side folded into a later completed journey.
  for (final (index, sequence) in _sequences.indexed) {
    final event = events.singleWhere((event) => event.sequence == sequence);
    expect(
      event.confirmedBalanceFen,
      _balances[index],
      reason: '0x18 sequence $sequence',
    );
  }
  final latest = journeys.singleWhere(
    (journey) => journey.events.any((event) => event.sequence == 583),
  );
  expect(_clean(latest.balanceAfterText), '¥8.40');
  final bus = journeys.singleWhere(
    (journey) => journey.events.any((event) => event.sequence == 577),
  );
  expect(_clean(bus.balanceAfterText), '¥12.80');
}

void _expectCompleteCycles(Iterable<TUnionTripRecord> cycles) {
  final records = cycles.toList();
  expect(records, hasLength(30));
  expect(records.map((record) => _clean(record.rawHex)), _completeCycles);
  expect(records.map((record) => record.amountFen), _completeCycleAmounts);
  expect(records.map((record) => record.balanceFen), _completeCycleBalances);
  // These are the record's own balances. Equal entry/exit balances do not
  // establish whether the operator wrote them before or after the deduction.
  expect(records[7].amountFen, 540);
  expect(records[7].balanceFen, 1000);
  expect(records[8].balanceFen, 1000);
}

JourneyPresentation<T> _reportedEpJourney<T>(
  List<JourneyPresentation<T>> journeys,
) => journeys.singleWhere((journey) {
  final time = journey.start?.time;
  return time != null &&
      time.year == 2026 &&
      time.month == 10 &&
      time.day == 17 &&
      time.hour == 11 &&
      time.minute == 46 &&
      time.second == 51;
});

void _expectReportedEpJourney<T>(JourneyPresentation<T> journey) {
  expect(journey.state, JourneyState.completed);
  expect(journey.mode, TripModeFilter.rail);
  expect(journey.start?.station, '工业大学');
  expect(journey.start?.line, '3号线');
  expect(journey.end?.station, '长青桥');
  expect(journey.end?.line, '10号线');
  expect(journey.end?.time?.hour, 13);
  expect(journey.end?.time?.minute, 26);
  expect(journey.end?.time?.second, 47);
  expect(journey.duration, const Duration(hours: 1, minutes: 39, seconds: 56));
  expect(_clean(journey.amountText), '-¥5.40');
  expect(journey.events.map((event) => event.role).toSet(), {
    JourneyEventRole.entry,
    JourneyEventRole.exit,
  });
  expect(journey.events.every((event) => event.sequence == null), isTrue);
  expect(journey.events.map((event) => event.processBalance?.recordedFen), [
    1000,
    1000,
  ]);
  // The next physical 1E operation is a bus debit with a confirmed 0x18
  // balance. The intervening 0x18 recharge independently closes this journey:
  // 1000 - 540 + 1000 - 180 = 1280. The original two balances stay 1000.
  expect(_clean(journey.balanceAfterText), '¥4.60');
}

List<JourneyEvent<TripEntryInfo>> _completeLiveEvents(
  ScanPresentation view,
  ReferenceDataController reference,
) {
  final rails = [
    for (final record in view.transitProcessRecords) ?record.railTransit,
  ];
  final buses = [
    for (final record in view.transitProcessRecords) ?record.busTransit,
  ];
  final stream = buildTripStream(
    trips: view.analysis!.trips,
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
  return [
    for (final entry in stream)
      describeJourneyEvent(
        entry,
        display,
        describeTripEntry(entry, display, remote: false),
        applicationRecordId: evidence[entry]?.applicationRecordId,
        processPositions: evidence[entry]?.processPositions ?? const {},
      ),
  ];
}

Future<ScanPresentation> _readObservedPrefix(
  ReferenceDataController reference, {
  bool complete = false,
}) async {
  // SYNTHETIC identity only. No real serial, FCI, or holder data is copied.
  final public = List<int>.filled(30, 0)
    ..setRange(0, 8, [1, 1, 0x10, 0, 0xFF, 0xFF, 0xFF, 0xFF])
    ..setRange(8, 10, [2, 1])
    ..setRange(10, 20, [
      0x31,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      0x99,
      1,
    ])
    ..setRange(20, 28, [0x20, 0x26, 1, 1, 0x20, 0x99, 0x12, 0x31]);
  final management = List<int>.filled(60, 0)..setRange(6, 8, [0x10, 0]);
  final responses = <String, List<int>>{
    '00A40000023F0000': [0x90, 0],
    '00A4040008A00000063201010500': [0x90, 0],
    '00B0950000': [...public, 0x90, 0],
    '00B0960000': [...List<int>.filled(56, 0), 0x90, 0],
    '00B0970000': [...management, 0x90, 0],
    '805C000204': [0, 0, 7, 0x30, 0x90, 0],
    '00B201C500': [0x6A, 0x86],
    for (final (index, raw) in _transactions.indexed)
      '00B2${_byte(index + 1)}C400': [..._hex(raw), 0x90, 0],
    for (final (index, raw)
        in (complete ? _completeApplications : _applications).indexed)
      '00B2${_byte(index + 1)}D400': [..._hex(raw), 0x90, 0],
    if (complete) ...{
      '00B201F500': [0x6A, 0x86],
      for (final (index, raw) in _completeCycles.indexed)
        '00B2${_byte(index + 1)}F400': [..._hex(raw), 0x90, 0],
      '00B21FF400': [0x6A, 0x83],
    },
  };
  final commands = <String>[];
  final unit = CommonUnitTu(
    ApduExchange(
      transceive: (command) async {
        final hex = command.map(_byte).join();
        commands.add(hex);
        if (!complete && hex == '00B20AD400') {
          throw PlatformException(
            code: 'TRANSCEIVE_FAILED',
            message: 'Tag was lost.',
            details: {
              'sessionId': 'synthetic-shenyang-capture',
              'exception': 'android.nfc.TagLostException',
            },
          );
        }
        // Unobserved files are fixture boundaries, not source-log SW evidence.
        return responses[hex] ?? const [0x6A, 0x83];
      },
    ),
  );
  final info = CardInfo();
  final records = <ApduRecord>[];
  expect(await unit.select(info, records), isTrue);
  if (complete) {
    await unit.read(info, records);
    expect(commands, contains('00B21FF400'));
  } else {
    await expectLater(
      unit.read(info, records),
      throwsA(isA<ApduTransportException>()),
    );
    expect(commands.last, '00B20AD400');
    expect(
      commands.where(
        (command) =>
            command.startsWith('00B2') && command.substring(6, 8) == 'F4',
      ),
      isEmpty,
    );
  }
  final card = unit.parsedCard!;
  expect(card.transactions, hasLength(10));
  expect(card.transitProcessRecords, hasLength(complete ? 48 : 9));
  return ScanPresentation(TransitReadOutcome(card), reference.knowledge!);
}

Future<
  ({
    String encoded,
    ArchiveHistoryResult history,
    ArchiveHistoryResult restoredHistory,
  })
>
_saveAndRestore(ScanPresentation view) async {
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
  const attempt = 'synthetic-shenyang-capture';
  try {
    controller.stage(
      view,
      attempt,
      DateTime(2026, 10, 30, 19, 27, 27),
      const [],
    );
    expect(controller.pending, isNotNull);
    final staged = controller.pending!.sessionDataJson!;
    expect(
      CardSessionSnapshot.decode(staged)!.trips
          .map((trip) => trip.balanceAfterFen),
      _balances,
    );
    expect(await controller.accept(attempt), isTrue);
    final card = (await repository.getAllCards()).single;
    final history = await ArchiveHistory(repository).load(card.id);
    // Accept enriches observed currency/identity metadata. Capture its stored
    // text as the preservation boundary while checking staged balances above.
    final encoded = history.batches.single.decoded.rawJson;
    final rows = await repository.getArchiveRows(card.id);
    final restored = CardArchiveDocument.decode(
      CardArchiveDocument(
        card: rows.card!,
        batches: rows.batches,
        fieldObservationTimes: const {},
      ).encode(),
    );
    expect(restored.batches.single.payloadJson, encoded);
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

String? _clean(String? value) => value?.replaceAll(RegExp(r'\s+'), '');
String _byte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
