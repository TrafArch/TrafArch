import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/qr/qr_image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(qrImagePickerChannel, null);
  });

  test('成功选择：返回原生回传的图片绝对路径', () async {
    messenger.setMockMethodCallHandler(qrImagePickerChannel, (call) async {
      expect(call.method, 'pickImage');
      return '/data/user/0/com.kajolno.TrafArch/cache/qr_picked/picked_1.img';
    });

    final path = await pickQrImageFromGallery();

    expect(
      path,
      '/data/user/0/com.kajolno.TrafArch/cache/qr_picked/picked_1.img',
    );
  });

  test('用户取消：返回 null', () async {
    messenger.setMockMethodCallHandler(qrImagePickerChannel, (call) async {
      return null;
    });

    expect(await pickQrImageFromGallery(), isNull);
  });

  test('原生读取失败：PlatformException 向上传播', () async {
    messenger.setMockMethodCallHandler(qrImagePickerChannel, (call) async {
      throw PlatformException(
        code: 'IMAGE_READ_FAILED',
        message: '无法打开所选图片',
      );
    });

    await expectLater(
      pickQrImageFromGallery(),
      throwsA(isA<PlatformException>()),
    );
  });
}