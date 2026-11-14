import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../updates/update_service.dart';
import 'reference_package.dart';

/// Only published reference files live here; never user overrides or archives.
class ReferenceUpdates {
  ReferenceUpdates(this.builtin);
  final AssetBundle builtin;
  final Map<String, ReferenceUpdate> active = {};

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/trafarch_reference_updates')
      ..createSync(recursive: true);
  }

  Future<AssetBundle> bundleFor(Map<String, ReferenceUpdate> updates) async {
    final directory = await _directory();
    final manifest = jsonDecode(
      await builtin.loadString('assets/data/reference_manifest.json'),
    ) as Map<String, dynamic>;
    final files = <String, Uint8List>{};
    for (final entry in updates.entries) {
      final spec = Map<String, dynamic>.from(entry.value.spec);
      // Unique virtual names avoid TU/CU filename collisions.
      spec['file'] = '${entry.key}-${spec['sha256']}.sqlite';
      (manifest['packages'] as Map)[entry.key] = spec;
      final file = File('${directory.path}/${spec['sha256']}.sqlite');
      if (await file.length() > ReferenceUpdate.maxPackageBytes) {
        throw const FormatException('Stored package too large');
      }
      files['assets/data/${spec['file']}'] = await file.readAsBytes();
    }
    files['assets/data/reference_manifest.json'] = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest)),
    );
    return _OverlayBundle(builtin, files);
  }

  Future<void> restore() async {
    final directory = await _directory();
    for (final protocol in ['TU', 'CU']) {
      try {
        final record = File('${directory.path}/$protocol.json');
        if (!await record.exists()) continue;
        if (await record.length() > 256 * 1024) continue;
        final update = ReferenceUpdate.fromJson(
          jsonDecode(await record.readAsString()) as Map<String, dynamic>,
        );
        final bundle = await bundleFor({protocol: update});
        final package = await ReferencePackage.open(protocol, bundle: bundle);
        package.close();
        active[protocol] = update;
      } catch (_) {
        // Corrupt or incompatible installed package: use built-in independently.
      }
    }
  }

  Future<AssetBundle> stage(
    String protocol,
    ReferenceUpdate update,
    Uint8List bytes,
  ) async {
    if (!['TU', 'CU'].contains(protocol)) {
      throw ArgumentError.value(protocol, 'protocol');
    }
    if (bytes.length != update.spec['bytes']) {
      throw const FormatException('Reference download size mismatch');
    }
    // Validate before persisting any candidate bytes using the same package path.
    final manifest = jsonDecode(
      await builtin.loadString('assets/data/reference_manifest.json'),
    ) as Map<String, dynamic>;
    (manifest['packages'] as Map)[protocol] = update.spec;
    final overlay = _OverlayBundle(builtin, {
      'assets/data/reference_manifest.json': Uint8List.fromList(
        utf8.encode(jsonEncode(manifest)),
      ),
      'assets/data/${update.spec['file']}': bytes,
    });
    final package = await ReferencePackage.open(protocol, bundle: overlay);
    package.close();
    final directory = await _directory();
    final file = File('${directory.path}/${update.spec['sha256']}.sqlite');
    await file.writeAsBytes(bytes, flush: true);
    return bundleFor({...active, protocol: update});
  }

  Future<void> activate(String protocol, ReferenceUpdate update) async {
    final directory = await _directory();
    final temporary = File('${directory.path}/$protocol.pending');
    await temporary.writeAsString(
      jsonEncode({'url': update.url.toString(), 'package': update.spec}),
      flush: true,
    );
    await temporary.rename('${directory.path}/$protocol.json');
    active[protocol] = update;
  }
}

class _OverlayBundle extends CachingAssetBundle {
  _OverlayBundle(this.base, this.files);
  final AssetBundle base;
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    return bytes == null ? base.load(key) : ByteData.sublistView(bytes);
  }
}
