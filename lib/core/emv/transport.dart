// D:\iteam\TrafArch\lib\core\emv\transport.dart
/// EMV 模块的传输注入点：发送一条 APDU（命令字节）返回响应（含 SW1SW2）。
/// 与 AppState._transceive / LocalTransceive 同签名，可直接复用现有 NFC 通道，
/// 使本模块不依赖任何会话实现、可独立测试。
typedef EmvTransceive = Future<List<int>> Function(List<int> command);