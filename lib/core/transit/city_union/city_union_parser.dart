import '../../card/card_parser.dart';
import '../tunion/tunion_apdu.dart';
import '../tunion/tunion_models.dart';
import 'city_union_codec.dart';
import 'city_union_file_parser.dart';
import 'city_union_models.dart';

/// City Union（住建部城市一卡通，CJ/T 331-2016）读取解析器。
///
/// 读取流程对齐社区实测可用序列（TU-Reader 等开源读卡工具）：
/// - 先选择主文件（MF 3F00）复位（失败忽略）；
/// - 城市一卡通应用 AID：A00000000386980701（CLA 0x00 / 0x80 双尝试）；
/// - SFI 0x15 公共应用基本信息文件：READ BINARY 整体读取（30 字节）；
/// - SFI 0x18 电子钱包本地消费交易明细（循环记录）：逐条 READ RECORD，
///   单条 23 字节，不假定记录 1 是最新交易；
/// - SFI 0x1A 充值交易明细（循环记录）：逐条 READ RECORD，单条 23 字节。
///
/// 职责边界（读取层）：
/// - 只负责应用选择、文件定位与原始字节读取，字段解码由
///   [CityUnionFileParser] 按 SFI 分发到各表解析器；
/// - 循环记录文件不按定长对整文件切片；记录不符合标准布局时保留
///   原始字节（[CityUnionRawFileView]），不丢弃、不猜测字段值；
/// - SELECT / READ BINARY / READ RECORD 为 ISO 7816-4 通用命令，
///   复用 [TUnionApdu] 构建；6CXX 重发与 61XX 链式响应处理策略与
///   TUnionParser 一致。
class CityUnionParser implements CardParser {
  /// 城市一卡通应用 AID（住建部 CPU 交通卡 / 数字城市一卡通）。
  static const List<int> walletAid = [
    0xA0, 0x00, 0x00, 0x00, 0x03, 0x86, 0x98, 0x07, 0x01,
  ];

  /// 公共应用基本信息文件（SFI 0x15）标准长度 0x1E = 30 字节。
  static const _publicFileSize = 0x1E;

  /// 记录号物理上限（READ RECORD 的 P1 为单字节）：仅作协议边界，
  /// 防止异常卡忽略记录号导致无界读取；正常读至记录未找到即停止。
  static const _maxRecordNumber = 0xFE;

  /// 单次 READ BINARY 补读的最大长度。
  static const _readBinaryChunk = 64;

  final ApduTransceive _transceive;

  CityUnionParser(this._transceive);

  List<int>? _selectedAid;

  /// 已选中的应用 AID；未选择时为 null。
  List<int>? get selectedAid => _selectedAid;

  @override
  String get parserId => CardParserIds.cityUnion;

  @override
  String get parserName => '城市一卡通（CJ/T 331-2016）';

  /// CardParser 统一入口：应用选择 → 标准文件读取。
  /// 应用选择失败（非城市一卡通卡）时返回 null。
  @override
  Future<ParsedCard?> parse() async {
    final selected = await selectApplication();
    if (!selected) return null;
    final files = await readFiles();
    return ParsedCard(
      parserId: parserId,
      parserName: parserName,
      info: const TUnionCardInfo(),
      transactions: const [],
      cityUnionFiles: files,
      selectedAidHex: CityUnionCodec.hex(_selectedAid ?? const []),
    );
  }

  /// 应用选择：先选择主文件（MF 3F00）复位（住建部卡惯例，失败忽略），
  /// 然后按 CLA 0x00 / 0x80 尝试城市一卡通 AID。
  Future<bool> selectApplication() async {
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

  /// 读取已接入解析器的标准文件并返回统一视图列表：
  /// 0x15 公共应用基本信息、0x18 电子钱包本地消费交易明细、
  /// 0x1A 充值交易明细；文件不存在 / 未写入时跳过（不产出视图）。
  Future<List<CityUnionFileView>> readFiles() async {
    final out = <CityUnionFileView>[];

    final public = await _readTransparentFile(
      CityUnionFileIds.publicBasicInfo,
      _publicFileSize,
    );
    if (public != null) {
      out.add(_parseSafely(CityUnionFileIds.publicBasicInfo, public));
    }

    out.addAll(await _readRecords(CityUnionFileIds.walletLocalConsumption));
    out.addAll(await _readRecords(CityUnionFileIds.walletRecharge));
    return out;
  }

  /// 逐条 READ RECORD 读取记录文件（0x18、0x1A 循环记录）。
  ///
  /// 终止条件与 TUnionParser 循环记录读取一致：
  /// - 读取失败（记录未找到 6A83 等）→ 停止；
  /// - 空数据 → 停止；
  /// - 空白记录（全 0x00 / 0xFF，循环记录槽未写入）→ 跳过继续；
  /// - 内容与首个非空记录一致（部分卡忽略记录号）→ 停止，避免重复
  ///   条目与记录号错位的误解析。
  /// 每条按 [CityUnionFileParser] 解析；布局不符的记录保留原始字节。
  Future<List<CityUnionFileView>> _readRecords(int sfi) async {
    final out = <CityUnionFileView>[];
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
    return out;
  }

  /// 按 SFI 解析单条记录；记录长度 / 布局不符（[FormatException]）时
  /// 不丢弃数据，返回原始占位视图并保留解析器的错误说明。
  CityUnionFileView _parseSafely(int sfi, List<int> data) {
    try {
      return CityUnionFileParser.parse(sfi, data);
    } on FormatException catch (e) {
      return CityUnionRawFileView(sfi: sfi, raw: data, reason: e.message);
    }
  }

  /// READ BINARY 读取透明（二进制）文件：
  /// P1 = 0x80 | SFI，P2 = 文件内偏移。
  /// 先以 Le = 0x00 整体读取，数据不足时再按偏移补读；
  /// 全 0x00 / 0xFF（未写入）返回 null。
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

  /// 收发 APDU：自动处理 6CXX 重发与 61XX 链式响应（支持多段），
  /// 策略与 TUnionParser 一致（段数上限 32）。
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

  /// 判断两段字节内容是否完全相等（记录重复读取检测）。
  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}