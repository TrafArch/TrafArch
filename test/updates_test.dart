import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/reference_package.dart';
import 'package:transit_card_analyzer/features/reference_data/data/reference_updates.dart';
import 'package:transit_card_analyzer/features/settings/presentation/about_page.dart';
import 'package:transit_card_analyzer/features/updates/update_service.dart';
import 'package:transit_card_analyzer/features/updates/update_prompt.dart';
import 'package:transit_card_analyzer/features/reference_data/application/reference_data_controller.dart';

import 'support/published_reference_fixture.dart';

Map<String, dynamic> appManifest(int build) => {
  'format_version': 1,
  'app': {
    'build': build,
    'version': 'next',
    'notes': '更新说明',
    'download_url': 'https://example.com/app.apk',
  },
};

class FixtureBundle extends CachingAssetBundle {
  FixtureBundle(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(files[key]!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual checks bypass startup cache without replacing it', () async {
    var calls = 0;
    final service = UpdateService(
      currentBuild: 1,
      manifestUrl: 'https://example.com/manifest.json',
      fetch: (_, _) async =>
          Uint8List.fromList(utf8.encode(jsonEncode(appManifest(++calls)))),
    );
    expect((await service.checkOnce())!.build, 1);
    expect((await service.checkNow())!.build, 2);
    expect((await service.checkNow())!.build, 3);
    expect((await service.checkOnce())!.build, 1);
    expect(calls, 3);
  });

  for (final invalidFormat in [false, true]) {
    testWidgets(
      'manual failure reports error, startup silent: $invalidFormat',
      (tester) async {
        var calls = 0;
        final service = UpdateService(
          currentBuild: 1,
          manifestUrl: 'https://example.com/manifest.json',
          fetch: (_, _) async {
            calls++;
            if (!invalidFormat) throw const SocketException('offline');
            return Uint8List.fromList(utf8.encode('{}'));
          },
        );
        expect(await service.checkOnce(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: AboutPage(updates: service, openPrivacyPolicy: () async {}),
          ),
        );
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
        expect(find.text('检查更新失败，请稍后重试'), findsOneWidget);
        expect(find.text('暂无更新'), findsNothing);
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
        expect(calls, 3);
      },
    );
  }

