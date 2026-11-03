import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_history.dart';
import 'package:transit_card_analyzer/features/archive/domain/card_session_snapshot.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_record_presenter.dart';
import 'package:transit_card_analyzer/features/archive/presentation/archive_trip_presenter.dart';
import 'package:transit_card_analyzer/protocols/transit/card_parser.dart';

// The 48-byte body is the real 1E #3 response from
// transit_card_log_20261103_202948.txt (2026-09-30 17:56:17).
// The old archive envelope below is synthetic: the user supplied an APDU log,
// not the historical JSON that produced the screenshot's excessive fare.
const _rawExit =
    '04221041310603638201000200D70003000E0100000E0600002026093017561722101217221000000000000002BC0000';
const _oldAmount = 234946560;
const _oldBalance = 235274240;
const _context = ArchiveContext(
  systemId: CardParserIds.tunion,
  applicationId: 'A000000632010105',
  currencyCode: 'CNY',
  minorUnitDigits: 2,
  clockBasis: 'device-local-card-time-unverified',
);

void main() {
  test('旧档案详情文本从完整沈阳EP原文展示2.70元和15.50元记录余额', () {
    final capture = _capture();
    final original = jsonEncode(capture.record.fields);

    expect(archiveRecordBalanceFen(capture.record), 1550);
    final text = archiveRecordText(capture.record);
    expect(text, contains('金额 ¥ 2.70'));
    expect(text, contains('记录余额 ¥ 15.50'));
    expect(text, isNot(contains('2349465.60')));
    expect(text, isNot(contains('2352742.40')));
    _expectPreserved(capture, original);
  });

  test('旧档案行程卡派生金额正确而捕获JSON和字段保持原值', () {
    final capture = _capture();
    final original = jsonEncode(capture.record.fields);
    final projection = _present(capture);

    expect(projection.entries.single.info.amountText, '-¥ 2.70');
    expect(projection.entries.single.info.subText, '记录余额 ¥ 15.50');
    expect(projection.journeys.single.amountText, '-¥ 2.70');
    // A recorded balance is not independently verified post-journey money.
    expect(projection.journeys.single.balanceAfterText, isNull);
    expect(capture.record.fields['amountFen'], _oldAmount);
    expect(capture.record.fields['balanceFen'], _oldBalance);
    _expectPreserved(capture, original);
  });

  test('已经按当前口径保存的金额不被重复反转', () {
    final capture = _capture(overrides: {'amountFen': 270, 'balanceFen': 1550});
    final original = jsonEncode(capture.record.fields);

    expect(archiveRecordBalanceFen(capture.record), 1550);
    expect(archiveRecordText(capture.record), contains('金额 ¥ 2.70'));
    expect(_present(capture).entries.single.info.amountText, '-¥ 2.70');
    _expectPreserved(capture, original);
  });

  final conflictingFields = <String, Map<String, dynamic>>{
    '缺少原文': {'rawHex': null},
    '原文被截断': {'rawHex': _rawExit.substring(0, 94)},
    '类型与原文不同': {'typeCode': 0x02},
    '终端与原文不同': {'terminalId': '0000413106036382'},
    '应用分类与原文不同': {'appTypeCode': 0x02},
    '线路站点与原文不同': {'lineStationCode': '000200D8000300'},
    '受理城市与原文不同': {'cityCode': '3310'},
    '收单机构与原文不同': {'acquirerId': '1217221000000001'},
    '卡内民用时间与原文不同': {
      'capturedTimes': {'time': _civil('2026-09-30T17:56:18.000')},
    },
    '捕获时间和民用时间均与原文不同': {
      'time': DateTime.utc(2026, 9, 30, 17, 56, 18).millisecondsSinceEpoch,
      'capturedTimes': {'time': _civil('2026-09-30T17:56:18.000')},
    },
    '金额已被独立修改': {'amountFen': 12345},
    '余额已被独立修改': {'balanceFen': 54321},
    '捕获时间戳与民用时间冲突': {
      'time': DateTime.utc(2026, 9, 30, 17, 56, 18).millisecondsSinceEpoch,
    },
    '民用时间缺少换算依据': {
      'capturedTimes': {
        'time': {
          'civil': '2026-09-30T17:56:17.000',
          'basis': 'parser-local-unverified',
        },
      },
    },
    '民用时间自称UTC但同时声明本地': {
      'capturedTimes': {
        'time': {..._civil('2026-09-30T17:56:17.000Z')},
      },
    },
    '换算偏移与时间戳冲突': {
      'capturedTimes': {
        'time': {
          ..._civil('2026-09-30T17:56:17.000'),
          'conversionOffsetMinutes': 480,
        },
      },
    },
  };
  for (final conflict in conflictingFields.entries) {
    test('${conflict.key}时保留捕获金额而不借原文覆盖', () {
      _expectCapturedMoney(_capture(overrides: conflict.value));
    });
  }

  for (final system in [CardParserIds.cityUnion, 'unknown', null]) {
    test('非TU或未知系统$system不采用TU派生金额', () {
      _expectCapturedMoney(_capture(context: _withContext(systemId: system)));
    });
  }
  for (final currency in ['HKD', 'MOP', null]) {
    test('币种$currency不采用人民币EP派生金额', () {
      _expectCapturedMoney(_capture(context: _withContext(currency: currency)));
    });
  }
  for (final digits in [0, 3, null]) {
    test('金额精度$digits不采用分单位EP派生金额', () {
      _expectCapturedMoney(_capture(context: _withContext(digits: digits)));
    });
  }
  test('其他钱包AID不采用交通联合派生金额', () {
    _expectCapturedMoney(
      _capture(context: _withContext(applicationId: 'A00000000386980701')),
    );
  });

  test('同城已核实EC类型16记录仍按原大端金额展示', () {
    _expectCapturedMoney(
      _capture(
        overrides: {
          'typeCode': 0x16,
          'terminalId': '2210413106034014',
          'lineStationCode': '00010079000300',
          'amountFen': 450,
          'balanceFen': 840,
          'time': DateTime.utc(2026, 10, 25, 14, 1, 42).millisecondsSinceEpoch,
          'capturedTimes': {'time': _civil('2026-10-25T14:01:42.000')},
          'rawHex': '1622104131060340140100010079000300000001C2000003482026102514014222101217221000000000000002BC0000',
        },
      ),
    );
  });

  test('其他城市已核实EP轨道记录仍按大端金额和余额展示', () {
    _expectCapturedMoney(
      _capture(
        overrides: {
          'terminalId': '0000413106146227',
          'lineStationCode': '00010015000000',
          'amountFen': 0,
          'balanceFen': 1500,
          'time': DateTime.utc(2026, 10, 29, 18, 1, 10).millisecondsSinceEpoch,
          'capturedTimes': {'time': _civil('2026-10-29T18:01:10.000')},
          'cityCode': '3310',
          'acquirerId': '01663310FFFFFFFF',
          'rawHex': '040000413106146227010001001500000000000000000005DC20261029180110331001663310FFFFFFFF000000000000',
        },
      ),
    );
  });
}

