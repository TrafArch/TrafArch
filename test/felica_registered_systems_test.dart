import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

List<int> _packet(List<int> payload) => [payload.length + 1, ...payload];

void main() {
  test(
    'listed public systems select their own IDm and retain independent data',
    () async {
      var current = 0;
      final polls = <int>[];
      final result = await FelicaReader((cmd) async {
        if (cmd[1] == 0) {
          current = (cmd[2] << 8) | cmd[3];
          polls.add(current);
          if (current == 0x8008) expect(cmd, [6, 0, 0x80, 8, 1, 0x17]);
          return _packet([
            1,
            ...List.filled(8, current & 255),
            ...List.filled(8, 0),
          ]);
        }
        final idm = List.filled(8, current & 255);
        expect(cmd.sublist(2, 10), idm);
        if (cmd[1] == 0x0C) {
          return _packet([
            0x0D,
            ...idm,
            5,
            0x88,
            0xB4,
            0x12,
            0x34,
            0x80,
            8,
            0,
            3,
            0,
            3,
          ]);
        }
        if (cmd[1] == 2) return _packet([3, ...idm, 1, 0, 0]);
        if (current == 3) return _packet([7, ...idm, 0xA1, 0xB2]);
        if (current == 0x8008) {
          expect(cmd.sublist(10), [1, 0x17, 1, 1, 0x80, 0]);
          return _packet([
            7,
            ...idm,
            0,
            0,
            1,
            0,
            0,
            3,
            0x52,
            ...List.filled(12, 0),
          ]);
        }
        if (current == 0x88B4) {
          return _packet([7, ...idm, 0, 0, 1, ...List.filled(16, 0)]);
        }
        fail('Unexpected command $cmd on system $current');
      }).read();
      expect(polls, [0xFFFF, 3, 0x8008, 0x88B4]);
      expect(result.cardProductType, FelicaCardType.suica);
      expect(result.systemResults.keys, [3, 0x8008, 0x88B4]);
      expect(result.systemResults[0x8008]!.idm, '0808080808080808');
      expect(
        result.systemResults[0x8008]!.wallets.single.balanceMinorUnits,
        5000,
      );
      expect(result.wallets.single.currency, 'JPY');
      expect(result.systemResults[0x88B4]!.idm, 'B4B4B4B4B4B4B4B4');
      expect(result.systemResults[0x88B4]!.rawBlocks, hasLength(1));
      expect(result.systemResults[0x88B4]!.frames.map((f) => f.command[1]), [
        0,
        6,
      ]);
      final captured = jsonDecode(
        jsonEncode(captureReadResult(FelicaReadOutcome(result))),
      ) as Map;
      expect(captured['systemResults']['8008']['idm'], '0808080808080808');
      expect(captured['systemResults']['88B4']['rawBlocks'], hasLength(1));
      expect(
        captureParserRecords(FelicaReadOutcome(result))
            .where((r) => (r['fields'] as Map)['systemCode'] == 0x8008),
        isNotEmpty,
      );
    },
  );

  test('later terminal failure retains earlier system data and skips remaining systems', () async {
    var selected = 0;
    final polls = <int>[];
    final result = await FelicaReader((cmd) async {
      if (cmd[1] == 0) {
        selected = (cmd[2] << 8) | cmd[3];
        polls.add(selected);
        if (selected == 0x8008) {
          throw const TransportFailure(
            kind: TransportFailureKind.tagLost,
            message: 'removed',
          );
        }
        return _packet([1, ...List.filled(8, 1), ...List.filled(8, 0)]);
      }
      if (cmd[1] == 0x0C) {
        return _packet([
          0x0D,
          ...List.filled(8, 1),
          3,
          0,
          3,
          0x80,
          8,
          0x88,
          0xB4,
        ]);
      }
      if (cmd[1] == 2) return _packet([3, ...List.filled(8, 1), 1, 0, 0]);
      return _packet([7, ...List.filled(8, 1), 0xA1, 0]);
    }).read();
    expect(polls, [0xFFFF, 3, 0x8008]);
    expect(result.systemResults[3]!.wallets, isNotEmpty);
    expect(result.systemResults[0x8008]!.idm, isNull);
    expect(result.systemResults[0x8008]!.state, FelicaReadState.tagLost);
    expect(result.systemResults.containsKey(0x88B4), isFalse);
  });
}
