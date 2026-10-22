import '../protocol/felica_protocol.dart';
import '../protocol/felica_frame_evidence.dart';

/// Observed service evidence, reusable only within the same scan context.
class FelicaServiceProbe {
  const FelicaServiceProbe({
    required this.versions,
    required this.frames,
    this.error,
  });
  final List<int> versions;
  final List<FelicaFrameEvidence> frames;
  final FelicaProtocolException? error;
  // Keep the existing detection rule; correlation is validated by the protocol.
  bool get verified => error == null && versions.isNotEmpty;
}
