import 'dart:convert';

import '../archive/domain/pending_card_save.dart';
import '../archive/domain/card_archive_identity.dart';
import '../archive/domain/card_session_snapshot.dart';

/// Temporary continuation data. Captured JSON is never reparsed by a protocol
/// reader, migrated, imported, or silently committed to the card archive.
class RecoveryCapture {
  const RecoveryCapture({
    required this.readAt,
    required this.summary,
    required this.frames,
    this.pending,
    this.snapshotJson,
    this.canSave = false,
    this.interrupted = false,
  });
  final DateTime readAt;
  final Map<String, Object?> summary;
  final List<Map<String, dynamic>> frames;
  final PendingCardSave? pending;
  final String? snapshotJson;
  final bool canSave;
  final bool interrupted;

  RecoveryCapture withoutPendingSave() => RecoveryCapture(
    readAt: readAt,
    summary: summary,
    frames: frames,
    pending: pending,
    snapshotJson: snapshotJson,
    interrupted: interrupted,
  );

  Map<String, Object?> toJson() => {
    'readAt': readAt.toIso8601String(),
    'summary': summary,
    'frames': frames,
    'snapshotJson': snapshotJson,
    'interrupted': interrupted,
    'canSave': canSave,
    if (pending case final item?)
      'pending': {
        'id': item.pendingSaveId,
        'fingerprint': item.fingerprint,
        'cardNumber': item.cardNumber,
        'balanceFen': item.balanceFen,
        'currencyCode': item.currencyCode,
        'transactionCount': item.transactionCount,
        'readAt': item.readAt?.toIso8601String(),
        'snapshot': item.sessionDataJson,
        'identity': {
          'cardType': item.identity.cardType,
          'officialName': item.identity.officialName,
          'issuerName': item.identity.issuerName,
          'cityName': item.identity.cityName,
          'source': item.identity.identificationSource,
          'confidence': item.identity.confidence,
        },
      },
  };

  factory RecoveryCapture.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshotJson'] as String?;
    if (snapshot != null && CardSessionSnapshot.decode(snapshot) == null) {
      throw const FormatException('Invalid recovery snapshot');
    }
    final p = json['pending'] as Map<String, dynamic>?;
    final identity = p?['identity'] as Map<String, dynamic>?;
    final pending = p == null || identity == null
        ? null
        : PendingCardSave(
            pendingSaveId: p['id'] as String,
            fingerprint: p['fingerprint'] as String,
            readAt: DateTime.tryParse(p['readAt'] as String? ?? ''),
            cardNumber: p['cardNumber'] as String?,
            balanceFen: p['balanceFen'] as int?,
            currencyCode: p['currencyCode'] as String?,
            transactionCount: p['transactionCount'] as int?,
            sessionDataJson: p['snapshot'] as String?,
            identity: CardArchiveIdentity(
              cardType: identity['cardType'] as String,
              officialName: identity['officialName'] as String?,
              issuerName: identity['issuerName'] as String?,
              cityName: identity['cityName'] as String?,
              identificationSource: identity['source'] as String,
              confidence: (identity['confidence'] as num?)?.toDouble(),
            ),
          );
    if (pending?.sessionDataJson != null &&
        pending!.sessionDataJson != snapshot) {
      throw const FormatException('Mismatched recovery capture');
    }
    return RecoveryCapture(
      readAt: DateTime.parse(json['readAt'] as String),
      summary: Map<String, Object?>.from(json['summary'] as Map),
      frames: [
        for (final frame in json['frames'] as List)
          Map<String, dynamic>.from(frame as Map),
      ],
      snapshotJson: snapshot,
      pending: pending,
      canSave: json['canSave'] == true && pending != null,
      interrupted: json['interrupted'] == true,
    );
  }
}

class RecoveryState {
  const RecoveryState({
    required this.savedAt,
    required this.tab,
    this.route,
    this.capture,
    this.qrBytes,
    this.filters = const {},
  });
  static const maxBytes = 8 * 1024 * 1024;
  static const maxAge = Duration(hours: 24);
  final DateTime savedAt;
  final int tab;
  final String? route;
  final RecoveryCapture? capture;
  final List<int>? qrBytes;
  final Map<String, List<String>> filters;

  String encode() {
    final text = jsonEncode({
      'version': 1,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'tab': tab,
      'route': route,
      'capture': capture?.toJson(),
      'qrBytes': qrBytes,
      'filters': filters,
    });
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const FormatException('Recovery state too large');
    }
    return text;
  }

  static RecoveryState decode(String text, {DateTime? now}) {
    if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
      throw const FormatException('Recovery state too large');
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('Recovery version');
    final savedAt = DateTime.parse(data['savedAt'] as String);
    final age = (now ?? DateTime.now()).difference(savedAt);
    if (age > maxAge || age < const Duration(minutes: -5)) {
      throw const FormatException('Recovery expired');
    }
    final tab = data['tab'] as int;
    if (tab < 0 || tab > 3) throw const FormatException('Recovery tab');
    final route = data['route'] as String?;
    if (route != null && route.startsWith('/card/')) {
      // Validate before navigation, so malformed escaping cannot crash build.
      Uri.decodeComponent(route.substring(6));
    }
    final qr = (data['qrBytes'] as List?)?.cast<int>();
    if (qr != null && qr.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Recovery QR bytes');
    }
    return RecoveryState(
      savedAt: savedAt,
      tab: tab,
      route: route,
      capture: data['capture'] == null
          ? null
          : RecoveryCapture.fromJson(data['capture'] as Map<String, dynamic>),
      qrBytes: qr,
      filters: {
        for (final entry in (data['filters'] as Map).entries)
          entry.key as String: (entry.value as List).cast<String>(),
      },
    );
  }
}
