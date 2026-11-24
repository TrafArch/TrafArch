import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/application/cu_archive_projection.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/cu_trip_presenter.dart';
import 'package:transit_card_analyzer/features/trips/journey_presentation.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

const _cuWithLe = '00A4040009A0000000038698070100';
const _cuWithoutLe = '00A4040009A00000000386980701';
const _mfWithoutLe = '00A40000023F00';
const _cuPublic = '00B095001E';
const _cuFirstRecord = '00B201C417';
const _tuBus = '0001000000000000640941318000000120261114132051';
const _metroDebit = '0004000000000000B40912345678000120261114165240';
const _anotherDebit = '0005000000000000B40612345678000220261114165240';
const _zeroDebit = '0009000000000000000912345678000320261114164713';
const _recharge = '000A000000000003E80200000000000020261114092739';
const _validCuPublic =
    '019845200001000001014520019845200000000120240101203012310101';
const _tuSelect = '00A4040008A00000063201010500';
// The 2026-11-16 capture stops at TU 0x1E slot 24, before any CU probe.
// This TU slot follows the captured layout without a card identifier. The CU
// rows/clocks above are synthetic: they verify scheduling and retention, not
// the real card's unobserved CU response.
const _tuCycle =
    '060000413101538504020000000000000000000064000002BC20261114132051456012104560FFFFFFFF000000000000';

