library;

/// FeliCa 响应帧：`LEN | 响应码 | IDm(8) | 数据…`。
/// LEN 为整帧字节数（含 LEN 自身），与命令帧构造口径一致。
class FelicaResponse {
  final int code;
  final List<int> idm;

  /// IDm 之后的响应数据。
  final List<int> data;
  final List<int> raw;

  const FelicaResponse({
    required this.code,
    required this.idm,
    required this.data,
    required this.raw,
  });

  /// 严格校验 LEN 与帧长度：不一致视为格式异常，不猜测截断 / 补位。
  factory FelicaResponse.parse(List<int> frame) {
    if (frame.any((byte) => byte < 0 || byte > 255)) {
      throw const FormatException('FeliCa 响应包含非法字节');
    }
    if (frame.isEmpty) {
      throw const FormatException('FeliCa 响应为空');
    }
    final declaredLength = frame[0] & 0xFF;
    if (declaredLength != frame.length) {
      throw FormatException(
        'FeliCa 响应长度不符：声明 $declaredLength 字节，'
        '实际 ${frame.length} 字节',
      );
    }
    if (frame.length < 10) {
      throw FormatException('FeliCa 响应过短：${frame.length} 字节');
    }
    return FelicaResponse(
      code: frame[1] & 0xFF,
      idm: List<int>.unmodifiable(frame.sublist(2, 10)),
      data: List<int>.unmodifiable(frame.sublist(10)),
      raw: List<int>.unmodifiable(frame),
    );
  }
}
