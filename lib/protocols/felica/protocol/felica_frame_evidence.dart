import '../../transport/transport_failure.dart';

/// One physical request and its complete observed response, even if validation
/// fails. A failed send has no response; it is not represented as empty data.
class FelicaFrameEvidence {
  FelicaFrameEvidence({
    required this.stage,
    required List<int> command,
    List<int>? response,
    this.error,
    this.transportFailure,
  }) : command = List<int>.unmodifiable(command),
       response = response == null ? null : List<int>.unmodifiable(response);
  final String stage;
  final List<int> command;
  final List<int>? response;
  final Object? error;
  final TransportFailure? transportFailure;
}
