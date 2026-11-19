library;

/// The interpretation of bytes 6..9 depends on the processing operation.
enum SuicaRecordKind { rail, bus, shopping, special, unknown }

/// A code may be present without describing a station that can be looked up.
enum SuicaStationStatus { available, notRecorded, suppressed }

class SuicaStationCode {
  final int areaCode;
  final int lineCode;
  final int stationCode;
  final SuicaStationStatus status;
  final String? note;

  const SuicaStationCode({
    required this.areaCode,
    required this.lineCode,
    required this.stationCode,
    this.status = SuicaStationStatus.available,
    this.note,
  });

  bool get canLookup => status == SuicaStationStatus.available;

  String get statusLabel =>
      note ??
      switch (status) {
        SuicaStationStatus.available => '站点原码',
        SuicaStationStatus.notRecorded => '未记录站点',
        SuicaStationStatus.suppressed => '特殊端点，不匹配站名',
      };

  String get codeText => [areaCode, lineCode, stationCode]
      .map((code) => code.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join('/');

  Map<String, Object?> toJson() => {
    'areaCode': areaCode,
    'lineCode': lineCode,
    'stationCode': stationCode,
    'status': status.name,
    'note': note,
  };
}

/// Protocol evidence only; station names belong to the reference-data layer.
class SuicaTransactionDetails {
  final int terminalCode;
  final int processCode;

  /// The card's BE16 counter at bytes 13..14, independent of the block index.
  final int recordSequence;
  final int regionCode;
  final bool hasTime;
  final SuicaRecordKind kind;
  final SuicaStationCode? entryStation;
  final SuicaStationCode? exitStation;
  final int? busOperatorCode;

  /// Current post-transaction balance minus the adjacent older balance.
  /// This is an inferred balance change, not a guaranteed fare.
  final int? balanceChangeYen;

  const SuicaTransactionDetails({
    required this.terminalCode,
    required this.processCode,
    required this.recordSequence,
    required this.regionCode,
    required this.hasTime,
    required this.kind,
    this.entryStation,
    this.exitStation,
    this.busOperatorCode,
    this.balanceChangeYen,
  });

  String get kindLabel => switch (kind) {
    SuicaRecordKind.rail => '铁路',
    SuicaRecordKind.bus => '公交 / 路面电车',
    SuicaRecordKind.shopping => '购物 / 电子货币',
    SuicaRecordKind.special => '特殊处理',
    SuicaRecordKind.unknown => '未知记录',
  };

  String get processLabel =>
      _processLabels[processCode] ?? '未知处理（${_hex(processCode)}）';

  String get terminalLabel =>
      _terminalLabels[terminalCode] ?? '未知终端（${_hex(terminalCode)}）';

  SuicaTransactionDetails withBalanceChange(int? value) =>
      SuicaTransactionDetails(
        terminalCode: terminalCode,
        processCode: processCode,
        recordSequence: recordSequence,
        regionCode: regionCode,
        hasTime: hasTime,
        kind: kind,
        entryStation: entryStation,
        exitStation: exitStation,
        busOperatorCode: busOperatorCode,
        balanceChangeYen: value,
      );

  Map<String, Object?> toJson() => {
    'terminalCode': terminalCode,
    'processCode': processCode,
    'recordSequence': recordSequence,
    'regionCode': regionCode,
    'hasTime': hasTime,
    'kind': kind.name,
    'entryStation': entryStation?.toJson(),
    'exitStation': exitStation?.toJson(),
    'busOperatorCode': busOperatorCode,
    'balanceChangeYen': balanceChangeYen,
  };

  static String _hex(int value) =>
      '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  static const _processLabels = <int, String>{
    0x01: '乘车扣款',
    0x02: '充值',
    0x03: '购买磁票',
    0x04: '补票结算',
    0x05: '补票后进站',
    0x06: '窗口出站',
    0x07: '新卡发行',
    0x08: '窗口扣款',
    0x0C: '路面电车',
    0x0D: '公交（PiTaPa）',
    0x0F: '公交（IruCa）',
    0x11: '补发',
    0x13: '新干线扣款',
    0x14: '进站自动充值',
    0x15: '出站自动充值',
    0x17: '公交自动充值',
    0x18: '公交自动充值',
    0x1B: '公交扣款',
    0x1D: '公交扣款',
    0x1F: '公交充值',
    0x23: '购买活动票',
    0x33: '取消',
    0x46: '购物',
    0x48: '积分充值',
    0x49: '现金存入',
    0x4A: '取消购物',
    0x4B: '入场购物',
    0x84: '其他补票结算',
    0x85: '其他补票后进站',
    0x99: '里程票扣款',
    0xC6: '现金组合购物',
    0xCB: '现金组合入场购物',
  };

  static const _terminalLabels = <int, String>{
    0x03: '补票机',
    0x04: '便携终端',
    0x05: '车载设备',
    0x07: '售卡机',
    0x08: '售票机',
    0x09: '充值机',
    0x12: '售票机',
    0x14: '车站设备',
    0x15: '定期券售票机',
    0x16: '自动检票机',
    0x17: '简易检票机',
    0x18: '车站窗口',
    0x19: '绿色窗口',
    0x1A: '人工检票口',
    0x1B: '移动 FeliCa',
    0x1C: '换乘设备',
    0x1D: '接触式检票机',
    0x1F: '简易充值机',
    0x20: '售卡机',
    0x21: '补票机',
    0x22: '简易检票机',
    0x23: '换乘设备',
    0x24: '车内设备',
    0x34: '售卡机',
    0x35: '车载设备',
    0x36: '车载设备',
    0x46: 'VIEW ALTTE',
    0x48: 'VIEW ALTTE',
    0xC7: '购物终端',
    0xC8: '自动售货机',
  };
}
