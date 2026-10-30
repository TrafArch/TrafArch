import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';

void main() {
  for (final consume in [false, true]) {
    for (final version in [6, 7, 8, 12]) {
      for (final provenance in [null, false, true]) {
        test('历史余额独立佐证遵守版本与来源 $consume/$version/$provenance', () {
          // Synthetic legacy captures: v6/v7 balances remain readable, but
          // cannot become independent wallet evidence for a new projection.
          final record = ArchiveHistoryRecord(
            kind: ArchiveRecordKind.transaction,
            context: const ArchiveContext(
              currencyCode: 'CNY',
              minorUnitDigits: 2,
            ),
            fields: {
              'time': DateTime(2026, 10, 17, 13, 28).millisecondsSinceEpoch,
              'consume': consume,
              'typeName': consume ? '消费' : '充值',
              'amountFen': consume ? 180 : 1000,
              'balanceAfterFen': consume ? 1280 : 1460,
              'balanceAfterIsRecorded': ?provenance,
            },
            sources: [ArchiveRecordSource('read', 'trips[0]', version, null)],
          );
          final before = Map<String, dynamic>.from(record.fields);
          final projection = presentArchiveTrips([
            record,
          ], onDiagnostics: (_) {});
          expect(
            projection.entries.single.journeyEvent!.walletDeltaFen,
            version >= 8 && provenance == false
                ? (consume ? -180 : 1000)
                : null,
          );
          expect(record.fields, before);
        });
      }
    }
  }
}
