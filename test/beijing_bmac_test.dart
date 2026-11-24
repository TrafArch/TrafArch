import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/card_identification_service.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_types.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/features/home/presentation/result_labels.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/local/cards/beijing_bmac.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';

void main() {
  const motSelect = '00A404001091560000144D4F542E424D4143303031';
  const motRecord = '00B2011C32';
  test('MOT.BMAC001 alone retains its raw file without inventing any wallet fields', () async {
    final commands = <String>[];
    final scan = await LocalCardReader((cmd) async {
      final hex = LocalHex.bytesToHex(cmd);
      commands.add(hex);
      if (hex == motSelect) return [0x90, 0];
      if (hex == motRecord) return [0xAB, 0xCD, 0x90, 0];
      return [0x6A, 0x82];
    }).scan();
    final evidence = scan.applications.singleWhere(
      (a) => a.appId == 'mot_bmac',
    );
    expect(evidence.confirmed, isTrue);
    expect(evidence.observations['SFI 0x03 #1'], 'ABCD');
    expect(evidence.recordCount, 0);
    expect(evidence.cardNumber, isNull);
    expect(evidence.balanceFen, isNull);
    expect(scan.result?.parsedCard.parserName, 'MOT.BMAC001');
    expect(scan.result?.parsedCard.info.balanceFen, isNull);
    expect(
      commands,
      containsAllInOrder([
        '00A40000021001',
        motSelect,
        motRecord,
        '00A404000B535558494E2E4444463031',
      ]),
    );
    expect(commands.where((c) => c == motSelect), hasLength(1));
    expect(commands, isNot(contains('805C000204')));
  });
  test('MOT.BMAC001 tag loss preserves the selected application and stops the next probe', () async {
    final commands = <String>[];
    final scan = await LocalCardReader((cmd) async {
      final hex = LocalHex.bytesToHex(cmd);
      commands.add(hex);
      if (hex == motSelect) return [0x90, 0];
      if (hex == motRecord) throw _lost;
      return [0x6A, 0x82];
    }).scan();
    final ev = scan.applications.singleWhere((e) => e.appId == 'mot_bmac');
    expect(ev.confirmed, isTrue);
    expect(ev.state, ApplicationProbeState.partial);
    expect(ev.transportFailure?.kind, TransportFailureKind.tagLost);
    expect(commands.last, motRecord);
    expect(
      scan.applications.singleWhere((e) => e.appId == 'suzhou_suxin').probed,
      isFalse,
    );
  });

  for (final mfPresent in [false, true]) {
    test(
      'one unclassified DF1001 after MF present=$mfPresent never claims a Beijing balance',
      () async {
        final commands = <String>[];
        final scan = await LocalCardReader((cmd) async {
          final hex = LocalHex.bytesToHex(cmd);
          commands.add(hex);
          if (hex == '00A40000023F00' && mfPresent) return [0x90, 0];
          if (hex == '00A40000021001') return [0x90, 0];
          if (hex == '805C000204') return [0, 0, 0, 23, 0x90, 0];
          return [0x6A, 0x82];
        }).scan();
        expect(commands.where((c) => c == '00A40000021001'), hasLength(1));
        final evidence = scan.applications.singleWhere(
          (a) => a.appId == 'df1001',
        );
        expect(evidence.state, ApplicationProbeState.confirmed);
        expect(evidence.displayName, 'DF 1001');
        expect(evidence.balanceFen, isNull);
        expect(
          commands.skip(commands.indexOf('00A40000021001') + 1).first,
          startsWith('00A404'),
        );
        expect(scan.result, isNull);
      },
    );
  }

  test('legacy issuer marker keeps the ten-byte number and original overdraft offset', () async {
    final link = _Link()..balance = 0;
    final result = await LocalCardReader((cmd) async {
      final response = await link.call(cmd);
      if (LocalHex.bytesToHex(cmd) == '00B084003C') {
        response.setRange(0, 10, [0x10, 0, 0, 0, 0, 0, 0x12, 0x34, 0x56, 0x78]);
      }
      return response;
    }).read();
    final evidence = result!.applications.singleWhere(
      (a) => a.appId == 'df1001',
    );
    expect(evidence.confirmed, isTrue);
    expect(evidence.cardNumber, '10000000000012345678');
    expect(evidence.balanceFen, -99);
    expect(result.readResult.info.isBeijing, isTrue);
    expect(result.readResult.info.isBmac, isFalse);
    expect(
      link.commands
          .map(LocalHex.bytesToHex)
          .where((hex) => hex == '00A40000021001'),
      hasLength(1),
    );
  });
  test('explicit different FID cannot supply a Beijing balance', () async {
    final link = _Link();
    final result = await LocalCardReader((cmd) async {
      final response = await link.call(cmd);
      if (LocalHex.bytesToHex(cmd) == '00A40000021001') {
        return LocalHex.hexToBytes('620483023F009000');
      }
      return response;
    }).scan();
    expect(result.result, isNull);
    final evidence = result.applications.singleWhere(
      (a) => a.appId == 'df1001',
    );
    expect(evidence.confirmed, isFalse);
    expect(
      link.commands.map(LocalHex.bytesToHex),
      isNot(contains('805C000204')),
    );
  });
  test('BMAC reads documented offsets and keeps ambiguous years raw', () async {
    final link = _Link();
    final info = CardInfo();
    final extras = CardExtras();
    final records = <ApduRecord>[];
    final reader = BeijingBmac(ApduExchange(transceive: link.call));
    expect(await reader.select(info, records, extras), isTrue);
    await reader.read(info, records, extras);
    expect(info.cardNumber, '1234567890123456');
    expect(info.issueDate, DateTime.utc(2020, 1, 2));
    expect(info.expiryDate, DateTime.utc(2030, 12, 31));
    expect(info.observedBalance, 12345);
    expect(info.issuerCode, isEmpty);
    expect(info.isBeijing, isFalse);
    expect(info.copy().isBmac, isTrue);
    expect(extras.slots['bmac.overdraftRaw'], 123);
    expect(extras.slots['bmac.transactionCount'], 0x1234);
    final recharges = extras.slots['bmac.recharges']! as List;
    expect(recharges.length, 3);
    expect(recharges.first, containsPair('balanceBeforeRaw', 100));
    expect(recharges.first, containsPair('balanceAfterRaw', 200));
    expect(recharges.first, containsPair('dateBcd', '241031'));
    expect(recharges.first, containsPair('terminalHex', '300040000570'));
    final bus = extras.slots['bmac.bus']! as Map;
    expect(bus['lineCode'], 0x1234);
    expect(bus['directionRaw'], 0xAB);
    expect(bus['boardingTimeBcd'], '241031123456');
    expect(bus['boardingTimeBcdValid'], isTrue);
    expect(records.where((r) => r.type == 2), isEmpty);
    expect(link.commands.where((c) => c[1] == 0xB2).length, 3);
  });

  for (final balance in [0, 12345]) {
    test('wallet $balance uses documented overdraft offset', () async {
      final link = _Link()..balance = balance;
      final info = CardInfo();
      final extras = CardExtras();
      final reader = BeijingBmac(ApduExchange(transceive: link.call));
      expect(await reader.select(info, [], extras), isTrue);
      await reader.read(info, [], extras);
      expect(info.observedBalance, balance == 0 ? -123 : balance);
    });
  }

  for (final mutation in ['short', 'bcd', 'date', 'order', 'basic', 'df']) {
    test('rejects invalid identity: $mutation', () async {
      final link = _Link()..mutation = mutation;
      final info = CardInfo();
      final reader = BeijingBmac(ApduExchange(transceive: link.call));
      expect(await reader.select(info, [], CardExtras()), isFalse);
      expect(info.isLocalCard, isFalse);
      expect(info.cardNumber, isEmpty);
    });
  }

  test(
    'rejected balance stays unknown and malformed optional data stays raw',
    () async {
      final link = _Link()
        ..rejectBalance = true
        ..badOptional = true;
      final info = CardInfo();
      final extras = CardExtras();
      final reader = BeijingBmac(ApduExchange(transceive: link.call));
      expect(await reader.select(info, [], extras), isTrue);
      await reader.read(info, [], extras);
      expect(info.observedBalance, isNull);
      final entries = extras.slots['bmac.recharges']! as List;
      expect((entries.first as Map)['dateBcdValid'], isFalse);
      expect(
        (extras.slots['bmac.bus']! as Map)['boardingTimeBcdValid'],
        isFalse,
      );
    },
  );

  test(
    'pipeline produces independent BMAC identity and no generic trips',
    () async {
      final link = _Link();
      final result = await LocalCardReader(link.call).read();
      final parsed = result!.parsedCard;
      expect(parsed.parserId, CardParserIds.beijingBmac);
      expect(parsed.info.applicationSerial, '1234567890123456');
      expect(parsed.localCard!.extras.slots['bmac.recharges'], hasLength(3));
      expect(parsed.localCard!.trips, isEmpty);
      final identity = CardIdentificationService(KnowledgeBase.empty())
          .identify(parsed)!;
      expect(identity.identity.cardType, CardTypes.beijingBmac);
      expect(identity.identity.cityName, '北京');
      expect(identity.cardNumber, '1234567890123456');
      expect(identity.fingerprint, 'beijing_bmac::1234567890123456');
      expect(CardParserIds.isTUnionFamily(parsed.parserId), isFalse);
      expect(transitTypeLabel(parsed.parserId), BeijingBmac.moduleName);
      expect(link.commands.first, [
        0,
        0xA4,
        4,
        0,
        8,
        ...'PAY.APPY'.codeUnits,
        0,
      ]);
    },
  );

  for (final failAt in ['805C000204', '00B2029C17', '00B0940018']) {
    test(
      'confirmed BMAC preserves partial result on loss at $failAt',
      () async {
        final link = _Link()..failAt = failAt;
        final result = await LocalCardReader(link.call).read();
        expect(result!.parsedCard.parserId, CardParserIds.beijingBmac);
        expect(result.parsedCard.info.applicationSerial, '1234567890123456');
        expect(
          result.parsedCard.info.balanceFen,
          failAt == '805C000204' ? isNull : 12345,
        );
        expect(result.readResult.transportFailure, same(_lost));
        expect(result.readResult.readError, isA<ApduTransportException>());
        expect(link.callsAfterFailure, 0);
        if (failAt == '00B2029C17') {
          expect(
            result.readResult.extras.slots['bmac.recharges'],
            hasLength(1),
          );
        }
      },
    );
  }
}

