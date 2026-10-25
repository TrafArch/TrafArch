import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uri secureUpdateUri(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const FormatException('Update URL must be HTTPS without credentials');
  }
  return uri;
}

typedef UpdateFetch = Future<Uint8List> Function(Uri uri, int maxBytes);

/// No cookies, user data, or redirects. The deadline covers the entire body.
Future<Uint8List> fetchUpdate(Uri uri, int maxBytes) async {
  secureUpdateUri(uri.toString());
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != 200 || response.contentLength > maxBytes) {
        throw const HttpException('Invalid update response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const HttpException('Update exceeds size limit');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    })().timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}

class ReferenceUpdate {
  ReferenceUpdate.fromJson(Map<String, dynamic> json)
    : url = secureUpdateUri(json['url'] as String),
      spec = Map<String, dynamic>.unmodifiable(json['package'] as Map) {
    if (spec['bytes'] is! int ||
        (spec['bytes'] as int) <= 0 ||
        (spec['bytes'] as int) > maxPackageBytes ||
        spec['content_version'] is! String ||
        spec['tables'] is! Map ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch('${spec['sha256']}') ||
        !RegExp(r'^[A-Za-z0-9_.-]+\.sqlite$').hasMatch('${spec['file']}')) {
      throw const FormatException('Invalid reference update');
    }
  }
  static const maxPackageBytes = 128 * 1024 * 1024;
  final Uri url;
  final Map<String, dynamic> spec;
}

class UpdateManifest {
  UpdateManifest.fromJson(Map<String, dynamic> json) {
    if (json['format_version'] != 1) {
      throw const FormatException('Unsupported update manifest');
    }
    final app = json['app'] as Map;
    build = app['build'] as int;
    version = app['version'] as String;
    notes = app['notes'] as String;
    downloadUrl = secureUpdateUri(app['download_url'] as String);
    if (build < 1 || version.isEmpty) {
      throw const FormatException('Invalid app version');
    }
    final refs = json['references'] as Map? ?? const {};
    references = Map.unmodifiable({
      for (final protocol in ['TU', 'CU'])
        if (refs[protocol] != null)
          protocol: ReferenceUpdate.fromJson(
            Map<String, dynamic>.from(refs[protocol] as Map),
          ),
    });
  }
  late final int build;
  late final String version;
  late final String notes;
  late final Uri downloadUrl;
  late final Map<String, ReferenceUpdate> references;
  bool isNewerThan(int currentBuild) => build > currentBuild;
}

class UpdateService {
  UpdateService({
    required this.currentBuild,
    this.manifestUrl = const String.fromEnvironment('UPDATE_MANIFEST_URL'),
    this.fetch = fetchUpdate,
  });
  final int currentBuild;
  final String manifestUrl;
  final UpdateFetch fetch;
  Future<UpdateManifest?>? _checking;
  bool get isConfigured => manifestUrl.trim().isNotEmpty;

  Future<UpdateManifest?> checkOnce() => _checking ??= _checkSilently();
  Future<UpdateManifest?> _checkSilently() async {
    try {
      return await checkNow();
    } catch (_) {
      // Optional background checks must not interrupt offline use.
      return null;
    }
  }

  /// Always fetch anew; manual callers must distinguish errors from no update.
  Future<UpdateManifest?> checkNow() async {
    if (!isConfigured) return null;
    const limit = 256 * 1024;
    final bytes = await fetch(secureUpdateUri(manifestUrl), limit);
    if (bytes.length > limit) {
      throw const FormatException('Manifest too large');
    }
    return UpdateManifest.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }
}
