import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/browser/feedback_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const browser = MethodChannelFeedbackBrowser();
  const channel = MethodChannel('transit_card_analyzer/browser');

  String? copied;
  setUp(() {
    copied = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('问卷使用专用 Custom Tab 通道并传递完整 URL', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'com.microsoft.emmx';
    });

    await browser.open(Uri.parse('https://example.com/form?id=001#upload'));

    expect(received?.method, 'openCustomTab');
    expect(received?.arguments, {
      'url': 'https://example.com/form?id=001#upload',
    });
    expect(copied, isNull);
  });

  test('拒绝非网页地址且不调用平台', () async {
    var launches = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      launches++;
      return 'com.microsoft.emmx';
    });

    for (final url in ['file:///tmp/a', 'javascript:alert(1)', 'https:/form']) {
      await expectLater(
        browser.open(Uri.parse(url)),
        throwsA(isA<FeedbackBrowserException>()),
      );
    }
    expect(launches, 0);
    expect(copied, isNull);
  });

  test('任何返回的 Custom Tabs 提供方都视为启动成功，不再校验白名单', () async {
    for (final provider in [
      'org.mozilla.firefox_beta',
      'com.brave.browser',
      'com.vivaldi.browser',
      'com.android.chrome.canary',
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => provider);
      await expectLater(
        browser.open(Uri.parse('https://example.com/form')),
        completes,
      );
    }
    expect(copied, isNull);
  });

  test('原生层返回 null 时复制链接并带剪贴板标记抛错', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(
        isA<FeedbackBrowserException>()
            .having((e) => e.copiedToClipboard, 'copiedToClipboard', isTrue)
            .having(
              (e) => e.message,
              'message',
              '链接已复制到剪贴板，请前往浏览器打开',
            ),
      ),
    );
    expect(copied, 'https://example.com/form');
  });

  test('没有原生通道时复制链接并带剪贴板标记抛错', () async {
    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(
        isA<FeedbackBrowserException>().having(
          (e) => e.copiedToClipboard,
          'copiedToClipboard',
          isTrue,
        ),
      ),
    );
    expect(copied, 'https://example.com/form');
  });

  test('浏览器不可用错误也走剪贴板回退', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'BROWSER_UNAVAILABLE');
    });

    await expectLater(
      browser.open(Uri.parse('https://example.com/survey')),
      throwsA(
        isA<FeedbackBrowserException>()
            .having((e) => e.copiedToClipboard, 'copiedToClipboard', isTrue)
            .having(
              (e) => e.message,
              'message',
              '链接已复制到剪贴板，请前往浏览器打开',
            ),
      ),
    );
    expect(copied, 'https://example.com/survey');
  });

  test('无效地址标记 INVALID_URL 时不假报复制', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'INVALID_URL');
    });

    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(
        isA<FeedbackBrowserException>()
            .having((e) => e.copiedToClipboard, 'copiedToClipboard', isFalse)
            .having((e) => e.message, 'message', contains('无效')),
      ),
    );
    expect(copied, isNull);
  });
}
