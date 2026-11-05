import 'dart:typed_data';

/// EMV / PBOC 非接触式只读流程常用 APDU 命令构建。
///
/// 仅构建 SELECT / GET DATA / READ RECORD / GET RESPONSE。
/// 不提供 GPO：部分非接触卡在处理 GPO 时已递增 ATC。
class ApduCommand {
  ApduCommand._();

  /// SELECT FILE（按 AID/DF 名称选择应用）。
  /// P1 = 0x04（by name），P2 = 0x00（请求返回 FCI），Le = 0x00。
  static Uint8List select(List<int> aid, {int cla = 0x00}) =>
      Uint8List.fromList([cla, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00]);

  /// 只读取应用交易计数器，不启动交易，不请求生成应用密文。
  static Uint8List getApplicationTransactionCounter() =>
      Uint8List.fromList([0x80, 0xCA, 0x9F, 0x36, 0x00]);

  /// READ RECORD：P1 = 记录号（从 1 起），P2 = (SFI << 3) | 0x04，Le = 0x00。
  static Uint8List readRecord(int sfi, int record, {int le = 0x00}) =>
      Uint8List.fromList([
        0x00,
        0xB2,
        record & 0xFF,
        ((sfi << 3) | 0x04) & 0xFF,
        le & 0xFF,
      ]);

  /// GET RESPONSE：读取 61XX 指示的剩余数据。
  static Uint8List getResponse(int cla, int le) =>
      Uint8List.fromList([cla, 0xC0, 0x00, 0x00, le & 0xFF]);
}
