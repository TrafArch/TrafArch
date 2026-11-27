import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/recovery/capture_read_result.dart';
import 'package:transit_card_analyzer/features/scan/application/card_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/application/parser_diagnostic_capture.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/protocols/felica/models/amusement_ic_data.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_card_type.dart';
import 'package:transit_card_analyzer/protocols/felica/models/felica_models.dart';

// Synthetic code and identifiers only; these do not belong to a physical card.
const _accessCode = '50101234567890123456';
const _idm = '012E000000000001';
const _complete = AmusementIcData(
  accessCode: _accessCode,
  issuer: 'SEGA Aime',
  dataFormatCode: 0x0078,
  spad0Hex: '00000000000000000000000000000000',
  idBlockHex: '01234567890123456789000000000000',
);
const _partial = AmusementIcData(
  dataFormatCode: 99,
  spad0Hex: '00000000000000000000000000000000',
  note: '未知数据格式，尚未解析 Access Code。',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic identity preserves access code without making IDm a card number', () {
    final captured = jsonDecode(
      jsonEncode(captureCardInfo(FelicaReadOutcome(_card()))),
    ) as Map;
    expect(captured['accessCode'], _accessCode);
    expect(captured['issuer'], 'SEGA Aime');
    expect(captured['idm'], _idm);
    expect(captured['cardNumber'], isNull);
    final partial = captureCardInfo(FelicaReadOutcome(_card(data: _partial)));
    expect(partial['accessCode'], isNull);
    expect(partial['cardNumber'], isNull);
    expect(partial['idm'], _idm);
  });

  test('parser diagnostics and recovery JSON freeze access code and original block evidence', () {
    final outcome = FelicaReadOutcome(_card());
    final records =
        jsonDecode(jsonEncode(captureParserRecords(outcome).toList())) as List;
    final record = records.cast<Map>().singleWhere(
      (row) => row['fieldCategory'] == 'amusementIc',
    );
    expect(record['parserId'], 'felica.amusementIc');
    final fields = record['fields'] as Map;
    expect(fields['accessCode'], _accessCode);
    expect(fields['issuer'], 'SEGA Aime');
    expect(fields['dataFormatCode'], 0x0078);
    expect(fields['idBlockHex'], '01234567890123456789000000000000');
    final capture = jsonDecode(jsonEncode(captureReadResult(outcome))) as Map;
    expect(capture['amusementIc'], fields);
    expect(capture['idm'], _idm);
    expect(capture['wallets'], isEmpty);
    expect(capture['transactions'], isEmpty);

    final partial = jsonDecode(
      jsonEncode(captureReadResult(FelicaReadOutcome(_card(data: _partial)))),
    ) as Map;
    expect((partial['amusementIc'] as Map)['accessCode'], isNull);
    expect((partial['amusementIc'] as Map)['dataFormatCode'], 99);
    expect((partial['amusementIc'] as Map)['note'], _partial.note);
  });
}

FelicaScanResult _card({AmusementIcData? data = _complete}) => FelicaScanResult(
  cardType: 'amusementIc',
  displayName: 'Amusement IC',
  cardProductType: FelicaCardType.amusementIc,
  idm: _idm,
  scannedAt: DateTime(2026, 11, 16, 12),
  amusementIc: data,
  statuses: [
    FelicaReadStatus(
      stage: 'Amusement IC',
      state: data?.accessCode == null
          ? FelicaReadState.partial
          : FelicaReadState.success,
      message: data?.accessCode == null ? '读取未完成' : '读取成功',
    ),
  ],
);
