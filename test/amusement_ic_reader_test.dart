import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

const _idm = <int>[0x01, 0x2E, 0x3A, 0x4B, 0x5C, 0x6D, 0x7E, 0x8F];
const _pmm = <int>[0x00, 0xF1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
const _encryptedSpad0 = <int>[
  0x89,
  0x3D,
  0x69,
  0x18,
  0x06,
  0xEC,
  0xCF,
  0xEF,
  0x90,
  0xC8,
  0x77,
  0x3D,
  0x41,
  0xEE,
  0xE2,
  0x31,
];

List<int> _packet(List<int> body) => [body.length + 1, ...body];

class _AicTag {
  _AicTag({
    this.dfc = 0x0078,
    this.idFailure,
    this.spadFailure,
    this.idStatus = 0,
    this.spad0 = _encryptedSpad0,
    this.transformResponse,
  });

  final int dfc;
  final TransportFailure? idFailure;
  final TransportFailure? spadFailure;
  final int idStatus;
  final List<int> spad0;
  final List<int> Function(int blockNumber, List<int> response)?
  transformResponse;
  final commands = <List<int>>[];

  List<int> get idBlock => [
    ..._idm,
    (dfc >> 8) & 0xFF,
    dfc & 0xFF,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  Future<List<int>> transceive(List<int> command) async {
    commands.add(List<int>.of(command));
    if (command[1] == 0x00) {
      return _packet([0x01, ..._idm, ..._pmm]);
    }
    if (command[1] != 0x06) {
      throw StateError('FeliCa Lite does not support this command');
    }
    // Only one non-encrypted service and one short-format block are allowed.
    if (command.length != 16 ||
        command[10] != 1 ||
        command[11] != 0x0B ||
        command[12] != 0 ||
        command[13] != 1 ||
        command[14] != 0x80 ||
        !const [0x82, 0x00].contains(command[15])) {
      throw StateError('Unexpected AIC read request: $command');
    }
    final idRead = command[15] == 0x82;
    final failure = idRead ? idFailure : spadFailure;
    if (failure != null) throw failure;
    if (idRead && idStatus != 0) {
      return _packet([0x07, ..._idm, idStatus >> 8, idStatus & 0xFF]);
    }
    final response = _packet([
      0x07,
      ..._idm,
      0,
      0,
      1,
      ...(idRead ? idBlock : spad0),
    ]);
    return transformResponse?.call(command[15], response) ?? response;
  }

  Future<FelicaScanResult> read() =>
      FelicaReader(transceive).read(preferredSystemCode: 0x88B4);
}

void main() {
  test(
    'AIC Lite reads its identity then SPAD0 without unsupported discovery',
    () async {
      final tag = _AicTag();
      final result = await tag.read();

      expect(result.cardType, 'amusement_ic');
      expect(result.displayName, contains('Aime'));
      expect(result.state, FelicaReadState.success);
      expect(result.amusementIc?.accessCode, '50101234567890123456');
      expect(result.amusementIc?.issuer, 'Aime');
      expect(result.amusementIc?.dataFormatCode, 0x0078);
      expect(result.idm, '012E3A4B5C6D7E8F');
      expect(result.wallets, isEmpty);
      expect(result.transactions, isEmpty);
      expect(result.rawBlocks.map((block) => block.bytes), [
        tag.idBlock,
        _encryptedSpad0,
      ]);
      expect(tag.commands, [
        [6, 0, 0x88, 0xB4, 0, 0],
        [16, 6, ..._idm, 1, 0x0B, 0, 1, 0x80, 0x82],
        [16, 6, ..._idm, 1, 0x0B, 0, 1, 0x80, 0],
      ]);
    },
  );

  test('Unknown Lite DFC keeps raw identity and never reads SPAD0', () async {
    final tag = _AicTag(dfc: 0xFFFF);
    final result = await tag.read();

    expect(result.cardProductType, FelicaCardType.unknown);
    expect(result.amusementIc?.accessCode, isNull);
    expect(result.amusementIc?.issuer, isNull);
    expect(result.amusementIc?.dataFormatCode, 0xFFFF);
    expect(result.rawBlocks.single.bytes, tag.idBlock);
    expect(result.wallets, isEmpty);
    expect(result.transactions, isEmpty);
    expect(tag.commands.map((command) => command[1]), [0, 6]);
  });

  test(
    'AIC tag loss during SPAD0 keeps identified product and identity bytes',
    () async {
      final tag = _AicTag(
        spadFailure: const TransportFailure(
          kind: TransportFailureKind.tagLost,
          message: 'tag left after identity',
        ),
      );
      final result = await tag.read();

      expect(result.cardType, 'amusement_ic');
      expect(result.displayName, contains('Aime'));
      expect(result.state, FelicaReadState.tagLost);
      expect(result.amusementIc?.accessCode, isNull);
      expect(result.amusementIc?.issuer, 'Aime');
      expect(result.rawBlocks.first.bytes, tag.idBlock);
      expect(
        result.statuses.last.transportFailure?.kind,
        TransportFailureKind.tagLost,
      );
      expect(result.frames, hasLength(3));
      expect(tag.commands.map((command) => command[1]), [0, 6, 6]);
    },
  );

  test(
    'AIC rejected identity read stops before SPAD0 and preserves response',
    () async {
      final tag = _AicTag(idStatus: 0x01A1);
      final result = await tag.read();

      expect(result.cardProductType, FelicaCardType.unknown);
      expect(result.statuses.last.state, FelicaReadState.accessDenied);
      expect(result.state, FelicaReadState.accessDenied);
      expect(
        result.statuses.last.rawResponse,
        _packet([0x07, ..._idm, 1, 0xA1]),
      );
      expect(result.wallets, isEmpty);
      expect(tag.commands.map((command) => command[1]), [0, 6]);
    },
  );

  test(
    'AIC rejected SPAD0 read keeps identity and reports access denied',
    () async {
      final denied = _packet([0x07, ..._idm, 1, 0xA1]);
      final tag = _AicTag(
        transformResponse: (block, response) => block == 0 ? denied : response,
      );
      final result = await tag.read();
      expect(result.cardProductType, FelicaCardType.amusementIc);
      expect(result.amusementIc?.issuer, 'Aime');
      expect(result.amusementIc?.accessCode, isNull);
      expect(result.statuses.last.state, FelicaReadState.accessDenied);
      expect(result.statuses.last.rawResponse, denied);
      expect(result.state, FelicaReadState.accessDenied);
      expect(tag.commands.map((command) => command[1]), [0, 6, 6]);
    },
  );

  test(
    'AIC candidate selection is metadata-only and unrelated cards add no RF',
    () async {
      final commands = <List<int>>[];
      final protocol = FelicaProtocol((command) async {
        commands.add(command);
        throw StateError('No RF expected during candidate selection');
      });
      for (final item in const [
        (systemCode: 0x88B4, expected: 'amusement_ic'),
        (systemCode: 0x8008, expected: 'octopus'),
        (systemCode: 0x1234, expected: 'felica_generic'),
      ]) {
        final selected = await CardAdapterRegistry.defaults().select(
          FelicaCardContext(
            idm: '012E3A4B5C6D7E8F',
            idmBytes: _idm,
            systemCodes: [item.systemCode],
            protocol: protocol,
          ),
        );
        expect(selected.cardType, item.expected);
      }
      expect(commands, isEmpty);
    },
  );

  test(
    'Existing Suica selection retains its single SF service probe',
    () async {
      final commands = <List<int>>[];
      final selected = await CardAdapterRegistry.defaults().select(
        FelicaCardContext(
          idm: '012E3A4B5C6D7E8F',
          idmBytes: _idm,
          systemCodes: const [0x0003],
          protocol: FelicaProtocol((command) async {
            commands.add(command);
            return _packet([0x03, ..._idm, 1, 0, 0]);
          }),
        ),
      );
      expect(selected.cardType, 'suica');
      expect(commands, [
        [13, 2, ..._idm, 1, 0x0F, 0x09],
      ]);
    },
  );

  for (final item in const [
    (dfc: 0x0068, issuer: 'e-amusement'),
    (dfc: 0x002A, issuer: 'Banapass'),
    (dfc: 0x003A, issuer: 'Banapass'),
    (dfc: 0x0079, issuer: 'NESiCA'),
  ]) {
    test('DFC ${item.dfc} does not accept a valid SEGA Access Code', () async {
      final tag = _AicTag(dfc: item.dfc);
      final result = await tag.read();

      expect(result.cardType, 'amusement_ic');
      expect(result.amusementIc?.issuer, item.issuer);
      expect(result.amusementIc?.accessCode, isNull);
      expect(result.amusementIc?.spad0Hex, '893D691806ECCFEF90C8773D41EEE231');
      expect(result.state, FelicaReadState.malformed);
      expect(result.wallets, isEmpty);
      expect(tag.commands, hasLength(3));
    });
  }

  test(
    'Invalid SPAD0 bytes retain the identified product but no Access Code',
    () async {
      final tag = _AicTag(spad0: List<int>.filled(16, 0));
      final result = await tag.read();

      expect(result.cardType, 'amusement_ic');
      expect(result.amusementIc?.accessCode, isNull);
      expect(result.amusementIc?.spad0Hex, '00000000000000000000000000000000');
      expect(result.state, FelicaReadState.malformed);
      expect(result.rawBlocks.last.bytes, List<int>.filled(16, 0));
    },
  );

  // Synthetic vectors independently checked against the published algorithm;
  // these establish offline decoding, not validity for any game account.
  for (final item in const [
    (
      dfc: 0x0078,
      issuer: 'Aime',
      encrypted: 'A0669FFA18B71412179C536A8C3DB1C3',
      code: '50001234567890123400',
    ),
    (
      dfc: 0x002A,
      issuer: 'Banapass',
      encrypted: 'E3D03F1923657E6C4F64645E7560C8D7',
      code: '51001234567890123499',
    ),
    (
      dfc: 0x003A,
      issuer: 'Banapass',
      encrypted: 'E3D03F1923657E6C4F64645E7560C8D7',
      code: '51001234567890123499',
    ),
    (
      dfc: 0x0068,
      issuer: 'e-amusement',
      encrypted: '8D973832C1012DB613F7E0252D3D1F27',
      code: '52012345678901234567',
    ),
    (
      dfc: 0x0079,
      issuer: 'NESiCA',
      encrypted: 'F6591B0F140A4A845943D941F494761A',
      code: '53001234567890123498',
    ),
  ]) {
    test(
      'DFC ${item.dfc} publishes its matching ${item.issuer} Access Code',
      () async {
        final tag = _AicTag(
          dfc: item.dfc,
          spad0: FelicaHex.hexToBytes(item.encrypted),
        );
        final result = await tag.read();

        expect(result.cardProductType, FelicaCardType.amusementIc);
        expect(result.amusementIc?.issuer, item.issuer);
        expect(result.amusementIc?.accessCode, item.code);
        expect(result.state, FelicaReadState.success);
        expect(result.wallets, isEmpty);
        expect(tag.commands, hasLength(3));
      },
    );
  }

  for (final failure in const [
    TransportFailure(kind: TransportFailureKind.tagLost, message: 'tag left'),
    TransportFailure(kind: TransportFailureKind.timeout, message: 'timeout'),
    TransportFailure(
      kind: TransportFailureKind.cancelled,
      message: 'cancelled',
    ),
    TransportFailure(kind: TransportFailureKind.staleSession, message: 'stale'),
  ]) {
    test(
      'Identity ${failure.kind.name} stops AIC reads and retains the failure',
      () async {
        final tag = _AicTag(idFailure: failure);
        final result = await tag.read();

        expect(result.cardProductType, FelicaCardType.unknown);
        expect(result.amusementIc?.accessCode, isNull);
        expect(result.statuses.last.transportFailure?.kind, failure.kind);
        expect(
          result.state,
          failure.kind == TransportFailureKind.tagLost
              ? FelicaReadState.tagLost
              : FelicaReadState.failed,
        );
        expect(tag.commands.map((command) => command[1]), [0, 6]);
        expect(result.frames.last.response, isNull);
      },
    );
  }

  for (final targetBlock in const [0x82, 0]) {
    test(
      'Mismatched response IDm on block $targetBlock is not decoded',
      () async {
        final tag = _AicTag(
          transformResponse: (block, response) => block == targetBlock
              ? [...response.sublist(0, 2), 0xFF, ...response.sublist(3)]
              : response,
        );
        final result = await tag.read();

        expect(result.state, FelicaReadState.malformed);
        expect(result.amusementIc?.accessCode, isNull);
        expect(result.statuses.last.rawResponse?[2], 0xFF);
        expect(tag.commands, hasLength(targetBlock == 0x82 ? 2 : 3));
        if (targetBlock == 0) {
          expect(result.amusementIc?.issuer, 'Aime');
          expect(result.rawBlocks.first.bytes, tag.idBlock);
        }
      },
    );
  }

  for (final mutation in const [
    'length',
    'count',
    'shortBlock',
    'responseCode',
  ]) {
    test(
      'Malformed $mutation identity response is retained without SPAD0 read',
      () async {
        final tag = _AicTag(
          transformResponse: (block, response) => switch (mutation) {
            'length' => [response[0] - 1, ...response.sublist(1)],
            'count' => [...response.sublist(0, 12), 2, ...response.sublist(13)],
            'shortBlock' => [
              response[0] - 1,
              ...response.sublist(1, response.length - 1),
            ],
            _ => [response[0], 0x09, ...response.sublist(2)],
          },
        );
        final result = await tag.read();

        expect(result.amusementIc?.accessCode, isNull);
        expect(result.cardProductType, FelicaCardType.unknown);
        expect(result.statuses.last.state.isFailure, isTrue);
        expect(result.statuses.last.rawResponse, isNotEmpty);
        expect(tag.commands, hasLength(2));
      },
    );
  }
}
