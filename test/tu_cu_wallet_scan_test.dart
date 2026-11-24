import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/scan/application/tu_cu_wallet_scan.dart';
import 'package:transit_card_analyzer/protocols/transit/local/apdu_exchange.dart';
import 'package:transit_card_analyzer/protocols/transit/multiapp/application_evidence.dart';
import 'package:transit_card_analyzer/protocols/transport/transport_failure.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_hex.dart';
import 'package:transit_card_analyzer/protocols/transit/local/local_card_models.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_reader.dart';

void main() {
  test(
    'the TU unit rejects foreign DF names and never selects electronic cash',
    () async {
      final commands = <String>[];
      final unit = CommonUnitTu(
        ApduExchange(
          transceive: (cmd) async {
            final hex = LocalHex.bytesToHex(cmd);
            commands.add(hex);
            if (hex.contains('A000000632010105')) {
              return LocalHex.hexToBytes('6F0A8408A0000006320101069000');
            }
            return [0x6A, 0x82];
          },
        ),
      );
      expect(await unit.select(CardInfo(), []), isFalse);
      expect(commands.where((c) => c.contains('A000000632010106')), isEmpty);
    },
  );
  test(
    'TU public observations survive loss at the next identity file',
    () async {
      const raw =
          '01984520FFFFFFFF0101031049304000000000012024010120301231AABB';
      final scan = await TuCuWalletScan(
        ApduExchange(
          transceive: (cmd) async {
            final hex = LocalHex.bytesToHex(cmd);
            if (hex.contains('A000000632010105')) return [0x90, 0];
            if (hex == '00B0950000') return LocalHex.hexToBytes('${raw}9000');
            if (hex == '00B0960000') {
              throw const TransportFailure(
                kind: TransportFailureKind.tagLost,
                message: 'fixture',
              );
            }
            return [0x6A, 0x82];
          },
        ),
      ).read();
      expect(scan.tu.evidence.toJson()['observations'], {'SFI 0x15': raw});
      expect(scan.tu.evidence.state, ApplicationProbeState.partial);
      expect(scan.cu.evidence.state, ApplicationProbeState.notProbed);
    },
  );

  test('TU purse scan cannot claim an electronic cash AID and CU remains independent', () async {
    final commands = <String>[];
    final scan = TuCuWalletScan(
      ApduExchange(
        transceive: (apdu) async {
          final hex = apdu
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .toUpperCase();
          commands.add(hex);
          if (hex.contains('A000000632010106') ||
              hex.contains('A00000000386980701')) {
            return [0x90, 0];
          }
          if (hex == '805C000204') return [0, 0, 0, 5, 0x90, 0];
          return [0x6A, 0x82];
        },
      ),
    );
    final read = await scan.read();
    expect(commands.where((cmd) => cmd.contains('A000000632010106')), isEmpty);
    expect(read.tu.evidence.state, ApplicationProbeState.selectRejected);
    expect(read.cu.evidence.balanceFen, 5);
    expect(read.cu.readResult.info.isTU, isFalse);
    expect(read.cu.card?.selectedAidHex, 'A00000000386980701');
  });

  test(
    'terminal TU selection failure leaves CU unprobed and has no follow-up I/O',
    () async {
      var sends = 0;
      final result = await TuCuWalletScan(
        ApduExchange(
          transceive: (_) async {
            sends++;
            throw const TransportFailure(
              kind: TransportFailureKind.timeout,
              message: 'fixture',
            );
          },
        ),
      ).read();
      expect(sends, 1);
      expect(result.tu.evidence.state, ApplicationProbeState.failed);
      expect(
        result.tu.evidence.transportFailure?.kind,
        TransportFailureKind.timeout,
      );
      expect(result.cu.evidence.state, ApplicationProbeState.notProbed);
    },
  );
}
