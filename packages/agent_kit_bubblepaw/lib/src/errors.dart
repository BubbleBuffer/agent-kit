/// A safe adapter failure. Messages never contain host responses or credentials.
class BubblePawException implements Exception {
  const BubblePawException(
    this.code,
    this.message, {
    this.rpcCode,
    this.rpcMessage,
    this.rpcData,
  });

  final String code;
  final String message;

  /// The JSON-RPC error `code` the host returned, set only for the typed host
  /// errors in [typedHostErrorCodes]; null for every other failure.
  final int? rpcCode;

  /// The `message` the host returned with that typed error. [message] stays
  /// the fixed adapter text; the host's own text is kept here, only for the
  /// documented typed errors (config refusals), never for arbitrary failures.
  final String? rpcMessage;

  /// The JSON-RPC error `data` the host returned with that typed error.
  final Object? rpcData;

  /// Host codes whose code, message and data reach the caller: the
  /// `config.set` refusals `-32010` unknown key, `-32011` wrong type,
  /// `-32012` invalid value and `-32013` write failed (BubblePaw Core
  /// `docs/host-api.md`).
  static const typedHostErrorCodes = <int>{-32010, -32011, -32012, -32013};

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
  const BubblePawHostExited({required this.exitCode, required this.stderrTail})
    : super('hostExited', 'The BubblePaw host exited.');

  final int exitCode;

  /// Bounded metadata about stderr; arbitrary host text is always redacted.
  final String stderrTail;
}
