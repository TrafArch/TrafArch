import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/app/app_dependencies.dart';
import 'package:transit_card_analyzer/features/settings/presentation/feedback_page.dart';
import 'package:transit_card_analyzer/features/settings/presentation/survey_page.dart';
import 'package:transit_card_analyzer/platform/storage/app_logger.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browserChannel = MethodChannel('transit_card_analyzer/browser');
  const emailChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(browserChannel, null);
    messenger.setMockMethodCallHandler(emailChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  AppDependencies createApp() {
    final app = AppDependencies(
      database: testDatabase(),
      settingsStore: MemorySettingsStore(),
      logger: AppLogger(store: MemoryLogStore()),
    );
    addTearDown(app.dispose);
    return app;
  }

  testWidgets('问卷启动浏览器且保留反馈页，不创建旧 WebView', (tester) async {
    final launched = <String>[];
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      launched.add((call.arguments as Map)['url'] as String);
      return 'com.microsoft.emmx';
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));

    await tester.tap(find.text('填写反馈问卷'));
    await tester.pumpAndSettle();

    expect(launched, [
      'https://trafarch.feishu.cn/share/base/form/shrcniZ6QaPgqGazU1bpdmZyNPh',
    ]);
    expect(find.byType(FeedbackPage), findsOneWidget);
    expect(find.byType(SurveyPage), findsNothing);
    expect(find.text('暂时无法打开问卷'), findsNothing);
  });

  testWidgets('无浏览器失败留页，可复制问卷地址并重新尝试', (tester) async {
    var launches = 0;
    String? copied;
    messenger.setMockMethodCallHandler(browserChannel, (_) async {
      launches++;
      if (launches == 1) throw PlatformException(code: 'BROWSER_UNAVAILABLE');
      return 'com.android.chrome';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));

    await tester.tap(find.text('填写反馈问卷'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackPage), findsOneWidget);
    expect(find.byType(SurveyPage), findsNothing);
    expect(find.text('暂时无法打开问卷'), findsOneWidget);
    expect(find.textContaining('Edge 或 Chrome'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('复制问卷链接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制问卷链接'));
    await tester.pumpAndSettle();
    expect(
      copied,
      'https://trafarch.feishu.cn/share/base/form/shrcniZ6QaPgqGazU1bpdmZyNPh',
    );

    await tester.ensureVisible(find.text('重新打开问卷'));
    await tester.tap(find.text('重新打开问卷'));
    await tester.pumpAndSettle();
    expect(launches, 2);
    expect(find.text('暂时无法打开问卷'), findsNothing);
    expect(find.byType(FeedbackPage), findsOneWidget);
  });

  testWidgets('浏览器调用未完成时防止重复启动', (tester) async {
    final pending = Completer<String>();
    var launches = 0;
    messenger.setMockMethodCallHandler(browserChannel, (_) {
      launches++;
      return pending.future;
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));

    await tester.tap(find.text('填写反馈问卷'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(launches, 1);

    pending.complete('com.microsoft.emmx');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('邮箱可复制且不会启动邮件应用', (tester) async {
    String? copied;
    var launches = 0;
    messenger.setMockMethodCallHandler(emailChannel, (_) async {
      launches++;
      return true;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));
    await tester.tap(find.byTooltip('复制邮箱'));
    await tester.pumpAndSettle();
    expect(copied, 'support@trafarch.top');
    expect(launches, 0);
    expect(find.text('邮箱地址已复制到剪贴板'), findsOneWidget);
  });

  testWidgets('点按邮箱使用外部应用打开 mailto', (tester) async {
    MethodCall? launched;
    messenger.setMockMethodCallHandler(emailChannel, (call) async {
      launched = call;
      return true;
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));
    await tester.tap(find.text('邮箱'));
    await tester.pumpAndSettle();
    expect(launched?.method, 'launch');
    expect((launched!.arguments as Map)['url'], 'mailto:support@trafarch.top');
    expect((launched!.arguments as Map)['useWebView'], isFalse);
    expect(find.byType(FeedbackPage), findsOneWidget);
  });

  for (final throwsError in [false, true]) {
    testWidgets('邮件应用启动失败可继续复制邮箱（异常：$throwsError）', (tester) async {
      messenger.setMockMethodCallHandler(emailChannel, (_) async {
        if (throwsError) throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
        return false;
      });
      await tester.pumpWidget(
        MaterialApp(home: FeedbackPage(app: createApp())),
      );
      await tester.tap(find.text('邮箱'));
      await tester.pumpAndSettle();
      expect(find.text('无法打开邮件应用，请安装或启用邮件应用，或复制邮箱地址。'), findsOneWidget);
      expect(find.byTooltip('复制邮箱'), findsOneWidget);
      expect(find.byType(FeedbackPage), findsOneWidget);
    });
  }

  testWidgets('QQ 群号仍可复制', (tester) async {
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: FeedbackPage(app: createApp())));

    await tester.tap(find.byTooltip('复制群号'));
    await tester.pumpAndSettle();

    expect(copied, '1106608008');
    expect(find.text('QQ 群号已复制到剪贴板'), findsOneWidget);
  });
}
