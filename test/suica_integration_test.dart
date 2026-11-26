import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/protocols/felica/felica.dart';

FelicaReadOutcome _outcome() => FelicaReadOutcome(
  FelicaScanResult(
    cardType: 'suica',
    displayName: 'Suica',
    cardProductType: FelicaCardType.suica,
    scannedAt: DateTime(2025, 10, 20),
    transactions: [
      const SuicaRecordParser()
          .parseBlock(
            blockNumber: 0,
            bytes: [0x16, 1, 0, 0, 0x33, 0x54, 1, 1, 1, 3, 0x84, 3, 0, 0, 2, 0],
          )
          .toTransaction(),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Suica decoded evidence preserves station and date precision in recovery and diagnostics', () {
    final outcome = _outcome();
    final captured =
        (captureReadResult(outcome)['transactions'] as List).single as Map;
    expect(captured['suica'], isA<Map>());
    expect((captured['suica'] as Map)['hasTime'], isFalse);
    final record = captureParserRecords(outcome)
        .singleWhere((row) => row['fieldCategory'] == 'transactions');
    expect((record['fields'] as Map)['suica'], captured['suica']);
  });
}
