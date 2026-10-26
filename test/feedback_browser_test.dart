import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/browser/feedback_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const browser = MethodChannelFeedbackBrowser();
  const channel = MethodChannel('transit_card_analyzer/browser');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

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
  });

  test('没有受支持浏览器时返回可展示的失败而不尝试其他通道', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'BROWSER_UNAVAILABLE');
    });

    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(
        isA<FeedbackBrowserException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Edge'), contains('Chrome')),
        ),
      ),
    );
  });

  test('没有原生通道或返回未知提供方不能假报启动成功', () async {
    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(isA<FeedbackBrowserException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => 'other.browser');
    await expectLater(
      browser.open(Uri.parse('https://example.com/form')),
      throwsA(isA<FeedbackBrowserException>()),
    );
  });
}
