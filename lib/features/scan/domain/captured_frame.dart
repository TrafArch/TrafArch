/// Immutable physical exchange evidence. Protocol fields are projections over
/// these bytes; failed and empty responses remain distinguishable.
class CapturedFrame {
  CapturedFrame({
    required this.sessionId,
    required this.index,
    required this.transport,
    required this.capturedAt,
    required List<int> command,
    List<int>? response,
    this.errorCode,
    this.error,
  }) : command = List.unmodifiable(command),
       response = response == null ? null : List.unmodifiable(response);
  final String sessionId;
  final int index;
  final String transport;
  final DateTime capturedAt;
  final List<int> command;
  final List<int>? response;
  final String? errorCode;
  final String? error;

  Map<String, dynamic> toJson() => {
    'kind': 'physical_frame',
    'sessionId': sessionId,
    'index': index,
    'transport': transport,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'command': command,
    'response': response,
    'errorCode': errorCode,
    'error': error,
  };
}
