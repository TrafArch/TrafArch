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

void main() {
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
          _mfWithoutLe,
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

  test('unrelated TU card keeps fast CU selection only', () async {
    final chip = _Chip(city: '4560');
    final card = (await LocalCardReader(chip.call).read())!.parsedCard;
    expect(card.transactions, hasLength(1));
    expect(card.cityUnionFiles, isEmpty);
    expect(chip.commands, isNot(contains(_cuWithoutLe)));
  });

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
  });

  final String city;
  final bool validPublic;
  final String? interruptAt;
  final bool metroPair;
  final String cuFci;
  final commands = <String>[];

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
    return [
      for (var i = 0; i < response.length; i += 2)
        int.parse(response.substring(i, i + 2), radix: 16),
    ];
  }
}
