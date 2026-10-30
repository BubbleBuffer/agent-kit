import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';

abstract interface class BubblePawTransport {
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]);

  Stream<Map<String, Object?>> get notifications;

  Future<void> dispose();
}

/// Newline-delimited JSON-RPC 2.0 over a single owned child's standard IO.
class StdioBubblePawTransport implements BubblePawTransport {
  StdioBubblePawTransport._(
    this._exitCode,
    this._terminate, {
    required Stream<List<int>> stdout,
    required StreamSink<List<int>> stdin,
    required Stream<List<int>> stderr,
    required this.requestTimeout,
    required this.shutdownTimeout,
  }) : _input = stdin {
    _stdoutSubscription = stdout.listen(
      _receive,
      onError: (Object error, StackTrace stack) => _fail(
        const BubblePawException('protocolError', 'The host output failed.'),
      ),
      onDone: () {
        if (_line.isNotEmpty && _failure == null) {
          _fail(
            const BubblePawException(
              'protocolError',
              'The host returned an incomplete JSON record.',
            ),
          );
        }
        if (!_stdoutDone.isCompleted) _stdoutDone.complete();
      },
    );
    _stderrSubscription = stderr.listen(
      _receiveStderr,
      onError: (Object error, StackTrace stack) {
        _appendStderr('[stderr unavailable]');
      },
      onDone: () {
        _flushStderrLine();
        if (!_stderrDone.isCompleted) _stderrDone.complete();
      },
    );
    // Sink errors can arrive asynchronously after add() has returned.
    unawaited(
      _input.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!_closing) {
            _fail(
              const BubblePawException(
                'writeFailed',
                'The host input pipe failed.',
              ),
            );
          }
        },
      ),
    );
    unawaited(_watchExit());
  }

  static const int _maxRecordBytes = 16 * 1024 * 1024;
  static const int _maxStderrTail = 2048;

  static Future<StdioBubblePawTransport> start({
    required String binaryPath,
    required String workspaceDirectory,
    required String dataDirectory,
    List<String> arguments = const [],
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 5),
  }) async {
    _validateTimeouts(requestTimeout, shutdownTimeout);
    final Process process;
    try {
      process = await Process.start(binaryPath, [
        '--workspace',
        workspaceDirectory,
        '--data-dir',
        dataDirectory,
        ...arguments,
        'stdio',
      ]);
    } on Object {
      throw const BubblePawException(
        'startFailed',
        'The BubblePaw host could not be started.',
      );
    }
    return StdioBubblePawTransport._(
      process.exitCode,
      () {
        process.kill(ProcessSignal.sigkill);
      },
      stdout: process.stdout,
      stdin: process.stdin,
      stderr: process.stderr,
      requestTimeout: requestTimeout,
      shutdownTimeout: shutdownTimeout,
    );
  }

  /// Exercises the production framing and lifecycle with an in-process peer.
  factory StdioBubblePawTransport.forTesting({
    required Stream<List<int>> stdout,
    required StreamSink<List<int>> stdin,
    Stream<List<int>>? stderr,
    required Future<int> exitCode,
    void Function()? terminate,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 5),
  }) {
    _validateTimeouts(requestTimeout, shutdownTimeout);
    return StdioBubblePawTransport._(
      exitCode,
      terminate ?? () {},
      stdout: stdout,
      stdin: stdin,
      stderr: stderr ?? const Stream<List<int>>.empty(),
      requestTimeout: requestTimeout,
      shutdownTimeout: shutdownTimeout,
    );
  }

  static void _validateTimeouts(Duration request, Duration shutdown) {
    if (request <= Duration.zero || shutdown <= Duration.zero) {
      throw ArgumentError('Transport timeouts must be positive.');
    }
  }

  final Duration requestTimeout;
  final Duration shutdownTimeout;
  final StreamSink<List<int>> _input;
  final Future<int> _exitCode;
  final void Function() _terminate;
  final _notifications = StreamController<Map<String, Object?>>.broadcast();
  final Map<int, _PendingRequest> _pending = {};
  final List<int> _line = [];
  final List<String> _stderrLines = [];
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  int _nextId = 1;
  int _stderrLineBytes = 0;
  int _stderrTailLength = 0;
  bool _closing = false;
  bool _exited = false;
  bool _terminated = false;
  bool _notificationsClosed = false;
  BubblePawException? _failure;
  Future<void>? _disposeFuture;

  @override
  Stream<Map<String, Object?>> get notifications => _notifications.stream;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) => _request(method, params, requestTimeout);

  Future<Object?> _request(
    String method,
    Map<String, Object?> params,
    Duration timeout, {
    bool duringShutdown = false,
  }) {
    final failure = _failure;
    if (failure != null) return Future<Object?>.error(failure);
    if (_closing && !duringShutdown) {
      return Future<Object?>.error(
        const BubblePawException(
          'transportClosed',
          'The BubblePaw transport is closed.',
        ),
      );
    }
    final id = _nextId++;
    final List<int> record;
    try {
      record = utf8.encode(
        '${jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params})}\n',
      );
    } on Object {
      return Future<Object?>.error(
        const BubblePawException(
          'protocolError',
          'Request parameters must be JSON encodable.',
        ),
      );
    }
    final completer = Completer<Object?>();
    final timer = Timer(timeout, () {
      _pending
          .remove(id)
          ?.completer
          .completeError(
            const BubblePawException(
              'requestTimeout',
              'The BubblePaw request deadline elapsed.',
            ),
          );
    });
    _pending[id] = _PendingRequest(completer, timer);
    try {
      _input.add(record);
    } on Object {
      _fail(
        const BubblePawException('writeFailed', 'The host input pipe failed.'),
      );
    }
    return completer.future;
  }

  void _receive(List<int> bytes) {
    if (_failure != null) return;
    var start = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != 10) continue;
      if (!_appendRecordBytes(bytes, start, index)) return;
      _parseRecord();
      if (_failure != null) return;
      start = index + 1;
    }
    _appendRecordBytes(bytes, start, bytes.length);
  }

  bool _appendRecordBytes(List<int> bytes, int start, int end) {
    if (_line.length + end - start > _maxRecordBytes) {
      _fail(
        const BubblePawException(
          'protocolError',
          'The host JSON record exceeds the transport limit.',
        ),
      );
      return false;
    }
    _line.addAll(bytes.getRange(start, end));
    return true;
  }

  void _parseRecord() {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(_line));
    } on FormatException {
      _line.clear();
      _protocolError();
      return;
    }
    _line.clear();
    if (decoded is! Map<String, Object?> || decoded['jsonrpc'] != '2.0') {
      _protocolError();
      return;
    }
    if (!decoded.containsKey('id')) {
      if (decoded['method'] is! String ||
          decoded.containsKey('result') ||
          decoded.containsKey('error') ||
          (decoded.containsKey('params') &&
              decoded['params'] is! Map<String, Object?> &&
              decoded['params'] is! List<Object?>)) {
        _protocolError();
        return;
      }
      if (!_notificationsClosed) _notifications.add(decoded);
      return;
    }
    final id = decoded['id'];
    final hasResult = decoded.containsKey('result');
    final hasError = decoded.containsKey('error');
    if (id is! int ||
        id < 1 ||
        id >= _nextId ||
        decoded.containsKey('method') ||
        hasResult == hasError) {
      _protocolError();
      return;
    }
    final error = decoded['error'];
    if (hasError &&
        (error is! Map<String, Object?> ||
            error['code'] is! int ||
            error['message'] is! String)) {
      _protocolError();
      return;
    }
    // A reply can arrive after a deadline. Its monotonically issued ID is known,
    // but it must never complete a different request or grow a tombstone set.
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();
    if (hasError) {
      pending.completer.completeError(
        _classifyRpcError(
          (error as Map<String, Object?>)['code']! as int,
          error['message']! as String,
        ),
      );
    } else {
      pending.completer.complete(decoded['result']);
    }
  }

  /// The host-API code for a run that needs a model before any provider is
  /// configured (BubblePaw Core v0.5.1). Its message names config keys and
  /// host methods, never credentials, so it is kept for the user.
  static const _noProviderCode = -32004;

  static BubblePawException _classifyRpcError(int code, String message) {
    if (code == _noProviderCode) {
      return BubblePawException('noProvider', message);
    }
    // v0.2.2 uses -32000 for all command errors. Inspect its known error
    // phrases privately, then discard arbitrary host text and identifiers.
    final text = message.toLowerCase();
    if (text.startsWith('session already has an active run ') ||
        text == 'session has an active run' ||
        text.startsWith('session is busy') ||
        text.startsWith('sessionbusy')) {
      return const BubblePawException('busy', 'The session has an active run.');
    }
    if (text.startsWith('unknown session') ||
        text.startsWith('unknown approval') ||
        text.contains('not found') ||
        text.startsWith('unknown or expired')) {
      return const BubblePawException(
        'notFound',
        'The requested host resource was not found.',
      );
    }
    if ((text.startsWith('approval ') && text.contains(' is already ')) ||
        text.contains('already resolved') ||
        text.contains('already decided') ||
        text.contains('already answered')) {
      return const BubblePawException(
        'conflict',
        'The requested operation conflicts with the host state.',
      );
    }
    if (text.contains('denied') ||
        text.contains('permission') ||
        text.contains('belongs to another workspace')) {
      return const BubblePawException(
        'denied',
        'The host denied the requested operation.',
      );
    }
    if (text.startsWith('invalid ') ||
        text.contains('does not belong to') ||
        text.startsWith('provide exactly') ||
        text.contains(' is required') ||
        text.contains(' must be ') ||
        text.contains('missing required')) {
      return const BubblePawException(
        'invalid',
        'The host rejected invalid request parameters.',
      );
    }
    return const BubblePawException(
      'rpcError',
      'The BubblePaw host rejected the request.',
    );
  }

  void _protocolError() => _fail(
    const BubblePawException(
      'protocolError',
      'The host returned an invalid JSON-RPC record.',
    ),
  );

  void _receiveStderr(List<int> bytes) {
    // Stderr is an untrusted channel: even a normal-looking token or path can
    // contain credentials. Keep only byte counts, never arbitrary host text.
    for (final byte in bytes) {
      if (byte == 10) {
        _flushStderrLine();
      } else {
        _stderrLineBytes++;
      }
    }
  }

  void _flushStderrLine() {
    if (_stderrLineBytes == 0) return;
    _appendStderr('[stderr redacted: $_stderrLineBytes bytes]');
    _stderrLineBytes = 0;
  }

  void _appendStderr(String line) {
    _stderrLines.add(line);
    _stderrTailLength += line.length + 1;
    while (_stderrTailLength > _maxStderrTail && _stderrLines.isNotEmpty) {
      _stderrTailLength -= _stderrLines.removeAt(0).length + 1;
    }
  }

  Future<void> _watchExit() async {
    final int code;
    try {
      code = await _exitCode;
    } on Object {
      _fail(
        const BubblePawException(
          'hostExited',
          'The host exit status is unavailable.',
        ),
      );
      return;
    }
    _exited = true;
    // Process.exitCode can complete before the pipes deliver their final bytes.
    await _bounded(Future.wait<void>([_stdoutDone.future, _stderrDone.future]));
    _flushStderrLine();
    if (!_closing) {
      _fail(
        BubblePawHostExited(
          exitCode: code,
          stderrTail: _stderrLines.join('\n'),
        ),
      );
    } else {
      _rejectPending(
        BubblePawHostExited(
          exitCode: code,
          stderrTail: _stderrLines.join('\n'),
        ),
      );
    }
  }

  void _rejectPending(BubblePawException error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final request in pending) {
      request.timer.cancel();
      request.completer.completeError(error);
    }
  }

  void _fail(BubblePawException error) {
    if (_failure != null) return;
    _failure = error;
    _line.clear();
    _rejectPending(error);
    if (!_notificationsClosed) _notifications.addError(error);
    _closeNotifications();
    unawaited(dispose());
  }

  void _closeNotifications() {
    if (_notificationsClosed) return;
    _notificationsClosed = true;
    // A paused broadcast listener must not block child cleanup.
    unawaited(_notifications.close());
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _closing = true;
    _rejectPending(
      const BubblePawException(
        'transportClosed',
        'The BubblePaw transport is closed.',
      ),
    );
    if (_failure == null && !_exited) {
      try {
        await _request(
          'shutdown',
          const {},
          shutdownTimeout,
          duringShutdown: true,
        );
      } on Object {
        // Cleanup continues after a rejected, timed-out, or broken shutdown.
      }
    }
    try {
      await _bounded(_input.close());
    } on Object {
      // Closing a broken pipe is expected after a host failure.
    }
    if (!_exited) await _bounded(_exitCode.then<void>((_) {}));
    if (!_exited && !_terminated) {
      _terminated = true;
      try {
        _terminate();
      } on Object {
        /* Already exited or unavailable. */
      }
      await _bounded(_exitCode.then<void>((_) {}));
    }
    await _bounded(_stdoutSubscription.cancel());
    await _bounded(_stderrSubscription.cancel());
    if (!_stdoutDone.isCompleted) _stdoutDone.complete();
    if (!_stderrDone.isCompleted) _stderrDone.complete();
    _line.clear();
    _closeNotifications();
  }

  Future<void> _bounded(Future<Object?> operation) async {
    try {
      await operation.timeout(shutdownTimeout);
    } on Object {
      // Resource cleanup and pipe draining must remain bounded.
    }
  }
}

class _PendingRequest {
  _PendingRequest(this.completer, this.timer);

  final Completer<Object?> completer;
  final Timer timer;
}
