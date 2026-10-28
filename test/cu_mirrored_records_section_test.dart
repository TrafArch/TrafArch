import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/transit_analysis/cu_transaction_analysis.dart';
import 'package:transit_card_analyzer/features/trips/cu_transaction_list.dart';
import 'package:transit_card_analyzer/features/trips/shanghai_mirrored_records.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_file_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/city_union/city_union_models.dart';

void main() {
  testWidgets(
    'mirrored CU is folded initially and retains details and all source labels',
    (tester) async {
      final view = _view(14);
      await _show(
        tester,
        ShanghaiMirroredRecords(independent: [], mirrored: [view]),
        sourceLabels: {
          view: 'batch-a/cuProjection.transactions[0], batch-b/cuProjection.transactions[1]',
        },
      );
      expect(find.text('城市一卡通应用记录 · 1 条'), findsOneWidget);
      expect(find.textContaining('交易序号 14'), findsNothing);
      await tester.tap(find.text('城市一卡通应用记录 · 1 条'));
      await tester.pumpAndSettle();
      expect(find.textContaining('交易序号 14'), findsOneWidget);
      await tester.tap(find.textContaining('交易序号 14'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('batch-a/cuProjection.transactions[0], batch-b/'),
        findsOneWidget,
      );
      expect(find.text(view.record.rawHex), findsOneWidget);
    },
  );

  testWidgets(
    'unmatched CU remains visible beside a collapsed mirrored group',
    (tester) async {
      await _show(
        tester,
        ShanghaiMirroredRecords(
          independent: [_view(13)],
          mirrored: [_view(14)],
        ),
      );
      expect(find.textContaining('交易序号 13'), findsOneWidget);
      expect(find.textContaining('交易序号 14'), findsNothing);
      expect(find.text('城市一卡通应用记录 · 1 条'), findsOneWidget);
    },
  );

  testWidgets('ordinary CU list has no redundant fold or empty list section', (
    tester,
  ) async {
    await _show(
      tester,
      ShanghaiMirroredRecords(independent: [_view(13)], mirrored: []),
    );
    expect(find.textContaining('交易序号 13'), findsOneWidget);
    expect(find.textContaining('城市一卡通应用记录'), findsNothing);
    await _show(tester, ShanghaiMirroredRecords(independent: [], mirrored: []));
    expect(find.byType(CuTransactionList), findsNothing);
  });
}

Future<void> _show(
  WidgetTester tester,
  ShanghaiMirroredRecords records, {
  Map<CuTransactionView, String> sourceLabels = const {},
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CuApplicationRecords(
          records: records,
          sourceLabels: sourceLabels,
        ),
      ),
    ),
  ),
);

CuTransactionView _view(int sequence) => CuTransactionView(
  record: CityUnionFileParser.parseWalletRecord(
    0x18,
    [
      0,
      sequence,
      0,
      0,
      0,
      0,
      0,
      1,
      0x90,
      9,
      0x20,
      0,
      0x11,
      1,
      0x26,
      0x18,
      0x20,
      0x26,
      0x10,
      0x24,
      0x23,
      4,
      4,
    ],
    kind: CityUnionTransactionKind.consumption,
    recordNumber: 1,
  ),
  transactionTime: DateTime.utc(2026, 10, 24, 15, 4, 4),
  location: ReferenceMatch(ReferenceMatchStatus.unknown, const []),
);
