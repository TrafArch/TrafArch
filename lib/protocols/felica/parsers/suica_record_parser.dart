library;

import '../felica_hex.dart';
import '../models/felica_models.dart';
import '../models/felica_card_type.dart';
import '../models/suica_transaction_details.dart';
import 'felica_block_parser.dart';

/// Suica 历史记录布局（块 0..19，块 0 同时提供最新余额）。
///
/// 公开格式：
/// 0 端末種 / 1 処理 / 2 未解释 / 3 出入场状态 / 4-5 日付（16 位打包）/
/// 6-9 类型相关字段 / 10-11 残高（小端）/ 12 未解释 / 13-14 流水号（大端）/
/// 15 区域位。未解释字段只作为原始证据，不推断含义。
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
    this.sequenceOffset = 13,
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
  final SuicaTransactionDetails? suica;

  const SuicaHistoryRecord({
    required this.blockNumber,
    required this.raw,
    this.time,
    this.amountYen,
    this.type,
    this.terminal,
    required this.decoded,
    this.note,
    this.suica,
  });

  String get rawHex => FelicaHex.bytesToHex(raw);

  /// 未写入块：不是有效交易记录，调用方应跳过。
  bool get isBlank => SuicaRecordParser.isBlankHistoryBlock(raw);

  FelicaTransaction toTransaction({int? balanceChangeYen}) => FelicaTransaction(
    time: time,
    amountMinorUnits: amountYen,
    type: type,
    locationCode: terminal,
    rawHex: rawHex,
    decoded: decoded,
    sequence: blockNumber,
    note: note,
    amountIsBalance: true,
    walletKind: FelicaWalletKind.suicaJpy,
    currency: 'JPY',
    suica: suica?.withBalanceChange(balanceChangeYen),
  );
}

/// Suica 记录解析器。
///
/// 字段布局见 [SuicaRecordLayout]（真实卡片格式）：
/// - 余额块（块 0）与历史块同构，残高在 bytes 10-11（小端无符号）；
/// - 日付在 bytes 4-5（16 位打包），物販 / 自販機记录另有时刻 bytes 6-7；
/// - bytes 6-9 在乘车记录中为入出場情報，不按时间解释。
/// 历史记录的金额字段是交易后残高，不是单笔交易额；残高或日期不合法时
/// 保留原始字节并将相关字段置空（不猜测）。
class SuicaRecordParser {
  const SuicaRecordParser({this.layout = SuicaRecordLayout.standard});

  final SuicaRecordLayout layout;

  /// Suica 余额上限 20,000 日元。
  static const int maxPlausibleAmount = 20000;

  /// Empty 090F slots may retain only the byte-3 initialization marker 0x80.
  /// Match that complete block exactly; unknown dates/codes are not evidence
  /// that a record is empty. Keep the generic FeliCa blank rule unchanged.
  static bool isBlankHistoryBlock(List<int> bytes) =>
      FelicaBlockParser.isBlank(bytes) ||
      (FelicaBlockParser.isValidBlock(bytes) &&
          bytes.indexed.every(
            (entry) => (entry.$2 & 0xFF) == (entry.$1 == 3 ? 0x80 : 0),
          ));

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
    if (isBlankHistoryBlock(bytes)) {
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
    final kind = _recordKind(consoleCode, processCode);
    final time = kind == SuicaRecordKind.shopping
        ? _detailTime(bytes, layout.detailOffset)
        : null;

    final balanceValid = balance <= maxPlausibleAmount;
    final decoded = balanceValid && date != null;
    final region = bytes[layout.regionOffset] & 0xFF;
    final details = SuicaTransactionDetails(
      terminalCode: consoleCode,
      processCode: processCode,
      recordSequence:
          ((bytes[layout.sequenceOffset] & 0xFF) << 8) |
          (bytes[layout.sequenceOffset + 1] & 0xFF),
      regionCode: region,
      hasTime: date != null && time != null,
      kind: kind,
      entryStation:
          kind == SuicaRecordKind.rail || kind == SuicaRecordKind.special
          ? _station(bytes, true, region, processCode, consoleCode, kind, date)
          : null,
      exitStation: kind == SuicaRecordKind.rail
          ? _station(bytes, false, region, processCode, consoleCode, kind, date)
          : null,
      busOperatorCode: kind == SuicaRecordKind.bus
          ? ((bytes[layout.detailOffset] & 0xFF) << 8) |
                (bytes[layout.detailOffset + 1] & 0xFF)
          : null,
    );
    final notes = <String>[
      '金额字段为交易后残高，非单笔交易额',
      if (!balanceValid) '残高未通过校验，保留其他字段与原始字节',
      if (date == null) '日期未通过校验，保留其他字段与原始字节',
      if (kind == SuicaRecordKind.shopping && time == null) '购物时刻未通过校验，仅保留有效日期',
    ];

    return SuicaHistoryRecord(
      blockNumber: blockNumber,
      raw: raw,
      time: date == null
          ? null
          : DateTime(
              date.year,
              date.month,
              date.day,
              time?.hour ?? 0,
              time?.minute ?? 0,
            ),
      amountYen: balanceValid ? balance : null,
      type: processCode == 0 ? null : FelicaHex.byteCode(processCode),
      terminal: consoleCode == 0 ? null : FelicaHex.byteCode(consoleCode),
      decoded: decoded,
      note: notes.join('；'),
      suica: details,
    );
  }

