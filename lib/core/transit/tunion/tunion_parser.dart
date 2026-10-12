import 'tunion_apdu.dart';
import 'tunion_codec.dart';
import 'tunion_models.dart';
import 'tunion_process_parser.dart';
import '../../card/card_parser.dart';

/// 交通联合（T-Union）电子钱包解析器。
///
/// 读取与解码遵循 JT/T 978.2《城市公共交通IC卡技术规范 第2部分：卡片》，
/// 读取流程对齐主流读卡工具（NFCard）实测可用序列，兼容多发卡方实现差异。
///
/// 应用选择（附录 C 应用指令）：
/// - 先选择主文件（MF 3F00）复位（失败忽略）；
/// - 交通部电子钱包 AID：A000000632010105（优先）；
/// - 交通部电子现金 AID：A000000632010106（兜底）；
/// - 均失败时经 1PAY / 2PAY 支付系统目录引导后重试。
///
/// 电子钱包标准文件（附录 B 应用数据与文件）：
/// - SFI 0x15 公共应用信息文件（二进制，30 字节）；
/// - SFI 0x16 持卡人基本信息文件（二进制，55 字节）；
/// - SFI 0x17 管理信息文件（二进制，60 字节，含城市代码）；
/// - SFI 0x18 交易明细文件（循环记录，23 字节/记录，最多 10 条）；
/// - SFI 0x1A 公共交通过程信息变长记录文件（记录 1 城市轨道应用信息记录、
///   记录 2 公共汽电车应用信息记录、…、记录 13 优惠信息记录）；
/// - SFI 0x1E 公共交通过程信息循环记录文件（定长循环记录，最近乘车过程信息）。
///
/// 电子钱包交易指令：
/// - READ BINARY：Le=0x00 整体读取，不足时按偏移补读；
/// - GET BALANCE（80 5C xx 02 04）：P1=0x00 / 0x03 双尝试（4 字节大端，单位：分）；
/// - READ RECORD：先整体读取（P2=(SFI<<3)|0x05），失败时逐条读取（P2=(SFI<<3)|0x04）；
///   批量数据按定长切分：0x18 交易明细 23 字节/条，0x1E 循环记录 48 字节/条。
///
/// 职责边界（读取层）：
/// - 只负责应用选择、文件定位与原始字节读取，不做字段语义解码；
///   过程记录解码由 TUnionProcessParser 承担，字节工具由 TUnionCodec 提供；
/// - 解码失败时保留原始数据（TUnionProcessRecord.raw），不猜测字段值。
class TUnionParser implements CardParser {
  /// 交通部电子钱包应用 AID。
  static const List<int> walletAid = [
    0xA0, 0x00, 0x00, 0x06, 0x32, 0x01, 0x01, 0x05,
  ];

