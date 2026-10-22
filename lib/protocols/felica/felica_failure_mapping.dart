import '../transport/transport_failure.dart';
import 'models/felica_models.dart';
import 'protocol/felica_protocol.dart';

/// Presentation compatibility stays outside the wire protocol. A timeout or
/// unknown native failure does not prove that a tag has physically left.
FelicaReadState felicaFailureState(FelicaProtocolException error) {
  final failure = error.transportFailure;
  if (failure != null) {
    return switch (failure.kind) {
      TransportFailureKind.tagLost => FelicaReadState.tagLost,
      TransportFailureKind.unsupportedProfile => FelicaReadState.unsupported,
      TransportFailureKind.rejectedStatus => FelicaReadState.accessDenied,
      TransportFailureKind.malformedFrame => FelicaReadState.malformed,
      _ => FelicaReadState.failed,
    };
  }
  return switch (error.reason) {
    // Preserve the existing empty-response display contract. Native timeout
    // and unknown I/O failures use their distinct typed branch above.
    FelicaFailureReason.noResponse => FelicaReadState.tagLost,
    FelicaFailureReason.malformed ||
    FelicaFailureReason.mismatchedRequest => FelicaReadState.malformed,
    _ => FelicaReadState.failed,
  };
}

extension FelicaProtocolReadState on FelicaProtocolException {
  FelicaReadState get readState => felicaFailureState(this);
}
