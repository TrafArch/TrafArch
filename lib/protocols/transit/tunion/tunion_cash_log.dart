import '../../iso7816/ber_tlv.dart';
import '../../transport/transport_failure.dart';
import '../local/apdu_exchange.dart';
import '../local/local_hex.dart';
import 'tunion_apdu.dart';
import 'tunion_codec.dart';
import 'tunion_reader.dart';

const _purchaseLogSfi = 0x0B;
const _maxRecords = 0xFE;

/// The cash application's purchase log is distinct from the wallet's 0x18.
/// The FCI gives record coordinates and 9F4F gives the field layout.
class TUnionCashLog {
  const TUnionCashLog({
    this.confirmed = false,
    this.formatHex,
    this.records = const [],
    this.issue,
    this.transportFailure,
  });

  final bool confirmed;
  final String? formatHex;
  final List<TUnionCashLogRecord> records;
  final String? issue;
  final TransportFailure? transportFailure;

  Map<String, Object?> toJson() => {
    'kind': 'tu_cash_log',
    'formatHex': ?formatHex,
    'records': [for (final record in records) record.toJson()],
  };

  static TUnionCashLog? fromPayload(Object? data) {
    if (data is! Map || data['kind'] != 'tu_cash_log') return null;
    final records = data['records'];
    if (records is! List || records.length > _maxRecords) return null;
    final formatHex = data['formatHex'];
    final format = _readHex(formatHex);
    final layout = format == null ? null : _CashLogLayout.parse(format);
    return TUnionCashLog(
      confirmed: true,
      formatHex: formatHex is String ? formatHex : null,
      records: [for (final item in records) ?_restoreRecord(item, layout)],
    );
  }

  static TUnionCashLogRecord? _restoreRecord(
    Object? data,
    _CashLogLayout? layout,
  ) {
    if (data is! Map || data['recordNumber'] is! int) return null;
    final number = data['recordNumber'] as int;
    final rawHex = data['rawHex'];
    final bytes = _readHex(rawHex);
    if (number < 1 || number > _maxRecords || bytes == null) return null;
    return layout?.decode(number, bytes) ??
        TUnionCashLogRecord(recordNumber: number, rawHex: rawHex as String);
  }

  static List<int>? _readHex(Object? data) {
    if (data is! String ||
        data.isEmpty ||
        data.length.isOdd ||
        data.length > 512 ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(data)) {
      return null;
    }
    return LocalHex.hexToBytes(data);
  }
}

class TUnionCashLogRecord {
  const TUnionCashLogRecord({
    required this.recordNumber,
    required this.rawHex,
    this.time,
    this.amountFen,
  });

  final int recordNumber;
  final String rawHex;
  final DateTime? time;

  /// Present only for a decoded purchase with an explicit CNY currency field.
  final int? amountFen;
  bool get isPurchase => time != null && (amountFen ?? 0) > 0;

  Map<String, Object?> toJson() => {
    'recordNumber': recordNumber,
    'rawHex': rawHex,
    'time': ?time?.toIso8601String(),
    'amountFen': ?amountFen,
  };
}

/// Sends only SELECT, GET DATA (log format), and READ RECORD. No payment
/// initialization is needed to read a card's publicly accessible purchase log.
class TUnionCashLogReader {
  const TUnionCashLogReader(this._apdu);

  final ApduExchange _apdu;

  static const _exchangePolicy = ExchangePolicy(
    follow6100: true,
    correct6c00: true,
    correctContinuationLe: true,
    continuationCla: 0,
  );

