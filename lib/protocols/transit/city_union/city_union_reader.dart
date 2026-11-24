library;

import '../../iso7816/ber_tlv.dart';
import '../card_parser.dart';
import 'city_union_codec.dart';
import 'city_union_file_parser.dart';
import 'city_union_models.dart';
import 'qingdao_metro_tap.dart';
import '../tunion/tunion_apdu.dart';
import '../tunion/tunion_models.dart';
import '../local/apdu_exchange.dart';
import '../local/local_card_models.dart';

/// 城市一卡通通用单元（CU）：SELECT + CJ/T 331-2016 完整识读（新模块主体）。
///
/// 本单元已内联原 `CityUnionParser` 的全部读取实现（老模块移除）：
/// - 应用选择：MF 3F00 复位 + 住建部 AID A00000000386980701
///   按 CLA 0x00 / 0x80 双尝试；
/// - 文件读取：SFI 0x15 / 0x18 / 0x10 / 城市异地通道，产出带 [CityUnionFileView] 视图的
///   [ParsedCard]（parserId [CardParserIds.cityUnion]），继续供专家页与
///   卡片档案链路消费；
/// - 同步回填新架构 [CardInfo] 与交易流水（[ApduRecord.type] == 2）。
///
/// CU 记录金额的单位标准未定义（表 7 / 表 9），流水仅保留原始字段，
/// 不折算余额差额（不猜测）。公共信息后优先读取可选余额，再读取记录；
/// 失败证据与部分数据分别保存。
class CommonUnitCu {
  CommonUnitCu(this._apdu, {this.onProgress});

  final ApduExchange _apdu;

  /// 模块内部识读进度（0.0–1.0）：供统一识读流程映射为整体百分比；可空。
  final void Function(double progress)? onProgress;

  void _report(double progress) => onProgress?.call(progress);

  /// 城市一卡通应用 AID（住建部 CPU 交通卡 / 数字城市一卡通）。
  static const List<int> walletAid = [
    0xA0,
    0x00,
    0x00,
    0x00,
    0x03,
    0x86,
    0x98,
    0x07,
    0x01,
  ];

  /// 公共应用基本信息文件（SFI 0x15）标准长度 0x1E = 30 字节。
  static const _publicFileSize = 0x1E;

  /// TripReader CU 标准记录通道最多读取 31 条。
  static const _maxRecordNumber = 31;

  /// 展示 / 日志用的模块名（与原解析器同名，保持日志连续性）。
  static const String moduleName = '城市一卡通（CJ/T 331-2016）';

  /// 识读成功后的标准文件解析结果（未识读 / 失败时为 null）。
  ParsedCard? parsedCard;

  List<int>? _selectedAid;
  bool _fciNamesWallet = false;