  /// Only adjacent valid physical blocks establish a balance change. The card's
  /// counter can skip values between recorded operations, so require forward
  /// order rather than a step of one. No initial balance or wrap is guessed.
  List<FelicaTransaction> toTransactions(List<SuicaHistoryRecord> records) => [
    for (var index = 0; index < records.length; index++)
      if (!records[index].isBlank)
        records[index].toTransaction(
          balanceChangeYen: index + 1 < records.length
              ? _balanceChange(records[index], records[index + 1])
              : null,
        ),
  ];

  static int? _balanceChange(
    SuicaHistoryRecord current,
    SuicaHistoryRecord older,
  ) {
    final currentTime = current.time;
    final olderTime = older.time;
    final currentBalance = current.amountYen;
    final olderBalance = older.amountYen;
    final currentSequence = current.suica?.recordSequence;
    final olderSequence = older.suica?.recordSequence;
    if (current.isBlank ||
        older.isBlank ||
        !current.decoded ||
        !older.decoded ||
        older.blockNumber != current.blockNumber + 1 ||
        currentTime == null ||
        olderTime == null ||
        currentBalance == null ||
        olderBalance == null ||
        currentSequence == null ||
        olderSequence == null ||
        olderSequence <= 0 ||
        currentSequence <= olderSequence) {
      return null;
    }
    // A date-only railway record cannot be ordered by an invented midnight.
    final currentDay = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
    );
    final olderDay = DateTime(olderTime.year, olderTime.month, olderTime.day);
    if (currentDay.isBefore(olderDay)) return null;
    return currentBalance - olderBalance;
  }

  static SuicaRecordKind _recordKind(int terminal, int process) {
    if (!_knownProcesses.contains(process)) return SuicaRecordKind.unknown;
    if (_shoppingProcesses.contains(process)) return SuicaRecordKind.shopping;
    if (_busProcesses.contains(process) ||
        const {0x05, 0x35, 0x36}.contains(terminal)) {
      return SuicaRecordKind.bus;
    }
    if (process == 0x01 || process == 0x13) return SuicaRecordKind.rail;
    return SuicaRecordKind.special;
  }

  SuicaStationCode _station(
    List<int> bytes,
    bool entry,
    int region,
    int process,
    int terminal,
    SuicaRecordKind kind,
    DateTime? date,
  ) {
    final offset = layout.detailOffset + (entry ? 0 : 2);
    final line = bytes[offset] & 0xFF;
    final station = bytes[offset + 1] & 0xFF;
    final areaBits = (region >> (entry ? 6 : 4)) & 3;
    final area = line < 0x80 ? 0 : areaBits + 1;
    var status = SuicaStationStatus.available;
    String? note;
    if (line == 0) {
      status = SuicaStationStatus.notRecorded;
      note = '未记录线路，不匹配站名';
    } else if ((area == 0 && line == 0x56 && station == 0x40) ||
        station == 0xF0) {
      status = SuicaStationStatus.suppressed;
      note = '特殊端点，不匹配站名';
    } else if (process == 0x07 && (terminal == 0x17 || terminal == 0x22)) {
      status = SuicaStationStatus.suppressed;
      note = '简易检票设备发行记录，不匹配站名';
    } else if (area == 0 &&
        line == 1 &&
        station == 6 &&
        (date == null || date.isBefore(DateTime(2020, 3, 14)))) {
      // This key was reused when Takanawa Gateway opened. Preserve the raw
      // key; an old or undated record cannot use today's station name safely.
      status = SuicaStationStatus.suppressed;
      note = '历史站码曾复用，日期不足以匹配现行站名';
    } else if (kind == SuicaRecordKind.special &&
        entry &&
        areaBits == 3 &&
        line >= 1 &&
        line < 16) {
      // This pattern may encode a bus operator. Without a verified operator
      // table, do not mistake its low first byte for an area-zero JR line.
      status = SuicaStationStatus.suppressed;
      note = '可能为公交运营商字段，未确认站点';
    }
    return SuicaStationCode(
      areaCode: area,
      lineCode: line,
      stationCode: station,
      status: status,
      note: note,
    );
  }

  static const _shoppingProcesses = {0x46, 0x49, 0x4A, 0x4B, 0xC6, 0xCB};
  static const _busProcesses = {
    0x0C,
    0x0D,
    0x0F,
    0x17,
    0x18,
    0x1B,
    0x1D,
    0x1F,
    0x23,
  };
  static const _knownProcesses = {
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x0C,
    0x0D,
    0x0F,
    0x11,
    0x13,
    0x14,
    0x15,
    0x17,
    0x18,
    0x1B,
    0x1D,
    0x1F,
    0x23,
    0x33,
    0x46,
    0x48,
    0x49,
    0x4A,
    0x4B,
    0x84,
    0x85,
    0x99,
    0xC6,
    0xCB,
  };

  /// 日付：16 位打包，高 7 位年（2000+）、中间 4 位月、低 5 位日。
  static DateTime? _packedDate(List<int> bytes, int offset) {
    if (offset + 2 > bytes.length) return null;
    final value = ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    final year = 2000 + (value >> 9);
    final month = (value >> 5) & 0x0F;
    final day = value & 0x1F;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// 时刻仅在购物类处理记录中解释（不能仅凭端末码判断）：
  /// 高 5 位时、中间 6 位分。
  static ({int hour, int minute})? _detailTime(List<int> bytes, int offset) {
    if (bytes.length < offset + 2) return null;
    final packed = ((bytes[offset] & 0xFF) << 8) | (bytes[offset + 1] & 0xFF);
    final hour = packed >> 11;
    final minute = (packed >> 5) & 0x3F;
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }
}
