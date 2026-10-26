import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/platform/storage/archive_document_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const store = MethodChannelArchiveDocumentStore();
  const channel = MethodChannel('transit_card_analyzer/archive_documents');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('打开 JSON 保留所选文件名称和完整 UTF-8 文本', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {'name': '乘车记录.json', 'content': '{"卡号":"00123"}'};
    });
    final picked = await store.openJson();
    expect(received?.method, 'openJson');
    expect(picked?.name, '乘车记录.json');
    expect(picked?.content, '{"卡号":"00123"}');
  });

  test('另存为 JSON 使用专用通道并保留文件内容', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return '卡片备份.json';
    });
    final saved = await store.saveJson('卡片备份.json', '{"records":[]}');
    expect(saved, '卡片备份.json');
    expect(received?.method, 'saveJson');
    expect(received?.arguments, {
      'fileName': '卡片备份.json',
      'content': '{"records":[]}',
    });
  });

  test('用户取消打开或保存均返回 null', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await store.openJson(), isNull);
    expect(await store.saveJson('archive.json', '{}'), isNull);
  });

  test('非法文件名在调用平台前拒绝', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return 'saved.json';
    });
    for (final name in [
      '../x.json',
      'a\\b.json',
      'card.txt',
      '',
      'x\u0000.json',
    ]) {
      await expectLater(store.saveJson(name, '{}'), throwsArgumentError);
    }
    expect(calls, 0);
  });

  test('原生返回错误结构不能当作已成功读取文件', () async {
    for (final response in [
      <String, Object?>{'name': 'x.json'},
      <String, Object?>{'name': 'x.json', 'content': 12},
      <String, Object?>{'name': '', 'content': '{}'},
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(store.openJson(), throwsA(isA<PlatformException>()));
    }
  });

  test('平台存储失败保持失败，不能返回伪成功文件名', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'DOCUMENT_WRITE_FAILED', message: '空间不足');
    });
    await expectLater(
      store.saveJson('archive.json', '{}'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'DOCUMENT_WRITE_FAILED',
        ),
      ),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => '');
    await expectLater(
      store.saveJson('archive.json', '{}'),
      throwsA(isA<PlatformException>()),
    );
  });
}
