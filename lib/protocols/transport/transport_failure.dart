import 'dart:async';

/// Platform adapters classify native errors; protocol code never guesses from
/// a platform code or message. Unknown I/O failures stay [unknown].
enum TransportFailureKind {
  cancelled,
  staleSession,
  tagLost,
  timeout,
  disconnected,
  malformedFrame,
  rejectedStatus,
  unsupportedProfile,
  resourceLimit,
  unknown,
}

class TransportFailure implements Exception {
  const TransportFailure({
    required this.kind,
    required this.message,
    this.code,
    this.details,
    this.cause,
    this.stackTrace,
  });

  final TransportFailureKind kind;
  final String message;
  final String? code;
  final Object? details;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Only an application rejection/non-match allows another profile attempt.
  bool get stopsSession => switch (kind) {
    TransportFailureKind.rejectedStatus ||
    TransportFailureKind.unsupportedProfile => false,
    _ => true,
  };

  factory TransportFailure.from(Object error, StackTrace stackTrace) {
    if (error is TransportFailure) return error;
    return TransportFailure(
      kind: error is TimeoutException
          ? TransportFailureKind.timeout
          : TransportFailureKind.unknown,
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => '${code ?? kind.name}: $message';
}
