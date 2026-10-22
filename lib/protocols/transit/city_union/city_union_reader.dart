library;

import '../card_parser.dart';
import 'city_union_codec.dart';
import 'city_union_file_parser.dart';
import 'city_union_models.dart';
import '../tunion/tunion_apdu.dart';
import '../tunion/tunion_models.dart';
import '../local/apdu_exchange.dart';
import '../local/local_card_models.dart';

/// 城市一卡通通用单元（CU）：SELECT + CJ/T 331-2016 完整识读（新模块主体）。
///
/// 本单元已内联原 `CityUnionParser` 的全部读取实现（老模块移除）：
/// - 应用选择：MF 3F00 复位 + 住建部 AID A00000000386980701
///   按 CLA 0x00 / 0x80 双尝试；
/// - 文件读取：SFI 0x15 / 0x18 / 0x1A，产出带 [CityUnionFileView] 视图的
///   [ParsedCard]（parserId [CardParserIds.cityUnion]），继续供专家页与
///   卡片档案链路消费；
/// - 同步回填新架构 [CardInfo] 与交易流水（[ApduRecord.type] == 2）。
///
/// CU 记录金额的单位标准未定义（表 7 / 表 9），流水仅保留原始字段，
/// 不折算余额差额（不猜测）。逐条 APDU 序列与原 `CityUnionParser.parse()`
/// 保留既有读取顺序；失败证据与部分数据分别保存。
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

  /// 记录号物理上限（READ RECORD 的 P1 为单字节，协议边界）。
  static const _maxRecordNumber = 0xFE;

  /// 展示 / 日志用的模块名（与原解析器同名，保持日志连续性）。
  static const String moduleName = '城市一卡通（CJ/T 331-2016）';

  /// 识读成功后的标准文件解析结果（未识读 / 失败时为 null）。
  ParsedCard? parsedCard;

  List<int>? _selectedAid;

  /// 已选中的应用 AID；未选择时为 null。
  List<int>? get selectedAid => _selectedAid;

  Future<bool> select(CardInfo info, List<ApduRecord> records) async {
    if (info.isCU) return true;
    if (!await _selectApplication()) return false;
    info.isCU = true;
    return true;
  }

  /// 完整识读：读取标准文件并生成统一视图列表。
  ///
  /// [readBalance] 为 true 时额外读取电子钱包余额（GET BALANCE，相对当前
  /// 选中的住建部应用）——仅在双应用卡的次应用探测中启用；默认 false 时
  /// 保留 CU 文件读取顺序；失败证据与部分数据分别保存。
  Future<ParsedCard?> read(
    CardInfo info,
    List<ApduRecord> records, {
    bool readBalance = false,
  }) async {
    if (_selectedAid == null) return null;

    final files = <CityUnionFileView>[];
    int? balance;
    try {
      await _readFiles(files);
      _report(0.9);
      balance = readBalance ? await _readBalance() : null;
      _report(1);
    } finally {
      parsedCard = ParsedCard(
        parserId: CardParserIds.cityUnion,
        parserName: moduleName,
        info: const TUnionCardInfo().withBalance(balance),
        transactions: const [],
        cityUnionFiles: List.unmodifiable(files),
        selectedAidHex: CityUnionCodec.hex(_selectedAid ?? const []),
      );
      _applyToCardInfo(info, files);
      // Keep the CU summary consistent with ParsedCard for dual-application
      // merging, including a successfully read zero balance.
      if (balance != null) info.balance = balance;
      _appendRecords(info, records, files);
    }
    return parsedCard;
  }

  // ---- CU 应用与文件读取 ----

  /// 应用选择：先选择主文件（MF 3F00）复位（失败忽略），
  /// 然后按 CLA 0x00 / 0x80 尝试城市一卡通 AID。
  Future<bool> _selectApplication() async {
    await _exchange(TUnionApdu.selectFile(const [0x3F, 0x00]));
    for (final cla in const [0x00, 0x80]) {
      final resp = await _exchange(TUnionApdu.select(walletAid, cla: cla));
      if (_isSuccess(resp)) {
        _selectedAid = walletAid;
        return true;
      }
    }
    return false;
  }

  /// 读取标准文件并返回统一视图列表：0x15 / 0x18 / 0x1A。
  Future<void> _readFiles(List<CityUnionFileView> out) async {
    final public = await _readTransparentFile(
      CityUnionFileIds.publicBasicInfo,
      _publicFileSize,
    );
    if (public != null) {
      out.add(_parseSafely(CityUnionFileIds.publicBasicInfo, public));
    }
    _report(0.3); // 0x15 公共应用基本信息读取完成

    await _readRecords(CityUnionFileIds.walletLocalConsumption, out);
    _report(0.65); // 0x18 本地消费交易读取完成
    await _readRecords(CityUnionFileIds.walletRecharge, out);
    _report(0.9); // 0x1A 充值交易读取完成
  }

  /// 逐条 READ RECORD 读取记录文件（0x18、0x1A 循环记录）。
  Future<void> _readRecords(int sfi, List<CityUnionFileView> out) async {
    List<int>? firstData;
    for (var i = 1; i <= _maxRecordNumber; i++) {
      final resp = await _exchange(TUnionApdu.readRecord(sfi, i));
      if (!_isSuccess(resp)) break;
      final data = _stripSw(resp);
      if (data.isEmpty) break;
      if (_isBlankRecord(data)) continue;
      if (firstData != null && _listEquals(data, firstData)) break;
      firstData ??= data;
      out.add(_parseSafely(sfi, data));
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
  /// 的解释不一致导致数据起点偏移）；长度不足时不再静默拼接，直接失败，
  /// 由上层保留原始数据。
  Future<List<int>?> _readTransparentFile(int sfi, int length) async {
    final whole = await _exchange(
      TUnionApdu.readBinary(sfi, offset: 0, le: length),
    );
    if (!_isSuccess(whole)) return null;
    final data = _stripSw(whole);
    if (data.length != length) return null;
    if (data.every((b) => b == 0x00 || b == 0xFF)) return null;
    return data;
  }

  /// 收发 APDU：自动处理 6CXX 重发与 61XX 链式响应（段数上限 32）。
  Future<List<int>> _exchange(List<int> apdu) => _apdu.exchangeTransit(apdu);

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
    final serial = public.displayApplicationSerialNumber;
    if (serial != null && serial.isNotEmpty) info.cardNumber = serial;
    final city = _cityCodeOf(public.cityCode);
    if (city != 0) info.cityCode = city;
    info.expiryDate =
        _dateTimeOf(public.applicationExpiryDate, null) ?? info.expiryDate;
    info.issueDate =
        _dateTimeOf(public.applicationStartDate, null) ?? info.issueDate;
  }

  /// 0x18 本地消费 / 0x1A 充值明细 → 新架构流水（type == 2）。
  void _appendRecords(
    CardInfo info,
    List<ApduRecord> records,
    List<CityUnionFileView> files,
  ) {
    for (final f in files) {
      if (f is CjT331WalletLocalConsumption) {
        records.add(
          ApduRecord()
            ..type = 2
            ..label = 'CU 0x18#${f.sequence}'
            ..timestamp =
                _dateTimeOf(f.transactionDate, f.transactionTime) ??
                DateTime.fromMillisecondsSinceEpoch(0)
            ..terminalHex = f.terminalNumber
            ..cityCode = info.cityCode,
        );
      } else if (f is CjT331WalletRecharge) {
        records.add(
          ApduRecord()
            ..type = 2
            ..label = 'CU 0x1A#${f.sequence}'
            ..timestamp =
                _dateTimeOf(f.transactionDate, f.transactionTime) ??
                DateTime.fromMillisecondsSinceEpoch(0)
            ..terminalHex = f.terminalNumber
            ..cityCode = info.cityCode,
        );
      }
    }
  }

  static int _cityCodeOf(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    return int.tryParse(raw) ?? int.tryParse(raw, radix: 16) ?? 0;
  }

  /// "YYYY-MM-DD" / "HH:MM:SS" 组合解析；任一非法返回 null（不猜测）。
  static DateTime? _dateTimeOf(String? date, String? time) {
    if (date == null || date.isEmpty) return null;
    final iso = (time == null || time.isEmpty) ? date : '${date}T$time';
    return DateTime.tryParse(iso);
  }

  /// 读取电子钱包余额（GET BALANCE，相对当前选中的住建部 CU 应用）。
  /// 命令形态与交通联合及本项目地方卡一致：`80 5C 00 02 04`，返回 4 字节
  /// 大端无符号整数，单位为分；需剥离末尾状态字 `90 00` 后取前 4 字节。
  /// CLA 0x80 失败时回退 0x00；均失败返回 null（不猜测）。
  Future<int?> _readBalance() async {
    for (final cla in const [0x80, 0x00]) {
      final resp = await _exchange(TUnionApdu.getBalance(cla: cla, p1: 0x00));
      if (!_isSuccess(resp) || resp.length < 6) continue;
      return (resp[0] << 24) | (resp[1] << 16) | (resp[2] << 8) | resp[3];
    }
    return null;
  }
}
