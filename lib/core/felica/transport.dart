// D:\iteam\TrafArch\lib\core\felica\transport.dart
/// FeliCa 模块的传输注入点：发送完整帧（含 LEN），返回完整响应帧（含 LEN）。
/// 与 EMV 模块的 EmvTransceive / local_card 的 LocalTransceive 同思路，
/// 由上层注入（AppState._felicaTransceive），模块不依赖任何会话实现。
typedef FelicaTransceive = Future<List<int>> Function(List<int> frame);