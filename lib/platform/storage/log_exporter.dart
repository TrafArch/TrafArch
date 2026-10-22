import 'package:flutter/services.dart';

/// 日志导出通道：将文本内容保存到手机下载目录。
abstract class LogExporter {
  /// 保存 [content] 为下载目录下的 [fileName]，返回展示用保存路径。
  /// 失败以 [PlatformException] 抛出（权限拒绝 / 写入失败等）。
  Future<String> saveToDownloads(String fileName, String content);
}

/// 原生（Android MethodChannel）实现：
/// - Android 10+：MediaStore Downloads，无需权限；
/// - Android 9-：公共 Download 目录（需存储权限，由原生层请求）。
class MethodChannelLogExporter implements LogExporter {
  static const _channel = MethodChannel('transit_card_analyzer/export');

  const MethodChannelLogExporter();

  @override
  Future<String> saveToDownloads(String fileName, String content) async {
    final path = await _channel.invokeMethod<String>('saveToDownloads', {
      'fileName': fileName,
      'content': content,
    });
    if (path == null || path.isEmpty) {
      throw PlatformException(code: 'EXPORT_FAILED', message: '原生层未返回保存路径');
    }
    return path;
  }
}
