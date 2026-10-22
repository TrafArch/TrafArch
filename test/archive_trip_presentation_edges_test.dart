import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/archive_context.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';

void main() {
  test('空类型名的合法旧交易仍可展示', () {
    final entries = presentArchiveTrips([
      const ArchiveHistoryRecord(
        kind: ArchiveRecordKind.transaction,
        context: ArchiveContext(currencyCode: 'CNY', minorUnitDigits: 2),
        fields: {
          'time': 1,
          'sequence': 1,
          'consume': true,
          'amountFen': 100,
          'terminalId': '',
          'typeName': '',
        },
        sources: [],
      ),
    ], onDiagnostics: (_) {});
    expect(entries.single.info.title, '其他 · 序号 1');
  });

  test('0x1A零值及未知扩展不虚构进出站事件', () {
    final entries = presentArchiveTrips([
      const ArchiveHistoryRecord(
        kind: ArchiveRecordKind.rail,
        context: ArchiveContext(),
        fields: {
          'status': 0,
          'entryTime': null,
          'exitTime': null,
          'entryAmountFen': 0,
          'exitAmountFen': 0,
          'entryStationId': '0000',
          'exitFutureFlag': 'future-extension',
        },
        sources: [],
      ),
    ], onDiagnostics: (_) {});
    expect(entries, hasLength(1));
    expect(entries.single.dateText, '日期未知');
    expect(entries.single.info.title, isNot('进站'));
    expect(entries.single.info.title, isNot('出站'));
  });
}
