import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/data/app_database.dart';
import 'package:transit_card_analyzer/features/archive/data/card_repository.dart';

void main() {
  for (final section in ['trips', 'rails', 'buses', 'cycle']) {
    test('$section新显示证据不拆分同一原始记录且保留各批原文来源', () {
      final payloads = [
        _payload(section, referenceVersion: 'v0'),
        _payload(
          section,
          display: const {'line': '旧显示', 'station': '甲站'},
          referenceVersion: 'v1',
        ),
        _payload(
          section,
          display: const {'line': '新显示', 'station': '乙站'},
          referenceVersion: 'v2',
        ),
      ];
      final history = _history(payloads);
      expect(history.records, hasLength(1));
      final record = history.records.single;
      expect(
        record.sources.map((source) => source.batchId),
        containsAll(['batch-0', 'batch-1', 'batch-2']),
      );
      expect(record.sources, hasLength(3));
      expect(record.fields['rawHex'], '000001');
      expect(record.fields['futureRawField'], {'code': '0010'});
      expect(record.fields['capturedDisplay'], {
        'line': '新显示',
        'station': '乙站',
      });
      expect(record.context.applicationId, 'A000000632010105');
      expect(record.context.referencePackages, {
        'TU': {'contentVersion': 'v2'},
      });
      for (final batch in history.batches) {
        final index = int.parse(batch.id.split('-').last);
        expect(batch.decoded.rawJson, payloads[index]);
        expect(batch.decoded.snapshot!.encode(), payloads[index]);
      }
      for (final source in record.sources) {
        final provenance = source.provenance as Map;
        expect((provenance['record'] as Map)['originalSource'], '0001');
        final index = int.parse(source.batchId.split('-').last);
        expect(provenance['referencePackages'], {
          'TU': {'contentVersion': 'v$index'},
        });
      }
    });

    test('$section仍以未知原字段原始码及上下文区分记录', () {
      for (final changed in [
        _payload(section, unknown: '0011'),
        _payload(section, raw: '000002'),
        _payload(section, currency: 'HKD'),
      ]) {
        final history = _history([_payload(section), changed]);
        expect(history.records, hasLength(2));
        expect(
          history.records.every((record) => record.sources.length == 1),
          isTrue,
        );
      }
    });
  }
}

String _payload(
  String section, {
  Map<String, dynamic>? display,
  String unknown = '0010',
  String raw = '000001',
  String currency = 'CNY',
  String referenceVersion = 'v1',
}) => jsonEncode({
  'v': 3,
  'parseVersion': 8,
  'context': {
    'systemId': 'TU',
    'applicationId': 'A000000632010105',
    'currencyCode': currency,
    'minorUnitDigits': 2,
    'clockBasis': 'device-local-card-time-unverified',
    'referencePackages': {
      'TU': {'contentVersion': referenceVersion},
    },
  },
  'trips': [],
  'rails': [],
  'buses': [],
  'cycle': [],
  section: [
    {
      if (section == 'rails' || section == 'buses') 'status': 2,
      if (section == 'trips' || section == 'cycle') ...{
        'time': 1792972800000,
        'amountFen': 300,
        'terminalId': '000000004100',
      },
      if (section == 'trips') ...{
        'sequence': 1,
        'consume': true,
        'typeName': '消费',
      },
      if (section == 'cycle') ...{
        'typeCode': 4,
        'appTypeCode': 2,
        'lineStationCode': '0001000A000100',
        'balanceFen': 9000,
      },
      'rawHex': raw,
      'futureRawField': {'code': unknown},
      'capturedDisplay': ?display,
    },
  ],
  'recordProvenance': {
    '$section[0]': {'originalSource': '0001'},
  },
  'unknownEnvelope': {'raw': '000F'},
});

ArchiveHistoryResult _history(List<String> payloads) => ArchiveHistory.project(
  ArchiveRows(
    card: _card,
    batches: [
      for (var i = 0; i < payloads.length; i++)
        CardReadBatch(
          id: 'batch-$i',
          cardId: _card.id,
          cardFingerprint: _card.cardFingerprint,
          readAt: i + 1,
          parseVersion: 8,
          payloadJson: payloads[i],
        ),
    ],
  ),
);

const _card = SavedCard(
  id: 'display-card',
  cardFingerprint: 'display-fingerprint',
  cardType: 'china_tunion',
  identificationSource: 'test',
  cardNumber: '00004041',
  createdAt: 1,
  updatedAt: 1,
);
