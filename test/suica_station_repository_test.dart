import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:transit_card_analyzer/features/reference_data/data/suica_station_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('trafarch-suica-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => temporary.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    temporary.deleteSync(recursive: true);
  });

  test('published Tokyo lookup preserves source database bytes', () async {
    final file = File('assets/suica/suica_stationcode.db');
    final before = sha256.convert(file.readAsBytesSync()).toString();
    final repository = await SuicaStationRepository.load(_PublishedBundle());
    try {
      final station = repository.lookup(
        areaCode: 0,
        lineCode: 1,
        stationCode: 1,
      );
      expect(station?.companyName, 'JR東日本');
      expect(station?.lineName, '東海道本');
      expect(station?.stationName, '東京');
      expect(
        repository.hash,
        '57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd',
      );
      expect(
        repository.lookup(areaCode: 255, lineCode: 255, stationCode: 255),
        isNull,
      );
    } finally {
      repository.close();
      repository.close();
    }
    expect(sha256.convert(file.readAsBytesSync()).toString(), before);
  });

  test('lookup uses all three keys and preserves nullable names', () async {
    final bundle = _fixture(temporary, [
      [0, 1, 1, 'first company', 'first line', 'first station'],
      [1, 1, 1, 'second company', 'second line', 'second station'],
      [1, 2, 1, null, null, 'third station'],
      [1, 1, 2, null, '', null],
    ]);
    final repository = await SuicaStationRepository.load(bundle);
    addTearDown(repository.close);
    expect(
      repository.lookup(areaCode: 0, lineCode: 1, stationCode: 1)?.stationName,
      'first station',
    );
    expect(
      repository.lookup(areaCode: 1, lineCode: 1, stationCode: 1)?.stationName,
      'second station',
    );
    final third = repository.lookup(areaCode: 1, lineCode: 2, stationCode: 1);
    expect(third?.stationName, 'third station');
    expect(third?.lineName, isNull);
    final empty = repository.lookup(areaCode: 1, lineCode: 1, stationCode: 2);
    expect(empty, isNotNull);
    expect(empty?.companyName, isNull);
    expect(empty?.lineName, '');
    expect(empty?.stationName, isNull);
    expect(
      repository.lookup(areaCode: -1, lineCode: 1, stationCode: 1),
      isNull,
    );
  });

  test(
    'published hexadecimal station keys match the original reader',
    () async {
      final repository = await SuicaStationRepository.load(_PublishedBundle());
      addTearDown(repository.close);
      for (final (area, line, station, expectedLine, expectedStation) in [
        (1, 0xEF, 0x04, '都営浅草', '蔵前'),
        (1, 0xAE, 0x09, '成田空港', '成田空港'),
        (1, 0xF3, 0x19, '都営大江戸', '東新宿'),
        (1, 0xF3, 0x07, '都営大江戸', '蔵前'),
        (1, 0xF2, 0x22, '都営大江戸', '都庁前'),
        (1, 0xE4, 0x37, '日比谷', '神谷町'),
        (1, 0xE6, 0x21, '半蔵門', '渋谷'),
        (1, 0xE3, 0x31, '銀座', '末広町'),
        (1, 0xE7, 0x0A, '副都心', '東新宿'),
        (3, 0xEF, 0x04, '名古屋', '烏森'),
      ]) {
        final result = repository.lookup(
          areaCode: area,
          lineCode: line,
          stationCode: station,
        );
        expect(result?.lineName, expectedLine);
        expect(result?.stationName, expectedStation);
      }
    },
  );

  test(
    'hexadecimal numbers do not silently select a different station',
    () async {
      final repository = await SuicaStationRepository.load(_PublishedBundle());
      addTearDown(repository.close);
      expect(
        repository
            .lookup(areaCode: 0, lineCode: 3, stationCode: 0x0D)
            ?.stationName,
        '新宿',
      );
      expect(
        repository
            .lookup(areaCode: 0, lineCode: 3, stationCode: 0x13)
            ?.stationName,
        '阿佐ヶ谷',
      );
      expect(
        repository
            .lookup(areaCode: 0, lineCode: 1, stationCode: 0x19)
            ?.stationName,
        '藤沢',
      );
    },
  );

  test('every published hex key resolves to its exact source record', () async {
    final repository = await SuicaStationRepository.load(_PublishedBundle());
    addTearDown(repository.close);
    final source = sqlite3.open(
      'assets/suica/suica_stationcode.db',
      mode: OpenMode.readOnly,
    );
    addTearDown(source.close);
    final rows = source.select('SELECT * FROM stationcode');
    expect(rows, hasLength(6435));
    for (final row in rows) {
      // Source keys are hex strings even where SQLite stores numeric-looking
      // strings as INTEGER. Decode the database's namespace into NFC bytes.
      final result = repository.lookup(
        areaCode: int.parse('${row['areacode']}', radix: 16),
        lineCode: int.parse('${row['linecode']}', radix: 16),
        stationCode: int.parse('${row['stationorder']}', radix: 16),
      );
      expect(result, isNotNull, reason: 'source row ${row['_id']}');
      expect(result!.companyName, row['companyname']);
      expect(result.lineName, row['linename']);
      expect(result.stationName, row['stationname']);
    }
  });

  test(
    'conflicting exact-key matches remain unknown, identical duplicates agree',
    () async {
      final repository = await SuicaStationRepository.load(
        _fixture(temporary, [
          [0, 1, 1, 'a', 'line', 'station'],
          [0, 1, 1, 'b', 'line', 'station'],
          [0, 1, 2, 'same', 'line', 'station'],
          [0, 1, 2, 'same', 'line', 'station'],
        ]),
      );
      addTearDown(repository.close);
      expect(
        repository.lookup(areaCode: 0, lineCode: 1, stationCode: 1),
        isNull,
      );
      expect(
        repository
            .lookup(areaCode: 0, lineCode: 1, stationCode: 2)
            ?.companyName,
        'same',
      );
    },
  );

  test('invalid asset digest is rejected instead of queried', () async {
    final bundle = _fixture(temporary, [
      [0, 1, 1, 'a', 'line', 'station'],
    ]);
    bundle.manifest['database']['sha256'] = '0' * 64;
    await expectLater(
      SuicaStationRepository.load(bundle),
      throwsFormatException,
    );
  });

  test(
    'bad cached bytes are replaced only with verified source bytes',
    () async {
      final bundle = _fixture(temporary, [
        [0, 1, 1, 'a', 'line', 'station'],
      ]);
      final initial = await SuicaStationRepository.load(bundle);
      initial.close();
      final cached = temporary
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith(
              '${bundle.manifest['database']['sha256']}.db',
            ),
          )
          .single;
      cached.writeAsBytesSync([1, 2, 3]);
      final reopened = await SuicaStationRepository.load(bundle);
      addTearDown(reopened.close);
      expect(
        reopened.lookup(areaCode: 0, lineCode: 1, stationCode: 1)?.stationName,
        'station',
      );
      expect(cached.readAsBytesSync(), bundle.bytes);
    },
  );

  test('concurrent loads share recovery of a damaged cache', () async {
    final bundle = _fixture(temporary, [
      [0, 1, 1, 'a', 'line', 'station'],
    ]);
    final initial = await SuicaStationRepository.load(bundle);
    initial.close();
    final cached = temporary
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('${bundle.manifest['database']['sha256']}.db'),
        )
        .single;
    cached.writeAsBytesSync([1, 2, 3]);
    final repositories = <SuicaStationRepository>[];
    final failures = <Object>[];
    await Future.wait([
      for (var i = 0; i < 6; i++)
        SuicaStationRepository.load(bundle).then<void>(
          repositories.add,
          onError: (Object error) => failures.add(error),
        ),
    ]);
    try {
      expect(failures, isEmpty);
      expect(repositories, hasLength(6));
      for (final repository in repositories) {
        expect(
          repository
              .lookup(areaCode: 0, lineCode: 1, stationCode: 1)
              ?.stationName,
          'station',
        );
      }
      expect(cached.readAsBytesSync(), bundle.bytes);
    } finally {
      for (final repository in repositories) {
        repository.close();
      }
    }
  });
}

