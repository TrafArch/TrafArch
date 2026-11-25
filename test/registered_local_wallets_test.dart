import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/local_card_reader.dart';
import 'package:transit_card_analyzer/features/scan/application/registered_local_wallets.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

const suxin = '00A404000B535558494E2E4444463031';
const suzhouPinVerify = '0020000003123456';
const cika = '00A4040008535A504B5F5A5959';
const tft = '00A404000DD156000015B9ABB9B2D3A6D3C3';
const mf = '00A40000023F00';
const folder1002 = '00A40000021002';
const missing = [0x6A, 0x82];
const ok = [0x90, 0];
const common = '0123456789ABCDEF00009876543210112233445520200101202911300000';
const sale = '0001000000000001230911223344556620261124173859';

void main() {
  test(
    'SUXIN keeps public fields when balance and transactions return 6982',
    () async {
      final publicInfo = LocalHex.hexToBytes(common);
      final stats = List<int>.filled(50, 0)
        ..setRange(8, 12, [0x6A, 0xEF, 0x48, 0x72])
        ..[38] = 40;
      const denied = [0x69, 0x82];
      final fci = [
        0x6F,
        0x30,
        0x84,
        11,
        ...'SUXIN.DDF01'.codeUnits,
        0xA5,
        0x21,
        0x9F,
        0x0C,
        30,
        ...publicInfo,
      ];
      var selected = false;
      final commands = <String>[];
      final scan = await LocalCardReader((bytes) async {
        final cmd = LocalHex.bytesToHex(bytes);
        if (bytes[1] == 0xA4) {
          selected = cmd == suxin;
          return selected ? [...fci, ...ok] : missing;
        }
        if (!selected) return missing;
        if (cmd == suzhouPinVerify) return ok;
        commands.add(cmd);
        return switch (cmd) {
          '00B095001E' => [...publicInfo, ...ok],
          '805C000104' || '00B201C417' => denied,
          '00B201CC32' => [...stats, ...ok],
          _ => fail('Unexpected command in SUXIN: $cmd'),
        };
      }).scan();
      expect(commands, [
        '00B095001E',
        '805C000104',
        '00B201CC32',
        '00B201C417',
      ]);
      final wallet = scan.applications.singleWhere((app) => app.confirmed);
      expect(wallet.appId, 'suzhou_suxin');
      expect(wallet.state, ApplicationProbeState.partial);
      expect(wallet.balanceFen, isNull);
      expect(wallet.trips, isEmpty);
      expect(wallet.records.where((r) => r.hasError).map((r) => r.response), [
        denied,
        denied,
      ]);
      expect(wallet.records.singleWhere((r) => r.label == '0x19 #1').response, [
        ...stats,
        ...ok,
      ]);
      final result = scan.result!.readResult;
      expect(result.info.issueDate, DateTime(2020, 1, 1));
      expect(result.info.expiryDate, DateTime(2029, 11, 30));
      expect(
        result.extras.slots['suxin.discountTime'],
        '2026-11-23T20:33:50+08:00',
      );
      expect(result.extras.slots['suxin.statsCount'], 40);
      expect(wallet.notes, [
        contains('钱包余额 · 6982 安全状态不满足'),
        contains('0x18 #1 · 6982 安全状态不满足'),
      ]);
    },
  );

  test(
    'SUXIN preserves a successful purse read and dated statistics',
    () async {
      final stats = List<int>.filled(50, 0)
        ..setRange(8, 12, [0x6A, 0xC2, 0x00, 0x00]);
      final apps = await readRegisteredLocalWallets((bytes) async {
        return switch (LocalHex.bytesToHex(bytes)) {
          suxin => ok,
          suzhouPinVerify => ok,
          '00B095001E' => [...LocalHex.hexToBytes(common), ...ok],
          '805C000104' => [0, 0, 0x07, 0xD0, ...ok],
          '00B201CC32' => [...stats, ...ok],
          '00B201C417' => [...LocalHex.hexToBytes(sale), ...ok],
          _ => missing,
        };
      });
      final wallet = apps.first;
      expect(wallet.state, ApplicationProbeState.readSucceeded);
      expect(wallet.balanceFen, 2000);
      expect(wallet.trips.single.balanceDelta, -291);
      final slots = (wallet.payload as ReadResult).extras.slots;
      expect(slots['suxin.discountTime'], '2026-11-01T00:00:00+08:00');
      expect(slots['suxin.statsCount'], 0);
    },
  );

  test('SUXIN rejected PIN stops before protected reads', () async {
    final sent = <String>[];
    final apps = await readRegisteredLocalWallets((bytes) async {
      final cmd = LocalHex.bytesToHex(bytes);
      sent.add(cmd);
      return switch (cmd) {
        suxin => ok,
        suzhouPinVerify => [0x63, 0xC2],
        _ => missing,
      };
    });
    final wallet = apps.first;
    expect(wallet.confirmed, isFalse);
    expect(wallet.state, ApplicationProbeState.selectRejected);
    expect(wallet.transportFailure?.kind, TransportFailureKind.rejectedStatus);
    expect(sent.take(2), [suxin, suzhouPinVerify]);
    expect(sent, isNot(contains('00B095001E')));
  });

  test(
    'SUXIN keeps undated and malformed discount records as raw observations',
    () async {
      for (final clock in [
        [0, 0, 0, 0],
        [0x68, 0xBC, 0, 0], // 2026-02-30
        [0x6A, 0xEF, 0x88, 0x72], // hour 24
        [0x6A, 0xEF, 0x4F, 0x32], // minute 60
        [0x6A, 0xEF, 0x48, 0x7C], // second 60
        [0x20, 0x26, 0x11, 0x01], // valid BCD date, invalid packed month
      ]) {
        final stats = List<int>.filled(50, 0)
          ..setRange(8, 12, clock)
          ..[38] = 40;
        final apps = await readRegisteredLocalWallets((bytes) async {
          return switch (LocalHex.bytesToHex(bytes)) {
            suxin => ok,
            suzhouPinVerify => ok,
            '00B201CC32' => [...stats, ...ok],
            _ => missing,
          };
        });
        final wallet = apps.first.payload as ReadResult;
        expect(wallet.extras.slots, isEmpty, reason: 'clock $clock');
        expect(
          wallet.records.singleWhere((r) => r.label == '0x19 #1').response,
          [...stats, ...ok],
        );
      }
    },
  );

  test('two Suzhou applications keep independent identities, expiry, balances and access failures', () async {
    var directory = '';
    final apps = await readRegisteredLocalWallets((bytes) async {
      final cmd = LocalHex.bytesToHex(bytes);
      if (cmd == suzhouPinVerify) return ok;
      if ([suxin, cika, mf].contains(cmd)) {
        directory = cmd;
        return ok;
      }
      if (directory == suxin && cmd == '00B095001E') {
        return [...LocalHex.hexToBytes(common), ...ok];
      }
      if (directory == suxin && cmd == '805C000104') return [0x69, 0x82];
      if (directory == suxin && cmd == '00B201C417') {
        return [...LocalHex.hexToBytes(sale), ...ok];
      }
      if (directory == mf && cmd == '00B086001A') {
        final body = List.filled(26, 0)
          ..[6] = 2
          ..[9] = 0x50;
        return [...body, ...ok];
      }
      if (directory == cika && cmd == '805C000204') return [0, 0, 0, 0, ...ok];
      return missing;
    });
    expect(apps.map((a) => a.appId), ['suzhou_suxin', 'suzhou_cika', 'tft']);
    final wallet = apps[0];
    final info = (wallet.payload as ReadResult).info;
    expect(info.cardNumber, '98765432101122334455');
    expect(info.displayCardNumber, '0123456789ABCDEF');
    expect(wallet.cardNumber, info.displayCardNumber);
    expect(info.expiryDate, DateTime(2029, 11, 30));
    expect(wallet.balanceFen, isNull);
    expect(wallet.state, ApplicationProbeState.partial);
    expect(wallet.transportFailure?.kind, TransportFailureKind.rejectedStatus);
    expect(wallet.trips.single.balanceDelta, -291);
    final counts = (apps[1].payload as ReadResult).info;
    expect(apps[1].state, ApplicationProbeState.readSucceeded);
    expect(counts.observedRemainingTrips, 0);
    expect(
      counts.expiryDate,
      DateTime.utc(1970).add(const Duration(days: 0x5000)),
    );
    expect(apps[1].balanceFen, isNull);
    expect(apps[1].cardNumber, isNull);
    expect(apps[2].state, ApplicationProbeState.selectRejected);
  });

  test(
    'TFT monthly statistics and the 1002 directory retain their own evidence',
    () async {
      var directory = '';
      final apps = await readRegisteredLocalWallets((bytes) async {
        final cmd = LocalHex.bytesToHex(bytes);
        if (cmd == tft || cmd == folder1002) {
          directory = cmd;
          return ok;
        }
        if (directory == tft && cmd == '00B095001E') {
          return [...LocalHex.hexToBytes(common), ...ok];
        }
        if (directory == tft && cmd == '805C000204') {
          return [0, 0, 0x05, 0xDC, ...ok];
        }
        if (directory == tft && cmd == '00B202D433') {
          final stats = List.filled(51, 0)
            ..[38] = 0x12
            ..[40] = 0x03
            ..[41] = 0x84
            ..[46] = 0x26
            ..[47] = 0x11;
          return [...stats, ...ok];
        }
        if (directory == folder1002 && cmd == '00B09A0030') {
          final table = List.filled(48, 0)
            ..setRange(0, 4, [0x19, 0, 0, 1])
            ..setRange(4, 8, [0x20, 0x26, 1, 0x23]);
          return [...table, ...ok];
        }
        if ((directory == tft || directory == folder1002) &&
            cmd == '00B201C417') {
          return [...LocalHex.hexToBytes(sale), ...ok];
        }
        return missing;
      });
      final wallet = apps.last;
      expect(wallet.state, ApplicationProbeState.readSucceeded);
      expect(wallet.balanceFen, 1500);
      final payload = wallet.payload as ReadResult;
      expect(payload.extras.slots['tft.statsMonth'], 202611);
      expect(payload.extras.slots['tft.statsCount'], 18);
      expect(payload.extras.slots['tft.statsAmountFen'], 900);
      expect(payload.extras.slots['tft.monthlyCounts'], {'2026-02': 291});
      expect(wallet.trips.map((t) => t.directory), ['TFT', '1002']);
      expect(wallet.trips.map((t) => t.balanceDelta), [-291, 0]);
      expect(wallet.trips.map((t) => t.tripDelta), [null, -291]);
      expect(wallet.recordCount, 2);
      expect(
        payload.records
            .where((r) => r.commandHex == '00B2018417')
            .map((r) => r.directory),
        ['TFT'],
      );
      expect(
        payload.records
            .where((r) => r.commandHex == '00B2014C17')
            .map((r) => r.directory),
        ['TFT', '1002'],
      );
    },
  );

  test(
    'CIKA failed MF selection never reads 0x06 in the old directory',
    () async {
      final sent = <String>[];
      final apps = await readRegisteredLocalWallets((bytes) async {
        final cmd = LocalHex.bytesToHex(bytes);
        sent.add(cmd);
        return cmd == cika ? ok : missing;
      });
      expect(apps[1].confirmed, isTrue);
      expect(apps[1].state, ApplicationProbeState.partial);
      expect(
        (apps[1].payload as ReadResult).info.observedRemainingTrips,
        isNull,
      );
      expect(sent, isNot(contains('00B086001A')));
      expect(sent, isNot(contains('805C000204')));
    },
  );

  test(
    'tag loss stops all later APDUs and preserves successfully read fields',
    () async {
      final sent = <String>[];
      final apps = await readRegisteredLocalWallets((bytes) async {
        final cmd = LocalHex.bytesToHex(bytes);
        sent.add(cmd);
        if (cmd == suxin) return ok;
        if (cmd == suzhouPinVerify) return ok;
        if (cmd == '00B095001E') return [...LocalHex.hexToBytes(common), ...ok];
        throw const TransportFailure(
          kind: TransportFailureKind.tagLost,
          message: 'removed',
        );
      });
      expect(apps.single.state, ApplicationProbeState.partial);
      expect(apps.single.cardNumber, '0123456789ABCDEF');
      expect(apps.single.transportFailure?.kind, TransportFailureKind.tagLost);
      expect(apps.single.records.last.hasError, isTrue);
      expect(sent, isNot(contains(cika)));
    },
  );

  test(
    'truncated SELECT frame is a transport failure distinct from refusal',
    () async {
      final apps = await readRegisteredLocalWallets((_) async => [0x90]);
      expect(apps.single.state, ApplicationProbeState.failed);
      expect(apps.single.confirmed, isFalse);
      expect(
        apps.single.transportFailure?.kind,
        TransportFailureKind.malformedFrame,
      );
    },
  );

  test(
    'missing optional TFT folder keeps purse success and raw rejection',
    () async {
      final apps = await readRegisteredLocalWallets((bytes) async {
        return switch (LocalHex.bytesToHex(bytes)) {
          tft => ok,
          '00B095001E' => [...LocalHex.hexToBytes(common), ...ok],
          '805C000204' => [0xFF, 0xFF, 0xFF, 0x88, ...ok],
          _ => missing,
        };
      });
      final wallet = apps.last;
      expect(wallet.state, ApplicationProbeState.readSucceeded);
      expect(wallet.balanceFen, -120);
      expect(wallet.records.last.commandHex, folder1002);
      expect(wallet.records.last.response, missing);
    },
  );
}
