import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/qr/application/qr_acquisition.dart';

void main() {
  const acquisition = QrAcquisition();

  group('应用内相机获取', () {
    test('仅打开一次相机并原样保留二进制载荷', () async {
      var cameraCalls = 0;
      final source = [0x00, 0x80, 0x91, 0xff];
      final result = await acquisition.scan(
        openCamera: () async {
          cameraCalls++;
          return source;
        },
      );

      expect(cameraCalls, 1);
      expect(result, isA<AcquiredQrPayload>());
      final payload = result as AcquiredQrPayload;
      expect(payload.origin, QrPayloadOrigin.camera);
      expect(payload.bytes, [0x00, 0x80, 0x91, 0xff]);
      source[0] = 1;
      expect(payload.bytes.first, 0);
      expect(() => payload.bytes.add(1), throwsUnsupportedError);
    });

    test('等待相机返回后再完成获取', () async {
      final camera = Completer<List<int>?>();
      var completed = false;
      final pending = acquisition.scan(openCamera: () => camera.future);
      unawaited(pending.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      camera.complete([0x91]);
      expect(await pending, isA<AcquiredQrPayload>());
      expect(completed, isTrue);
    });

    test('相机取消返回取消结果', () async {
      final result = await acquisition.scan(openCamera: () async => null);
      expect(result, isA<QrAcquisitionCancelled>());
    });

    test('空载荷返回取消结果', () async {
      final result = await acquisition.scan(openCamera: () async => []);
      expect(result, isA<QrAcquisitionCancelled>());
    });

    test('相机调用异常保持向上传播', () async {
      final error = StateError('camera unavailable');
      await expectLater(
        acquisition.scan(openCamera: () async => throw error),
        throwsA(same(error)),
      );
    });
  });
}
