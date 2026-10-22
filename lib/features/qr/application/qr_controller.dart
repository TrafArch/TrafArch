import 'dart:convert';

import '../../../protocols/transit/qr/jt_t1179_qr_parser.dart';
import '../../../platform/qr/gms_qr_scanner.dart';
import '../../../shared/application/owned_notifier.dart';

class QrController extends OwnedNotifier {
  QrController({required this.log});
  final void Function(String) log;
  bool gmsAvailable = false;
  Future<void> detect({required bool warmUp}) async {
    final available = await isGmsQrScanAvailable();
    if (disposed) return;
    gmsAvailable = available;
    notifyListeners();
    if (available && warmUp) warmUpGmsQrScanner();
  }

  JtT1179QrData? _qrData;

  /// 最近一次解析成功的 JT/T 1179 二维码数据；解析失败或清除后为 null。
  JtT1179QrData? get qrData => _qrData;

  List<int>? _qrRaw;

  /// 最近一次获取到的二维码原始字节（成功 / 失败均保留，供原始数据查看）。
  List<int>? get qrRaw => _qrRaw;

  String? _qrError;

  /// 最近一次二维码解析失败原因；再次解析或清除时重置。
  String? get qrError => _qrError;

  /// 是否已有二维码解析结果。
  bool get hasQrData => _qrData != null;

  /// 解析二维码原始字节（相机扫描得到的二进制数据）。
  /// 成功时保存解析结果并清除错误；失败时保留原始字节并记录错误。
  bool parseQrBytes(List<int> bytes) {
    _qrRaw = List<int>.unmodifiable(bytes);
    try {
      _qrData = JtT1179QrParser.parse(bytes);
      _qrError = null;
      log('二维码解析成功：${bytes.length} 字节');
      notifyListeners();
      return true;
    } catch (e) {
      _qrData = null;
      _qrError = '$e';
      log('二维码解析失败：$e');
      notifyListeners();
      return false;
    }
  }

  /// 解析文本形式的二维码数据（自动识别 HEX / Base64）；
  /// 无法解码为字节或解析失败时返回 false 并记录错误。
  bool parseQrText(String input) {
    final bytes = decodeQrText(input);
    if (bytes == null) {
      _qrRaw = null;
      _qrData = null;
      _qrError = '无法识别输入内容：请输入十六进制或 Base64 编码的二维码数据';
      log('二维码解析失败：输入内容无法识别为 HEX / Base64');
      notifyListeners();
      return false;
    }
    return parseQrBytes(bytes);
  }

  /// 文本 → 字节：十六进制字符串（允许空白 / `:` / `-` 分隔与 `0x` 前缀）
  /// 优先按 HEX 解码，否则回退 Base64；均无法解码时返回 null。
  static List<int>? decodeQrText(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    final compact = text.replaceAll(RegExp(r'[\s:\-]'), '');
    if (compact.isNotEmpty &&
        compact.length.isEven &&
        RegExp(r'^[0-9A-Fa-f]+$').hasMatch(compact)) {
      return [
        for (var i = 0; i < compact.length; i += 2)
          int.parse(compact.substring(i, i + 2), radix: 16),
      ];
    }
    try {
      final normalized = input.trim().replaceAll(RegExp(r'\s'), '');
      final bytes = base64.decode(base64.normalize(normalized));
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// 清除二维码状态（解析结果、原始字节与错误）。
  void clearQr() {
    if (_qrData == null && _qrRaw == null && _qrError == null) return;
    _qrData = null;
    _qrRaw = null;
    _qrError = null;
    notifyListeners();
  }
}
