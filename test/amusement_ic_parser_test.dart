import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/felica/models/amusement_ic_data.dart';
import 'package:transit_card_analyzer/protocols/felica/parsers/amusement_ic_parser.dart';

List<int> _bytes(String hex) => [
  for (var index = 0; index < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
];

void main() {
  const parser = AmusementIcParser();

  group('AmusementIcParser', () {
    // Synthetic SPAD0 fixtures generated independently from the published
    // substitution/rotation specification, then checked against its inverse.
    // These are not real cards, and their five-digit checksums are unverified.
    const fixtures = {
      'A0669FFA18B71412179C536A8C3DB1C3': '50001234567890123400',
      '893D691806ECCFEF90C8773D41EEE231': '50101234567890123456',
      'E3D03F1923657E6C4F64645E7560C8D7': '51001234567890123499',
      '8D973832C1012DB613F7E0252D3D1F27': '52012345678901234567',
      'F6591B0F140A4A845943D941F494761A': '53001234567890123498',
    };

    for (final fixture in fixtures.entries) {
      test('decodes ${fixture.value.substring(0, 3)} without using IDm', () {
        final input = _bytes(fixture.key);
        final original = List<int>.of(input);

        expect(parser.parseAccessCode(input), fixture.value);
        expect(input, original, reason: 'Reading must not mutate raw evidence');
      });
    }

    test('accepts upper version nibble without undocumented restrictions', () {
      expect(
        parser.parseAccessCode(_bytes('893D6977F7D73B0A8831603D41EEE231')),
        '50101234567890123456',
      );
    });

    test('rejects unsupported lower version nibble', () {
      expect(
        parser.parseAccessCode(_bytes('893D6977ACD93A5C0361E6458954E231')),
        isNull,
      );
    });

    test(
      'rejects nondecimal nibbles instead of showing hexadecimal as code',
      () {
        expect(
          parser.parseAccessCode(_bytes('AB34BED0C2ECCFEF90C8773DD0FCBD31')),
          isNull,
        );
      },
    );

    test('rejects unsupported company and all-zero decoded identifiers', () {
      for (final encrypted in [
        'E33733B2CA5DAFCA9034AAC7339F5931',
        '626262626262626262626262626262C3',
      ]) {
        expect(parser.parseAccessCode(_bytes(encrypted)), isNull);
      }
    });

    test('rejects truncated, oversized and invalid-byte SPAD0', () {
      final valid = _bytes('893D691806ECCFEF90C8773D41EEE231');
      for (final input in <List<int>>[
        [],
        valid.sublist(0, 15),
        [...valid, 0],
        [-1, ...valid.skip(1)],
        [256, ...valid.skip(1)],
        List<int>.filled(16, 0),
        List<int>.filled(16, 255),
      ]) {
        expect(parser.parseAccessCode(input), isNull);
      }
    });
  });

  group('AmusementIcData', () {
    test(
      'round-trips code and protocol evidence without losing raw fields',
      () {
        const details = AmusementIcData(
          accessCode: '50101234567890123456',
          issuer: 'SEGA / Aime',
          dataFormatCode: 0x0078,
          spad0Hex: '893D691806ECCFEF90C8773D41EEE231',
          idBlockHex: '012E0304050607080078000000000000',
          note: '仅校验格式，未验证发卡方校验码。',
        );

        final restored = AmusementIcData.fromJson(details.toJson());
        expect(restored, isNotNull);
        expect(restored!.toJson(), details.toJson());
        expect(restored.formattedAccessCode, '5010 1234 5678 9012 3456');
      },
    );

    test(
      'retains identification evidence when access code cannot be decoded',
      () {
        final restored = AmusementIcData.fromJson({
          'dataFormatCode': 0x0078,
          'idBlockHex': '012e0304050607080078000000000000',
        });

        expect(restored?.accessCode, isNull);
        expect(restored?.formattedAccessCode, isNull);
        expect(restored?.dataFormatCode, 0x0078);
        expect(restored?.idBlockHex, '012e0304050607080078000000000000');
      },
    );

    test('accepts unknown future fields without deriving an access code', () {
      final restored = AmusementIcData.fromJson({
        'note': '读取失败',
        'futureField': true,
      });
      expect(restored?.note, '读取失败');
      expect(restored?.accessCode, isNull);
    });

    test('rejects corrupt snapshots without stringifying invalid values', () {
      for (final value in <Object?>[
        null,
        [],
        '50101234567890123456',
        <String, Object?>{},
        {'unknown': true},
        {'accessCode': 501},
        {'accessCode': '5010 1234 5678 9012 3456'},
        {'accessCode': '5010123456789012345A'},
        {'accessCode': '5010123456789012345'},
        {'issuer': 7},
        {'note': false},
        {'dataFormatCode': '0078'},
        {'dataFormatCode': 120.0},
        {'dataFormatCode': -1},
        {'dataFormatCode': 0x10000},
        {'spad0Hex': '00'},
        {'idBlockHex': '012E030405060708007800000000000Z'},
        {'note': 'valid note', 'spad0Hex': false},
      ]) {
        expect(AmusementIcData.fromJson(value), isNull, reason: '$value');
      }
    });

    test('does not format an invalid directly constructed access code', () {
      expect(
        const AmusementIcData(accessCode: '123').formattedAccessCode,
        isNull,
      );
    });
  });
}
