import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/features/scan/domain/scan_presentation.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';
import 'package:transit_card_analyzer/protocols/transit/tunion/tunion_models.dart';

void main() {
  test('实时与历史按各自发卡地区识别异地且忽略未知地区码', () {
    for (final (home, destination, expected) in <(String?, String?, bool)>[
      ('2900', '1610', true), // 上海卡在太原使用。
      ('3910', '2900', true), // 福州卡在上海使用。
      ('2900', '2900', false),
      (' 2900 ', '2900 ', false),
      (' ab12 ', 'AB12', false),
      (' ab12 ', 'CD34', true),
      for (final unknown in [
        null,
        '',
        '   ',
        '0000',
        'FFFF',
        'ffff',
        '0F0F',
      ]) ...[(unknown, '2900', false), ('2900', unknown, false)],
    ]) {
      final scan = ScanPresentation(
        TransitReadOutcome(
          ParsedCard(
            parserId: CardParserIds.tunion,
            parserName: '异地展示测试',
            selectedAidHex: 'A000000632010105',
            info: TUnionCardInfo(cityCode: home),
            transactions: const [],
          ),
        ),
        KnowledgeBase.empty(),
      );
      final snapshot = CardSessionSnapshot.decode(
        CardSessionSnapshot(cardCityCode: home).encode(),
      )!;
      final fields = <String, dynamic>{
        'typeCode': 6,
        'appTypeCode': 2,
        'cityCode': destination,
        'amountFen': 100,
      };
      final original = jsonEncode(fields);
      final saved = presentArchiveTrips([
        ArchiveHistoryRecord(
          kind: ArchiveRecordKind.process,
          fields: fields,
          cardCityCode: snapshot.cardCityCode,
          context: const ArchiveContext(),
          sources: const [],
        ),
      ], onDiagnostics: (_) {}).entries.single;
      final reason = '发卡地区 $home，刷卡地区 $destination';
      expect(scan.isRemoteUse(destination), expected, reason: reason);
      expect(snapshot.isRemoteUse(destination), expected, reason: reason);
      expect(saved.remote, expected, reason: reason);
      expect(jsonEncode(fields), original);
    }
  });
}
