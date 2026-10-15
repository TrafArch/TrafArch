/// 状态字（SW1SW2）解释：原样保存状态字，仅在展示层给出中性提示。
/// 不因 6982/6985 等访问受限状态自动尝试任何绕过。
class StatusWord {
  StatusWord._();

  static String describe(int sw) {
    final sw1 = (sw >> 8) & 0xFF;
    final sw2 = sw & 0xFF;
    if (sw1 == 0x61) return '正常结束（还有 $sw2 字节待 GET RESPONSE）';
    if (sw1 == 0x6C) return 'Le 错误（正确长度 $sw2）';
    switch (sw) {
      case 0x9000:
        return '成功';
      case 0x6283:
        return '选择的文件已失效';
      case 0x6700:
        return '长度错误';
      case 0x6881:
        return '逻辑通道不支持';
      case 0x6882:
        return '安全消息不支持';
      case 0x6982:
        return '安全状态不满足（读取被访问条件拒绝）';
      case 0x6985:
        return '使用条件不满足';
      case 0x6A82:
        return '文件 / 应用未找到';
      case 0x6A83:
        return '记录未找到';
      case 0x6A86:
        return 'P1/P2 参数错误';
      case 0x6D00:
        return 'INS 不支持';
      case 0x6E00:
        return 'CLA 不支持';
      default:
        return 'SW=${sw.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    }
  }
}