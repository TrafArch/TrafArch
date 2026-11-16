import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

const _initialIdm = [1, 2, 3, 4, 5, 6, 7, 8];
const _selectedIdm = [8, 7, 6, 5, 4, 3, 2, 1];
List<int> _packet(List<int> body) => [body.length + 1, ...body];

void main() {
  for (final icType in [0xF0, 0xF1]) {
    test(
      'Lite IC type $icType selects 88B4 before reading its current IDm',
      () async {
        final commands = <List<int>>[];
        final result = await FelicaReader((command) async {
          commands.add(command);
          if (command[1] == 0) {
            final wildcard = command[2] == 0xFF;
            return _packet([
              1,
              ...(wildcard ? _initialIdm : _selectedIdm),
              0,
              icType,
              0,
              0,
              0,
              0,
              0,
              0,
            ]);
          }
          expect(command[1], 6);
          expect(command.sublist(2, 10), _selectedIdm);
          expect(command.last, 0x82);
          // Unknown DFC: keep evidence without reading SPAD0.
          return _packet([7, ..._selectedIdm, 0, 0, 1, ...List.filled(16, 0)]);
        }).read();
        expect(commands.map((c) => c[1]), [0, 0, 6]);
        expect(commands[1], [6, 0, 0x88, 0xB4, 0, 0]);
        expect(result.idm, '0807060504030201');
        expect(result.systemCodes, [0x88B4]);
        expect(result.cardProductType, FelicaCardType.unknown);
        expect(result.amusementIc?.accessCode, isNull);
        expect(result.rawBlocks, hasLength(1));
      },
    );
  }

  test(
    'Unconfirmed IC types preserve generic discovery and send no AIC reads',
    () async {
      final commands = <List<int>>[];
      final result = await FelicaReader((command) async {
        commands.add(command);
        if (command[1] == 0) {
          return _packet([1, ..._initialIdm, 0, 0xF2, 0, 0, 0, 0, 0, 0]);
        }
        expect(command[1], 0x0C);
        return _packet([0x0D, ..._initialIdm, 1, 0x12, 0x34]);
      }).read();
      expect(commands.map((c) => c[1]), [0, 0x0C]);
      expect(result.cardProductType, FelicaCardType.unknown);
      expect(result.amusementIc, isNull);
    },
  );

  test(
    'A listed Lite system is explicitly selected before block reads',
    () async {
      final commands = <List<int>>[];
      final result = await FelicaReader((command) async {
        commands.add(command);
        if (command[1] == 0) {
          return _packet([
            1,
            ...(commands.length == 1 ? _initialIdm : _selectedIdm),
            ...List.filled(8, 0),
          ]);
        }
        if (command[1] == 0x0C) {
          return _packet([0x0D, ..._initialIdm, 2, 0x12, 0x34, 0x88, 0xB4]);
        }
        expect(command[1], 6);
        expect(command.sublist(2, 10), _selectedIdm);
        return _packet([7, ..._selectedIdm, 0, 0, 1, ...List.filled(16, 0)]);
      }).read();
      expect(commands.map((c) => c[1]), [0, 0x0C, 0, 6]);
      expect(commands[2], [6, 0, 0x88, 0xB4, 0, 0]);
      expect(result.idm, '0807060504030201');
      expect(result.rawBlocks, hasLength(1));
    },
  );

  test(
    'Lite discovered via its NDEF system selects 88B4 without system query',
    () async {
      final commands = <List<int>>[];
      await FelicaReader((command) async {
        commands.add(command);
        if (command[1] == 0) {
          return _packet([1, ..._initialIdm, 0, 0xF1, 0, 0, 0, 0, 0, 0]);
        }
        expect(command[1], 6);
        return _packet([7, ..._initialIdm, 0, 0, 1, ...List.filled(16, 0)]);
      }).read(preferredSystemCode: 0x12FC);
      expect(commands.map((c) => c[1]), [0, 0, 6]);
      expect(commands[0], [6, 0, 0x12, 0xFC, 0, 0]);
      expect(commands[1], [6, 0, 0x88, 0xB4, 0, 0]);
    },
  );

  test(
    'Lite selection failure stops without using the wildcard IDm for reads',
    () async {
      final commands = <List<int>>[];
      final result = await FelicaReader((command) async {
        commands.add(command);
        if (commands.length == 1) {
          return _packet([1, ..._initialIdm, 0, 0xF1, 0, 0, 0, 0, 0, 0]);
        }
        throw const TransportFailure(
          kind: TransportFailureKind.tagLost,
          message: 'lost',
        );
      }).read();
      expect(commands.map((c) => c[1]), [0, 0]);
      expect(result.state, FelicaReadState.tagLost);
      expect(result.amusementIc, isNull);
      expect(result.rawBlocks, isEmpty);
    },
  );
}
