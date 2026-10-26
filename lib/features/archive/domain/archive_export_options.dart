enum ArchiveExportMode { fullBackup, selectedRecords }

/// Stable JSON column names; labels are only used in the field picker.
enum ArchiveExportField {
  cardName('card_name', '卡片名称'),
  cardNumber('card_number', '卡号'),
  recordType('record_type', '记录类型'),
  source('source', '记录来源'),
  time('time', '交易时间'),
  entryTime('entry_time', '进入时间'),
  exitTime('exit_time', '离开时间'),
  timeBasis('time_basis', '时间依据'),
  entryStation('entry_station', '进入站点'),
  exitStation('exit_station', '离开站点'),
  entryStationCode('entry_station_code', '进入站点编码'),
  exitStationCode('exit_station_code', '离开站点编码'),
  entryLine('entry_line', '进入线路'),
  exitLine('exit_line', '离开线路'),
  entryLineCode('entry_line_code', '进入线路编码'),
  exitLineCode('exit_line_code', '离开线路编码'),
  station('station', '站点（未区分进出）'),
  stationCode('station_code', '站点编码（未区分进出）'),
  line('line', '线路（未区分进出）'),
  lineCode('line_code', '线路编码（未区分进出）'),
  amount('amount', '交易金额'),
  currency('currency', '币种'),
  amountRaw('amount_raw', '原始金额'),
  amountUnit('amount_unit', '原始金额单位'),
  balance('balance', '余额'),
  city('city', '交易城市'),
  terminal('terminal', '终端编码');

  const ArchiveExportField(this.key, this.label);
  final String key;
  final String label;

  static ArchiveExportField? fromKey(String key) {
    for (final field in values) {
      if (field.key == key) return field;
    }
    return null;
  }
}

class ArchiveExportOptions {
  ArchiveExportOptions({
    this.mode = ArchiveExportMode.selectedRecords,
    Set<ArchiveExportField>? fields,
  }) : fields = Set.unmodifiable(fields ?? defaultFields) {
    if (mode == ArchiveExportMode.selectedRecords && this.fields.isEmpty) {
      throw ArgumentError('请至少选择一个导出字段');
    }
  }

  final ArchiveExportMode mode;
  final Set<ArchiveExportField> fields;

  static const defaultFields = {
    ArchiveExportField.cardName,
    ArchiveExportField.recordType,
    ArchiveExportField.source,
    ArchiveExportField.time,
    ArchiveExportField.entryTime,
    ArchiveExportField.exitTime,
    ArchiveExportField.timeBasis,
    ArchiveExportField.entryStation,
    ArchiveExportField.exitStation,
    ArchiveExportField.entryLine,
    ArchiveExportField.exitLine,
    ArchiveExportField.station,
    ArchiveExportField.line,
    ArchiveExportField.amount,
    ArchiveExportField.currency,
    ArchiveExportField.amountRaw,
    ArchiveExportField.amountUnit,
  };
}
