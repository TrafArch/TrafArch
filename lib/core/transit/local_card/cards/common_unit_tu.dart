library;

import '../../../card/card_parser.dart';
import '../../tunion/tunion_apdu.dart';
import '../../tunion/tunion_codec.dart';
import '../../tunion/tunion_models.dart';
import '../../tunion/tunion_process_parser.dart';
import '../apdu_exchange.dart';
import '../local_card_models.dart';

/// 交通联合通用单元（TU）：SELECT + JT/T 978.2 完整识读（新模块主体）。
///
/// 本单元已内联原 `TUnionParser` 的全部读取实现（老模块移除）：
/// - 应用选择：MF 复位 / 电子钱包 + 电子现金双 AID / CLA 0x00, 0x80 双尝试 /
///   1PAY, 2PAY 支付系统目录引导；
/// - 文件读取：0x15 / 0x16 / 0x17 / 0x18 / 0x1A / 0x1E + GET BALANCE，
///   产出 [ParsedCard]（parserId [CardParserIds.tunion]）供既有分析与展示链路；
/// - 同步回填新架构 [CardInfo] 字段与行程流水（[ApduRecord.type] == 2）。
///
/// 读取遵循 JT/T 978.2，逐条 APDU 日志由注入的 transceive 承载，
/// 序列与原 `TUnionParser.parse()` 完全一致（零行为漂移）。
class CommonUnitTu {
  CommonUnitTu(this._apdu, {this.onProgress});

  final ApduExchange _apdu;

  /// 模块内部识读进度（0.0–1.0）：供统一识读流程映射为整体百分比；可空。
  final void Function(double progress)? onProgress;

  void _report(double progress) => onProgress?.call(progress);

  /// 交通部电子钱包应用 AID。
  static const List<int> walletAid = [
    0xA0,
    0x00,
    0x00,
    0x06,
    0x32,
    0x01,
    0x01,
    0x05,
  ];

  /// 交通部电子现金应用 AID。
  static const List<int> cashAid = [
    0xA0,
    0x00,
    0x00,
    0x06,
    0x32,
    0x01,
    0x01,
    0x06,
  ];

  /// 电子钱包应用标准文件 SFI。
  static const _publicFileSfi = 0x15; // 公共应用信息文件
  static const _holderFileSfi = 0x16; // 持卡人基本信息文件
  static const _managementFileSfi = 0x17; // 管理信息文件
  static const _transactionFileSfi = 0x18; // 交易明细文件
  static const _processVarFileSfi = 0x1A; // 公共交通过程信息变长记录文件
  static const _processCycleFileSfi = 0x1E; // 公共交通过程信息循环记录文件

  /// 标准文件与记录长度（字节）。
  static const _publicFileSize = 30;
  static const _holderFileSize = 55;
  static const _managementFileSize = 60;
  static const _transactionRecordSize = 23;

  /// 交易明细为循环记录文件，最多读取 10 条。
  static const _maxTransactionRecords = 10;

  /// 变长记录文件最多 18 条记录（附录 B.2.4 记录号 1~18）。
  static const _maxVarProcessRecords = 18;

  /// 循环记录（0x1E）逐条读取的记录号物理上限（P1 单字节，协议边界）。
  static const _maxCycleRecordNumber = 0xFE;

  /// 循环记录文件（SFI 0x1E）单条记录长度：48 字节定长。
  static const _cycleRecordSize = 0x30;

  /// 变长记录文件（SFI 0x1A）记录号与记录名称对照（附录 B.2.4）。
  static const _varRecordNames = [
    '城市轨道应用信息记录', // 1
    '公共汽电车应用信息记录', // 2
    '城市水上客运应用信息记录', // 3
    '出租汽车应用信息记录', // 4
    '租赁汽车应用信息记录', // 5
    '公共自行车应用信息记录', // 6
    '停车收费应用信息记录', // 7
    '长途客运应用信息记录', // 8
    '轮渡应用信息记录', // 9
    '城际铁路应用信息记录', // 10
    '民航应用信息记录', // 11
    '高速公路收费应用信息记录', // 12
    '优惠信息记录', // 13
    '市郊铁路应用信息记录', // 14（2023 版）
    '公共充电桩应用信息记录', // 15（2023 版）
    '预留记录', // 16
    '预留记录', // 17
    '行业巡检信息记录', // 18（2023 版）
  ];

