import 'dart:math';
import 'dart:typed_data';

/// 按卡片 PDOL（FCI 标签 9F38）自动组包 GET PROCESSING OPTIONS 命令数据。
///
/// 只读分析用途：授权金额为 0、交易类型为消费、终端国家与货币为人民币；
/// 收录 EMV 通用标签与 PBOC 专有标签（9F7A 电子现金指示器、DF69 国密
/// 支持指示器）的安全默认值；未收录标签按声明长度补 0x00（不猜测语义）。
class PdolDataBuilder {
  PdolDataBuilder._();

  /// 终端数据默认值（按标签）；实际输出长度以 PDOL 声明的长度为准。
  static const Map<String, List<int>> _defaults = {
    // TTQ（终端交易属性）：支持 qPBOC、联机 PIN 与签名。
    '9F66': [0x36, 0x00, 0x40, 0x00],
    '9F02': [0x00], // 授权金额（按声明长度补 0）
    '9F03': [0x00], // 其它金额（按声明长度补 0）
    '9F1A': [0x01, 0x56], // 终端国家代码：中国
    '5F2A': [0x01, 0x56], // 交易货币代码：人民币
    '9C': [0x00], // 交易类型：消费
    '95': [0x00], // 终端验证结果（无异常，按声明长度补 0）
    '9F35': [0x22], // 终端类型：金融终端（具备联机与脱机能力）
    '9F33': [0xE0, 0xF8, 0xC8], // 终端性能
    '9F40': [0xF0, 0x00, 0xF0, 0xA0, 0x01], // 附加终端性能
    // 电子现金指示器：支持（金额为 0 且交易类型为消费，符合置 1 条件）。
    '9F7A': [0x01],
    // 国密支持指示器：不支持（本工具不做国密运算，如实声明）。
    'DF69': [0x00],
    // IFD 序列号。
    '9F1E': [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
  };

  /// 按 [pdol]（9F38 原始值）组包；条目结构为「标签（1–2 字节）+ 长度（1 字节）」。
  /// [now] / [random] 可注入以便测试（交易日期时间与不可预知数）。
  static Uint8List build(List<int> pdol, {DateTime? now, Random? random}) {
    final clock = now ?? DateTime.now();
    final rng = random ?? Random();
    final out = <int>[];
    var i = 0;
    while (i < pdol.length) {
      final tagBytes = <int>[pdol[i++]];
      while ((tagBytes.last & 0x1F) == 0x1F && i < pdol.length) {
        tagBytes.add(pdol[i++]);
      }
      if (i >= pdol.length) break;
      final len = pdol[i++];
      final tag = tagBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      out.addAll(_fit(_valueFor(tag, len, clock, rng), len));
    }
    return Uint8List.fromList(out);
  }

  static List<int> _valueFor(String tag, int len, DateTime now, Random rng) =>
      switch (tag) {
        // 交易日期 / 时间：n6 数值按 BCD 编码逐字节取值。
        '9A' => [_bcd(now.year % 100), _bcd(now.month), _bcd(now.day)],
        '9F21' => [_bcd(now.hour), _bcd(now.minute), _bcd(now.second)],
        // 不可预知数：按声明长度取随机字节。
        '9F37' => List<int>.generate(len > 0 ? len : 0, (_) => rng.nextInt(256)),
        _ => _defaults[tag] ?? const [0x00],
      };

  /// 裁剪或补零到 PDOL 声明的长度。
  static List<int> _fit(List<int> value, int len) {
    if (len <= 0) return const [];
    final out = value.take(len).toList();
    while (out.length < len) {
      out.add(0x00);
    }
    return out;
  }

  static int _bcd(int v) => ((v ~/ 10) << 4) | (v % 10);
}