class _PublishedBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

class _FixtureBundle extends CachingAssetBundle {
  _FixtureBundle(this.bytes, this.manifest);
  final Uint8List bytes;
  final Map<String, dynamic> manifest;

  @override
  Future<ByteData> load(String key) async => switch (key) {
    'assets/suica/manifest.json' => ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    ),
    'assets/suica/suica_stationcode.db' => ByteData.sublistView(bytes),
    _ => throw StateError('Unexpected asset: $key'),
  };
}

_FixtureBundle _fixture(Directory directory, List<List<Object?>> rows) {
  final file = File('${directory.path}/fixture.db');
  final database = sqlite3.open(file.path);
  try {
    database.execute(
      'CREATE TABLE stationcode (_id INTEGER PRIMARY KEY NOT NULL, areacode INTEGER NOT NULL, linecode INTEGER NOT NULL, stationorder INTEGER NOT NULL, companyname TEXT, linename TEXT, stationname TEXT)',
    );
    database.execute(
      'CREATE TABLE android_metadata (locale TEXT DEFAULT \'ja_JP\')',
    );
    for (final row in rows) {
      database.execute(
        'INSERT INTO stationcode(areacode,linecode,stationorder,companyname,linename,stationname) VALUES(?,?,?,?,?,?)',
        row,
      );
    }
  } finally {
    database.close();
  }
  final bytes = file.readAsBytesSync();
  return _FixtureBundle(bytes, {
    'format_version': 1,
    'database': {
      'file': 'suica_stationcode.db',
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      'tables': {'android_metadata': 0, 'stationcode': rows.length},
    },
  });
}
