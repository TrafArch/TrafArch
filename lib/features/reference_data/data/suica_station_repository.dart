import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Names from one exact original Suica station-code key. Null and empty source
/// fields remain distinct; this model does not infer a city or operator.
class SuicaStation {
  const SuicaStation({this.companyName, this.lineName, this.stationName});

  final String? companyName;
  final String? lineName;
  final String? stationName;
}

/// Independent, verified Suica source package. It never opens TU/CU packages.
/// The owner closes the read-only SQLite connection when the reference data is
/// retired. Cache files are byte-identical copies of the bundled original.
class SuicaStationRepository {
  SuicaStationRepository._(this._database, this.hash);

  final Database _database;
  final String hash;
  bool _closed = false;

  static const _filename = 'suica_stationcode.db';
  static const _assetRoot = 'assets/suica';
  static final _cacheInstallations = <String, Future<void>>{};

  static Future<SuicaStationRepository> load(AssetBundle bundle) async {
    final manifest = jsonDecode(
      await bundle.loadString('$_assetRoot/manifest.json'),
    );
    if (manifest is! Map || manifest['format_version'] != 1) {
      throw const FormatException('Unsupported Suica reference manifest');
    }
    final spec = manifest['database'];
    if (spec is! Map || spec['file'] != _filename) {
      throw const FormatException('Invalid Suica database manifest');
    }
    final hash = spec['sha256'];
    final length = spec['bytes'];
    final tables = spec['tables'];
    if (hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
        length is! int ||
        length <= 0 ||
        tables is! Map ||
        tables['stationcode'] is! int ||
        (tables['stationcode'] as int) < 0) {
      throw const FormatException('Invalid Suica database digest or counts');
    }
    final data = await bundle.load('$_assetRoot/$_filename');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length != length || sha256.convert(bytes).toString() != hash) {
      throw const FormatException('Suica reference asset digest mismatch');
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/trafarch_suica_reference');
    await directory.create(recursive: true);
    final installed = File('${directory.path}/$hash.db');
    Future<bool> cacheVerified() async =>
        await installed.exists() &&
        await installed.length() == length &&
        sha256.convert(await installed.readAsBytes()).toString() == hash;

    // Readers in this isolate share one installation/recovery. In particular,
    // simultaneous loads must not race while deleting the same damaged cache.
    final installation = _cacheInstallations.putIfAbsent(
      installed.path,
      () async {
        if (!await cacheVerified()) {
          final staging = await directory.createTemp('install-');
          final temporary = File('${staging.path}/$_filename');
          try {
            await temporary.writeAsBytes(bytes, flush: true);
            if (await installed.exists() && !await cacheVerified()) {
              await installed.delete();
            }
            try {
              if (!await installed.exists()) {
                await temporary.rename(installed.path);
              }
            } on FileSystemException {
              // A separate initializer may have installed the same valid bytes.
              if (!await cacheVerified()) rethrow;
            }
          } finally {
            if (await temporary.exists()) await temporary.delete();
            await staging.delete();
          }
        }
        if (!await cacheVerified()) {
          throw const FormatException('Suica reference cache digest mismatch');
        }
      },
    );
    try {
      await installation;
    } finally {
      if (identical(_cacheInstallations[installed.path], installation)) {
        _cacheInstallations.remove(installed.path);
      }
    }

    final database = sqlite3.open(installed.path, mode: OpenMode.readOnly);
    try {
      final integrity = database.select('PRAGMA quick_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('Suica reference integrity check failed');
      }
      final columns = database
          .select('PRAGMA table_info(stationcode)')
          .map((row) => row['name'])
          .toSet();
      if (!columns.containsAll(const {
        '_id',
        'areacode',
        'linecode',
        'stationorder',
        'companyname',
        'linename',
        'stationname',
      })) {
        throw const FormatException('Suica stationcode schema mismatch');
      }
      final count = database.select('SELECT COUNT(*) AS n FROM stationcode');
      if (count.single['n'] != tables['stationcode']) {
        throw const FormatException('Suica stationcode record count mismatch');
      }
      return SuicaStationRepository._(database, hash);
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  /// Exactly matches the source's area, line and station-order namespace.
  /// The original reader queries unpadded lowercase hexadecimal strings.
  /// INTEGER affinity stores numeric-looking hex keys as numbers, while keys
  /// containing a-f stay TEXT; binding the decoded decimal byte can misidentify
  /// a station (for example NFC 0x0d must query 'd', not source key '13').
  /// Identical duplicate rows agree; conflicting names never choose a winner.
  SuicaStation? lookup({
    required int areaCode,
    required int lineCode,
    required int stationCode,
  }) {
    if (_closed) throw StateError('Suica station repository is closed');
    final rows = _database.select(
      'SELECT DISTINCT companyname,linename,stationname FROM stationcode '
      'WHERE areacode=? AND linecode=? AND stationorder=? LIMIT 2',
      [
        areaCode.toRadixString(16),
        lineCode.toRadixString(16),
        stationCode.toRadixString(16),
      ],
    );
    if (rows.length != 1) return null;
    final row = rows.single;
    return SuicaStation(
      companyName: row['companyname'] as String?,
      lineName: row['linename'] as String?,
      stationName: row['stationname'] as String?,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _database.close();
  }
}