  /// 已选中的应用 AID；未选择时为 null。
  List<int>? get selectedAid => _selectedAid;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    // 历史发现标记不能证明当前仍选中 CU，必须实际选择应用。
    _selectedAid = null;
    parsedCard = null;
    observations.clear();
    _fciNamesWallet = false;
    balanceResponses.clear();
    stalePublicFile = false;
    if (!await _selectApplication()) return false;
    info.isCU = true;
    return true;
  }

  /// Each successful response is kept with its purse selector (P2).
  final balanceResponses = <String, String>{};
  final observations = <String, String>{};
  bool stalePublicFile = false;

  /// Read application-relative files first. The optional display-number file
  /// lives under MF and is read only after wallet records are safe.
  Future<ParsedCard?> read(
    CardInfo info,
    List<ApduRecord> records, {
    bool readBalance = false,
    ParsedCard? tuWallet,
  }) async {
    if (_selectedAid == null) return null;
    parsedCard = null;
    stalePublicFile = false;
    balanceResponses.clear();
    final files = <CityUnionFileView>[];
    int? balance;
    try {
      await _readPublicInfo(files);
      final public = files.whereType<CjT331PublicInfo>().firstOrNull;
      // Some cards acknowledge SELECT but continue serving the previous
      // application's files. Compare the independently observed TU identity.
      final tu = tuWallet?.info;
      if (public != null &&
          tu != null &&
          tu.issuerId != null &&
          tu.applicationSerial != null) {
        final raw = public.rawHex.replaceAll(' ', '');
        stalePublicFile =
            raw.startsWith(tu.issuerId!) &&
            raw.substring(20, 40) == tu.applicationSerial;
        if (stalePublicFile) {
          observations['SFI 0x15'] = raw;
          files.clear();
          return null;
        }
      }

      if (readBalance) balance = await _readBalance();
      final mirrors = <String, int>{};
      final independentIdentity =
          _fciNamesWallet &&
          public?.issuerCode != null &&
          public?.industryCode != null &&
          public?.applicationSerialNumber != null &&
          !public!.fields.any(
            (f) => f.key == 'applicationStartDate' && f.hasError,
          );
      if (!independentIdentity && tuWallet != null) {
        for (final record in tuWallet.transactions) {
          final raw = record.rawHex?.replaceAll(' ', '').toUpperCase();
          if (raw != null) {
            mirrors.update(raw, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
      for (final sfi in const [0x18, 0x10, 0x1A, 0x06, 0x19]) {
        await _readRecords(sfi, files, mirrors);
      }
      final debits = files.whereType<CityUnionWalletTransaction>().where(
        (r) => r.sfi == 0x18 && r.kind == CityUnionTransactionKind.consumption,
      );
      if (debits.any((r) => r.amountRaw == 0) &&
          debits.any((r) => r.amountRaw > 0)) {
        for (final slot in const [3, 7]) {
          final resp = await _exchange(
            TUnionApdu.readRecord(0x19, slot, le: 0x20),
          );
          if (!_isSuccess(resp)) continue;
          final data = _stripSw(resp);
          final tap = QingdaoMetroTap(slot, data);
          if (tap.clock != null) {
            files.add(tap);
          } else if (data.length != 23 && !_isBlankRecord(data)) {
            files.add(
              CityUnionRawFileView(
                sfi: 0x19,
                recordNumber: slot,
                raw: data,
                reason: '第 $slot 槽未确认时间布局',
              ),
            );
          }
        }
      }
      if (public != null) await _readDisplayNumber(public, files);
      _report(1);
    } finally {
      if (!stalePublicFile) _publish(info, records, files, balance: balance);
    }
    return parsedCard;
  }

  void _publish(
    CardInfo info,
    List<ApduRecord> records,
    List<CityUnionFileView> files, {
    required int? balance,
  }) {
    parsedCard = ParsedCard(
      parserId: CardParserIds.cityUnion,
      parserName: moduleName,
      info: const TUnionCardInfo().withBalance(balance),
      transactions: const [],
      cityUnionFiles: List.unmodifiable(files),
      selectedAidHex: CityUnionCodec.hex(walletAid),
    );
    _applyToCardInfo(info, files);
    if (balance != null) info.balance = balance;
    _appendRecords(info, records, files);
  }

  // ---- CU 应用与文件读取 ----

  /// CU 专用 SELECT 兼容：保留带 Le 主路径，状态字拒绝后仅尝试一次
  /// 无 Le case 3。共享 exchange 按 hasLe 校正 6C，不会改写 FID/AID。
  /// 传输异常直接传播，不能继续尝试下一条命令。
  Future<List<int>> _selectWithCompatibility(List<int> withLe) async {
    final response = await _exchange(withLe);
    if (_isSuccess(response)) return response;
    return _exchange(withLe.sublist(0, withLe.length - 1));
  }

  Future<List<int>> _selectMf() =>
      _selectWithCompatibility(TUnionApdu.selectFile(const [0x3F, 0x00]));

  /// MF 状态字拒绝不阻止按 AID 选择；CLA 00 带/无 Le 后才尝试
  /// CLA 80 带/无 Le，每次成功立即停止，不改变 TU 的命令构建默认值。
  Future<bool> _selectApplication() async {
    await _selectMf();
    for (final cla in const [0x00, 0x80]) {
      final resp = await _selectWithCompatibility(
        TUnionApdu.select(walletAid, cla: cla),
      );
      if (_isSuccess(resp)) {
        final fci = _stripSw(resp);
        final matches = BerTlvParser.selectedAidMatches(fci, walletAid);
        if (matches == false) continue;
        _fciNamesWallet = matches == true;
        if (fci.isNotEmpty) {
          observations['SELECT FCI'] = CityUnionCodec.hex(fci);
        }
        _selectedAid = walletAid;
        return true;
      }
    }
    return false;
  }

  /// 读取当前 CU 应用的 0x15 公共信息并保留非标准长度。
  Future<void> _readPublicInfo(List<CityUnionFileView> out) async {
    final public = await _readTransparentFile(
      CityUnionFileIds.publicBasicInfo,
      _publicFileSize,
    );
    if (public != null) {
      if (public.length > _publicFileSize) {
        out.add(
          _parseSafely(
            CityUnionFileIds.publicBasicInfo,
            public.sublist(0, _publicFileSize),
          ),
        );
        out.add(
          CityUnionRawFileView(
            sfi: CityUnionFileIds.publicBasicInfo,
            raw: public,
            reason: '公共信息响应 ${public.length} 字节：按前 30 字节解析，完整响应保留',
          ),
        );
      } else {
        out.add(_parseSafely(CityUnionFileIds.publicBasicInfo, public));
      }
    }
    _report(0.3); // 0x15 公共应用基本信息读取完成
  }

  Future<void> _readDisplayNumber(
    CjT331PublicInfo public,
    List<CityUnionFileView> files,
  ) async {
    _selectedAid = null;
    final mf = await _selectMf();
    if (!_isSuccess(mf)) return;
    final extra = await _readTransparentFile(0x05, 0x2C);
    if (extra == null) return;
    observations['MF SFI 0x05'] = CityUnionCodec.hex(extra);
    if (extra.length != 44) return;
    final digits = extra.sublist(32);
    if (digits.every((b) => b >= 0x30 && b <= 0x39)) {
      files[files.indexOf(public)] = public.withCityDisplayNumber(
        String.fromCharCodes(digits),
      );
    }
  }

  /// 0x1A may hold standard recharge or a consumption channel. 0x19
  /// may hold foreign transactions or 32-byte statistics. A file number
  /// alone provides neither a transaction type nor a debit/credit sign.
  Future<void> _readRecords(
    int sfi,
    List<CityUnionFileView> out,
    Map<String, int> mirrors,
  ) async {
    List<int>? firstData;
    for (var slot = 1; slot <= _maxRecordNumber; slot++) {
      final resp = await _exchange(
        TUnionApdu.readRecord(sfi, slot, le: sfi == 0x19 ? 0 : 0x17),
      );
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      if (_isBlankRecord(data)) continue;
      if (firstData != null && _listEquals(firstData, data)) break;
      firstData ??= data;
      final kind = CityUnionFileParser.walletRecordKind(sfi, data);
      CityUnionWalletTransaction? record;
      String? reason;
      if (kind == null) {
        reason = '记录长度或交易类型与钱包布局不符';
      } else {
        record = CityUnionFileParser.parseWalletRecord(
          sfi,
          data,
          kind: kind,
          recordNumber: slot,
        );
        final verifyWalletFields =
            sfi == 0x18 ||
            (sfi == 0x06 && kind == CityUnionTransactionKind.recharge);
        if (verifyWalletFields &&
            !CityUnionFileParser.hasVerifiableWalletFields(record)) {
          reason = '交易日期、时间或金额无法核实';
        } else if (sfi == 0x18) {
          final raw = CityUnionCodec.hex(data);
          final count = mirrors[raw] ?? 0;
          if (count > 0) {
            mirrors[raw] = count - 1;
            reason = '与同次读取的交通联合 0x18 交易原始字节一致';
          }
        }
      }
      out.add(
        reason == null
            ? record!
            : CityUnionRawFileView(
                sfi: sfi,
                recordNumber: slot,
                raw: data,
                reason: '第 $slot 槽 · $reason',
              ),
      );
    }
  }

  /// 按 SFI 解析单条记录；布局不符时保留原始字节（不丢弃、不猜测）。
  CityUnionFileView _parseSafely(int sfi, List<int> data) {
    try {
      return CityUnionFileParser.parse(sfi, data);
    } on FormatException catch (e) {
      return CityUnionRawFileView(sfi: sfi, raw: data, reason: e.message);
    }
  }

  /// READ BINARY 读取透明（二进制）文件；全空数据返回 null。
  ///
  /// 首次读取使用明确长度（不再用 Le=0x00，避免部分卡片对“读到文件尾”
  /// 的解释不一致导致数据起点偏移）；成功响应不按长度丢弃或静默拼接，
  /// 由上层解析标准前缀并保留超长/短响应证据。
  Future<List<int>?> _readTransparentFile(int sfi, int length) async {
    final whole = await _exchange(
      TUnionApdu.readBinary(sfi, offset: 0, le: length),
    );
    if (!_isSuccess(whole)) return null;
    final data = _stripSw(whole);
    // 短成功响应也交给上层保存原始证据，不伪造有效公共信息。
    if (data.length >= length && data.every((b) => b == 0x00 || b == 0xFF)) {
      return null;
    }
    return data;
  }

  /// 仅 CU 只读指令允许一次 6700 / 6C00 长度校正；SELECT 策略不变。
  Future<List<int>> _exchange(List<int> apdu) async {
    if (apdu[1] != 0xB0 && apdu[1] != 0xB2 && apdu[1] != 0x5C) {
      return _apdu.exchangeTransit(apdu);
    }
    final result = await _apdu.exchange(
      apdu,
      policy: const ExchangePolicy(correct6c00: true, retry6700: true),
    );
    return result.response?.raw ?? const [];
  }

  bool _isSuccess(List<int> resp) => ApduSw.isSuccess(resp);

  static List<int> _stripSw(List<int> resp) =>
      resp.length >= 2 ? resp.sublist(0, resp.length - 2) : const [];

  static bool _isBlankRecord(List<int> d) =>
      d.every((b) => b == 0x00 || b == 0xFF);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- 新架构回填（保持不变） ----

  /// 0x15 公共应用基本信息 → 新架构卡汇总（缺失字段不猜测、不覆盖）。
  void _applyToCardInfo(CardInfo info, List<CityUnionFileView> files) {
    final public = files.whereType<CjT331PublicInfo>().firstOrNull;
    if (public == null) return;
    if (public.issuerCode != null) info.issuerCode = public.issuerCode!;
    final serial = public.cityCardNumber;
    if (serial != null && serial.isNotEmpty) info.cardNumber = serial;
    final city = public.displayCityCode ?? 0;
    if (city != 0) info.cityCode = city;
    info.expiryDate =
        _dateTimeOf(public.applicationExpiryDate, null) ?? info.expiryDate;
    info.issueDate =
        _dateTimeOf(public.applicationStartDate, null) ?? info.issueDate;
  }

  /// CU 消费、充值、异地通道 → 新架构流水（type == 2）。
  void _appendRecords(
    CardInfo info,
    List<ApduRecord> records,
    List<CityUnionFileView> files,
  ) {
    for (final f in files) {
      final hex = f.rawHex.replaceAll(' ', '');
      final raw = [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      if (f is CityUnionWalletTransaction) {
        records.add(
          ApduRecord()
            ..type = 2
            ..label =
                'CU ${CityUnionCodec.sfiLabel(f.sfi)}#${f.recordNumber ?? f.sequence}'
            ..timestamp =
                (f.transactionTime == null
                    ? null
                    : _dateTimeOf(f.transactionDate, f.transactionTime)) ??
                DateTime.fromMillisecondsSinceEpoch(0)
            ..response = [...raw, 0x90, 0x00]
            ..recordNumber = f.recordNumber ?? f.sequence
            ..posType = f.transactionType
            ..fileSelector = f.sfi
            ..terminalHex = f.terminalHex ?? '',
        );
      }
    }
  }

  /// "YYYY-MM-DD" / "HH:MM:SS" 组合解析；任一非法返回 null（不猜测）。
  static DateTime? _dateTimeOf(String? date, String? time) {
    if (date == null || date.isEmpty) return null;
    final iso = (time == null || time.isEmpty) ? date : '${date}T$time';
    return DateTime.tryParse(iso);
  }

  /// 读取电子钱包余额（GET BALANCE，相对当前选中的住建部 CU 应用）。
  /// 跳过首字节；金额最高字节为 FF 且补码大于 -100000 时认负数。
  Future<int?> _readBalance() async {
    for (final selector in const [0x02, 0x01]) {
      for (final cla in const [0x80, 0x00]) {
        final resp = await _exchange([cla, 0x5C, 0x00, selector, 0x04]);
        if (!_isSuccess(resp)) continue;
        final data = _stripSw(resp);
        final key = CityUnionCodec.hexByte(selector);
        balanceResponses[key] = CityUnionCodec.hex(data);
        observations['GET BALANCE P2=$key'] = balanceResponses[key]!;
        break;
      }
    }
    final raw = balanceResponses.values.toSet().singleOrNull;
    if (raw == null || raw.length != 8) return null;
    final value = int.parse(raw.substring(2), radix: 16);
    final signed = value - 0x1000000;
    return raw.substring(2, 4) == 'FF' && signed > -100000 ? signed : value;
  }
}
