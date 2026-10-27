// Helpers for opt-in live acceptance. Tests use synthetic payloads and redacted
// recorded protocol ordering; no live credentials or model calls.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_kit_core/agent_kit_core.dart';

class LiveCheckFailure implements Exception {
  const LiveCheckFailure(this.message);
  final String message;
}

/// Fixed labels and numeric observations only: never event content or IDs.
class LiveCheckDiagnostic {
  const LiveCheckDiagnostic(this.name, this.passed, this.observed);
  final String name;
  final bool passed;
  final String observed;

  @override
  String toString() => '${passed ? 'PASS' : 'FAIL'}: $name; $observed';
}

List<LiveCheckDiagnostic> canonicalDiagnostics(
  ChatSnapshot? snapshot, {
  required String steeringText,
}) {
  final steering =
      snapshot?.items
          .whereType<UserMessage>()
          .where((message) => message.text == steeringText)
          .length ??
      0;
  final replies =
      snapshot?.items
          .whereType<AssistantMessage>()
          .where(
            (message) =>
                !message.streaming &&
                message.markdown.contains('STEERING_ACCEPTED'),
          )
          .length ??
      0;
  return [
    LiveCheckDiagnostic(
      'canonical snapshot',
      snapshot != null,
      'loaded=${snapshot == null ? 0 : 1}; required=1',
    ),
    LiveCheckDiagnostic(
      'canonical steering',
      steering > 0,
      'matches=$steering; required>=1',
    ),
    LiveCheckDiagnostic(
      'canonical final reply',
      replies > 0,
      'matches=$replies; required>=1',
    ),
  ];
}

class LiveCheckOptions {
  LiveCheckOptions._(this.values, this.hostArguments, this.timeout);
  final Map<String, String> values;
  final List<String> hostArguments;
  final Duration timeout;
  String get binary => values['--binary']!;
  String get config => values['--config']!;
  String? get workspace => values['--workspace'];
  String? get dataDirectory => values['--data-dir'];
  String? get trace => values['--trace'];

  factory LiveCheckOptions.parse(List<String> arguments) {
    const known = {
      '--binary',
      '--config',
      '--workspace',
      '--data-dir',
      '--trace',
      '--timeout-seconds',
    };
    final values = <String, String>{};
    var hostArguments = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final key = arguments[i];
      if (key == '--') {
        hostArguments = arguments.sublist(i + 1);
        break;
      }
      if (!known.contains(key) ||
          values.containsKey(key) ||
          i + 1 >= arguments.length ||
          arguments[i + 1].isEmpty ||
          arguments[i + 1].startsWith('--')) {
        throw const LiveCheckFailure('invalid options; use --help');
      }
      values[key] = arguments[++i];
    }
    if (!values.containsKey('--binary') || !values.containsKey('--config')) {
      throw const LiveCheckFailure('--binary and --config are required');
    }
    final seconds = int.tryParse(values['--timeout-seconds'] ?? '180');
    if (seconds == null || seconds < 1 || seconds > 3600) {
      throw const LiveCheckFailure('timeout must be 1 to 3600 seconds');
    }
    return LiveCheckOptions._(
      values,
      hostArguments,
      Duration(seconds: seconds),
    );
  }
}

