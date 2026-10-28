import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_process_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

void main() {
  const parser = TUnionProcessParser();

  for (final (name, filler) in const [
    ('zero', [0x00]),
    ('erased', [0xFF]),
    ('mixed blank', [0x00, 0xFF]),
  ]) {
    test('rail application header with $name body has no process event', () {
      final raw = _applicationRecord(1, filler);
      expect(parser.parseRailTransit(1, raw), isNull);
    });

    test('bus application header with $name body has no process event', () {
      final raw = _applicationRecord(2, filler);
      expect(parser.parseBusTransit(2, raw), isNull);
    });
  }

  test('70 templates do not turn empty application records into events', () {
    final rail = _applicationRecord(1, const [0]);
    final bus = _applicationRecord(2, const [0xFF]);
    expect(parser.parseRailTransit(1, [0x70, 0x81, 0x80, ...rail]), isNull);
    expect(parser.parseBusTransit(2, [0x70, 0x81, 0x80, ...bus]), isNull);
  });

  test(
    'nonempty unknown status survives even with no decoded time or city',
    () {
      final rail = _applicationRecord(1, const [0])..[14] = 0x42;
      final bus = _applicationRecord(2, const [0])..[14] = 0x42;
      final railRecord = parser.parseRailTransit(1, rail);
      final busRecord = parser.parseBusTransit(2, bus);
      expect(railRecord, isNotNull);
      expect(busRecord, isNotNull);
      expect(railRecord!.statusCode, 0x42);
      expect(busRecord!.statusCode, 0x42);
      expect(railRecord.entryTime, isNull);
      expect(busRecord.entryTime, isNull);
    },
  );

  test('nonempty issuer data survives when all standard fields are blank', () {
    final rail = _applicationRecord(1, const [0])..[127] = 0x5A;
    final bus = _applicationRecord(2, const [0])..[127] = 0x5A;
    final railRecord = parser.parseRailTransit(1, rail);
    final busRecord = parser.parseBusTransit(2, bus);
    expect(railRecord, isNotNull);
    expect(busRecord, isNotNull);
    expect(railRecord!.issuerCustom, endsWith('5A'));
    expect(busRecord!.issuerCustomHex, endsWith('5A'));
  });

  test(
    'partial application fields are retained without requiring a valid trip',
    () {
      final rail = _applicationRecord(1, const [0]).sublist(0, 30)..[15] = 0x29;
      final bus = _applicationRecord(2, const [0]).sublist(0, 30)..[15] = 0x29;
      final railRecord = parser.parseRailTransit(1, rail);
      final busRecord = parser.parseBusTransit(2, bus);
      expect(railRecord, isNotNull);
      expect(busRecord, isNotNull);
      expect(railRecord!.entryCityCode, '2900');
      expect(busRecord!.entryCityCode, '2900');
      expect(railRecord.entryTime, isNull);
      expect(busRecord.entryTime, isNull);
    },
  );

  test(
    'reader retains blank application bytes and physical responses',
    () async {
      final rail = List<int>.unmodifiable(_applicationRecord(1, const [0]));
      final bus = List<int>.unmodifiable(_applicationRecord(2, const [0]));
      final public = List<int>.filled(30, 0)
        ..[10] = 0x03
        ..[11] = 0x10
        ..[19] = 0x01;
      final capturedResponses = <List<int>>[];
      final apdu = ApduExchange(
        transceive: (command) async {
          if (command[1] == 0xA4) return const [0x90, 0x00];
          if (command[1] == 0xB0 && command[2] == 0x95) {
            return [...public, 0x90, 0x00];
          }
          if (command[1] == 0x5C) return const [0, 0, 0, 0, 0x90, 0x00];
          if (command[1] == 0xB2 && command[3] == 0xD4) {
            if (command[2] == 1) return [...rail, 0x90, 0x00];
            if (command[2] == 2) return [...bus, 0x90, 0x00];
          }
          return const [0x6A, 0x83];
        },
        onExchange: (result) {
          final response = result.response;
          if (response != null) capturedResponses.add(response.raw);
        },
      );
      final reader = CommonUnitTu(apdu);
      final info = CardInfo();
      final records = <ApduRecord>[];
      expect(await reader.select(info, records), isTrue);
      final card = await reader.read(info, records);
      expect(card, isNotNull);
      final applications = card!.transitProcessRecords;
      expect(applications, hasLength(2));
      expect(applications[0].raw, rail);
      expect(applications[1].raw, bus);
      expect(applications[0].railTransit, isNull);
      expect(applications[1].busTransit, isNull);
      expect(capturedResponses, contains(orderedEquals([...rail, 0x90, 0x00])));
      expect(capturedResponses, contains(orderedEquals([...bus, 0x90, 0x00])));
    },
  );
}

// Shanghai header prefix: 27 <record> 7D 01 01. The remaining header metadata
// below is synthetic and nonzero: header validity alone does not prove a trip.
// The body/custom-data area contains 114 bytes.
List<int> _applicationRecord(int number, List<int> filler) => [
  0x27,
  number,
  0x7D,
  0x01,
  0x01,
  0x00,
  0x20,
  0x26,
  0x10,
  0x24,
  0x00,
  0x00,
  0x00,
  0x01,
  for (var i = 0; i < 114; i++) filler[i % filler.length],
];
