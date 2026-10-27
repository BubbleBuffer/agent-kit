import 'dart:async';
import 'dart:convert';

import 'package:agent_kit_bubblepaw/src/errors.dart';
import 'package:agent_kit_bubblepaw/src/transport.dart';
import 'package:test/test.dart';

void main() {
  test('replays fragmented JSON lines, Unicode, CRLF and notifications', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    final notification = transport.notifications.first;
    peer.onRequest = (request) {
      final records = utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'text': 'Paw 🐾'},
        })}\r\n${jsonEncode({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': {'protocol_version': '0.1'},
        })}\n',
      );
      // One-byte chunks deliberately split the multi-byte UTF-8 character.
      for (final byte in records) {
        peer.output.add([byte]);
      }
    };

    expect(await transport.request('initialize'), {'protocol_version': '0.1'});
    expect(await notification, {
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'text': 'Paw 🐾'},
    });
  });

  test('correlates concurrent requests with out-of-order responses', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    final requests = <Map<String, Object?>>[];
    peer.onRequest = (request) {
      requests.add(request);
      if (requests.length == 2) {
        peer.reply(requests[1], 'second');
        peer.reply(requests[0], 'first');
      }
    };

    final first = transport.request('session.list');
    final second = transport.request('session.state', {'session_id': 's1'});
    expect(await Future.wait([first, second]), ['first', 'second']);
    expect(requests[0]['jsonrpc'], '2.0');
    expect(requests[1]['params'], {'session_id': 's1'});
  });

  test('accepts a null result', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    peer.onRequest = (request) => peer.reply(request, null);
    expect(await transport.request('initialize'), isNull);
  });

  test('RPC errors omit raw host messages and response data', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    peer.onRequest = (request) => peer.send({
      'jsonrpc': '2.0',
      'id': request['id'],
      'error': {
        'code': -32000,
        'message': 'Authorization: Bearer private-token',
        'data': {'password': 'private-password'},
      },
    });

    await expectLater(transport.request('session.open'), throwsA(
      isA<BubblePawException>()
        .having((error) => error.code, 'code', 'rpcError')
        .having((error) => error.toString(), 'safe rendering',
          isNot(contains('private-'))),
    ));
    peer.onRequest = (request) => peer.reply(request, 'still usable');
    expect(await transport.request('session.list'), 'still usable');
  });

  for (final entry in <String, String>{
    'Session already has an active run r1; steer or follow up instead': 'busy',
    'Session is busy': 'busy',
    'Unknown session: s1': 'notFound',
    'Unknown approval: a1': 'notFound',
    'Parent not found': 'notFound',
    'Approval a1 is already approved_once': 'conflict',
    'Approval already resolved': 'conflict',
    'session_id is required': 'invalid',
    'after must be a sequence number': 'invalid',
    'Invalid request parameters': 'invalid',
    'Permission denied': 'denied',
    'Session belongs to another workspace': 'denied',
    'Unrecognized provider failure': 'rpcError',
    'Provider failed while logging an active run': 'rpcError',
  }.entries) {
    test('classifies host errors safely as ${entry.value}: ${entry.key}',
        () async {
      final peer = _Peer();
      final transport = peer.transport();
      addTearDown(() => _cleanup(transport, peer));
      peer.onRequest = (request) => peer.send({
        'jsonrpc': '2.0',
        'id': request['id'],
        'error': {'code': -32000, 'message': entry.key},
      });
      await expectLater(transport.request('run.start'),
        throwsA(_code(entry.value)));
    });
  }

  test('deadline rejects only its request and tolerates its late response',
      () async {
    final peer = _Peer();
    final transport = peer.transport(
      requestTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() => _cleanup(transport, peer));
    final received = Completer<Map<String, Object?>>();
    peer.onRequest = received.complete;
    final expired = transport.request('session.list');
    await expectLater(expired, throwsA(_code('requestTimeout')));
    peer.reply(await received.future, 'too late');
    peer.onRequest = (request) => peer.reply(request, 'fresh');
    expect(await transport.request('session.list'), 'fresh');
  });

  for (final malformed in <String>[
    'not-json\n',
    '[]\n',
    '{"jsonrpc":"1.0","id":1,"result":null}\n',
    '{"jsonrpc":"2.0","id":999,"result":null}\n',
    '{"jsonrpc":"2.0","id":1,"result":null,"error":{}}\n',
    '{"jsonrpc":"2.0","id":1,"error":{"code":"bad","message":"x"}}\n',
    '{"jsonrpc":"2.0","method":"event","params":false}\n',
    '{"jsonrpc":"2.0","id":null,"result":null}\n',
  ]) {
    test('rejects malformed protocol record ${jsonEncode(malformed)}', () async {
      final peer = _Peer();
      final transport = peer.transport();
      addTearDown(() => _cleanup(transport, peer));
      final errors = <Object>[];
      final notificationsDone = Completer<void>();
      transport.notifications.listen(
        (_) {},
        onError: (Object error) => errors.add(error),
        onDone: notificationsDone.complete,
      );
      peer.onRequest = (_) => peer.output.add(utf8.encode(malformed));

      await expectLater(transport.request('initialize'),
        throwsA(_code('protocolError')));
      await notificationsDone.future;
      expect(errors, [isA<BubblePawException>()]);
      await expectLater(transport.request('session.list'),
        throwsA(_code('protocolError')));
    });
  }

  test('rejects invalid UTF-8 and incomplete records', () async {
    for (final bytes in <List<int>>[
      [0xff, 10],
      utf8.encode('{"jsonrpc":"2.0"'),
    ]) {
      final peer = _Peer();
      final transport = peer.transport();
      peer.onRequest = (_) {
        peer.output.add(bytes);
        unawaited(peer.exit(1));
      };
      await expectLater(transport.request('initialize'),
        throwsA(_code('protocolError')));
      await _cleanup(transport, peer);
    }
  });

  test('maps host exit to pending requests and notification listeners', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    final notificationErrors = <Object>[];
    final notificationsDone = Completer<void>();
    transport.notifications.listen(
      (_) {},
      onError: (Object error) => notificationErrors.add(error),
      onDone: notificationsDone.complete,
    );
    peer.onRequest = (_) {
      peer.stderr.add(utf8.encode('token=private-token\npassword=private-secret'));
      unawaited(peer.exit(17));
    };

    await expectLater(transport.request('session.list'), throwsA(
      isA<BubblePawHostExited>()
        .having((error) => error.exitCode, 'exit code', 17)
        .having((error) => error.stderrTail, 'redacted tail',
          allOf(isNotEmpty, isNot(contains('private-')))),
    ));
    await notificationsDone.future;
    expect(notificationErrors.single, isA<BubblePawHostExited>());
    expect(peer.killCount, 0);
  });

  test('bounds the redacted stderr tail', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    peer.onRequest = (_) {
      peer.stderr.add(utf8.encode(List.filled(1000, 'secret\n').join()));
      unawaited(peer.exit(2));
    };

    await expectLater(transport.request('initialize'), throwsA(
      isA<BubblePawHostExited>()
        .having((error) => error.stderrTail.length, 'tail length',
          lessThanOrEqualTo(2048))
        .having((error) => error.stderrTail, 'tail contents',
          isNot(contains('secret'))),
    ));
  });

  test('dispose sends shutdown, closes stdin, and is idempotent', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    final done = transport.notifications.drain<void>();
    final first = transport.dispose();
    final second = transport.dispose();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second, done]);

    expect(peer.shutdownCount, 1);
    expect(peer.inputClosed, isTrue);
    expect(peer.killCount, 0);
    await expectLater(transport.request('initialize'),
      throwsA(_code('transportClosed')));
  });

  test('dispose completes pending requests and kills only an unresponsive peer',
      () async {
    final peer = _Peer()..respondToShutdown = false;
    final transport = peer.transport(
      shutdownTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(() => _cleanup(transport, peer));
    final request = transport.request('session.list');
    final rejected = expectLater(request, throwsA(_code('transportClosed')));
    await transport.dispose();
    await rejected;

    expect(peer.shutdownCount, 1);
    expect(peer.inputClosed, isTrue);
    expect(peer.killCount, 1);
    await transport.dispose();
    expect(peer.killCount, 1);
  });

  test('a paused notification listener does not block disposal', () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    final listener = transport.notifications.listen((_) {});
    listener.pause();
    await transport.dispose();
    await listener.cancel();
    expect(peer.inputClosed, isTrue);
  });

  test('non-JSON parameters fail safely without corrupting later requests',
      () async {
    final peer = _Peer();
    final transport = peer.transport();
    addTearDown(() => _cleanup(transport, peer));
    await expectLater(transport.request('initialize', {'invalid': Object()}),
      throwsA(_code('protocolError')));
    peer.onRequest = (request) => peer.reply(request, 'ok');
    expect(await transport.request('initialize'), 'ok');
  });

  test('requires positive timeouts', () async {
    final peer = _Peer();
    // The rejected constructors never subscribe to the fake's output pipes.
    peer.output.stream.listen((_) {});
    peer.stderr.stream.listen((_) {});
    addTearDown(peer.close);
    expect(() => peer.transport(requestTimeout: Duration.zero),
      throwsArgumentError);
    expect(() => peer.transport(shutdownTimeout: Duration.zero),
      throwsArgumentError);
  });
}