  /// 交通部电子现金应用 AID。
  static const List<int> cashAid = [
    0xA0, 0x00, 0x00, 0x06, 0x32, 0x01, 0x01, 0x06,
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

  /// 循环记录（0x1E）逐条读取的记录号物理上限：READ RECORD 的 P1 为
  /// 单字节记录号（0x01~0xFE），仅作协议边界防止读取失控；
  /// 0x1E 文件条数由卡片填充决定，不设业务条数上限。
  static const _maxCycleRecordNumber = 0xFE;

  /// 循环记录文件（SFI 0x1E）单条记录长度：48 字节定长。
  static const _cycleRecordSize = 0x30;

  /// 变长记录文件（SFI 0x1A）记录号与记录名称对照（附录 B.2.4；
  /// 记录 14/15/18 为 2023 版由原预留记录更新的新应用类型）。
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

  final Future<List<int>> Function(List<int> apdu) _transceive;

  TUnionParser(this._transceive);

  List<int>? _selectedAid;
  List<int>? _fciDiscretionary;

  /// 已选中的应用 AID；未选择时为 null。
  List<int>? get selectedAid => _selectedAid;

  /// SELECT 响应（FCI）中的发卡机构自定义数据（9F0C / BF0C）。
  List<int>? get fciDiscretionaryData => _fciDiscretionary;

  @override
  String get parserId => CardParserIds.tunion;

  @override
  String get parserName => '交通联合电子钱包（JT/T 978.2）';

  /// CardParser 统一入口：应用选择 → 标准文件 → 余额 → 交易明细。
  /// 应用选择失败（非交通联合卡）时返回 null。
  @override
  Future<ParsedCard?> parse() async {
    final selected = await selectApplication(const [walletAid, cashAid]);
    if (!selected) return null;
    final info = await readCardInfo();
    final balance = await readBalance();
    final merged = (info ?? const TUnionCardInfo())
        .withBalance(balance ?? info?.balanceFen);
    final transactions = await readTransactions();
    final processRecords = await readTransitProcessRecords();
    return ParsedCard(
      parserId: parserId,
      parserName: parserName,
      info: merged,
      transactions: transactions,
      transitProcessRecords: processRecords,
      selectedAidHex: TUnionCodec.hexBytes(_selectedAid ?? const []) ?? '',
    );
  }

  /// 应用选择：先复位选择主文件（MF），失败则忽略；
  /// 然后依次尝试候选 AID（CLA 0x00 / 0x80），
  /// 均失败时经 1PAY / 2PAY 支付系统目录引导后重试。
  Future<bool> selectApplication(List<List<int>> candidateAids) async {
    // 部分卡片需要从主文件开始选择，否则后续 AID 选择失败
    await _exchange(TUnionApdu.selectFile(const [0x3F, 0x00]));
    if (await _selectAid(candidateAids)) return true;

    // 目录引导：选择 1PAY/2PAY 支付系统目录后再重试应用选择
    for (final dir in const ['1PAY.SYS.DDF01', '2PAY.SYS.DDF01']) {
      await _exchange(TUnionApdu.select(dir.codeUnits));
      if (await _selectAid(candidateAids)) return true;
    }
    return false;
  }

  /// 依次尝试候选 AID，命中即解析 FCI 自定义数据。
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

  /// 读取并解码电子钱包标准文件（SFI 0x15 / 0x16 / 0x17）。
  Future<TUnionCardInfo?> readCardInfo() async {
    final public =
        await _readTransparentFile(_publicFileSfi, _publicFileSize) ??
            _publicInfoFromFci();
    final holder = await _readTransparentFile(_holderFileSfi, _holderFileSize);
    final management = await _readManagementFile();
    if (public == null && holder == null && management == null) return null;
    return _decodeCardInfo(public, holder, management);
  }

  /// GET BALANCE：读取电子钱包余额，返回 4 字节大端金额（分）。
  /// 依次尝试 P1 = 0x03（T-Union 电子钱包主流实现）与 0x00（标准），
  /// 优先返回非零值。
  Future<int?> readBalance() async {
    final wallet = await _queryBalance(0x03);
    if (wallet != null && wallet != 0) return wallet;
    final standard = await _queryBalance(0x00);
    if (standard != null && standard != 0) return standard;
    return wallet ?? standard;
  }

  Future<int?> _queryBalance(int p1) async {
    for (final cla in const [0x80, 0x00]) {
      final resp = await _exchange(TUnionApdu.getBalance(cla: cla, p1: p1));
      if (!_isSuccess(resp) || resp.length < 6) continue;
      return (resp[0] << 24) | (resp[1] << 16) | (resp[2] << 8) | resp[3];
    }
    return null;
  }

  /// 读取交易明细文件（SFI 0x18 循环记录），最多 10 条。
  /// 先整体读取（P2 = (SFI<<3)|0x05，从记录 1 读到文件末尾，
  /// 响应为多条 23 字节记录拼接），失败时逐条读取（P2 = (SFI<<3)|0x04）。
  Future<List<TUnionTransaction>> readTransactions() async {
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

  /// 读取公共交通过程信息记录（附录 B.2.4 / B.2.5）：
  /// - SFI 0x1A 变长记录文件：逐条 READ RECORD（P2 = (0x1A<<3)|0x04 = 0xD4），
  ///   记录 1/2 即城市轨道/公共汽电车应用信息记录；
  /// - SFI 0x1E 循环记录文件：整体读取（P2 = 0xF5）按 48 字节定长切分，
  ///   不可用时回退逐条 READ RECORD（P2 = 0xF4），读至记录未找到（6A83）为止；
  /// - 逐条读取全部失败时，按“整体读取”（P2 = (SFI<<3)|0x05）兜底展示原始数据。
  Future<List<TUnionProcessRecord>> readTransitProcessRecords() async {
    final records = <TUnionProcessRecord>[];
    records.addAll(await _readVarProcessRecords());
    records.addAll(await _readCycleProcessRecords());
    return records;
  }

  Future<List<TUnionProcessRecord>> _readVarProcessRecords() async {
    final out = <TUnionProcessRecord>[];
    List<int>? firstData;
    for (var i = 1; i <= _maxVarProcessRecords; i++) {
      final resp =
          await _exchange(TUnionApdu.readRecord(_processVarFileSfi, i));
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      // 记录 1 / 2（城市轨道、公共汽电车应用信息记录）即使为初始值（全 0）
      // 也保留，按字段视图展示初始值；其余记录未写入时跳过继续读取。
      if (_isBlankRecord(data) && i > 2) continue;
      // 部分卡片忽略记录号，每次读取都返回同一条记录：读到与首个非空
      // 记录一致的内容时停止，避免重复条目与记录号错位的误解析。
      if (firstData != null && _listEquals(data, firstData)) break;
      firstData ??= data;
      out.add(_buildVarProcessRecord(i, data));
    }
    if (out.isEmpty) {
      final blob = await _readWholeRecordFile(_processVarFileSfi);
      if (blob != null) {
        // 整体数据自记录 1 读起：70 模板拼接或 27 记录头完整格式拼接时按
        // 条切分并解析，记录 1/2 可直接进入字段视图；无法切分时保持整体
        // 兜底，由展示层按记录 1 前缀解析（记录 2 起始位置无法定位，不猜测）。
        out.addAll(_splitVarProcessBlob(blob.raw) ?? [blob]);
      }
    }
    return out;
  }

  /// 构造 0x1A 变长记录条目（挂载记录 1/2 的字段解析结果）。
  static TUnionProcessRecord _buildVarProcessRecord(
          int number, List<int> data) =>
      TUnionProcessRecord(
        sfi: _processVarFileSfi,
        recordNumber: number,
        recordName: number <= _varRecordNames.length
            ? _varRecordNames[number - 1]
            : '记录 $number',
        raw: data,
        railTransit: _processParser.parseRailTransit(number, data),
        busTransit: _processParser.parseBusTransit(number, data),
      );

  /// 将 0x1A 整体读取数据切分为独立记录条目。
  ///
  /// 支持两种真机整体布局：
  /// - 27 记录头完整格式连续拼接：交 [_splitRecordHeaderBlob] 按记录头
  ///   自述长度切分；
  /// - 连续的 70 记录模板（含 0x81/0x82 扩展长度）：按模板边界切分，
  ///   声明长度不完整（记录被截断）或非模板的尾部残留丢弃；
  /// 两种形态均不成立（首块不合法 / 长度为 0 / 内容不足 16 字节）时返回
  /// null，交由整体数据兜底展示（不猜测记录边界）。
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

  /// 按 27 记录头（[27] 记录号 记录长度）切分完整格式记录。
  ///
  /// 每条记录头自述内容长度（3 + 长度字段 = 单条记录字节数），可精确定位
  /// 边界；记录号取记录头字节（越界时按顺序号兜底），供记录 1/2 的字段
  /// 解析。声明长度越界（记录被截断）或尾部残留非记录头时停止；首条即
  /// 不合法时返回 null（不猜测）。
  static List<TUnionProcessRecord>? _splitRecordHeaderBlob(List<int> blob) {
    final out = <TUnionProcessRecord>[];
    var pos = 0;
    while (pos + 3 <= blob.length && blob[pos] == 0x27) {
      final contentLength = blob[pos + 2];
      if (contentLength < 0x10) break;
      final end = pos + 3 + contentLength;
      if (end > blob.length) break;
      final number = blob[pos + 1];
      out.add(_buildVarProcessRecord(
        number >= 1 && number <= _maxVarProcessRecords
            ? number
            : out.length + 1,
        blob.sublist(pos, end),
      ));
      pos = end;
    }
    return out.isEmpty ? null : out;
  }

  /// 解析 70 记录模板长度头：返回（头长度, 内容长度）；
  /// 非 70 模板或长度头不合法（不定长 / 超过两字节扩展 / 长度为 0）返回 null。
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

  /// 读取公共交通过程信息循环记录（SFI 0x1E，48 字节定长）。
  ///
  /// 整体读取优先（对齐 NFCard 批量策略）：P2 = (SFI<<3)|0x05 从记录 1
  /// 读至文件末尾（61XX 链式补齐后按 48 字节切分逐条解码），通常
  /// 1~3 次 APDU 即可读完；整体读取不可用（部分卡片不支持批量）或
  /// 布局无法切分（模板包裹 / 非定长实现）时，回退逐条读取
  /// （P2 = 0xF4），读至记录未找到（6A83）/ 空数据 / 内容重复为止，
  /// 不设固定条数上限（0x1E 条数由卡片填充决定）。
  Future<List<TUnionProcessRecord>> _readCycleProcessRecords() async {
    final blob = await _readWholeRecordFile(_processCycleFileSfi);
    if (blob != null) {
      final split = _splitCycleRecords(blob.raw);
      if (split != null) return split;
    }

    final out = <TUnionProcessRecord>[];
    List<int>? firstData;
    for (var i = 1; i <= _maxCycleRecordNumber; i++) {
      final resp =
          await _exchange(TUnionApdu.readRecord(_processCycleFileSfi, i));
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      if (_isBlankRecord(data)) continue;
      // 部分卡片忽略记录号，每次读取都返回记录 1：读到与首个非空记录
      // 完全一致的内容时停止，避免无界重复读取同一条数据。
      if (firstData != null && _listEquals(data, firstData)) break;
      firstData ??= data;
      out.add(TUnionProcessRecord(
        sfi: _processCycleFileSfi,
        recordNumber: i,
        recordName: '循环记录 $i',
        raw: data,
        trip: _processParser.parseCycleTrip(data),
      ));
    }
    // 逐条与整体均失败（布局无法切分）时，复用已读整体数据兜底展示
    if (out.isEmpty && blob != null) out.add(blob);
    return out;
  }

  /// 将整体读取的循环记录数据按 48 字节定长切分并逐条解码。
  ///
  /// 防错位校验：首个非空记录必须能通过 [TUnionProcessParser.parseCycleTrip]
  /// 布局校验，否则返回 null 交由逐条读取回退（避免模板包裹 / 非定长实现
  /// 的卡被按 48 字节错切展示）；空槽（全 0x00 / 0xFF）跳过，
  /// 与逐条读取语义一致。
  List<TUnionProcessRecord>? _splitCycleRecords(List<int> blob) {
    if (blob.length < _cycleRecordSize) return null;
    final out = <TUnionProcessRecord>[];
    var validated = false;
    for (var offset = 0;
        offset + _cycleRecordSize <= blob.length;
        offset += _cycleRecordSize) {
      final data = blob.sublist(offset, offset + _cycleRecordSize);
      if (_isBlankRecord(data)) continue;
      final trip = _processParser.parseCycleTrip(data);
      if (!validated) {
        if (trip == null) return null;
        validated = true;
      }
      out.add(TUnionProcessRecord(
        sfi: _processCycleFileSfi,
        recordNumber: offset ~/ _cycleRecordSize + 1,
        recordName: '循环记录 ${offset ~/ _cycleRecordSize + 1}',
        raw: data,
        trip: trip,
      ));
    }
    return out;
  }

  /// 整体读取记录文件（P2 = (SFI<<3)|0x05，从记录 1 读到文件末尾），
  /// 用于不支持逐条读取、或变长记录无法按条切分时的兜底展示。
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

  /// 将读取结果按 23 字节一条切分并解码（整体读取时响应可能含多条记录）。
  List<TUnionTransaction> _decodeRecords(List<int> data) {
    if (data.isEmpty) return const [];
    final payload = _unwrapRecordTemplate(data) ?? data;
    final out = <TUnionTransaction>[];
    for (var s = 0;
        s + _transactionRecordSize <= payload.length;
        s += _transactionRecordSize) {
      final record =
          _decodeTransaction(payload.sublist(s, s + _transactionRecordSize));
      if (record != null) out.add(record);
    }
    return out;
  }

  /// READ BINARY 读取透明（二进制）文件：
  /// P1 = 0x80 | SFI，P2 = 文件内偏移。
  /// 先以 Le = 0x00 整体读取（读取至文件末尾），
  /// 数据不足或失败时再按偏移以具体长度补读。
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
      if (_matchesFromStart(out, chunk)) break; // 卡片忽略偏移重复返回文件头
      out.addAll(chunk);
      if (chunk.length < want) break; // 已到文件尾
    }

    if (out.isEmpty) return null;
    final data = out.length > length ? out.sublist(0, length) : out;
    if (data.every((b) => b == 0x00 || b == 0xFF)) return null; // 全空数据
    return data;
  }

