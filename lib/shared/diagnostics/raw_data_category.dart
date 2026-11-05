/// Shared labels for expert raw-data presentation and captured diagnostics.
enum RawDataCategory {
  selection('应用／文件选择'),
  balance('余额查询'),
  publicInfo('公共应用信息（0x15）'),
  holderInfo('持卡人信息（0x16）'),
  managementInfo('管理信息（0x17）'),
  transactions('交易明细（0x18）'),
  file1A('0x1A 文件读取'),
  file1E('0x1E 文件读取'),
  felica('FeliCa 原始通信'),
  other('其他原始通信');

  const RawDataCategory(this.label);
  final String label;
}

enum ProcessDataCategory {
  rail1A('0x1A 城市轨道应用信息'),
  bus1A('0x1A 公共汽电车应用信息'),
  other1A('0x1A 整体／其他变长记录'),
  cycle1E('0x1E 过程循环记录');

  const ProcessDataCategory(this.label);
  final String label;
}

/// Classifies the command's file coordinate, without guessing its application
/// semantics. For example CU 0x1A is not a TU rail-process record.
({RawDataCategory category, int? sfi, int? recordNumber}) classifyRawCommand(
  List<int> command, {
  bool felica = false,
}) {
  if (felica) {
    return (category: RawDataCategory.felica, sfi: null, recordNumber: null);
  }
  final ins = command.length > 1 ? command[1] : null;
  final sfi = command.length >= 4 && ins == 0xB2 && (command[3] & 7) == 4
      ? command[3] >> 3
      : command.length >= 4 && ins == 0xB0 && (command[2] & 0x80) != 0
      ? command[2] & 0x1F
      : null;
  final category = switch (ins) {
    0xA4 => RawDataCategory.selection,
    0x5C => RawDataCategory.balance,
    _ => switch (sfi) {
      0x15 => RawDataCategory.publicInfo,
      0x16 => RawDataCategory.holderInfo,
      0x17 => RawDataCategory.managementInfo,
      0x18 => RawDataCategory.transactions,
      0x1A => RawDataCategory.file1A,
      0x1E => RawDataCategory.file1E,
      _ => RawDataCategory.other,
    },
  };
  return (
    category: category,
    sfi: sfi,
    recordNumber: ins == 0xB2 && command.length >= 4 ? command[2] : null,
  );
}

ProcessDataCategory classifyProcessRecord(int sfi, int recordNumber) =>
    sfi == 0x1E
    ? ProcessDataCategory.cycle1E
    : switch (recordNumber) {
        1 => ProcessDataCategory.rail1A,
        2 => ProcessDataCategory.bus1A,
        _ => ProcessDataCategory.other1A,
      };
