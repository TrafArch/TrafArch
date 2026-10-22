import 'package:flutter/services.dart' show AssetBundle;
import 'package:sqlite3/sqlite3.dart';

import 'reference_package.dart';
import 'reference_user_store.dart';
import 'tu_station_repository.dart';

/// Owned read-only TU package and independently persisted user data.
class TuDatabase {
  TuDatabase._(this.package, this.users)
    : repository = TuStationRepository(package.db, userDatabase: users?.db);
  final ReferencePackage package;
  final ReferenceUserStore? users;
  final TuStationRepository repository;
  String? userStorageError;
  Database get db => package.db;
  static const assetPath = 'assets/data/TrafArch_Database_TU.sqlite';

  static Future<TuDatabase> open({AssetBundle? bundle}) async {
    ReferenceUserStore? users;
    String? error;
    // Extract legacy edits before installing a new asset. Failed migration
    // leaves its source untouched and stays visible to the application.
    try {
      users = await ReferenceUserStore.open();
      error = users.migrationError;
    } catch (e) {
      error = '用户站点数据库不可用：$e';
    }
    try {
      final package = await ReferencePackage.open('TU', bundle: bundle);
      return TuDatabase._(package, users)..userStorageError = error;
    } catch (_) {
      users?.close();
      rethrow;
    }
  }

  int get userVersion => 1;
  Map<String, String> get sourceMetadata => {
    'content_version': package.version,
    'sha256': package.hash,
  };

  void close() {
    package.close();
    users?.close();
  }
}
