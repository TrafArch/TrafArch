import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/registered_local_wallets.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';

const suxin = '00A404000B535558494E2E4444463031';
const cika = '00A4040008535A504B5F5A5959';
const tft = '00A404000DD156000015B9ABB9B2D3A6D3C3';
const mf = '00A40000023F00';
const folder1002 = '00A40000021002';
const missing = [0x6A, 0x82];
const ok = [0x90, 0];
const common = '0123456789ABCDEF00009876543210112233445520200101202911300000';
const sale = '0001000000000001230911223344556620261124173859';

void main() {
  test('two Suzhou applications keep independent identities, expiry, balances and access failures', () async {
    var directory = '';
    final apps = await readRegisteredLocalWallets((bytes) async {
      final cmd = LocalHex.bytesToHex(bytes);
      if ([suxin, cika, mf].contains(cmd)) {
        directory = cmd;
        return ok;
      }
      expect(bytes[1], isNot(0x20));
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
