import 'package:flutter/services.dart';

import '../../protocols/transport/transport_failure.dart';

/// Native codes are interpreted only at the platform boundary. A generic
/// TRANSCEIVE_FAILED does not establish that the card physically left.
TransportFailure mapNfcFailure(Object error, StackTrace stack) {
  if (error is! PlatformException) return TransportFailure.from(error, stack);
  final details = error.details;
  final exception = details is Map ? details['exception']?.toString() : null;
  final kind = switch (error.code) {
    'NFC_STOPPED' => TransportFailureKind.cancelled,
    'STALE_SESSION' => TransportFailureKind.staleSession,
    'TAG_NOT_CONNECTED' ||
    'FELICA_NOT_CONNECTED' => TransportFailureKind.disconnected,
    'NFC_BUSY' => TransportFailureKind.resourceLimit,
    'BAD_ARGUMENT' => TransportFailureKind.malformedFrame,
    _ =>
      exception == 'android.nfc.TagLostException'
          ? TransportFailureKind.tagLost
          : TransportFailureKind.unknown,
  };
  return TransportFailure(
    kind: kind,
    message: error.message ?? error.code,
    code: error.code,
    details: details,
    cause: error,
    stackTrace: stack,
  );
}
