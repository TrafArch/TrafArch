/// JT/T 978.2《城市公共交通IC卡技术规范 第2部分：卡片》应用指令构建。
///
/// 命令编码参考规范附录 C（应用指令）与 ISO 7816-4：
/// - 选择命令：按 DF 名称（AID）选择应用；
/// - 读二进制文件：P1 = 0x80 | SFI，P2 = 文件内偏移；
/// - 读记录：P1 = 记录号，P2 = (SFI << 3) | 0x04；
/// - 查询余额（电子钱包）：GET BALANCE 80 5C 00 02 04。
class TUnionApdu {
  TUnionApdu._();

  /// 选择命令：按 DF 名称（AID）选择应用。
  static List<int> select(List<int> dfName, {int cla = 0x00}) => [
    cla,
    0xA4,
    0x04,
    0x00,
    dfName.length,
    ...dfName,
    0x00,
  ];

  /// 选择命令：按文件标识符（FID，如主文件 3F00）选择。
  static List<int> selectFile(List<int> fid) => [
    0x00,
    0xA4,
    0x00,
    0x00,
    fid.length,
    ...fid,
    0x00,
  ];

  /// 读二进制文件命令：P1 = 0x80 | SFI，P2 = 文件内偏移，Le = 读取长度
  /// （Le = 0x00 表示读取至文件末尾）。
  static List<int> readBinary(int sfi, {int offset = 0, required int le}) => [
    0x00,
    0xB0,
    (0x80 | (sfi & 0x1F)) & 0xFF,
    offset & 0xFF,
    le & 0xFF,
  ];

  /// 读记录命令：P1 = 记录号（从 1 开始），P2 = (SFI << 3) | mode。
  /// mode = 0x04 读取指定记录；mode = 0x05 从指定记录起读到文件末尾。
  static List<int> readRecord(
    int sfi,
    int record, {
    int le = 0x00,
    int mode = 0x04,
  }) => [
    0x00,
    0xB2,
    record & 0xFF,
    ((sfi << 3) | (mode & 0x07)) & 0xFF,
    le & 0xFF,
  ];

  /// 电子钱包余额查询命令（GET BALANCE）。
  /// P1 = 0x00 电子钱包当前余额（JT/T 978.2 标准）；
  /// P1 = 0x03 透支限额 / 已透支金额相关数据（非余额，规范应为 8 字节，
  /// 此处 Le=04 仅取前 4 字节，只能作兜底参考，不可直接当余额展示）。
  static List<int> getBalance({int cla = 0x80, int p1 = 0x00}) => [
    cla,
    0x5C,
    p1 & 0xFF,
    0x02,
    0x04,
  ];

  /// 取响应命令：读取 61XX 指示的剩余数据，CLA 与原命令一致。
  static List<int> getResponse(int cla, int le) => [
    cla,
    0xC0,
    0x00,
    0x00,
    le & 0xFF,
  ];
}

/// ISO 7816-4 状态字（SW1SW2）判定与中文描述。
class ApduSw {
  ApduSw._();

  /// 提取响应末尾状态字，响应过短返回 null。
  static int? of(List<int> resp) => resp.length < 2
      ? null
      : (resp[resp.length - 2] << 8) | resp[resp.length - 1];

  static bool isSuccess(List<int> resp) => of(resp) == 0x9000;

  /// 状态字中文描述。
  static String describe(int sw) {
    final sw1 = (sw >> 8) & 0xFF;
    final sw2 = sw & 0xFF;
    if (sw1 == 0x61) return '还有 $sw2 字节待 GET RESPONSE';
    if (sw1 == 0x6C) return 'Le 错误，正确长度 $sw2';
    switch (sw) {
      case 0x9000:
        return '成功';
      case 0x6283:
        return '选择的文件已失效';
      case 0x6300:
        return '认证失败';
      case 0x6700:
        return '长度错误';
      case 0x6982:
        return '安全状态不满足';
      case 0x6985:
        return '使用条件不满足';
      case 0x6A80:
        return '数据域参数错误';
      case 0x6A82:
        return '文件未找到';
      case 0x6A83:
        return '记录未找到';
      case 0x6A86:
        return 'P1/P2 参数错误';
      case 0x6A88:
        return '引用数据未找到';
      case 0x6D00:
        return '指令不支持';
      case 0x6E00:
        return 'CLA 不支持';
      case 0x6F00:
        return '未知错误';
      default:
        return 'SW=${sw.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    }
  }
}
