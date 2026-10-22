import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';

void main() {
  test(
    '3910 issuer with Shanghai trips stays generic throughout reading',
    () async {
      final replay = _LogReplay();
      final stages = <String>[];
      final outcome = await LocalCardReader(
        replay.call,
        onStage: stages.add,
      ).read();

      replay.expectComplete();
      expect(outcome, isNotNull);
      expect(outcome!.shanghai, isNull);
      final card = outcome.parsedCard!;
      expect(card.parserId, CardParserIds.tunion);
      expect(card.selectedAidHex, 'A000000632010105');
      expect(card.info.issuerId, '01283910FFFFFFFF');
      expect(card.info.cityCode, '3910');
      expect(card.info.balanceFen, 410);
      expect(card.cityUnionBalanceFen, isNull);
      expect(card.dualApplication, isFalse);
      expect(card.transactionFileObserved, isTrue);
      expect(card.transactions.map((t) => t.amountFen), [
        300,
        0,
        100,
        100,
        90,
        1000,
      ]);
      expect(
        card.transitProcessRecords.where((r) => r.sfi == 0x1E),
        hasLength(5),
      );
      expect(
        card.transitProcessRecords.any((r) => r.trip?.cityCode == '2900'),
        isTrue,
        reason: 'Shanghai travel history does not establish Shanghai issuance',
      );
      expect(stages, isNotEmpty);
      expect(stages.where((s) => s.contains('上海')), isEmpty);
    },
  );

  test(
    'Shanghai status is emitted only after Shanghai identity is read',
    () async {
      // Synthetic identity derived from the log; all other responses are replayed.
      final replay = _LogReplay(shanghaiIdentity: true);
      final stages = <String>[];
      final shanghaiIdentitySnapshots = <bool>[];
      final outcome = await LocalCardReader(
        replay.call,
        onStage: (stage) {
          if (stage.contains('上海')) {
            shanghaiIdentitySnapshots.add(replay.identityRead);
          }
          stages.add(stage);
        },
      ).read();

      replay.expectComplete();
      expect(outcome!.parsedCard!.parserId, CardParserIds.shanghaiTunion);
      expect(outcome.shanghai!.isShanghaiTransitUnion, isTrue);
      expect(outcome.parsedCard!.info.balanceFen, 410);
      expect(outcome.parsedCard!.cityUnionBalanceFen, isNull);
      expect(outcome.parsedCard!.transactions, hasLength(6));
      expect(shanghaiIdentitySnapshots, everyElement(isTrue));
      expect(stages.where((s) => s.contains('上海')), hasLength(1));
      expect(stages.last, contains('上海'));
    },
  );

  test(
    'unsupported cards never acquire Shanghai status during probing',
    () async {
      final stages = <String>[];
      final outcome = await LocalCardReader(
        (_) async => const [0x6A, 0x82],
        onStage: stages.add,
      ).read();

      expect(outcome, isNull);
      expect(stages, isNotEmpty);
      expect(stages.where((s) => s.contains('上海')), isEmpty);
    },
  );
  test(
    'captured 3910 log uses 1E instead of also displaying 1A rail rows',
    () async {
      final replay = _LogReplay();
      final result = await LocalCardReader(replay.call).read();
      replay.expectComplete();
      final card = result!.parsedCard!;
      final snapshot = CardSessionSnapshot(
        cardCityCode: card.info.cityCode,
        rails: [
          for (final r in card.transitProcessRecords)
            if (r.railTransit != null) r.railTransit!,
        ],
        processTrips: [
          for (final r in card.transitProcessRecords)
            if (r.sfi == 0x1E && r.trip != null) r.trip!,
        ],
      );
      final captured = snapshot.encode();
      final envelope = jsonDecode(captured) as Map<String, dynamic>;
      final records = <ArchiveHistoryRecord>[
        for (final (section, kind) in [
          ('rails', ArchiveRecordKind.rail),
          ('cycle', ArchiveRecordKind.process),
        ])
          for (final (i, fields) in (envelope[section] as List).indexed)
            ArchiveHistoryRecord(
              kind: kind,
              fields: fields as Map<String, dynamic>,
              context: snapshot.context,
              sources: [
                ArchiveRecordSource('capture-3910', '$section[$i]', 1, null),
              ],
            ),
      ];

      final entries = presentArchiveTrips(records, onDiagnostics: (_) {});

      expect(entries.where((e) => e.source == ArchiveRecordKind.rail), isEmpty);
      expect(
        entries.where((e) => e.source == ArchiveRecordKind.process),
        hasLength(5),
      );
      expect(entries.any((e) => e.info.line == '0'), isFalse);
      // All captured evidence survives the display/analysis priority rule.
      expect(snapshot.rails, hasLength(1));
      expect(snapshot.processTrips, hasLength(5));
      expect(snapshot.encode(), captured);
      expect(
        records.where((r) => r.kind == ArchiveRecordKind.rail),
        hasLength(1),
      );
    },
  );
}

/// Substitutes only physical NFC I/O and rejects any changed command or order.
class _LogReplay {
  _LogReplay({this.shanghaiIdentity = false}) {
    final fixture = jsonDecode(
      File('test/fixtures/non_shanghai_tunion_3910_20261022.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    _exchanges = (fixture['exchanges'] as List).cast<Map<String, dynamic>>();
  }

  final bool shanghaiIdentity;
  late final List<Map<String, dynamic>> _exchanges;
  int _index = 0;
  bool identityRead = false;

  Future<List<int>> call(List<int> command) async {
    expect(
      _index,
      lessThan(_exchanges.length),
      reason: 'Unexpected extra APDU',
    );
    final exchange = _exchanges[_index++];
    expect(
      command,
      _bytes(exchange['command'] as String),
      reason: 'APDU #$_index',
    );
    var response = exchange['response'] as String;
    if (shanghaiIdentity) {
      response = response
          .replaceAll('01283910FFFFFFFF', '02002900FFFFFFFF')
          .replaceAll('020103105060001200716115', '020103104770001200716115');
      if (command.length >= 3 && command[1] == 0xB0 && command[2] == 0x97) {
        response = response.replaceFirst(
          '0000015639003910',
          '0000015629002900',
        );
      }
    }
    if (command.length >= 3 && command[1] == 0xB0 && command[2] == 0x95) {
      identityRead = true;
    }
    return _bytes(response);
  }

  void expectComplete() => expect(_index, _exchanges.length);

  static List<int> _bytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}
