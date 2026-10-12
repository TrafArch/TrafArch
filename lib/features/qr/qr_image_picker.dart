import 'package:flutter/services.dart';

/// 原生相册选图通道（Android 侧见 MainActivity：transit_card_analyzer/qr_image）。
///
/// 使用系统照片选择器 / 文件选择器选择图片，无需申请存储权限；
/// 所选图片由原生侧复制到应用私有缓存目录后回传绝对路径。
const MethodChannel qrImagePickerChannel =
    MethodChannel('transit_card_analyzer/qr_image');

/// 打开系统相册选择一张二维码图片。
///
/// 返回原生侧缓存后的图片绝对路径；用户取消时返回 null。
/// 等待 5 分钟未收到结果（如 Activity 被系统回收导致回调丢失）时抛出
/// TimeoutException，调用方可据此恢复界面状态。
Future<String?> pickQrImageFromGallery() {
  return qrImagePickerChannel
      .invokeMethod<String>('pickImage')
      .timeout(const Duration(minutes: 5));
}