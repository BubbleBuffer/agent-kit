/// A safe adapter failure. Messages never contain host responses or credentials.
class BubblePawException implements Exception {
  const BubblePawException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BubblePawException($code): $message';
}

class BubblePawProtocolMismatch extends BubblePawException {
  const BubblePawProtocolMismatch({
    required this.expectedVersion,
    required this.actualVersion,
  }) : super('protocolMismatch', 'The host protocol version is unsupported.');

  final String expectedVersion;
  final String? actualVersion;
}

class BubblePawHostExited extends BubblePawException {
  const BubblePawHostExited({
    required this.exitCode,
    required this.stderrTail,
  }) : super('hostExited', 'The BubblePaw host exited.');

  final int exitCode;

  /// Bounded metadata about stderr; arbitrary host text is always redacted.
  final String stderrTail;
}
