library;

/// FeliCa 命令码（JIS X 6319-4）。
abstract final class FelicaCommandCode {
  static const int polling = 0x00;
  static const int requestService = 0x02;
  static const int requestResponse = 0x04;
  static const int readWithoutEncryption = 0x06;
  static const int requestSystemCode = 0x0C;
}

/// FeliCa 命令帧构造。
///
/// 帧格式：`LEN | CMD | IDm(8) | 参数…`，LEN 为整帧字节数（含 LEN 自身），
/// 因此 `LEN = payload.length + 1`。
abstract final class FelicaCommand {
  static const int systemCodeWildcard = 0xFFFF;
  static const int idmLength = 8;
  static const int blockSize = 16;

  static List<int> frame(List<int> payload) {
    if (payload.isEmpty) {
      throw ArgumentError('FeliCa 命令载荷为空');
    }
    final length = payload.length + 1;
    if (length > 0xFF) {
      throw ArgumentError('FeliCa 命令超过单帧上限：$length 字节');
    }
    return [length, ...payload];
  }

  static List<int> polling({
    int systemCode = systemCodeWildcard,
    int requestCode = 0x00,
    int timeSlot = 0x00,
  }) =>
      frame([
        FelicaCommandCode.polling,
        (systemCode >> 8) & 0xFF,
        systemCode & 0xFF,
        requestCode,
        timeSlot,
      ]);

  static List<int> requestSystemCode(List<int> idm) {
    _requireIdm(idm);
    return frame([FelicaCommandCode.requestSystemCode, ...idm]);
  }

  /// Request Service：service code 在帧内按小端排列（0x090F → 0F 09）。
  static List<int> requestService({
    required List<int> idm,
    required List<int> serviceCodes,
  }) {
    _requireIdm(idm);
    if (serviceCodes.isEmpty || serviceCodes.length > 0xFF) {
      throw ArgumentError('服务码数量非法：${serviceCodes.length}');
    }
    return frame([
      FelicaCommandCode.requestService,
      ...idm,
      serviceCodes.length,
      for (final code in serviceCodes) ...[code & 0xFF, (code >> 8) & 0xFF],
    ]);
  }

  /// Read Without Encryption。
  ///
  /// 服务码小端；块列表元素为短格式大端 `0x80|块号`（见 [blockListElement]）。
  static List<int> readWithoutEncryption({
    required List<int> idm,
    required List<int> serviceCodes,
    required List<int> blockListElements,
  }) {
    _requireIdm(idm);
    if (serviceCodes.isEmpty || serviceCodes.length > 0x08) {
      throw ArgumentError('服务码数量非法：${serviceCodes.length}');
    }
    if (blockListElements.isEmpty || blockListElements.length > 0xFF) {
      throw ArgumentError('块列表元素数量非法：${blockListElements.length}');
    }
    final payload = <int>[
      FelicaCommandCode.readWithoutEncryption,
      ...idm,
      serviceCodes.length,
      for (final code in serviceCodes) ...[code & 0xFF, (code >> 8) & 0xFF],
      blockListElements.length,
      for (final element in blockListElements) ...[
        (element >> 8) & 0xFF,
        element & 0xFF,
      ],
    ];
    return frame(payload);
  }

  /// 块列表元素（2 字节短格式，大端）：
  /// 最高位固定 1，bit14..12 为服务码列表序号，bit11..0 为块号。
  /// 例如服务序号 0、块 0 → 0x8000（线上字节 `80 00`）。
  static int blockListElement(int serviceIndex, int blockNumber) {
    if (serviceIndex < 0 || serviceIndex > 0x07) {
      throw ArgumentError('服务序号越界：$serviceIndex（短格式仅支持 0-7）');
    }
    if (blockNumber < 0 || blockNumber > 0x0FFF) {
      throw ArgumentError('块号越界：$blockNumber');
    }
    return 0x8000 | ((serviceIndex & 0x07) << 12) | (blockNumber & 0x0FFF);
  }

  static void _requireIdm(List<int> idm) {
    if (idm.length != idmLength) {
      throw ArgumentError('IDm 必须为 8 字节，实际 ${idm.length} 字节');
    }
  }
}