/// Exercises kit events without serializing approvals behind the terminal wait.
/// Every distinct request receives its own approve-once decision, including
/// requests that arrive after the first approval or steering operation.
class LiveAcceptance {
  LiveAcceptance({required this.approve, required this.steer}) {
    // A command can fail while run.start is still returning its response.
    // Attach an error observer now; the main await still receives that error.
    unawaited(
      _finished.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final Future<void> Function(String) approve;
  final Future<String> Function() steer;
  final _finished = Completer<RunFinished>();
  final _usageObserved = Completer<void>();
  final _seenApprovals = <String>{};
  final _execCalls = <String>{};
  final _finishedExecCalls = <String>{};
  final _completedExecCalls = <String>{};
  final _operations = <Future<void>>[];
  bool _steeringStarted = false;
  bool _steered = false;
  bool _failed = false;
  int _failures = 0;
  int _completionEvents = 0;
  RunFinished? _completion;
  int approvals = 0;
  int steeringEvents = 0;
  int usageUpdates = 0;
  int gaps = 0;
  final _gapDetails = <String>[];
  int get completedExecs => _completedExecCalls.length;
  Future<RunFinished> get finished => _finished.future;
  Future<void> get settled async {
    await Future.wait(_operations);
  }

  /// Session usage can be reconciled after run.finished has been delivered.
  /// The caller applies the same overall live-run deadline to this wait.
  Future<void> verifyAfterUsage(RunFinished event, String runId) async {
    await settled;
    if (!_failed &&
        event.outcome == RunOutcome.completed &&
        usageUpdates == 0) {
      await _usageObserved.future;
    }
    verify(event, runId);
  }

  void onEvent(KitEvent event) {
    if (event is QueueAdded && event.input.mode == QueueMode.steer) {
      steeringEvents++;
    }
    if (event is UsageUpdated) {
      usageUpdates++;
      if (!_usageObserved.isCompleted) _usageObserved.complete();
    }
    if (event is GapEvent) {
      gaps++;
      _gapDetails.add(
        'kind=${event.kind}; seq=${event.seq}; skipped=${event.skipped ?? 'unknown'}',
      );
    }
    if (event is ApprovalRequested &&
        event.approval.state == ApprovalState.pending &&
        _seenApprovals.add(event.approval.id)) {
      _track(() async {
        await approve(event.approval.id);
        approvals++;
      });
    }
    if (event is ToolStarted && event.name == 'exec') {
      _execCalls.add(event.callId);
      if (!_steeringStarted) {
        _steeringStarted = true;
        _track(() async {
          final id = await steer();
          if (id.isEmpty) throw const LiveCheckFailure('steering ID missing');
          _steered = true;
        });
      }
    }
    if (event is ToolFinished && _execCalls.contains(event.callId)) {
      _finishedExecCalls.add(event.callId);
      if (_execSucceeded(event)) _completedExecCalls.add(event.callId);
    }
    if (event is RunFinished) {
      _completionEvents++;
      _completion ??= event;
      if (!_finished.isCompleted) _finished.complete(event);
    }
  }

  bool _execSucceeded(ToolFinished event) {
    if (event.state != WorkState.done) return false;
    if (event.exitCode != null) return event.exitCode == 0;
    // The adapter currently carries native exec diagnostics as JSON text.
    // Missing/invalid diagnostics cannot establish process success.
    try {
      final result = jsonDecode(event.output?.text ?? '');
      return result is Map<String, Object?> && result['exitCode'] == 0;
    } on Object {
      return false;
    }
  }

  void _track(Future<void> Function() action) {
    final future = (() async {
      try {
        await action();
      } on Object {
        fail();
      }
    })();
    _operations.add(future);
  }

  void fail() {
    _failed = true;
    _failures++;
    if (!_usageObserved.isCompleted) _usageObserved.complete();
    if (!_finished.isCompleted) {
      _finished.completeError(
        const LiveCheckFailure('event or command failed'),
      );
    }
  }

  void closed() {
    if (!_finished.isCompleted || usageUpdates == 0) fail();
  }

  void verify(RunFinished event, String runId) {
    if (_failed ||
        event.runId != runId ||
        event.outcome != RunOutcome.completed ||
        approvals < 2 ||
        completedExecs < 2 ||
        !_steered ||
        usageUpdates < 1 ||
        gaps != 0) {
      throw const LiveCheckFailure(
        'approval/exec/steering/usage/gap/completion checks failed',
      );
    }
  }

  List<LiveCheckDiagnostic> diagnostics({String? expectedRunId}) {
    final completion = _completion;
    final matches =
        completion != null &&
        expectedRunId != null &&
        completion.runId == expectedRunId;
    final completed = completion?.outcome == RunOutcome.completed;
    return [
      LiveCheckDiagnostic(
        'approvals',
        approvals >= 2,
        'requested=${_seenApprovals.length}; answered=$approvals; required>=2',
      ),
      LiveCheckDiagnostic(
        'exec starts',
        _execCalls.length >= 2,
        'started=${_execCalls.length}; required>=2',
      ),
      LiveCheckDiagnostic(
        'exec finishes',
        completedExecs >= 2,
        'finished=${_finishedExecCalls.length}; successful=$completedExecs; required>=2',
      ),
      LiveCheckDiagnostic(
        'steering',
        _steered,
        'events=$steeringEvents; started=${_steeringStarted ? 1 : 0}; delivered=${_steered ? 1 : 0}; required=1',
      ),
      LiveCheckDiagnostic(
        'usage',
        usageUpdates >= 1,
        'updates=$usageUpdates; required>=1',
      ),
      LiveCheckDiagnostic(
        'gaps',
        gaps == 0,
        'observed=$gaps; required=0'
            '${_gapDetails.isEmpty ? '' : '; ${_gapDetails.join(' | ')}'}',
      ),
      LiveCheckDiagnostic(
        'completion',
        matches && completed,
        'events=$_completionEvents; matched=${matches ? 1 : 0}; completed=${completed ? 1 : 0}; required=1',
      ),
      LiveCheckDiagnostic(
        'command/event health',
        !_failed,
        'failures=$_failures; required=0',
      ),
    ];
  }
}

/// A capture of actual pipe records, in observed line-completion order. Each
/// record is decoded and structurally redacted before reaching the file sink.
/// It is neither byte-exact raw data nor reconstructed adapter notifications.
class RedactedWireTrace {
  RedactedWireTrace(this._write);
  final void Function(String) _write;
  IOSink? _file;
  final _lines = <String, _WireLine>{};
  final _ids = <String, String>{};
  int _sequence = 0;
  bool _writeFailed = false;
  static const _limit = 16 * 1024 * 1024;

  static Future<RedactedWireTrace> open(String path) async {
    final file = File(path);
    if (await file.exists()) {
      throw const LiveCheckFailure('trace destination must be a new file');
    }
    final sink = file.openWrite();
    final trace = RedactedWireTrace(sink.writeln).._file = sink;
    unawaited(
      sink.done.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          trace._writeFailed = true;
        },
      ),
    );
    return trace;
  }