  testWidgets('unconfigured about hides update button and never fetches', (
    tester,
  ) async {
    var calls = 0;
    final service = UpdateService(
      currentBuild: 1,
      manifestUrl: '',
      fetch: (_, _) async {
        calls++;
        throw StateError('must not fetch');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(updates: service, openPrivacyPolicy: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('检查更新'), findsNothing);
    expect(await service.checkNow(), isNull);
    expect(await service.checkOnce(), isNull);
    expect(calls, 0);
  });

  for (final build in [1, 2, 3]) {
    testWidgets('manual about check build $build and shared download dialog', (
      tester,
    ) async {
      Uri? opened;
      final service = UpdateService(
        currentBuild: 2,
        manifestUrl: 'https://example.com/manifest.json',
        fetch: (_, _) async =>
            Uint8List.fromList(utf8.encode(jsonEncode(appManifest(build)))),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AboutPage(
            updates: service,
            openPrivacyPolicy: () async {},
            openUrl: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      if (build <= 2) {
        expect(find.text('暂无更新'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.text('发现新版本 next'), findsOneWidget);
        await tester.tap(find.text('暂不更新'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查更新'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('前往下载'));
        await tester.pumpAndSettle();
        expect(opened.toString(), 'https://example.com/app.apk');
        expect(find.byType(AlertDialog), findsNothing);
      }
    });
  }

  testWidgets(
    'pending manual check disables duplicates and tolerates disposal',
    (tester) async {
      var calls = 0;
      final pending = Completer<Uint8List>();
      final service = UpdateService(
        currentBuild: 1,
        manifestUrl: 'https://example.com/manifest.json',
        fetch: (_, _) {
          calls++;
          return pending.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AboutPage(updates: service, openPrivacyPolicy: () async {}),
        ),
      );
      final button = find.byType(OutlinedButton);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      pending.complete(
        Uint8List.fromList(utf8.encode(jsonEncode(appManifest(2)))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in [
    'missing document',
    'missing both fields',
    'missing issuerNames',
    'missing nameOverrides',
    'issuerNames not list',
    'empty issuerNames',
    'nameOverrides not list',
    'empty nameOverrides',
  ]) {
    test('CU naming contract and restore: $variant', () async {
      final directory = await Directory.systemTemp.createTemp('cu-contract-');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, (_) async => directory.path);
      final controller = ReferenceDataController(rootBundle);
      try {
        // Change only the catalog in a copy of the published package, then
        // recompute the digest so rejection cannot be caused by corruption.
        final manifest = jsonDecode(
          await rootBundle.loadString('assets/data/reference_manifest.json'),
        ) as Map<String, dynamic>;
        final builtinSpec = Map<String, dynamic>.from(
          (manifest['packages'] as Map)['CU'] as Map,
        );
        final data = await rootBundle.load(
          'assets/data/${builtinSpec['file']}',
        );
        final candidate = File('${directory.path}/candidate.sqlite');
        await candidate.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final db = sqlite3.open(candidate.path);
        try {
          final catalog = jsonDecode(
            db
                    .select(
                      "SELECT json FROM reference_documents WHERE name = 'card_catalog'",
                    )
                    .single['json']
                as String,
          ) as Map<String, dynamic>;
          switch (variant) {
            case 'missing both fields':
              catalog.remove('issuerNames');
              catalog.remove('nameOverrides');
            case 'missing issuerNames':
              catalog.remove('issuerNames');
            case 'missing nameOverrides':
              catalog.remove('nameOverrides');
            case 'issuerNames not list':
              catalog['issuerNames'] = {};
            case 'empty issuerNames':
              catalog['issuerNames'] = [];
            case 'nameOverrides not list':
              catalog['nameOverrides'] = {};
            case 'empty nameOverrides':
              catalog['nameOverrides'] = [];
          }
          if (variant == 'missing document') {
            db.execute(
              "DELETE FROM reference_documents WHERE name = 'card_catalog'",
            );
          } else {
            db.execute(
              "UPDATE reference_documents SET json = ? WHERE name = 'card_catalog'",
              [jsonEncode(catalog)],
            );
          }
        } finally {
          db.close();
        }
        final bytes = await candidate.readAsBytes();
        final spec = {
          ...builtinSpec,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        };
        (manifest['packages'] as Map)['CU'] = spec;
        final bundle = FixtureBundle({
          'assets/data/reference_manifest.json': Uint8List.fromList(
            utf8.encode(jsonEncode(manifest)),
          ),
          'assets/data/${spec['file']}': bytes,
        });
        final valid = variant == 'empty nameOverrides';
        if (valid) {
          final package = await ReferencePackage.open('CU', bundle: bundle);
          package.close();
        } else {
          await expectLater(
            ReferencePackage.open('CU', bundle: bundle),
            throwsFormatException,
          );
        }

        // Simulate a package persisted by an older app, bypassing stage's
        // current validation. Keep its metadata/content version unchanged.
        final stored = await Directory(
          '${directory.path}/trafarch_reference_updates',
        ).create();
        final oldFile = File('${stored.path}/${spec['sha256']}.sqlite');
        await oldFile.writeAsBytes(bytes);
        final record = File('${stored.path}/CU.json');
        final recordText = jsonEncode({
          'url': 'https://example.com/CU.sqlite',
          'package': spec,
        });
        await record.writeAsString(recordText);
        final updates = ReferenceUpdates(rootBundle);
        await updates.restore();
        expect(updates.active.containsKey('CU'), valid);
        await controller.initialize();
        expect(controller.error, isNull);
        expect(controller.knowledge!.loadIssues, isEmpty);
        expect(
          controller.knowledge!.packageHashes['CU'],
          valid ? spec['sha256'] : builtinSpec['sha256'],
        );
        expect(
          controller.knowledge!.packageHashes['TU'],
          (manifest['packages'] as Map)['TU']['sha256'],
        );
        expect(
          controller.knowledge!.cityUnionCards
              .resolveCard(rawHex: '86982000${'00' * 26}')
              ?.cardName,
          '上海公共交通卡',
        );
        expect(await record.readAsString(), recordText);
        expect(await oldFile.readAsBytes(), bytes);
      } finally {
        controller.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    });
  }

  test('CU independent install and restart preserve TU', () async {
    final directory = await Directory.systemTemp.createTemp('cu-updates-test-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    final files = <String, Uint8List>{};
    for (final name in [
      'reference_manifest.json',
      'TrafArch_Database_TU.sqlite',
      'TrafArch_Database_CU.sqlite',
    ]) {
      files['assets/data/$name'] = await File('assets/data/$name')
          .readAsBytes();
    }
    final bundle = FixtureBundle(files);
    final manifest = jsonDecode(
      utf8.decode(files['assets/data/reference_manifest.json']!),
    ) as Map;
    final spec = Map<String, dynamic>.from(
      (manifest['packages'] as Map)['CU'] as Map,
    );
    final update = ReferenceUpdate.fromJson({
      'url': 'https://example.com/CU.sqlite',
      'package': spec,
    });
    final controller = ReferenceDataController(bundle);
    final restart = ReferenceDataController(bundle);
    try {
      await controller.initialize();
      final tuHash = controller.knowledge!.packageHashes['TU'];
      await controller.installUpdate(
        'CU',
        update,
        fetch: (_, _) async => files['assets/data/${spec['file']}']!,
      );
      expect(controller.knowledge!.loadIssues, isEmpty);
      expect(controller.knowledge!.packageHashes['TU'], tuHash);
      await restart.initialize();
      expect(restart.knowledge!.packageHashes['CU'], spec['sha256']);
      expect(restart.knowledge!.packageHashes['TU'], tuHash);
    } finally {
      restart.dispose();
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    }
  });
  test(
    'disabled means zero fetches; build comparison and invalid URLs',
    () async {
      var calls = 0;
      final service = UpdateService(
        currentBuild: 2086,
        manifestUrl: '',
        fetch: (_, _) async {
          calls++;
          throw StateError('must not fetch');
        },
      );
      expect(await service.checkOnce(), isNull);
      expect(calls, 0);
      for (final build in [2085, 2086, 2087]) {
        expect(
          UpdateManifest.fromJson(appManifest(build)).isNewerThan(2086),
          build > 2086,
        );
      }
      for (final url in [
        'http://example.com',
        'file:///tmp/a',
        'https://user:pass@example.com',
        'https:///',
      ]) {
        expect(() => secureUpdateUri(url), throwsFormatException);
        expect(
          await UpdateService(
            currentBuild: 1,
            manifestUrl: url,
            fetch: (_, _) async {
              calls++;
              throw StateError('invalid');
            },
          ).checkOnce(),
          isNull,
        );
      }
      expect(calls, 0);
    },
  );

  testWidgets(
    'first frame prompt, once only, cancellable and external download',
    (tester) async {
      var calls = 0;
      Uri? opened;
      final service = UpdateService(
        currentBuild: 2086,
        manifestUrl: 'https://example.com/manifest.json',
        fetch: (_, _) async {
          calls++;
          return Uint8List.fromList(utf8.encode(jsonEncode(appManifest(2087))));
        },
      );
      Widget app() => MaterialApp(
        home: UpdatePrompt(
          service: service,
          openUrl: (uri) async {
            opened = uri;
            return true;
          },
          child: const Scaffold(),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 next'), findsOneWidget);
      await tester.tap(find.text('暂不更新'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(opened.toString(), 'https://example.com/app.apk');
      expect(calls, 1);
    },
  );

  test('TU independent install persists; digest/schema failure retains old snapshot; corrupt restart falls back', () async {
    final directory = await Directory.systemTemp.createTemp('updates-test-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    final builtin = FixtureBundle(publishTuFixture(null, {}));
    final updated = publishTuFixture(null, {
      'assets/data/tunion_card_prefixes.json':
          '{"entries":[{"prefix":"12345678","issuer":"1234","city":"新城市"}]}',
    });
    final manifest = jsonDecode(
      utf8.decode(updated['assets/data/reference_manifest.json']!),
    ) as Map;
    final spec = Map<String, dynamic>.from(
      (manifest['packages'] as Map)['TU'] as Map,
    );
    final update = ReferenceUpdate.fromJson({
      'url': 'https://example.com/TU.sqlite',
      'package': spec,
    });
    final bytes = updated['assets/data/${spec['file']}']!;
    final controller = ReferenceDataController(builtin);
    ReferenceDataController? restarted;
    try {
      await controller.initialize();
      final old = controller.knowledge!;
      await controller.installUpdate(
        'TU',
        update,
        fetch: (_, _) async => bytes,
      );
      expect(controller.knowledge!.packageHashes['TU'], spec['sha256']);
      expect(old.packageHashes['TU'], isNot(spec['sha256']));
      // Prior ScanPresentation's snapshot remains queryable.
      expect(old.cities.lookup('1234'), isNull);
      final current = controller.knowledge;
      final bad = Uint8List.fromList(bytes)..[0] ^= 1;
      await expectLater(
        controller.installUpdate('TU', update, fetch: (_, _) async => bad),
        throwsFormatException,
      );
      expect(controller.knowledge, same(current));
      final invalid = Uint8List.fromList(utf8.encode('not sqlite'));
      final invalidUpdate = ReferenceUpdate.fromJson({
        'url': 'https://example.com/TU.sqlite',
        'package': {
          ...spec,
          'bytes': invalid.length,
          'sha256': sha256.convert(invalid).toString(),
        },
      });
      await expectLater(
        controller.installUpdate(
          'TU',
          invalidUpdate,
          fetch: (_, _) async => invalid,
        ),
        throwsA(anything),
      );
      expect(controller.knowledge, same(current));
      restarted = ReferenceDataController(builtin);
      await restarted.initialize();
      expect(restarted.knowledge!.packageHashes['TU'], spec['sha256']);
      restarted.dispose();
      restarted = null;
      await File(
        '${directory.path}/trafarch_reference_updates/${spec['sha256']}.sqlite',
      ).writeAsBytes([0]);
      restarted = ReferenceDataController(builtin);
      await restarted.initialize();
      expect(restarted.knowledge!.packageHashes['TU'], old.packageHashes['TU']);
    } finally {
      restarted?.dispose();
      controller.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      await directory.delete(recursive: true);
    }
  });
}
