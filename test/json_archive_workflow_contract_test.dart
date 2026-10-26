import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/archive/application/archive_records_json.dart';

void main() {
  test('documented JSON is directly iterable by workflow and roundtrips', () {
    final sample = decodeArchiveRecords(
      File('docs/examples/trafarch-records.example.json').readAsStringSync(),
    );
    expect(sample.records, hasLength(2));
    expect(sample.records.first['entry_station_code'], '0001');
    expect(sample.records.first['amount'], '-3.00');
    expect(sample.records.last['amount'], isNull);
    expect(
      sample.records.every(
        (row) => row.values.every((value) => value == null || value is String),
      ),
      isTrue,
    );
    final encoded = encodeArchiveRecords(
      sample.records,
      fields: sample.fields,
      exportedAt: sample.exportedAt,
    );
    final restored = decodeArchiveRecords(encoded);
    expect(restored.records, sample.records);
    expect(restored.fields, sample.fields);
  });
}