  Stream<List<int>> tap(String direction, Stream<List<int>> stream) =>
      stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (bytes, sink) {
            add(direction, bytes);
            sink.add(bytes);
          },
          handleDone: (sink) {
            end(direction);
            sink.close();
          },
        ),
      );

  void add(String direction, List<int> bytes) {
    final line = _lines.putIfAbsent(direction, _WireLine.new);
    for (final byte in bytes) {
      if (byte == 10) {
        _emit(direction, line, complete: true);
      } else {
        line.length++;
        if (direction != 'stderr' && line.length <= _limit) {
          line.bytes.add(byte);
        }
      }
    }
  }

  void end(String direction) {
    final line = _lines[direction];
    if (line != null && line.length > 0) {
      _emit(direction, line, complete: false);
    }
  }

  void _emit(String direction, _WireLine line, {required bool complete}) {
    Object? record = '[REDACTED non-JSON or incomplete record]';
    if (direction == 'stderr') {
      record = '[REDACTED stderr]';
    } else if (complete && line.length <= _limit) {
      try {
        record = _redact(jsonDecode(utf8.decode(line.bytes)));
      } on Object {
        /* Never emit malformed source text. */
      }
    }
    final entry = jsonEncode({
      'order': ++_sequence,
      'direction': direction,
      'bytes': line.length,
      'complete': complete,
      'record': record,
    });
    line.bytes.clear();
    line.length = 0;
    try {
      _write(entry);
    } on Object {
      _writeFailed = true;
    }
  }

  Object? _redact(Object? value, [String? key]) {
    // Content-bearing containers are removed wholesale; nested keys and numeric
    // values can contain credentials too. Unknown fields use the same rule.
    if (key != null && !_keys.contains(key)) return '[REDACTED]';
    if (_contentKeys.contains(key)) return '[REDACTED]';
    if (value is Map<String, Object?>) {
      var unknown = 0;
      return <String, Object?>{
        for (final entry in value.entries)
          (_keys.contains(entry.key) ? entry.key : 'redacted_key_${++unknown}'):
              _redact(entry.value, entry.key),
      };
    }
    if (value is List<Object?>) {
      return [for (final item in value) _redact(item, key)];
    }
    if (_idKeys.contains(key) && value is String) {
      // Aliases retain correlation without publishing session/call IDs.
      if (_ids.length >= 10000 && !_ids.containsKey(value)) return '[REDACTED]';
      return _ids.putIfAbsent(value, () => 'id_${_ids.length + 1}');
    }
    if (value is String) {
      return (_values[key]?.contains(value) ?? false) ? value : '[REDACTED]';
    }
    if (value is num) {
      return const {
            'id',
            'sequence',
            'seq',
            'after',
            'last_seq',
            'code',
          }.contains(key)
          ? value
          : '[REDACTED]';
    }
    return value == null || value is bool ? value : '[REDACTED]';
  }

  Future<void> close() async {
    for (final direction in _lines.keys) {
      end(direction);
    }
    await _file?.flush();
    await _file?.close();
    if (_writeFailed) throw const LiveCheckFailure('trace write failed');
  }

  static const _idKeys = {
    'id',
    'session_id',
    'run_id',
    'invocation_id',
    'approval_id',
    'input_id',
    'message_id',
    'call_id',
  };
  static const _contentKeys = {
    'text',
    'error',
    'message',
    'arguments',
    'input',
    'output',
    'content',
    'command',
    'target',
    'path',
    'reason',
    'title',
    'model',
    'streaming_text',
    'options',
    'client',
    'metadata',
    'usage',
    'features',
  };
  static const _keys = {
    'jsonrpc',
    'id',
    'method',
    'params',
    'result',
    'code',
    'protocol_version',
    'session_id',
    'run_id',
    'invocation_id',
    'approval_id',
    'input_id',
    'message_id',
    'call_id',
    'sequence',
    'seq',
    'after',
    'last_seq',
    'durable',
    'type',
    'status',
    'state',
    'tool',
    'name',
    'approval',
    'decision',
    'events',
    'resync',
    'stopped',
    'exitCode',
    'text',
    'error',
    'message',
    'arguments',
    'input',
    'output',
    'content',
    'command',
    'target',
    'path',
    'reason',
    'title',
    'model',
    'streaming_text',
    'options',
    'client',
    'metadata',
    'usage',
    'features',
  };
  static const _values = <String, Set<String>>{
    'jsonrpc': {'2.0'},
    'protocol_version': {'0.1'},
    'method': {
      'initialize',
      'session.open',
      'session.state',
      'session.list',
      'run.start',
      'run.steer',
      'run.cancel',
      'approval.list',
      'approval.decide',
      'events.after',
      'event',
      'events.gap',
      'shutdown',
    },
    'type': {
      'run_started',
      'run_finished',
      'tool_started',
      'tool_finished',
      'approval_requested',
      'approval_resolved',
      'steering_accepted',
      'input_delivered',
      'paragraph',
      'text_delta',
      'model_request_started',
      'host_state_changed',
      'session_settled',
      'output',
    },
    'status': {'running', 'completed', 'failed', 'cancelled'},
    'state': {'pending', 'approved', 'denied', 'expired', 'cancelled', 'done'},
    'decision': {'approve', 'approve_session', 'deny'},
    'tool': {'exec', 'wait', 'poll'},
    'name': {'exec', 'wait', 'poll'},
  };
}

class _WireLine {
  final bytes = <int>[];
  int length = 0;
}

class WireTeeSink implements StreamSink<List<int>> {
  WireTeeSink(this.inner, this.trace, this.direction);
  final StreamSink<List<int>> inner;
  final RedactedWireTrace trace;
  final String direction;
  @override
  void add(List<int> data) {
    trace.add(direction, data);
    inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      add(bytes);
    }
  }

  @override
  Future<void> close() async {
    trace.end(direction);
    await inner.close();
  }

  @override
  Future<void> get done async {
    await inner.done;
  }
}