ArchiveContext _withContext({
  String? systemId = CardParserIds.tunion,
  String? applicationId = 'A000000632010105',
  String? currency = 'CNY',
  int? digits = 2,
}) => ArchiveContext(
  systemId: systemId,
  applicationId: applicationId,
  currencyCode: currency,
  minorUnitDigits: digits,
  clockBasis: _context.clockBasis,
);

Map<String, dynamic> _civil(String value) => {
  'civil': value,
  'conversionOffsetMinutes': 0,
  'basis': 'parser-local-unverified',
};

typedef _Capture = ({
  String payload,
  ArchiveBatchEvidence batch,
  ArchiveHistoryRecord record,
});

_Capture _capture({
  Map<String, dynamic> overrides = const {},
  ArchiveContext context = _context,
}) {
  final fields = <String, dynamic>{
    'typeCode': 0x04,
    'terminalId': '2210413106036382',
    'appTypeCode': 0x01,
    'lineStationCode': '000200D7000300',
    'amountFen': _oldAmount,
    'balanceFen': _oldBalance,
    'time': DateTime.utc(2026, 9, 30, 17, 56, 17).millisecondsSinceEpoch,
    'capturedTimes': {'time': _civil('2026-09-30T17:56:17.000')},
    'cityCode': '2210',
    'acquirerId': '1217221000000000',
    'rawHex': _rawExit,
    'syntheticUnknownField': {'retain': true},
    ...overrides,
  };
  final payload =
      '  ${jsonEncode({
        'v': 3,
        'parseVersion': 11,
        'cityCode': '3310',
        'context': context.toJson(),
        'trips': [],
        'rails': [],
        'buses': [],
        'cycle': [fields],
        'rawEvidence': [],
        'recordProvenance': {},
        'syntheticEvidence': 'legacy money display; not customer archive JSON',
      })}\n';
  final decoded = CardSessionSnapshot.decodeResult(payload);
  final batch = ArchiveBatchEvidence(
    id: 'synthetic-old-capture',
    readAt: DateTime.utc(2026, 11, 3).millisecondsSinceEpoch,
    storedParseVersion: 11,
    origin: 'synthetic-regression-test',
    timeSource: 'synthetic',
    decoded: decoded,
    issues: decoded.issues,
  );
  final record = ArchiveHistory.projectRecords([batch]).single;
  return (payload: payload, batch: batch, record: record);
}

ArchiveTripProjection _present(_Capture capture) => presentArchiveTrips(
  [capture.record],
  batches: [capture.batch],
  onDiagnostics: (_) {},
);

void _expectCapturedMoney(_Capture capture) {
  final original = jsonEncode(capture.record.fields);
  final fields = capture.record.fields;
  final amount = fields['amountFen'] as int;
  final balance = fields['balanceFen'] as int;
  final context = capture.record.context;

  expect(archiveRecordBalanceFen(capture.record), balance);
  final text = archiveRecordText(capture.record);
  expect(text, contains('金额 ${context.formatAmount(amount)}'));
  expect(text, contains('记录余额 ${context.formatAmount(balance)}'));
  final entry = _present(capture).entries.single;
  expect(entry.info.amountText, contains(context.formatAmount(amount)));
  expect(entry.info.subText, contains(context.formatAmount(balance)));
  _expectPreserved(capture, original);
}

void _expectPreserved(_Capture capture, String originalFields) {
  expect(jsonEncode(capture.record.fields), originalFields);
  expect(capture.batch.decoded.rawJson, capture.payload);
  expect(capture.batch.decoded.snapshot!.encode(), capture.payload);
}