  Future<TUnionCashLog> read() async {
    var confirmed = false;
    String? formatHex;
    String? issue;
    final records = <TUnionCashLogRecord>[];
    try {
      final selection = await _exchange(
        TUnionApdu.select(CommonUnitTu.cashAid),
      );
      if (!selection.isSuccess) {
        return TUnionCashLog(issue: '电子现金选择失败（${_status(selection)}）');
      }
      final fci = _single(_tlvs(selection.data), '6F');
      final aid = _single(fci?.children ?? const [], '84');
      if (aid == null ||
          TUnionCodec.hexBytes(aid.value) !=
              TUnionCodec.hexBytes(CommonUnitTu.cashAid)) {
        return const TUnionCashLog(issue: '电子现金选择响应缺少匹配的 AID');
      }
      confirmed = true;
      final a5 = _single(fci!.children, 'A5');
      final proprietary = _single(a5?.children ?? const [], 'BF0C');
      final entry = _single([
        ...?a5?.children,
        ...?proprietary?.children,
      ], '9F4D')?.value;
      // SFI 0x0B is the cash purchase log. DF4D/0x0C is a different log.
      if (entry == null ||
          entry.length != 2 ||
          entry.first != _purchaseLogSfi ||
          entry.last == 0) {
        return const TUnionCashLog(
          confirmed: true,
          issue: '卡片未声明有效的电子现金消费日志入口',
        );
      }

      final format = await _exchange(const [0x80, 0xCA, 0x9F, 0x4F, 0x00]);
      final definition = format.isSuccess
          ? _single(_tlvs(format.data), '9F4F')?.value
          : null;
      if (definition != null) formatHex = TUnionCodec.hexBytes(definition);
      final layout = definition == null
          ? null
          : _CashLogLayout.parse(definition);
      if (layout == null) issue = '未取得有效的电子现金日志格式，保留原始记录';

      final count = entry.last.clamp(1, _maxRecords);
      for (var number = 1; number <= count; number++) {
        final response = await _exchange(
          TUnionApdu.readRecord(entry.first, number),
        );
        if (!response.isSuccess) {
          if (response.sw1 != 0x6A || response.sw2 != 0x83) {
            issue = '电子现金消费日志第 $number 条读取失败（${_status(response)}）';
          }
          break;
        }
        final body = response.data;
        if (body.every((byte) => byte == 0 || byte == 0xFF)) continue;
        records.add(
          layout?.decode(number, body) ??
              TUnionCashLogRecord(
                recordNumber: number,
                rawHex: TUnionCodec.hexBytes(body)!,
              ),
        );
      }
      return TUnionCashLog(
        confirmed: true,
        formatHex: formatHex,
        records: List.unmodifiable(records),
        issue: issue,
      );
    } on ApduTransportException catch (error) {
      return TUnionCashLog(
        confirmed: confirmed,
        formatHex: formatHex,
        records: List.unmodifiable(records),
        issue: '电子现金消费日志读取中断',
        transportFailure: error.result.failure,
      );
    }
  }

  Future<ResponseApdu> _exchange(List<int> command) async {
    final result = await _apdu.exchange(command, policy: _exchangePolicy);
    final response = result.response;
    if (result.failure?.stopsSession == true || response == null) {
      throw ApduTransportException(result);
    }
    return response;
  }

  static RawBerTlv? _single(List<RawBerTlv> nodes, String tag) {
    final matches = nodes.where((node) => node.tagHex == tag).toList();
    return matches.length == 1 ? matches.single : null;
  }

  static List<RawBerTlv> _tlvs(List<int> data) {
    final result = BerTlvParser.parse(data);
    return result.accepted ? result.roots : const [];
  }

  static String _status(ResponseApdu response) =>
      '${TUnionCodec.hexByte(response.sw1)}${TUnionCodec.hexByte(response.sw2)}';
}

/// A DOL stores BER tags followed by a one-byte field length and no values.
class _CashLogLayout {
  const _CashLogLayout(this.length, this.fields);

  final int length;
  final Map<String, (int, int)> fields;

  static const _requiredFields = {
    '9A': 3,
    '9F21': 3,
    '9F02': 6,
    '5F2A': 2,
    '9C': 1,
  };

  static _CashLogLayout? parse(List<int> dol) {
    final fields = <String, (int, int)>{};
    var length = 0;
    var i = 0;
    while (i < dol.length) {
      final start = i++;
      if (dol[start] == 0 || dol[start] == 0xFF) return null;
      if ((dol[start] & 0x1F) == 0x1F) {
        while (i < dol.length && (dol[i++] & 0x80) != 0) {}
      }
      if (i >= dol.length) return null;
      final tag = TUnionCodec.hexBytes(dol.sublist(start, i))!;
      final width = dol[i++];
      if (_requiredFields.containsKey(tag)) {
        if (fields.containsKey(tag) || _requiredFields[tag] != width) {
          return null;
        }
        fields[tag] = (length, length + width);
      }
      length += width;
      if (length > 256) return null;
    }
    return fields.length == _requiredFields.length
        ? _CashLogLayout(length, fields)
        : null;
  }

  TUnionCashLogRecord? decode(int recordNumber, List<int> data) {
    if (data.length != length) return null;
    List<int> value(String tag) {
      final (start, end) = fields[tag]!;
      return data.sublist(start, end);
    }

    if (value('9C').single != 0 ||
        TUnionCodec.bcdString(value('5F2A')) != '0156') {
      return null;
    }
    final time = TUnionCodec.parseBcdDateTime([
      0x20,
      ...value('9A'),
      ...value('9F21'),
    ]);
    final amount = TUnionCodec.bcdString(value('9F02'));
    if (time == null || amount == null) return null;
    return TUnionCashLogRecord(
      recordNumber: recordNumber,
      rawHex: TUnionCodec.hexBytes(data)!,
      time: time,
      amountFen: int.parse(amount),
    );
  }
}