  /// 单次 READ BINARY 请求的最大长度。
  static const _readBinaryChunk = 64;

  /// 过程记录解析器：0x1E 行程解码与 0x1A 进出站记录挂载点。
  static const _processParser = TUnionProcessParser();

  /// 展示 / 日志用的模块名（与原解析器同名，保持日志连续性）。
  static const String moduleName = '交通联合电子钱包（JT/T 978.2）';

  /// 识读成功后的标准文件解析结果（未识读 / 失败时为 null）。
  ParsedCard? parsedCard;

  /// 最近一次读取到的交通联合卡信息（含应用序列号 / 发卡机构标识）。
  ///
  /// 即使 [read] 因应用序列号校验失败返回 null 也会保留，供上海交通卡
  /// （交通联合版）识别器以卡号前缀 / 发卡机构标识做辅助判定。
  TUnionCardInfo? _lastCardInfo;

  /// 最近一次读取的卡信息（失败时同样保留）；未读取时为 null。
  TUnionCardInfo? get lastCardInfo => _lastCardInfo;

  List<int>? _selectedAid;
  List<int>? _fciDiscretionary;

  /// 已选中的应用 AID；未选择时为 null。
  List<int>? get selectedAid => _selectedAid;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    if (info.isTU) return true;
    if (!await _selectApplication(const [walletAid, cashAid])) return false;
    info.isTU = true;
    info.isCU = false;
    return true;
  }

  /// 完整识读：卡信息 → 余额 → 交易明细 → 过程记录。
  /// 应用未选择时返回 null（由调用方转入下一个卡型模块）。
  Future<ParsedCard?> read(CardInfo info, List<ApduRecord> records) async {
    if (_selectedAid == null) return null;

    final cardInfo = await _readCardInfo();
    _lastCardInfo = cardInfo;
    if (!_isValidTUnionSerial(cardInfo)) {
      info.isTU = false;
      return null;
    }
    _report(0.25); // 卡信息文件读取完成
    final balance = await _readBalance();
    _report(0.4); // 余额读取完成
    final merged = (cardInfo ?? const TUnionCardInfo()).withBalance(
      balance ?? cardInfo?.balanceFen,
    );
    final transactions = await _readTransactions();
    _report(0.6); // 0x18 交易明细读取完成
    final processRecords = await _readTransitProcessRecords();
    _report(1); // 过程记录读取完成

    final parsed = ParsedCard(
      parserId: CardParserIds.tunion,
      parserName: moduleName,
      info: merged,
      transactions: transactions,
      transitProcessRecords: processRecords,
      selectedAidHex: TUnionCodec.hexBytes(_selectedAid ?? const []) ?? '',
    );
    _applyToCardInfo(info, merged);
    _appendTrips(info, records, transactions);
    parsedCard = parsed;
    return parsed;
  }

  /// 校验应用序列号是否符合交通联合 IIN 标准（JT/T 978.2）：
  /// 10 字节 BCD 纯数字，去前导零后以"31"开头；
  /// 不满足时视为非交通联合卡（即使 AID SELECT 成功也拒绝认定）。
  static bool _isValidTUnionSerial(TUnionCardInfo? info) {
    final serial = info?.applicationSerial;
    if (serial == null || serial.isEmpty) return false;
    if (!RegExp(r'^[0-9]+$').hasMatch(serial)) return false;
    final trimmed = serial.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.length >= 8 && trimmed.startsWith('31');
  }

  // ---- 以下为原 TUnionParser 读取实现（整体内联，行为零漂移） ----

  /// 应用选择：先复位选择主文件（MF），失败则忽略；
  /// 然后依次尝试候选 AID（CLA 0x00 / 0x80），
  /// 均失败时经 1PAY / 2PAY 支付系统目录引导后重试。
  Future<bool> _selectApplication(List<List<int>> candidateAids) async {
    await _exchange(TUnionApdu.selectFile(const [0x3F, 0x00]));
    if (await _selectAid(candidateAids)) return true;

    for (final dir in const ['1PAY.SYS.DDF01', '2PAY.SYS.DDF01']) {
      await _exchange(TUnionApdu.select(dir.codeUnits));
      if (await _selectAid(candidateAids)) return true;
    }
    return false;
  }

  Future<bool> _selectAid(List<List<int>> candidateAids) async {
    for (final aid in candidateAids) {
      for (final cla in const [0x00, 0x80]) {
        final resp = await _exchange(TUnionApdu.select(aid, cla: cla));
        if (!_isSuccess(resp)) continue;
        _selectedAid = aid;
        _fciDiscretionary = _extractFciDiscretionary(_stripSw(resp));
        return true;
      }
    }
    return false;
  }

  Future<TUnionCardInfo?> _readCardInfo() async {
    final public =
        await _readTransparentFile(_publicFileSfi, _publicFileSize) ??
        _publicInfoFromFci();
    final holder = await _readTransparentFile(_holderFileSfi, _holderFileSize);
    final management = await _readManagementFile();
    if (public == null && holder == null && management == null) return null;
    return _decodeCardInfo(public, holder, management);
  }

  Future<int?> _readBalance() async {
    // 优先使用标准电子钱包查询。P1=03 保留为原有兼容回退；
    // 它不能替代成功的 P1=00 响应，也不能与该响应相加。
    final standard = await _queryBalance(0x00);
    // Zero is a successful reading too; another response must not replace it.
    if (standard != null) return standard;
    final wallet = await _queryBalance(0x03);
    if (wallet != null && wallet != 0) return wallet;
    return standard ?? wallet;
  }

  Future<int?> _queryBalance(int p1) async {
    for (final cla in const [0x80, 0x00]) {
      final resp = await _exchange(TUnionApdu.getBalance(cla: cla, p1: p1));
      if (!_isSuccess(resp) || resp.length < 6) continue;
      return (resp[0] << 24) | (resp[1] << 16) | (resp[2] << 8) | resp[3];
    }
    return null;
  }

  Future<List<TUnionTransaction>> _readTransactions() async {
    final records = <TUnionTransaction>[];

    final bulk = await _exchange(
      TUnionApdu.readRecord(_transactionFileSfi, 1, mode: 0x05, le: 0x00),
    );
    if (_isSuccess(bulk)) {
      records.addAll(_decodeRecords(_stripSw(bulk)));
    }

    if (records.isEmpty) {
      for (var i = 1; i <= _maxTransactionRecords; i++) {
        final resp = await _exchange(
          TUnionApdu.readRecord(_transactionFileSfi, i, le: 0x00),
        );
        if (!_isSuccess(resp)) break;
        records.addAll(_decodeRecords(_stripSw(resp)));
        if (records.length >= _maxTransactionRecords) break;
      }
    }

    return records.length > _maxTransactionRecords
        ? records.sublist(0, _maxTransactionRecords)
        : records;
  }

  Future<List<TUnionProcessRecord>> _readTransitProcessRecords() async {
    final records = <TUnionProcessRecord>[];
    records.addAll(await _readVarProcessRecords());
    _report(0.8); // 0x1A 变长记录读取完成
    records.addAll(await _readCycleProcessRecords());
    return records;
  }

  Future<List<TUnionProcessRecord>> _readVarProcessRecords() async {
    final out = <TUnionProcessRecord>[];
    List<int>? firstData;
    for (var i = 1; i <= _maxVarProcessRecords; i++) {
      final resp = await _exchange(
        TUnionApdu.readRecord(_processVarFileSfi, i),
      );
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      if (_isBlankRecord(data) && i > 2) continue;
      if (firstData != null && _listEquals(data, firstData)) break;
      firstData ??= data;
      out.add(_buildVarProcessRecord(i, data));
    }
    if (out.isEmpty) {
      final blob = await _readWholeRecordFile(_processVarFileSfi);
      if (blob != null) {
        out.addAll(_splitVarProcessBlob(blob.raw) ?? [blob]);
      }
    }
    return out;
  }

  static TUnionProcessRecord _buildVarProcessRecord(
    int number,
    List<int> data,
  ) => TUnionProcessRecord(
    sfi: _processVarFileSfi,
    recordNumber: number,
    recordName: number <= _varRecordNames.length
        ? _varRecordNames[number - 1]
        : '记录 $number',
    raw: data,
    railTransit: _processParser.parseRailTransit(number, data),
    busTransit: _processParser.parseBusTransit(number, data),
  );

  static List<TUnionProcessRecord>? _splitVarProcessBlob(List<int> blob) {
    if (blob.isNotEmpty && blob[0] == 0x27) {
      return _splitRecordHeaderBlob(blob);
    }
    final out = <TUnionProcessRecord>[];
    var pos = 0;
    while (pos < blob.length && blob[pos] == 0x70) {
      final info = _templateLengthInfo(blob, pos);
      if (info == null) break;
      final (headerLen, contentLen) = info;
      if (contentLen < 0x10) break;
      final end = pos + headerLen + contentLen;
      if (end > blob.length) break;
      out.add(_buildVarProcessRecord(out.length + 1, blob.sublist(pos, end)));
      pos = end;
    }
    return out.isEmpty ? null : out;
  }

  static List<TUnionProcessRecord>? _splitRecordHeaderBlob(List<int> blob) {
    final out = <TUnionProcessRecord>[];
    var pos = 0;
    while (pos + 3 <= blob.length && blob[pos] == 0x27) {
      final contentLength = blob[pos + 2];
      if (contentLength < 0x10) break;
      final end = pos + 3 + contentLength;
      if (end > blob.length) break;
      final number = blob[pos + 1];
      out.add(
        _buildVarProcessRecord(
          number >= 1 && number <= _maxVarProcessRecords
              ? number
              : out.length + 1,
          blob.sublist(pos, end),
        ),
      );
      pos = end;
    }
    return out.isEmpty ? null : out;
  }

  static (int, int)? _templateLengthInfo(List<int> data, int pos) {
    if (pos + 1 >= data.length || data[pos] != 0x70) return null;
    var p = pos + 1;
    var len = data[p++];
    if (len == 0x81) {
      if (p >= data.length) return null;
      len = data[p++];
    } else if (len == 0x82) {
      if (p + 1 >= data.length) return null;
      len = (data[p] << 8) | data[p + 1];
      p += 2;
    } else if (len >= 0x80) {
      return null;
    }
    if (len == 0) return null;
    return (p - pos, len);
  }

  Future<List<TUnionProcessRecord>> _readCycleProcessRecords() async {
    final blob = await _readWholeRecordFile(_processCycleFileSfi);
    if (blob != null) {
      final split = _splitCycleRecords(blob.raw);
      if (split != null) return split;
    }

    final out = <TUnionProcessRecord>[];
    List<int>? firstData;
    for (var i = 1; i <= _maxCycleRecordNumber; i++) {
      final resp = await _exchange(
        TUnionApdu.readRecord(_processCycleFileSfi, i),
      );
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      if (_isBlankRecord(data)) continue;
      if (firstData != null && _listEquals(data, firstData)) break;
      firstData ??= data;
      out.add(
        TUnionProcessRecord(
          sfi: _processCycleFileSfi,
          recordNumber: i,
          recordName: '循环记录 $i',
          raw: data,
          trip: _processParser.parseCycleTrip(data),
        ),
      );
    }
    if (out.isEmpty && blob != null) out.add(blob);
    return out;
  }

  List<TUnionProcessRecord>? _splitCycleRecords(
    List<int> blob, [
    int depth = 0,
  ]) {
    if (depth > 3 || blob.length < _cycleRecordSize) return null;
    // Some cards wrap each record, others wrap the complete cyclic file.
    // Respect TLV boundaries before applying the 48-byte record stride.
    if (blob[0] == 0x70) {
      final out = <TUnionProcessRecord>[];
      var pos = 0;
      while (pos < blob.length) {
        final info = _templateLengthInfo(blob, pos);
        if (info == null) return null;
        final (header, length) = info;
        final end = pos + header + length;
        if (end > blob.length) return null;
        final body = blob.sublist(pos + header, end);
        final records = _splitCycleRecords(body, depth + 1);
        if (records == null) return null;
        for (final record in records) {
          out.add(
            TUnionProcessRecord(
              sfi: _processCycleFileSfi,
              recordNumber: out.length + 1,
              recordName: '循环记录 ${out.length + 1}',
              raw: length == _cycleRecordSize
                  ? blob.sublist(pos, end)
                  : record.raw,
              trip: record.trip,
            ),
          );
        }
        pos = end;
      }
      return out;
    }
    if (blob.length % _cycleRecordSize != 0) return null;
    final out = <TUnionProcessRecord>[];
    var validated = false;
    for (
      var offset = 0;
      offset + _cycleRecordSize <= blob.length;
      offset += _cycleRecordSize
    ) {
      final data = blob.sublist(offset, offset + _cycleRecordSize);
      if (_isBlankRecord(data)) continue;
      final trip = _processParser.parseCycleTrip(data);
      if (!validated) {
        if (trip == null) return null;
        validated = true;
      }
      out.add(
        TUnionProcessRecord(
          sfi: _processCycleFileSfi,
          recordNumber: offset ~/ _cycleRecordSize + 1,
          recordName: '循环记录 ${offset ~/ _cycleRecordSize + 1}',
          raw: data,
          trip: trip,
        ),
      );
    }
    return out;
  }

  Future<TUnionProcessRecord?> _readWholeRecordFile(int sfi) async {
    final resp = await _exchange(
      TUnionApdu.readRecord(sfi, 1, mode: 0x05, le: 0x00),
    );
    if (!_isSuccess(resp)) return null;
    final data = _stripSw(resp);
    if (data.isEmpty || _isBlankRecord(data)) return null;
    return TUnionProcessRecord(
      sfi: sfi,
      recordNumber: 0,
      recordName: '整体数据（未能按记录序号切分）',
      raw: data,
    );
  }

  List<TUnionTransaction> _decodeRecords(List<int> data) {
    if (data.isEmpty) return const [];
    final payload = _unwrapRecordTemplate(data) ?? data;
    final out = <TUnionTransaction>[];
    for (
      var s = 0;
      s + _transactionRecordSize <= payload.length;
      s += _transactionRecordSize
    ) {
      final record = _decodeTransaction(
        payload.sublist(s, s + _transactionRecordSize),
      );
      if (record != null) out.add(record);
    }
    return out;
  }

  Future<List<int>?> _readTransparentFile(int sfi, int length) async {
    final out = <int>[];

    final whole = await _exchange(
      TUnionApdu.readBinary(sfi, offset: 0, le: 0x00),
    );
    if (_isSuccess(whole)) {
      out.addAll(_stripSw(whole));
    }

    while (out.length < length) {
      final want = (length - out.length) > _readBinaryChunk
          ? _readBinaryChunk
          : length - out.length;
      final resp = await _exchange(
        TUnionApdu.readBinary(sfi, offset: out.length, le: want),
      );
      if (!_isSuccess(resp)) break;
      final chunk = _stripSw(resp);
      if (chunk.isEmpty) break;
      if (_matchesFromStart(out, chunk)) break;
      out.addAll(chunk);
      if (chunk.length < want) break;
    }

    if (out.isEmpty) return null;
    final data = out.length > length ? out.sublist(0, length) : out;
    if (data.every((b) => b == 0x00 || b == 0xFF)) return null;
    return data;
  }

  Future<List<int>?> _readManagementFile() async {
    final binary = await _readTransparentFile(
      _managementFileSfi,
      _managementFileSize,
    );
    if (binary != null) return binary;

    for (var i = 1; i <= 10; i++) {
      final resp = await _exchange(
        TUnionApdu.readRecord(_managementFileSfi, i),
      );
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.length >= 11 && data.any((b) => b != 0x00 && b != 0xFF)) {
        return data;
      }
    }
    return null;
  }

  List<int>? _publicInfoFromFci() {
    final data = _fciDiscretionary;
    if (data == null || data.length < 12) return null;
    final info = data.length >= _publicFileSize
        ? data.sublist(0, _publicFileSize)
        : data;
    if (info.every((b) => b == 0x00 || b == 0xFF)) return null;
    return info;
  }

  static List<int>? _extractFciDiscretionary(List<int> fci) {
    if (fci.isEmpty) return null;
    return _findTlvValue(fci, 0x9F0C) ?? _findTlvValue(fci, 0xBF0C);
  }

  static List<int>? _findTlvValue(List<int> data, int wanted) {
    var pos = 0;
    while (pos < data.length) {
      final first = data[pos];
      if (first == 0x00 || first == 0xFF) {
        pos++;
        continue;
      }
      var tag = first;
      pos++;
      if ((first & 0x1F) == 0x1F) {
        while (pos < data.length && (data[pos - 1] & 0x80) != 0) {
          tag = (tag << 8) | data[pos];
          pos++;
          if (tag > 0xFFFF) return null;
        }
      }
      if (pos >= data.length) return null;
      var len = data[pos++];
      if (len == 0x81 && pos < data.length) {
        len = data[pos++];
      } else if (len == 0x82 && pos + 1 < data.length) {
        len = (data[pos] << 8) | data[pos + 1];
        pos += 2;
      } else if (len > 0x82) {
        return null;
      }
      if (pos + len > data.length) return null;
      final value = data.sublist(pos, pos + len);
      if (tag == wanted) return value;
      if ((first & 0x20) != 0) {
        final nested = _findTlvValue(value, wanted);
        if (nested != null) return nested;
      }
      pos += len;
    }
    return null;
  }

  TUnionCardInfo _decodeCardInfo(
    List<int>? public,
    List<int>? holder,
    List<int>? management,
  ) {
    String? issuerId, appTypeId, appVersion, applicationSerial, issuerFci;
    DateTime? effectiveDate, expireDate;
    if (public != null) {
      issuerId = TUnionCodec.hexBytes(_sub(public, 0, 8));
      appTypeId = public.length > 8 ? TUnionCodec.hexByte(public[8]) : null;
      appVersion = public.length > 9 ? TUnionCodec.hexByte(public[9]) : null;
      applicationSerial = TUnionCodec.hexBytes(_sub(public, 10, 10));
      effectiveDate = TUnionCodec.parseBcdDate(_sub(public, 20, 4));
      expireDate = TUnionCodec.parseBcdDate(_sub(public, 24, 4));
      issuerFci = TUnionCodec.hexBytes(_sub(public, 28, 2));
    }

    String? cardTypeId, employeeFlag, holderName, idNumber, idType;
    if (holder != null) {
      cardTypeId = holder.isEmpty ? null : TUnionCodec.hexByte(holder[0]);
      employeeFlag = holder.length > 1 ? TUnionCodec.hexByte(holder[1]) : null;
      holderName = TUnionCodec.hexBytes(_sub(holder, 2, 20));
      idNumber = TUnionCodec.hexBytes(_sub(holder, 22, 32));
      idType = holder.length > 54 ? TUnionCodec.hexByte(holder[54]) : null;
    }

    String? countryCode, provinceCode, cityCode, interopCardType, cardKind;
    if (management != null) {
      countryCode = TUnionCodec.hexBytes(_sub(management, 0, 4));
      provinceCode = TUnionCodec.hexBytes(_sub(management, 4, 2));
      cityCode = TUnionCodec.hexBytes(_sub(management, 6, 2));
      interopCardType = TUnionCodec.hexBytes(_sub(management, 8, 2));
      cardKind = management.length > 10
          ? TUnionCodec.hexByte(management[10])
          : null;
    }

    return TUnionCardInfo(
      issuerId: issuerId,
      appTypeId: appTypeId,
      appVersion: appVersion,
      applicationSerial: applicationSerial,
      effectiveDate: effectiveDate,
      expireDate: expireDate,
      issuerFci: issuerFci,
      cardTypeId: cardTypeId,
      employeeFlag: employeeFlag,
      holderName: holderName,
      idNumber: idNumber,
      idType: idType,
      countryCode: countryCode,
      provinceCode: provinceCode,
      cityCode: cityCode,
      interopCardType: interopCardType,
      cardKind: cardKind,
    );
  }

  TUnionTransaction? _decodeTransaction(List<int> data) {
    final payload = _unwrapRecordTemplate(data) ?? data;
    if (payload.length < _transactionRecordSize) return null;
    if (payload.every((b) => b == 0x00)) return null;
    final date = TUnionCodec.parseBcdDate(payload.sublist(16, 20));
    if (date == null) return null;

    final timeBytes = payload.sublist(20, 23);
    var hour = 0, minute = 0, second = 0;
    if (timeBytes.every(TUnionCodec.isBcdByte)) {
      final t = TUnionCodec.bcdToInt(timeBytes);
      hour = t ~/ 10000;
      minute = (t ~/ 100) % 100;
      second = t % 100;
      if (hour > 23 || minute > 59 || second > 59) {
        hour = minute = second = 0;
      }
    }

    return TUnionTransaction(
      sequence: (payload[0] << 8) | payload[1],
      overdraftLimitFen: (payload[2] << 16) | (payload[3] << 8) | payload[4],
      amountFen:
          (payload[5] << 24) |
          (payload[6] << 16) |
          (payload[7] << 8) |
          payload[8],
      rawType: payload[9],
      terminalId:
          TUnionCodec.bcdString(payload.sublist(10, 16)) ??
          TUnionCodec.hexBytes(payload.sublist(10, 16)) ??
          '',
      time: DateTime(date.year, date.month, date.day, hour, minute, second),
      rawHex: TUnionCodec.hexBytes(payload),
    );
  }

  static List<int>? _unwrapRecordTemplate(List<int> data) {
    if (data.length < 3 || data[0] != 0x70) return null;
    var pos = 1;
    var len = data[pos++];
    if (len == 0x81 && pos < data.length) {
      len = data[pos++];
    } else if (len == 0x82 && pos + 1 < data.length) {
      len = (data[pos] << 8) | data[pos + 1];
      pos += 2;
    }
    if (len < _transactionRecordSize || pos + len > data.length) return null;
    return data.sublist(pos, pos + len);
  }

  /// 收发 APDU：自动处理 6CXX 重发与 61XX 链式响应（支持多段，段数上限 32）。
  Future<List<int>> _exchange(List<int> apdu) async {
    var resp = await _apdu.transceive(apdu);
    if (apdu.isNotEmpty &&
        resp.length >= 2 &&
        resp[resp.length - 2] == 0x6C &&
        resp.last != 0) {
      resp = await _apdu.transceive([
        ...apdu.sublist(0, apdu.length - 1),
        resp.last,
      ]);
    }
    var guard = 0;
    while (resp.length >= 2 &&
        resp[resp.length - 2] == 0x61 &&
        resp.last != 0 &&
        guard++ < 32) {
      final cla = apdu.isNotEmpty ? apdu[0] : 0x00;
      final data = resp.sublist(0, resp.length - 2);
      final chain = await _apdu.transceive(
        TUnionApdu.getResponse(cla, resp.last),
      );
      resp = [...data, ...chain];
      if (chain.isEmpty) break;
    }
    return resp;
  }

  bool _isSuccess(List<int> resp) => ApduSw.isSuccess(resp);

  static List<int> _stripSw(List<int> resp) =>
      resp.length >= 2 ? resp.sublist(0, resp.length - 2) : const [];

  static bool _isBlankRecord(List<int> d) =>
      d.every((b) => b == 0x00 || b == 0xFF);

  static bool _matchesFromStart(List<int> data, List<int> chunk) {
    if (data.length < chunk.length) return false;
    for (var i = 0; i < chunk.length; i++) {
      if (data[i] != chunk[i]) return false;
    }
    return true;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<int> _sub(List<int> d, int start, int len) {
    if (d.length <= start) return const [];
    final end = (start + len).clamp(start, d.length);
    return d.sublist(start, end);
  }

  // ---- 新架构回填（保持不变） ----

  /// 将 JT/T 978.2 解析结果回填新架构卡汇总（不猜测缺失字段）。
  void _applyToCardInfo(CardInfo info, TUnionCardInfo c) {
    if (c.issuerId != null) info.issuerCode = c.issuerId!;
    final number = c.displayCardNumber ?? c.applicationSerial;
    if (number != null) info.cardNumber = number;
    final city = _cityCodeOf(c.cityCode);
    if (city != 0) info.cityCode = city;
    info.balance = c.balanceFen ?? info.balance;
    info.issueDate = c.effectiveDate ?? info.issueDate;
    info.expiryDate = c.expireDate ?? info.expiryDate;
  }

  /// 0x18 交易明细 → 新架构流水（type == 2）。
  void _appendTrips(
    CardInfo info,
    List<ApduRecord> records,
    List<TUnionTransaction> transactions,
  ) {
    for (final t in transactions) {
      records.add(
        ApduRecord()
          ..type = 2
          ..label = 'TU 0x18#${t.sequence}'
          ..timestamp = t.time
          ..terminalHex = t.terminalId
          ..cityCode = info.cityCode
          ..balanceDelta = t.isConsume
              ? -t.amountFen
              : (t.isRecharge ? t.amountFen : 0),
      );
    }
  }

  static int _cityCodeOf(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? int.tryParse(raw, radix: 16) ?? 0;
  }
}
