library;

import '../felica_hex.dart';
import '../models/felica_models.dart';
import 'felica_block_parser.dart';

/// Suica 记录字段布局（块 0 与历史块 1..20 同构）。
///
/// 公开格式：
/// 0 端末種 / 1 処理 / 2-3 保留 / 4-5 日付（16 位打包）/
/// 6-9 入出場情報 / 10-11 残高（小端）/ 12-14 連番 / 15 リージョン。
class SuicaRecordLayout {
  final bool decodeFields;
  final int consoleOffset;
  final int processOffset;
  final int dateOffset;
  final int detailOffset;
  final int balanceOffset;
  final int sequenceOffset;
  final int regionOffset;

  const SuicaRecordLayout({
    required this.decodeFields,
    this.consoleOffset = 0,
    this.processOffset = 1,
    this.dateOffset = 4,
    this.detailOffset = 6,
    this.balanceOffset = 10,
    this.sequenceOffset = 12,
    this.regionOffset = 15,
  });

  static const standard = SuicaRecordLayout(decodeFields: true);
  static const rawOnly = SuicaRecordLayout(decodeFields: false);
}

/// 単条 Suica 历史记录解析结果。
class SuicaHistoryRecord {
  final int blockNumber;
  final List<int> raw;
  final DateTime? time;
  final int? amountYen;
  final String? type;
  final String? terminal;
  final bool decoded;
  final String? note;

  const SuicaHistoryRecord({
    required this.blockNumber,
    required this.raw,
    this.time,
    this.amountYen,
    this.type,
    this.terminal,
    required this.decoded,
    this.note,
  });

  String get rawHex => FelicaHex.bytesToHex(raw);

  /// 未写入块：不是有效交易记录，调用方应跳过。
  bool get isBlank => FelicaBlockParser.isBlank(raw);

  FelicaTransaction toTransaction() => FelicaTransaction(
        time: time,
        amountMinorUnits: amountYen,
        type: type,
        locationCode: terminal,
        rawHex: rawHex,
        decoded: decoded,
        sequence: blockNumber,
        note: note,
      );
}

/// Suica 记录解析器。
///
/// 已验证：余额块（块 0）前 2 字节为有符号小端日元金额。
/// 历史记录：类型 1、金额 4-5（有符号小端）、BCD 时间 6-11、
/// 终端 / 站点码 12-13（小端）；任一关键字段不合法即不解析该条。
class SuicaRecordParser {
  const SuicaRecordParser({this.layout = SuicaRecordLayout.standard});

  final SuicaRecordLayout layout;

  /// Suica 余额上限 20,000 日元。
  static const int maxPlausibleAmount = 20000;

  /// 解析余额块（块 0）。
  ///
  /// 余额在 bytes 10-11（小端无符号）；bytes 0-1 是
  /// 「端末種 / 処理」，误读会把 0x12(券売機)、0x07(新規) 拼成 1810。
  int? parseBalanceYen(List<int> block) {
    if (block.length < layout.balanceOffset + 2) return null;
    final value = FelicaHex.readLe16(block, layout.balanceOffset);
    if (value > maxPlausibleAmount) return null;
    return value;
  }

  SuicaHistoryRecord parseBlock({
    required int blockNumber,
    required List<int> bytes,
  }) {
    final raw = List<int>.unmodifiable(bytes);
    if (!FelicaBlockParser.isValidBlock(bytes)) {
      return SuicaHistoryRecord(
        blockNumber: blockNumber,
        raw: raw,
        decoded: false,
        note: '块长度异常：${bytes.length} 字节（期望 16）',
      );
    }
    if (FelicaBlockParser.isBlank(bytes)) {
      return SuicaHistoryRecord(
        blockNumber: blockNumber,
        raw: raw,
        decoded: false,
        note: '记录未写入（空块）',
      );
    }
    if (!layout.decodeFields) {
      return SuicaHistoryRecord(
        blockNumber: blockNumber,
        raw: raw,
        decoded: false,
        note: '记录字段解析未启用，仅保留原始字节',
      );
    }

    final consoleCode = bytes[layout.consoleOffset] & 0xFF;
    final processCode = bytes[layout.processOffset] & 0xFF;
    final balance = FelicaHex.readLe16(bytes, layout.balanceOffset);
    final date = _packedDate(bytes, layout.dateOffset);
    final time = _detailTime(bytes, consoleCode);

    final balanceValid = balance <= maxPlausibleAmount;
    final decoded = balanceValid && date != null;

    return SuicaHistoryRecord(
      blockNumber: blockNumber,
      raw: raw,
      time: date == null
          ? null
          : DateTime(date.year, date.month, date.day, time?.hour ?? 0,
              time?.minute ?? 0),
      amountYen: balanceValid ? balance : null,
      type: processCode == 0 ? null : FelicaHex.byteCode(processCode),
      terminal: consoleCode == 0 ? null : FelicaHex.byteCode(consoleCode),
      decoded: decoded,
      note: decoded ? '金额字段为交易后残高，非单笔交易额' : '残高或日期未通过校验，仅保留原始字节',
    );
  }

  /// 日付：16 位打包，高 7 位年（2000+）、中间 4 位月、低 5 位日。
  static DateTime? _packedDate(List<int> bytes, int offset) {
    if (offset + 2 > bytes.length) return null;
    final packed = FelicaHex.readLe16(bytes, offset - 1) & 0xFFFF;
    // 直接按大端组合：data[offset] << 8 | data[offset + 1]
    final value = ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    final year = 2000 + (value >> 9);
    final month = (value >> 5) & 0x0F;
    final day = value & 0x1F;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// 時刻仅在物販（0xC7）/ 自販機（0xC8）记录中写入 bytes 6-7：
  /// 高 5 位时、中间 6 位分。
  static ({int hour, int minute})? _detailTime(
    List<int> bytes,
    int consoleCode,
  ) {
    if (consoleCode != 0xC7 && consoleCode != 0xC8) return null;
    if (bytes.length < 8) return null;
    final packed = ((bytes[6] & 0xFF) << 8) | (bytes[7] & 0xFF);
    final hour = packed >> 11;
    final minute = (packed >> 5) & 0x3F;
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }
}