  /// 读取管理信息文件（SFI 0x17，60 字节二进制文件）。
  /// 部分发卡方将 0x17 实现为记录文件，二进制读取失败时回退 READ RECORD
  /// （P2 = (0x17 << 3) | 0x04 = 0xBC）。
  Future<List<int>?> _readManagementFile() async {
    final binary =
        await _readTransparentFile(_managementFileSfi, _managementFileSize);
    if (binary != null) return binary;

    for (var i = 1; i <= 10; i++) {
      final resp = await _exchange(TUnionApdu.readRecord(_managementFileSfi, i));
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.length >= 11 && data.any((b) => b != 0x00 && b != 0xFF)) {
        return data;
      }
    }
    return null;
  }

  /// FCI 回退：SELECT 响应中发卡机构自定义数据（9F0C，部分文档记为 BF0C）
  /// 与公共应用信息文件同构（30 字节）。
  List<int>? _publicInfoFromFci() {
    final data = _fciDiscretionary;
    if (data == null || data.length < 12) return null;
    final info =
        data.length >= _publicFileSize ? data.sublist(0, _publicFileSize) : data;
    if (info.every((b) => b == 0x00 || b == 0xFF)) return null;
    return info;
  }

  /// 从 SELECT 响应提取发卡机构自定义数据，依次查找 9F0C / BF0C。
  static List<int>? _extractFciDiscretionary(List<int> fci) {
    if (fci.isEmpty) return null;
    return _findTlvValue(fci, 0x9F0C) ?? _findTlvValue(fci, 0xBF0C);
  }

  /// 极简 BER-TLV 遍历：深度优先返回首个匹配标识的原始值。
  /// 支持 1~2 字节标识、短格式与 0x81 / 0x82 扩展长度、构造类递归。
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

  /// 解码标准文件为卡片信息。
  ///
  /// 公共应用信息文件（SFI 0x15，30 字节）：
  /// [00-07] 发卡机构标识　[08] 应用类型标识　[09] 应用版本
  /// [10-19] 应用序列号　[20-23] 应用生效日期（BCD YYYYMMDD）
  /// [24-27] 应用失效日期（BCD YYYYMMDD）　[28-29] 发卡机构自定义 FCI。
  ///
  /// 持卡人基本信息文件（SFI 0x16，55 字节）：
  /// [00] 卡类型标识　[01] 本行职工标识　[02-21] 持卡人姓名（HEX）
  /// [22-53] 持卡人证件号码（HEX）　[54] 持卡人证件类型。
  ///
  /// 管理信息文件（SFI 0x17，60 字节）：
  /// [00-03] 国际代码　[04-05] 省级代码　[06-07] 城市代码（银联地区码）
  /// [08-09] 互通卡种　[10] 卡种类型　[11-59] 预留。
  TUnionCardInfo _decodeCardInfo(
      List<int>? public, List<int>? holder, List<int>? management) {
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
      cardKind =
          management.length > 10 ? TUnionCodec.hexByte(management[10]) : null;
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

  /// 解码 23 字节交易明细记录（循环记录文件 SFI 0x18）：
  /// [00-01] 电子钱包消费交易序号　[02-04] 透支限额　[05-08] 交易金额（分）
  /// [09] 交易类型（0x06 消费 / 0x09 复合消费）　[10-15] 交易终端编号（BCD）
  /// [16-19] 交易日期（BCD YYYYMMDD）　[20-22] 交易时间（BCD HHMMSS）。
  /// 记录被 70 模板（TLV）包裹时自动剥离模板。
  TUnionTransaction? _decodeTransaction(List<int> data) {
    final payload = _unwrapRecordTemplate(data) ?? data;
    if (payload.length < _transactionRecordSize) return null;
    if (payload.every((b) => b == 0x00)) return null; // 空记录
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
      overdraftLimitFen:
          (payload[2] << 16) | (payload[3] << 8) | payload[4],
      amountFen: (payload[5] << 24) |
          (payload[6] << 16) |
          (payload[7] << 8) |
          payload[8],
      rawType: payload[9],
      terminalId: TUnionCodec.bcdString(payload.sublist(10, 16)) ??
          TUnionCodec.hexBytes(payload.sublist(10, 16)) ??
          '',
      time: DateTime(date.year, date.month, date.day, hour, minute, second),
    );
  }

  /// 剥离 70 记录模板（TLV）返回内容，非模板或长度不合法时返回 null。
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

  /// 收发 APDU：自动处理 6CXX 重发与 61XX 链式响应（支持多段）。
  /// 链式段数上限 32（约 8KB 数据 ≈ 170 条 48 字节记录）：覆盖 0x1E /
  /// 0x1A 大容量文件整体读取，同时防止异常卡无界返回 61XX。
  Future<List<int>> _exchange(List<int> apdu) async {
    var resp = await _transceive(apdu);
    if (apdu.isNotEmpty &&
        resp.length >= 2 &&
        resp[resp.length - 2] == 0x6C &&
        resp.last != 0) {
      resp = await _transceive(
        [...apdu.sublist(0, apdu.length - 1), resp.last],
      );
    }
    var guard = 0;
    while (resp.length >= 2 &&
        resp[resp.length - 2] == 0x61 &&
        resp.last != 0 &&
        guard++ < 32) {
      final cla = apdu.isNotEmpty ? apdu[0] : 0x00;
      final data = resp.sublist(0, resp.length - 2);
      final chain = await _transceive(TUnionApdu.getResponse(cla, resp.last));
      resp = [...data, ...chain];
      if (chain.isEmpty) break;
    }
    return resp;
  }

  bool _isSuccess(List<int> resp) => ApduSw.isSuccess(resp);

  /// 去掉响应末尾的状态字。
  static List<int> _stripSw(List<int> resp) =>
      resp.length >= 2 ? resp.sublist(0, resp.length - 2) : const [];

  /// 全 0x00 / 0xFF 视为未写入的空记录。
  static bool _isBlankRecord(List<int> d) =>
      d.every((b) => b == 0x00 || b == 0xFF);

  /// 判断 chunk 是否与 data 头部内容重复。
  static bool _matchesFromStart(List<int> data, List<int> chunk) {
    if (data.length < chunk.length) return false;
    for (var i = 0; i < chunk.length; i++) {
      if (data[i] != chunk[i]) return false;
    }
    return true;
  }

  /// 判断两段字节内容是否完全相等（循环记录重复读取检测）。
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
}