Matcher _code(String code) => isA<BubblePawException>()
  .having((error) => error.code, 'code', code);

Future<void> _cleanup(StdioBubblePawTransport transport, _Peer peer) async {
  await transport.dispose();
  await peer.close();
}

class _Peer {
  _Peer() {
    _inputSubscription = input.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        final request = jsonDecode(line) as Map<String, Object?>;
        if (request['method'] == 'shutdown') {
          shutdownCount++;
          if (respondToShutdown) {
            reply(request, {'stopped': true});
            unawaited(exit(0));
          }
        } else {
          onRequest?.call(request);
        }
      }, onDone: () { inputClosed = true; });
  }

  final output = StreamController<List<int>>();
  final stderr = StreamController<List<int>>();
  final input = StreamController<List<int>>();
  final _exit = Completer<int>();
  late final StreamSubscription<String> _inputSubscription;
  void Function(Map<String, Object?>)? onRequest;
  bool respondToShutdown = true;
  bool inputClosed = false;
  int shutdownCount = 0;
  int killCount = 0;
  Future<void>? _exitFuture;

  StdioBubblePawTransport transport({
    Duration requestTimeout = const Duration(seconds: 1),
    Duration shutdownTimeout = const Duration(milliseconds: 20),
  }) => StdioBubblePawTransport.forTesting(
    stdout: output.stream,
    stdin: input.sink,
    stderr: stderr.stream,
    exitCode: _exit.future,
    terminate: () {
      killCount++;
      unawaited(exit(-9));
    },
    requestTimeout: requestTimeout,
    shutdownTimeout: shutdownTimeout,
  );

  void send(Map<String, Object?> record) =>
    output.add(utf8.encode('${jsonEncode(record)}\n'));

  void reply(Map<String, Object?> request, Object? result) => send({
    'jsonrpc': '2.0', 'id': request['id'], 'result': result,
  });

  Future<void> exit(int code) => _exitFuture ??= _finishExit(code);

  Future<void> _finishExit(int code) async {
    if (!_exit.isCompleted) _exit.complete(code);
    await Future.wait([output.close(), stderr.close()]);
  }

  Future<void> close() async {
    await exit(0);
    await input.close();
    await _inputSubscription.cancel();
  }
}
