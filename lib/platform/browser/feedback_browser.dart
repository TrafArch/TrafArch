import 'package:flutter/services.dart';

/// Opens a web page using the supported browser's Android Custom Tab.
abstract interface class FeedbackBrowser {
  Future<void> open(Uri url);
}

class FeedbackBrowserException implements Exception {
  const FeedbackBrowserException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MethodChannelFeedbackBrowser implements FeedbackBrowser {
  const MethodChannelFeedbackBrowser();

  static const _channel = MethodChannel('transit_card_analyzer/browser');
  static const _unavailable =
      '无法启动 Edge 或 Chrome 的应用内浏览器。请安装或启用其中一个浏览器后重试，'
      '也可复制问卷链接自行打开。';

  @override
  Future<void> open(Uri url) async {
    if (!{'http', 'https'}.contains(url.scheme) || url.host.isEmpty) {
      throw const FeedbackBrowserException('问卷地址无效，请复制链接检查。');
    }
    try {
      final provider = await _channel.invokeMethod<String>('openCustomTab', {
        'url': url.toString(),
      });
      if (!{'com.microsoft.emmx', 'com.android.chrome'}.contains(provider)) {
        throw const FeedbackBrowserException(_unavailable);
      }
    } on MissingPluginException {
      throw const FeedbackBrowserException(_unavailable);
    } on PlatformException catch (error) {
      throw FeedbackBrowserException(
        error.code == 'INVALID_URL' ? '问卷地址无效，请复制链接检查。' : _unavailable,
      );
    }
  }
}
