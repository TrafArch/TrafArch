import 'package:flutter/services.dart';

/// Opens a web page in an Android browser.
///
/// 原生层不再固定浏览器包名：任何提供 Custom Tabs 服务的浏览器（Edge、Chrome、
/// Firefox Beta/Nightly、Brave、Vivaldi、Kiwi、三星互联网等）都可以打开。
/// Custom Tabs 不可用或启动失败时改用默认浏览器；两种方式都无法打开时，
/// 链接会自动复制到剪贴板，并抛出
/// [FeedbackBrowserException] （`copiedToClipboard == true`）供界面提示用户。
abstract interface class FeedbackBrowser {
  Future<void> open(Uri url);
}

class FeedbackBrowserException implements Exception {
  const FeedbackBrowserException(
    this.message, {
    this.copiedToClipboard = false,
  });

  final String message;

  /// 无可用浏览器时链接已复制到剪贴板，界面应以此为气泡提示而非可重试错误。
  final bool copiedToClipboard;

  @override
  String toString() => message;
}

class MethodChannelFeedbackBrowser implements FeedbackBrowser {
  const MethodChannelFeedbackBrowser();

  static const _channel = MethodChannel('transit_card_analyzer/browser');

  static const _copiedMessage = '链接已复制到剪贴板，请前往浏览器打开';

  @override
  Future<void> open(Uri url) async {
    if (!{'http', 'https'}.contains(url.scheme) || url.host.isEmpty) {
      throw const FeedbackBrowserException('问卷地址无效，请复制链接检查。');
    }
    final String? provider;
    try {
      provider = await _channel.invokeMethod<String>('openCustomTab', {
        'url': url.toString(),
      });
    } on MissingPluginException {
      await _copyToClipboard(url);
      throw const FeedbackBrowserException(
        _copiedMessage,
        copiedToClipboard: true,
      );
    } on PlatformException catch (error) {
      if (error.code == 'INVALID_URL') {
        throw const FeedbackBrowserException('问卷地址无效，请复制链接检查。');
      }
      await _copyToClipboard(url);
      throw const FeedbackBrowserException(
        _copiedMessage,
        copiedToClipboard: true,
      );
    }
    if (provider == null) {
      // Custom Tabs 和默认浏览器均无法打开：复制链接并提示用户手动打开。
      await _copyToClipboard(url);
      throw const FeedbackBrowserException(
        _copiedMessage,
        copiedToClipboard: true,
      );
    }
  }

  Future<void> _copyToClipboard(Uri url) =>
      Clipboard.setData(ClipboardData(text: url.toString()));
}