void main() {
  for (final serial in [
    '03104770000000000001',
    '03104970200000000001',
    '03104870400000000001',
  ]) {
    test(
      'TU identity $serial also reads the independent CU wallet before process files',
      () async {
        final chip = _Chip(processTail: true, interruptAt: '00B218F400');
        final result = (await LocalCardReader((apdu) async {
          final response = await chip.call(apdu);
          if (apdu.length == 5 &&
              apdu[1] == 0xB0 &&
              apdu[2] == 0x95 &&
              apdu[4] == 0) {
            response.setRange(10, 20, chip._hex(serial));
          }
          return response;
        }).read())!;
        expect(result.parsedCard.transactions, hasLength(1));
        expect(
          result.readResult.transportFailure?.kind,
          TransportFailureKind.tagLost,
        );
        expect(
          chip.commands,
          containsAllInOrder([
            _cuWithLe,
            _cuWithoutLe,
            _cuFirstRecord,
            _tuSelect,
          ]),
        );
        expect(
          result.parsedCard.cityUnionFiles
              .whereType<CityUnionWalletTransaction>(),
          isNotEmpty,
        );
        expect(chip.commands.last, '00B218F400');
      },
    );
  }

  test('Qingdao CU journey survives a later TU process disconnect', () async {
    final chip = _Chip(
      metroPair: true,
      processTail: true,
      interruptAt: '00B218F400',
    );
    final result = (await LocalCardReader(chip.call).read())!;
    final card = result.parsedCard;
    expect(card.transactions.single.rawHex, _tuBus);
    final views = analyzeCuTransactions(
      card.cityUnionFiles,
      KnowledgeBase.empty(),
    );
    final journey = projectJourneys([
      for (final view in views) describeCuTrip(view).journeyEvent!,
    ]).singleWhere((item) => item.state == JourneyState.completed);
    expect(journey.amountText, '-¥1.80');
    expect(journey.start?.station, isNull);
    expect(journey.end?.station, isNull);
    expect(
      card.transitProcessRecords.where((r) => r.sfi == 0x1E),
      hasLength(1),
    );
    expect(
      result.readResult.transportFailure?.kind,
      TransportFailureKind.tagLost,
    );
    expect(
      chip.commands,
      containsAllInOrder([
        _cuWithoutLe,
        _cuFirstRecord,
        '00B207CC20',
        _tuSelect,
        '00B201D400',
        '00B201F500',
        '00B218F400',
      ]),
    );
    expect(chip.commands.last, '00B218F400');
    expect(
      result.applications.where((a) => a.appId == 'cu').single.recordCount,
      3,
    );
  });

  test('Qingdao resumes sparse TU process records after CU reading', () async {
    final chip = _Chip(metroPair: true, processTail: true);
    final result = (await LocalCardReader(chip.call).read())!;
    final cycles = result.parsedCard.transitProcessRecords.where(
      (r) => r.sfi == 0x1E,
    );
    expect(cycles.map((r) => r.recordNumber), [1, 24]);
    expect(
      result.parsedCard.cityUnionFiles.whereType<CityUnionWalletTransaction>(),
      hasLength(3),
    );
    expect(result.readResult.readError, isNull);
    expect(
      chip.commands,
      containsAllInOrder([
        _cuFirstRecord,
        _tuSelect,
        '00B201D400',
        '00B218F400',
        '00B219F400',
      ]),
    );
  });

  test(
    'Qingdao TU restore rejection preserves CU and skips process reads',
    () async {
      final chip = _Chip(metroPair: true, rejectTuRestore: true);
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      expect(
        result.parsedCard.cityUnionFiles
            .whereType<CityUnionWalletTransaction>(),
        hasLength(3),
      );
      expect(result.readResult.readError, isNotNull);
      expect(chip.commands, isNot(contains('00B201D400')));
      expect(chip.commands, isNot(contains('00B201F500')));
    },
  );

  test(
    'Qingdao restore disconnect retains both wallets and stops APDUs',
    () async {
      final chip = _Chip(metroPair: true, loseOnTuRestore: true);
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      expect(
        result.parsedCard.cityUnionFiles
            .whereType<CityUnionWalletTransaction>(),
        hasLength(3),
      );
      expect(
        result.readResult.transportFailure?.kind,
        TransportFailureKind.tagLost,
      );
      expect(chip.commands.last, _tuSelect);
      expect(chip.commands, isNot(contains('00B201D400')));
      final cu = result.applications.where((a) => a.appId == 'cu').single;
      expect(cu.readError, isNull);
      expect(cu.recordCount, 3);
    },
  );

  test(
    'Qingdao rejected CU data still restores and finishes TU process scan',
    () async {
      final chip = _Chip(validPublic: false, processTail: true);
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      expect(result.parsedCard.cityUnionFiles, isEmpty);
      expect(
        result.parsedCard.transitProcessRecords
            .where((r) => r.sfi == 0x1E)
            .map((r) => r.recordNumber),
        [1, 24],
      );
      expect(result.readResult.readError, isNull);
      expect(
        chip.commands,
        containsAllInOrder([_cuPublic, _tuSelect, '00B201D400', '00B218F400']),
      );
      expect(
        chip.commands.where((command) => command == _cuWithoutLe),
        hasLength(1),
      );
    },
  );

  test(
    'Qingdao CU rejection then TU disconnect sends no later probes',
    () async {
      final chip = _Chip(
        validPublic: false,
        processTail: true,
        interruptAt: '00B218F400',
      );
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      expect(result.parsedCard.cityUnionFiles, isEmpty);
      expect(
        result.readResult.transportFailure?.kind,
        TransportFailureKind.tagLost,
      );
      expect(chip.commands.last, '00B218F400');
      expect(
        chip.commands.where((command) => command == _cuWithoutLe),
        hasLength(1),
      );
    },
  );

  test(
    'Qingdao CU fallback adds only independently supported transactions',
    () async {
      final chip = _Chip();
      final result = (await LocalCardReader(chip.call).read())!;
      final card = result.parsedCard;

      expect(card.transactions.single.rawHex, _tuBus);
      expect(card.dualApplication, isTrue);
      expect(
        chip.commands,
        containsAllInOrder([
          _cuWithLe,
          _cuWithoutLe,
          _cuPublic,
          _cuFirstRecord,
        ]),
      );
      final debits = card.cityUnionFiles
          .whereType<CityUnionWalletTransaction>();
      expect(debits.map((record) => record.sequence), [4, 5, 9, 10]);
      expect(debits.map((record) => record.interpretedAmountFen), [
        -180,
        -180,
        0,
        1000,
      ]);
      expect(debits.map((record) => record.transactionTime), [
        '16:52:40',
        '16:52:40',
        '16:47:13',
        '09:27:39',
      ]);
      expect(debits.last.kind, CityUnionTransactionKind.recharge);
      expect(
        card.cityUnionFiles.whereType<CityUnionRawFileView>().where(
          (file) => file.sfi == 0x18,
        ),
        hasLength(4),
      );
      final views = analyzeCuTransactions(
        card.cityUnionFiles,
        KnowledgeBase.empty(),
      );
      expect(views.map((view) => view.amountText()), [
        '-¥1.80',
        '-¥1.80',
        '-¥0.00',
        '+¥10.00',
      ]);
      expect(captureCuProjection(views)['transactions'], hasLength(4));
      final shown = describeCuTrip(views.first);
      expect(shown.journeyEvent?.role, JourneyEventRole.unknown);
      expect(shown.info.line, isNull);
    },
  );

  test('CU FCI and independent public identity retain an identical TU and CU transaction in both records', () async {
    final chip = _Chip(cuFci: '6F0B8409A00000000386980701');
    final result = (await LocalCardReader(chip.call).read())!;
    final cu = result.parsedCard.cityUnionFiles
        .whereType<CityUnionWalletTransaction>();
    expect(result.parsedCard.transactions.single.rawHex, _tuBus);
    expect(
      cu.singleWhere((row) => row.recordNumber == 2).rawHex.replaceAll(' ', ''),
      _tuBus,
    );
    expect(
      result.applications.singleWhere((app) => app.appId == 'cu').recordCount,
      5,
    );
  });

  test(
    'Qingdao latest metro clocks pair only the matching wallet rows',
    () async {
      final chip = _Chip(metroPair: true);
      final card = (await LocalCardReader(chip.call).read())!.parsedCard;
      final views = analyzeCuTransactions(
        card.cityUnionFiles,
        KnowledgeBase.empty(),
      );
      expect(chip.commands, containsAllInOrder(['00B203CC20', '00B207CC20']));
      expect(views.map((view) => view.amountText()), [
        '-¥1.80',
        '-¥0.00',
        '+¥10.00',
      ]);
      final events = views
          .map((view) => describeCuTrip(view).journeyEvent!)
          .toList();
      expect(events.map((event) => event.role), [
        JourneyEventRole.exit,
        JourneyEventRole.entry,
        JourneyEventRole.unknown,
      ]);
      final journey = projectJourneys(events)
          .singleWhere((item) => item.state == JourneyState.completed);
      expect(journey.amountText, '-¥1.80');
      expect(journey.start?.station, isNull);
      expect(journey.end?.station, isNull);
      expect(journey.duration, const Duration(minutes: 5, seconds: 27));

      final old = _batch('old', [
        for (final view in views) view.withQingdaoMetro(null),
      ]);
      final split = projectCuArchive(
        ArchiveHistoryResult(
          card: null,
          batches: [
            old,
            _batch('exit-only', [views[0]]),
            _batch('entry-only', [views[1]]),
          ],
        ),
      );
      expect(split.issues, isEmpty);
      expect(split.transactions, hasLength(3));
      expect(completeQingdaoMetroLinks(split.transactions), isEmpty);

      final archived = projectCuArchive(
        ArchiveHistoryResult(
          card: null,
          batches: [old, _batch('matched', views)],
        ),
      );
      expect(archived.issues, isEmpty);
      expect(archived.transactions, hasLength(3));
      expect(completeQingdaoMetroLinks(archived.transactions), hasLength(1));
      final saved = projectJourneys([
        for (final view in archived.transactions)
          describeCuTrip(view).journeyEvent!,
      ]).singleWhere((item) => item.state == JourneyState.completed);
      expect(saved.amountText, '-¥1.80');
    },
  );

  test(
    'changing the TU management city preserves CU compatibility and read order',
    () async {
      final chip = _Chip(city: '4560');
      final card = (await LocalCardReader(chip.call).read())!.parsedCard;
      expect(card.transactions, hasLength(1));
      expect(
        card.cityUnionFiles.whereType<CityUnionWalletTransaction>(),
        hasLength(4),
      );
      expect(chip.commands, contains(_cuWithoutLe));
      expect(
        chip.commands,
        containsAllInOrder([
          _cuWithLe,
          _cuWithoutLe,
          _tuSelect,
          '00B201D400',
          '00B201F500',
        ]),
      );
    },
  );

  test(
    'Qingdao fallback declines a SELECT reporting a different AID',
    () async {
      final chip = _Chip(cuFci: '6F0A8408A000000632010105');
      final card = (await LocalCardReader(chip.call).read())!.parsedCard;
      expect(card.transactions, hasLength(1));
      expect(card.cityUnionFiles, isEmpty);
      expect(chip.commands, contains(_cuWithoutLe));
      expect(chip.commands, isNot(contains(_cuPublic)));
    },
  );

  test(
    'Qingdao SELECT followed by stale TU public bytes creates no debits',
    () async {
      final chip = _Chip(validPublic: false);
      final card = (await LocalCardReader(chip.call).read())!.parsedCard;
      expect(card.transactions, hasLength(1));
      expect(card.cityUnionFiles, isEmpty);
      expect(chip.commands, contains(_cuPublic));
      expect(chip.commands, isNot(contains(_cuFirstRecord)));
    },
  );

  test(
    'Qingdao fallback with card removed before CU data preserves TU',
    () async {
      final chip = _Chip(interruptAt: _cuWithoutLe);
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      expect(
        result.readResult.transportFailure?.kind,
        TransportFailureKind.tagLost,
      );
      expect(chip.commands.last, _cuWithoutLe);
      final tu = result.applications.where((a) => a.appId == 'tu').single;
      final cu = result.applications.where((a) => a.appId == 'cu').single;
      expect(tu.state, ApplicationProbeState.partial);
      expect(tu.readError, isNull);
      expect(tu.transportFailure, isNull);
      expect(tu.notes, isNotEmpty);
      expect(cu.transportFailure?.kind, TransportFailureKind.tagLost);
    },
  );

  test(
    'Qingdao fallback with removal after a debit publishes that debit',
    () async {
      final chip = _Chip(interruptAt: '00B202C417');
      final result = (await LocalCardReader(chip.call).read())!;
      expect(result.parsedCard.transactions, hasLength(1));
      final debit = result.parsedCard.cityUnionFiles
          .whereType<CityUnionWalletTransaction>()
          .single;
      expect(debit.interpretedAmountFen, -180);
      expect(
        result.readResult.transportFailure?.kind,
        TransportFailureKind.tagLost,
      );
      expect(chip.commands.last, '00B202C417');
      final tu = result.applications.where((a) => a.appId == 'tu').single;
      final cu = result.applications.where((a) => a.appId == 'cu').single;
      expect(tu.state, ApplicationProbeState.partial);
      expect(tu.readError, isNull);
      expect(tu.transportFailure, isNull);
      expect(cu.transportFailure?.kind, TransportFailureKind.tagLost);
    },
  );
}

