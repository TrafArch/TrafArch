import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transit_card_analyzer/features/reference_data/data/reference_package.dart';
import 'package:transit_card_analyzer/features/reference_data/data/tunion_knowledge_base.dart';
import 'package:transit_card_analyzer/features/reference_data/domain/reference_match.dart';
import 'package:transit_card_analyzer/features/scan/application/card_read_coordinator.dart';
import 'package:transit_card_analyzer/features/scan/application/scan_controller.dart';
import 'package:transit_card_analyzer/features/scan/domain/card_read_outcome.dart';
import 'package:transit_card_analyzer/platform/nfc/felica_channel.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_models.dart';
import 'package:transit_card_analyzer/platform/nfc/nfc_service.dart';
import 'package:transit_card_analyzer/platform/storage/settings_store.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    directory = Directory.systemTemp.createTempSync('trafarch-contract-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    directory.deleteSync(recursive: true);
  });

  test('actual published packages load independently with separate city namespaces', () async {
    final kb = await KnowledgeBase.load(rootBundle);
    try {
      expect(kb.loadIssues, isEmpty);
      expect(kb.packageHashes.keys, containsAll(['TU', 'CU']));
      expect(kb.cities.lookup('1210')!.name, contains('石家庄'));
      expect(kb.cuCities!.lookup('1210')!.name, contains('锦州'));
      expect(kb.cuRepository!.busRouteCount, 13852);
      expect(kb.tuStations!.stationCount, 8004);
      expect(kb.cities.lookup('5210')!.name, '武汉');
      expect(kb.cities.lookup('5840')!.name, '深圳');
      final package = await ReferencePackage.open('CU', bundle: rootBundle);
      try {
        final document = package.document('card_catalog') as Map;
        final names = document['issuerNames'] as List;
        expect(names, hasLength(36));
        final overrides = document['nameOverrides'] as List;
        expect(overrides, hasLength(1));
        for (final row in [...names, ...overrides].cast<Map>()) {
          expect(row['name_zh_cn'], isNotEmpty);
          for (final removed in ['name_zh_tw', 'name_en', 'name_ja']) {
            expect(row.containsKey(removed), isFalse);
          }
        }
        for (final table in ['cu_card_names', 'cu_name_overrides']) {
          final columns = package.db
              .select('PRAGMA table_info($table)')
              .map((row) => row['name'])
              .toList();
          expect(columns, contains('name_zh_cn'));
          for (final removed in ['name_zh_tw', 'name_en', 'name_ja']) {
            expect(columns, isNot(contains(removed)));
          }
        }
        expect(
          package.db
              .select(
                "SELECT value FROM cu_name_metadata WHERE key='language_order'",
              )
              .single['value'],
          'zh-CN (source language index 1)',
        );
        for (final row in names.cast<Map>()) {
          expect(
            kb.cityUnionCards
                .resolveCard(rawHex: '${row['issuer_code']}${'00' * 26}')
                ?.cardName,
            row['name_zh_cn'],
            reason: '发行标识 ${row['issuer_code']} 必须经 KnowledgeBase.load 消费',
          );
        }
        expect(
          kb.cityUnionCards
              .resolveCard(cityCode: '2000', rawHex: '86982000${'00' * 26}')!
              .cardName,
          '上海公共交通卡',
        );
        expect(
          kb.cityUnionCards
              .resolveCard(
                cityCode: '2000',
                rawHex: '86982000${'00' * 24}4F00',
              )!
              .cardName,
          '上海都市旅游卡',
        );
        expect(
          kb.cityUnionCards
              .resolveCard(cityCode: '2000', rawHex: '12342000${'00' * 26}')!
              .cardName,
          isNull,
        );
      } finally {
        package.close();
      }
    } finally {
      kb.close();
    }
    final cu = await ReferencePackage.open('CU', bundle: _CuOnlyAssets());
    try {
      expect(cu.protocol, 'CU');
      expect(cu.document('card_catalog'), isA<Map>());
      expect(
        () => cu.db.execute('CREATE TABLE forbidden(id INTEGER)'),
        throwsA(anything),
      );
    } finally {
      cu.close();
    }
  });

  test('published CU preserves encoded line and station identifiers', () async {
    final package = await ReferencePackage.open('CU');
    try {
      final rows = package.db.select(
        "SELECT line_code,station_code,source_key,source_field FROM station_lookup "
        "WHERE line_code='0089' AND station_code='0007'",
      );
      expect(rows, isNotEmpty);
      expect(
        rows.every(
          (r) => r['line_code'] == '0089' && r['station_code'] == '0007',
        ),
        isTrue,
      );
      expect(
        rows.every((r) => r['source_key'] != null && r['source_field'] != null),
        isTrue,
      );
    } finally {
      package.close();
    }
  });

  test(
    'CU historical bus fallback requires every documented context condition',
    () async {
      final kb = await KnowledgeBase.load(rootBundle);
      try {
        final repository = kb.cuRepository!;
        final before = DateTime.fromMillisecondsSinceEpoch(1735675199999);
        ReferenceMatchStatus query({
          String region = '5180',
          int? carrier = 1,
          DateTime? at,
          bool enabled = true,
        }) => repository
            .resolveTerminal(
              'FFFFFFFF20000001',
              CuLookupContext(
                regionCode: region,
                decodedCarrierType: carrier,
                transactionTime: at,
                busLookupEnabled: enabled,
              ),
            )
            .status;
        final hit = repository.resolveTerminal(
          'FFFFFFFF20000001',
          CuLookupContext(
            regionCode: '5180',
            decodedCarrierType: 1,
            transactionTime: before,
            busLookupEnabled: true,
          ),
        );
        expect(hit.status, ReferenceMatchStatus.matched);
        expect(hit.value!.line, '963');
        expect(hit.value!.sourceKey, '20000001');
        expect(query(carrier: null, at: before), ReferenceMatchStatus.unknown);
        expect(query(carrier: 6, at: before), ReferenceMatchStatus.unknown);
        expect(query(carrier: 9, at: before), ReferenceMatchStatus.unknown);
        expect(query(region: '1000', at: before), ReferenceMatchStatus.unknown);
        expect(query(at: before, enabled: false), ReferenceMatchStatus.unknown);
        expect(query(), ReferenceMatchStatus.unknown);
        expect(
          query(at: DateTime.fromMillisecondsSinceEpoch(1735675200000)),
          ReferenceMatchStatus.unknown,
        );
      } finally {
        kb.close();
      }
    },
  );

  test(
    'updated TU installs independently of an existing stale cache',
    () async {
      final cache = Directory('${directory.path}/trafarch_reference');
      cache.createSync();
      final stale = File('${cache.path}/tu-${'0' * 64}.sqlite');
      stale.writeAsStringSync('old package');
      final package = await ReferencePackage.open('TU');
      try {
        expect(
          package.hash,
          'fa585d815b8f29ec52183e71f783ffa3acd7eacf1ca74907c44f5150e7529deb',
        );
        expect(
          package.db
              .select('SELECT COUNT(*) AS c FROM all_records')
              .single['c'],
          8004,
        );
        expect(
          File('${cache.path}/tu-${package.hash}.sqlite').existsSync(),
          isTrue,
        );
        expect(stale.readAsStringSync(), 'old package');
      } finally {
        package.close();
      }
    },
  );

  test('corrupted asset digest is rejected before installation', () async {
    await expectLater(
      ReferencePackage.open('TU', bundle: _TamperedAssets()),
      throwsFormatException,
    );
    expect(
      Directory('${directory.path}/trafarch_reference').existsSync(),
      isFalse,
    );
  });

  test(
    'settings serialize concurrent updates and preserve unrelated keys',
    () async {
      final store = FileSettingsStore();
      final file = File('${directory.path}/${FileSettingsStore.fileName}');
      file.writeAsStringSync('custom=keep\n');
      await Future.wait([
        store.write('first', '1'),
        store.write('second', '2'),
      ]);
      expect(await store.read('custom'), 'keep');
      expect(await store.read('first'), '1');
      expect(await store.read('second'), '2');
      expect(directory.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'unreadable settings are retained and a failed write does not reset them',
    () async {
      final store = FileSettingsStore();
      final file = File('${directory.path}/${FileSettingsStore.fileName}');
      final original = [0xFF, 0xFE, 0xFF];
      file.writeAsBytesSync(original);
      await expectLater(
        store.read('first'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.write('first', '1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.readAsBytesSync(), original);
      file.writeAsStringSync('custom=recovered\n');
      await store.write('first', '1');
      expect(await store.read('custom'), 'recovered');
    },
  );

  test(
    'cancelled discovery cannot publish or close its successor session',
    () async {
      final channel = _Sessions();
      final coordinator = _Coordinator();
      final scan = _scan(channel, coordinator);
      addTearDown(scan.dispose);
      final completed = <String>[];
      scan.onCompleted = (_, id, _, _) async => completed.add(id);
      final first = scan.scanOnce();
      final oldId = channel.pending.keys.single;
      await scan.stop();
      final second = scan.scanOnce();
      final newId = channel.pending.keys.last;
      channel.pending[oldId]!.complete(_tag(oldId));
      await first;
      expect(channel.closed, everyElement(oldId));
      expect(completed, isEmpty);
      expect(scan.phase, ScanPhase.waiting);
      channel.pending[newId]!.complete(_tag(newId));
      await second;
      expect(completed, [newId]);
      expect(scan.tag!.sessionId, newId);
      expect(scan.phase, ScanPhase.complete);
      expect(coordinator.reads, 1);
    },
  );

  test('mismatched echoed session is rejected before parsing', () async {
    final channel = _Sessions();
    final coordinator = _Coordinator();
    final scan = _scan(channel, coordinator);
    addTearDown(scan.dispose);
    final pending = scan.scanOnce();
    channel.pending.values.single.complete(_tag('wrong-session'));
    await pending;
    expect(scan.phase, ScanPhase.failed);
    expect(scan.error, contains('STALE_SESSION'));
    expect(coordinator.reads, 0);
  });

  test(
    'release failure remains visible after otherwise successful parsing',
    () async {
      final channel = _Sessions()..closeFails = true;
      final scan = _scan(channel, _Coordinator());
      addTearDown(scan.dispose);
      final pending = scan.scanOnce();
      channel.pending.values.single.complete(_tag(channel.pending.keys.single));
      await pending;
      expect(scan.outcome, isA<UnsupportedReadOutcome>());
      expect(scan.releaseError, contains('release failed'));
    },
  );
}

ScanController _scan(_Sessions channel, _Coordinator coordinator) =>
    ScanController(
      channel: channel,
      felicaChannel: const MethodChannelFelicaChannel(),
      coordinator: coordinator,
      logEvent: (_) {},
    );

NfcScanResult _tag(String id) => NfcScanResult(
  isoDepConnected: false,
  sessionId: id,
  uid: '01020304',
  technologies: const [],
  timestamp: DateTime.utc(2026),
);

class _Sessions implements SessionNfcChannel {
  final pending = <String, Completer<NfcScanResult?>>{};
  final closed = <String>[];
  bool closeFails = false;
  @override
  Future<NfcScanResult?> scanSession(String sessionId) =>
      (pending[sessionId] = Completer<NfcScanResult?>()).future;
  @override
  Future<void> closeSession(String sessionId) async {
    closed.add(sessionId);
    if (closeFails) throw StateError('release failed');
  }

  @override
  Future<List<int>> exchangeSession(String sessionId, List<int> apdu) async =>
      throw StateError('unexpected I/O');
  @override
  Future<NfcScanResult?> scanOnce() => throw StateError('legacy discovery');
  @override
  Future<void> stopScan() => throw StateError('legacy close');
  @override
  Future<List<int>> transceive(List<int> apdu) =>
      throw StateError('legacy exchange');
}

class _Coordinator extends CardReadCoordinator {
  _Coordinator() : super(MissingTestAssets());
  int reads = 0;
  @override
  Future<CardReadOutcome> read(
    NfcScanResult tag, {
    required Future<List<int>> Function(List<int>) apdu,
    required Future<List<int>> Function(List<int>) felica,
    required void Function(String) onStage,
    required void Function(int) onProgress,
  }) async {
    reads++;
    return const UnsupportedReadOutcome();
  }
}

class _CuOnlyAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.contains('_TU.sqlite')) throw StateError('CU attempted to load TU');
    return rootBundle.load(key);
  }
}

class _TamperedAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await rootBundle.load(key);
    if (!key.endsWith('_TU.sqlite')) return bytes;
    final corrupt = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    corrupt[0] ^= 1;
    return ByteData.sublistView(corrupt);
  }
}
