import 'dart:typed_data';

/// EMV / PBOC 非接触式只读流程常用 APDU 命令构建（ISO 7816-4 + EMV Book 1/2）。
///
/// 仅构建读取类命令（SELECT / GPO / READ RECORD / GET RESPONSE）；
/// 不包含任何写卡、刷卡、认证或交易命令。
class ApduCommand {
  ApduCommand._();

  /// SELECT FILE（按 AID/DF 名称选择应用）。
  /// P1 = 0x04（by name），P2 = 0x00（请求返回 FCI），Le = 0x00。
  static Uint8List select(List<int> aid, {int cla = 0x00}) =>
      Uint8List.fromList([cla, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00]);

  /// GET PROCESSING OPTIONS：CLA 0x80 / INS 0xA8，命令数据为 83 模板。
  ///
  /// [pdolData] 为按卡片 PDOL（9F38）逐项组包的数据：
  /// 非空时发送 `83 <len> <数据>`；为空时发送 `83 00`
  /// （卡片未提供 PDOL 时的规范形式）。
  static Uint8List getProcessingOptions({List<int> pdolData = const []}) {
    // EMV Book 3, 6.5.8: Lc counts the complete 83 TLV, not just its value.
    // A short APDU carries at most 255 data bytes (252 + tag/long length).
    if (pdolData.length > 252) {
      throw ArgumentError('PDOL 数据超过短 APDU 容量');
    }
    final length = pdolData.length;
    final data = <int>[0x83, if (length >= 0x80) 0x81, length, ...pdolData];
    return Uint8List.fromList([
      0x80,
      0xA8,
      0x00,
      0x00,
      data.length,
      ...data,
      0x00,
    ]);
  }

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