const _lost = TransportFailure(
  kind: TransportFailureKind.tagLost,
  message: 'synthetic BMAC tag loss',
);

class _Link {
  final commands = <List<int>>[];
  String? mutation;
  int balance = 12345;
  bool rejectBalance = false;
  bool badOptional = false;
  String? failAt;
  bool failed = false;
  int callsAfterFailure = 0;

  Future<List<int>> call(List<int> command) async {
    commands.add(List.of(command));
    if (failed) callsAfterFailure++;
    final hex = command
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    if (hex == failAt) {
      failed = true;
      throw _lost;
    }
    switch (hex) {
      case '00A40000023F00':
        return [0x90, 0];
      case '00A40000021001':
        return mutation == 'df' ? [0x6A, 0x82] : [0x90, 0];
      case '00B084003C':
        final raw = List<int>.filled(60, 0);
        raw.setRange(0, 8, [0x12, 0x34, 0x56, 0x78, 0x90, 0x12, 0x34, 0x56]);
        raw.setRange(24, 32, [0x20, 0x20, 0x01, 0x02, 0x20, 0x30, 0x12, 0x31]);
        if (mutation == 'bcd') raw[0] = 0xFA;
        if (mutation == 'date') raw[30] = 0x13;
        if (mutation == 'order') raw[29] = 0x10;
        return [...(mutation == 'short' ? raw.sublist(0, 32) : raw), 0x90, 0];
      case '00B0850020':
        final raw = List<int>.filled(mutation == 'basic' ? 10 : 32, 0);
        raw.setRange(0, 5, [0, 0, 123, 0x12, 0x34]);
        raw.setRange(6, 9, [0, 0, 99]);
        return [...raw, 0x90, 0];
      case '805C000204':
        return rejectBalance
            ? [0x69, 0x85]
            : [0, 0, balance >> 8, balance & 255, 0x90, 0];
      case '00B0940018':
        final raw = List<int>.filled(24, 0);
        raw.setRange(0, 7, [0x24, 0x10, 0x31, 0x12, 0x34, 0x56, 0xAB]);
        raw.setRange(9, 11, [0x34, 0x12]);
        if (badOptional) raw[3] = 0x25;
        return [...raw, 0x90, 0];
    }
    if (command[1] == 0xB2 && command[3] == 0x9C) {
      final raw = List<int>.filled(23, 0);
      raw.setRange(0, 6, [0, 0, 100, 0, 0, 200]);
      raw.setRange(8, 11, [0x24, 0x10, 0x31]);
      raw.setRange(11, 17, [0x30, 0, 0x40, 0, 0x05, 0x70]);
      if (badOptional) raw[9] = 0x1A;
      return [...raw, 0x90, 0];
    }
    return [0x6A, 0x82];
  }
}