ArchiveBatchEvidence _batch(String id, List<CuTransactionView> views) =>
    ArchiveBatchEvidence(
      id: id,
      readAt: 1,
      storedParseVersion: 15,
      origin: 'test',
      timeSource: 'test',
      issues: const [],
      decoded: CardSessionSnapshot.decodeResult(
        CardSessionSnapshot(
          extensions: {'cuProjection': captureCuProjection(views)},
        ).encode(),
      ),
    );

class _Chip {
  _Chip({
    this.city = '4520',
    this.validPublic = true,
    this.interruptAt,
    this.metroPair = false,
    this.cuFci = '',
    this.processTail = false,
    this.rejectTuRestore = false,
    this.loseOnTuRestore = false,
  });

  final String city;
  final bool validPublic;
  final String? interruptAt;
  final bool metroPair;
  final String cuFci;
  final bool processTail;
  final bool rejectTuRestore;
  final bool loseOnTuRestore;
  final commands = <String>[];
  var _tuSelections = 0;
  var _selected = '';

  Future<List<int>> call(List<int> apdu) async {
    final command = apdu
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    commands.add(command);
    if (command == interruptAt) {
      throw const TransportFailure(
        kind: TransportFailureKind.tagLost,
        message: 'fixture lost tag',
      );
    }
    if (command == _tuSelect || command == '80A4040008A00000063201010500') {
      _tuSelections++;
      if (loseOnTuRestore && _tuSelections > 1) {
        throw const TransportFailure(
          kind: TransportFailureKind.tagLost,
          message: 'fixture lost tag restoring TU',
        );
      }
      if (rejectTuRestore && _tuSelections > 1) return [0x6A, 0x82];
      _selected = 'tu';
    } else if (command == _cuWithoutLe) {
      _selected = 'cu';
    }
    if (apdu[1] == 0xB2 &&
        apdu[4] == 0 &&
        (apdu[3] == 0xD4 || apdu[3] == 0xF4 || apdu[3] == 0xF5)) {
      expect(_selected, 'tu', reason: 'Process files must be read in TU');
      if (processTail && apdu[3] == 0xF4 && apdu[2] <= 24) {
        final raw = apdu[2] == 1
            ? _tuCycle
            : apdu[2] == 24
            ? _tuCycle.replaceFirst('132051', '132052')
            : '00' * 48;
        return _hex(
          '$raw'
          '9000',
        );
      }
    }
    final response = switch (command) {
      '00A40000023F0000' || _mfWithoutLe => '9000',
      '00A4040008A00000063201010500' => '9000',
      '00B0950000' =>
        '01984520FFFFFFFF0101031049304000000000012024010120301231AABB9000',
      '00B0960000' => '01${'00' * 54}9000',
      '00B0970000' => '000001564500$city${'00' * 52}9000',
      '805C000204' => '000002089000',
      '00B201C500' => '${_tuBus}9000',
      '80A4040009A0000000038698070100' => '6E00',
      _cuWithoutLe => '${cuFci}9000',
      _cuPublic => validPublic ? '${_validCuPublic}9000' : '01984520FFFFFFFF0101031049304000000000012024010120301231AABB9000',
      _cuFirstRecord => '${_metroDebit}9000',
      '00B202C417' =>
        '${metroPair ? _zeroDebit.replaceFirst('0009', '0003') : _tuBus}9000',
      '00B203C417' => '${metroPair ? _recharge : '00' * 23}9000',
      '00B204C417' =>
        metroPair
            ? '6A83'
            : '0006000000000000B455123456780001202611142039019000',
      '00B205C417' => '0007000000000000B409123456780001202602302038019000',
      '00B206C417' => '0008000000010000B409123456780001202611142038019000',
      '00B207C417' => '${_anotherDebit}9000',
      '00B208C417' => '${_zeroDebit}9000',
      '00B209C417' => '${_recharge}9000',
      '00B20AC417' => '6A83',
      '00B203CC20' => '${'00' * 9}20261114164713${'00' * 16}9000',
      '00B207CC20' =>
        '${'00' * 7}20261114165240${'00' * 8}00002710${'00' * 6}9000',
      _ => '6A82',
    };
    return _hex(response);
  }

  List<int> _hex(String response) => [
    for (var i = 0; i < response.length; i += 2)
      int.parse(response.substring(i, i + 2), radix: 16),
  ];
}
