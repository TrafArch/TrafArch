import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'packaged Suica station database matches its packaged manifest',
    () async {
      final manifest = jsonDecode(
        await rootBundle.loadString('assets/suica/manifest.json'),
      ) as Map<String, dynamic>;
      final spec = manifest['database'] as Map<String, dynamic>;
      final data = await rootBundle.load('assets/suica/${spec['file']}');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, spec['bytes']);
      expect(sha256.convert(bytes).toString(), spec['sha256']);
    },
  );

  test(
    'packaged Amusement IC licenses and attribution can be loaded',
    () async {
      final license = await rootBundle.loadString(
        'third_party/amusement_ic/MPL-2.0.txt',
      );
      final attribution = await rootBundle.loadString(
        'third_party/amusement_ic/README.md',
      );
      expect(license, contains('Mozilla Public License Version 2.0'));
      expect(attribution, contains('PN532-Aime-Reader'));
    },
  );
}
