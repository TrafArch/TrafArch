import 'dart:typed_data';

/// 卡片通信抽象：解析器只依赖此接口，真实 NFC 与测试回放共用同一套解析代码。
abstract interface class CardTransport {
  /// 发送一条命令并返回原始响应字节（含 SW1SW2）。
  Future<Uint8List> transceive(Uint8List command);

  /// 释放通道（真实实现关闭 NFC 会话；回放实现为空操作）。
  Future<void> close();
}