// BubblePaw-Core v0.3.1: providers.list, roles.set_main, paged session.list
// and child.cancel. A part of backend_test.dart so that it shares its fake
// stdio peer.
part of 'backend_test.dart';

const _v031 = [
  'sessions',
  'events',
  'child_events',
  'providers.list',
  'roles.set_main',
  'session.list.pagination',
  'child.cancel',
];

// What the host sends: key_present only, never a key.
Json _providerWire({
  String main = 'demo/first',
  String activeMain = 'demo/first',
  bool reloadNeeded = false,
}) => {
  'target': {'path': '/home/u/.config/bubblepaw/config.toml', 'exists': true},
  'main': main,
  'active_main': activeMain,
  'launched_main': 'demo/first',
  'reload_needed': reloadNeeded,
  'restart_needed': false,
  'providers': [
    {
      'name': 'demo',
      'kind': 'chat-completions',
      'base_url': 'http://127.0.0.1:9000/v1',
      'key_env': 'DEMO_API_KEY',
      'key_present': true,
      'source': 'user',
      'models': [
        {'id': 'first', 'image_input': false},
        {'id': 'second', 'image_input': true},
      ],
    },
    {
      'name': 'remote',
      'kind': 'anthropic-messages',
      'key_env': 'REMOTE_API_KEY',
      'key_present': false,
      'models': [
        {'id': 'big'},
      ],
    },
    {
      'name': 'local',
      'kind': 'responses',
      'key_present': false,
      'models': [
        {'id': 'tiny'},
      ],
    },
  ],
};

Json _runState({String? model, String status = 'completed'}) => {
  'session': {'id': 's1', 'title': 'Synthetic chat'},
  'seq': 3,
  'messages': <Json>[],
  'runs': [
    {
      'id': 'r1',
      'model': model,
      'status': status,
      'started_at': '2026-10-29T10:00:00Z',
      'ended_at': status == 'running' ? null : '2026-10-29T10:01:00Z',
    },
  ],
  'inputs': <Json>[],
  'question': null,
  'todo': <Json>[],
};

void _hostControlTests() {
  group('BubblePaw-Core v0.3.1 host controls', () {
    test(
      'every capability stays off unless its feature is advertised',
      () async {
        final peer = _BackendPeer()..features = ['sessions', 'events'];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        for (final capability in [
          KitCapability.providers,
          KitCapability.defaultModel,
          KitCapability.models,
          KitCapability.children,
        ]) {
          expect(
            backend.capabilities.has(capability),
            isFalse,
            reason: '$capability',
          );
        }
        await expectLater(
          backend.listProviders(),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.setDefaultModel('demo/second'),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(backend.listModels(), throwsA(isA<KitUnsupported>()));
        await expectLater(
          backend.setModel('s1', 'demo/second'),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.cancelChild('s1', 'c1'),
          throwsA(isA<KitUnsupported>()),
        );
        await expectLater(
          backend.listChats(cursor: 'abc'),
          throwsA(isA<KitInvalid>()),
        );
        expect(peer.calls.map((c) => c.method), ['initialize']);
      },
    );

    test('each feature enables only its own capability', () async {
      Future<Set<KitCapability>> offered(List<String> extra) async {
        final peer = _BackendPeer()
          ..features = ['sessions', 'events', ...extra];
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        return backend.capabilities.values;
      }

      final base = (await offered(const [])).length;
      expect(
        await offered(['providers.list']),
        contains(KitCapability.providers),
      );
      expect(
        await offered(['providers.list']),
        isNot(contains(KitCapability.models)),
      );
      expect(
        await offered(['roles.set_main']),
        contains(KitCapability.defaultModel),
      );
      expect(
        await offered(['roles.set_main']),
        isNot(contains(KitCapability.models)),
      );
      expect(
        await offered(['providers.list', 'roles.set_main']),
        containsAll([
          KitCapability.providers,
          KitCapability.defaultModel,
          KitCapability.models,
        ]),
      );
      expect(await offered(['child.cancel']), contains(KitCapability.children));
      expect(await offered(['session.list.pagination']), hasLength(base));
    });

    test('providers.list maps the setup and carries no key', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) => method == 'providers.list'
          ? {
              ..._providerWire(),
              // Not part of the contract; a stray value must not get through.
              'api_key': 'sk-not-for-the-kit',
            }
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final setup = await backend.listProviders();
      expect(setup.main, 'demo/first');
      expect(setup.activeMain, 'demo/first');
      expect(setup.defaultModel, 'demo/first');
      expect(setup.reloadNeeded, isFalse);
      expect(setup.providers.map((p) => p.name), ['demo', 'remote', 'local']);
      final demo = setup.providers.first;
      expect(demo.kind, 'chat-completions');
      expect(demo.baseUrl, 'http://127.0.0.1:9000/v1');
      expect(demo.keyEnv, 'DEMO_API_KEY');
      expect(demo.keyPresent, isTrue);
      expect(demo.models.map((m) => demo.qualify(m)), [
        'demo/first',
        'demo/second',
      ]);
      expect(setup.providers[1].keyPresent, isFalse);
      expect(setup.toString(), isNot(contains('sk-not-for-the-kit')));
      expect(peer.calls.last.method, 'providers.list');
      expect(peer.calls.last.params, isEmpty);
    });

    test('listModels is the usable providers\' models, qualified', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) => method == 'providers.list'
          ? _providerWire()
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final models = await backend.listModels();
      // remote needs a key the host does not have; local needs none.
      expect(models.map((m) => m.id), [
        'demo/first',
        'demo/second',
        'local/tiny',
      ]);
      expect(models.first.label, 'demo/first');
    });

    test(
      'setDefaultModel sends provider/model and returns the setup',
      () async {
        final peer = _BackendPeer()..features = _v031;
        peer.handler = (method, params) => method == 'roles.set_main'
            ? _providerWire(
                main: params['model']! as String,
                activeMain: params['model']! as String,
              )
            : peer.defaultResponse(method, params);
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final setup = await backend.setDefaultModel('demo/second');
        expect(setup.defaultModel, 'demo/second');
        final call = peer.calls.singleWhere(
          (c) => c.method == 'roles.set_main',
        );
        expect(call.params, {'model': 'demo/second'});
        await expectLater(
          backend.setDefaultModel('second'),
          throwsA(isA<KitInvalid>()),
        );
        expect(
          peer.calls.where((c) => c.method == 'roles.set_main'),
          hasLength(1),
        );
      },
    );

    test(
      'a failed roles.set_main is a kit error without the host text',
      () async {
        final peer = _BackendPeer()..features = _v031;
        peer.handler = (method, params) => method == 'roles.set_main'
            ? const _RpcFailure(
                '/home/u/.config/bubblepaw/config.toml is masked',
              )
            : peer.defaultResponse(method, params);
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        await expectLater(
          backend.setDefaultModel('demo/second'),
          throwsA(
            isA<KitError>().having(
              (e) => e.message,
              'message',
              isNot(contains('config.toml')),
            ),
          ),
        );
      },
    );

    test('the composer shows the host default and a pick changes it', () async {
      var main = 'demo/first';
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) {
        if (method == 'providers.list') {
          return _providerWire(main: main, activeMain: main);
        }
        if (method == 'roles.set_main') {
          main = params['model']! as String;
          return _providerWire(main: main, activeMain: main);
        }
        if (method == 'session.list') {
          return <Json>[];
        }
        if (method == 'session.state') {
          // The last run used another model than the default.
          return _runState(model: 'demo/old');
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      expect((await backend.loadChat('s1')).model, 'demo/first');
      await backend.setModel('s1', 'demo/second');
      expect(
        peer.calls.singleWhere((c) => c.method == 'roles.set_main').params,
        {'model': 'demo/second'},
      );
      expect((await backend.loadChat('s1')).model, 'demo/second');
      // The default is read once, then kept.
      expect(
        peer.calls.where((c) => c.method == 'providers.list'),
        hasLength(1),
      );
    });

    test('a run in progress keeps its own model in the snapshot', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) {
        if (method == 'providers.list') {
          return _providerWire();
        }
        if (method == 'session.list') {
          return <Json>[];
        }
        if (method == 'session.state') {
          return _runState(model: 'demo/old', status: 'running');
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      expect((await backend.loadChat('s1')).model, 'demo/old');
    });

    test('a watched chat is told when the default changes', () async {
      var main = 'demo/first';
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) {
        if (method == 'providers.list') {
          return _providerWire(main: main, activeMain: main);
        }
        if (method == 'roles.set_main') {
          main = params['model']! as String;
          return _providerWire(main: main, activeMain: main);
        }
        if (method == 'session.list') {
          return <Json>[];
        }
        if (method == 'session.state') {
          return _runState(model: 'demo/old');
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final initial = await backend.loadChat('s1');
      // The host sequence does not move, so the changed model cannot be an
      // event in a free slot: the feed gets a gap and reloads the snapshot.
      final changed = Completer<KitEvent>();
      final subscription = backend.events('s1', after: initial.seq).listen((e) {
        if ((e is ChatSettingsChanged || e is GapEvent) &&
            !changed.isCompleted) {
          changed.complete(e);
        }
      });
      addTearDown(subscription.cancel);
      await peer.waitFor((c) => c.method == 'events.after');
      await backend.setDefaultModel('demo/second');
      await changed.future.timeout(const Duration(seconds: 2));
      expect((await backend.loadChat('s1')).model, 'demo/second');
    });

    test('session.list pages with a limit and the previous cursor', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) {
        if (method != 'session.list') {
          return peer.defaultResponse(method, params);
        }
        return params['cursor'] == null
            ? {
                // Host order is kept: created, not updated.
                'sessions': [
                  {
                    'id': 'b',
                    'title': 'Newer',
                    'updated_at': '2026-10-01T00:00:00Z',
                  },
                  {
                    'id': 'a',
                    'title': 'Older',
                    'updated_at': '2026-10-28T00:00:00Z',
                  },
                ],
                'next_cursor': 'page-2',
              }
            : {
                'sessions': [
                  {
                    'id': '9',
                    'title': 'Oldest',
                    'updated_at': '2026-09-01T00:00:00Z',
                  },
                ],
                'next_cursor': null,
              };
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final first = await backend.listChats();
      expect(first.chats.map((c) => c.id), ['b', 'a']);
      expect(first.nextCursor, 'page-2');
      final second = await backend.listChats(cursor: first.nextCursor);
      expect(second.chats.map((c) => c.id), ['9']);
      expect(second.nextCursor, isNull);
      final lists = peer.calls
          .where((c) => c.method == 'session.list')
          .toList();
      expect(lists[0].params, {'limit': BubblePawBackend.chatPageSize});
      expect(lists[1].params, {
        'limit': BubblePawBackend.chatPageSize,
        'cursor': 'page-2',
      });
    });

    test(
      'without the pagination feature the list is whole and unpaged',
      () async {
        final peer = _BackendPeer()..features = ['sessions', 'events'];
        peer.handler = (method, params) => method == 'session.list'
            ? [
                {'id': 'a', 'title': 'A', 'updated_at': '2026-10-01T00:00:00Z'},
                {'id': 'b', 'title': 'B', 'updated_at': '2026-10-28T00:00:00Z'},
              ]
            : peer.defaultResponse(method, params);
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final page = await backend.listChats();
        expect(page.chats.map((c) => c.id), ['b', 'a']);
        expect(page.nextCursor, isNull);
        expect(peer.calls.last.params, isEmpty);
      },
    );

    test('child lookups still read the whole list when it is paged', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) {
        if (method == 'session.list') {
          return [
            {'id': 's1', 'title': 'Parent'},
            {'id': 'c1', 'title': 'Child', 'parent_session_id': 's1'},
          ];
        }
        if (method == 'session.state') {
          return params['session_id'] == 'c1'
              ? _childState('c1', run: 'running')
              : peer.state(seq: 3);
        }
        return peer.defaultResponse(method, params);
      };
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      final snapshot = await backend.loadChat('s1');
      expect(snapshot.children.map((c) => c.id), ['c1']);
      expect(
        peer.calls
            .where((c) => c.method == 'session.list')
            .map((c) => c.params),
        everyElement(isEmpty),
      );
    });

    test(
      'cancelChild sends the parent and child, then refreshes the crew',
      () async {
        var running = true;
        final peer = _BackendPeer()..features = _v031;
        peer.handler = (method, params) {
          if (method == 'child.cancel') {
            running = false;
            return {
              'sessionId': params['child'],
              'handle': 'h',
              'status': 'cancelled',
            };
          }
          if (method == 'providers.list') {
            return _providerWire();
          }
          if (method == 'session.list') {
            return [
              {'id': 'c1', 'title': 'Child', 'parent_session_id': 's1'},
            ];
          }
          if (method == 'session.state') {
            return params['session_id'] == 'c1'
                ? _childState('c1', run: running ? 'running' : 'cancelled')
                : peer.state(seq: 3);
          }
          return peer.defaultResponse(method, params);
        };
        final backend = await peer.connect();
        addTearDown(() => peer.close(backend));
        final initial = await backend.loadChat('s1');
        expect(initial.children.single.state, WorkState.running);
        // A cancelled child changes no host sequence here, so the feed gets a
        // gap and reloads; a host that advances the sequence sends the child's
        // events instead.
        final finished = Completer<KitEvent>();
        final subscription = backend.events('s1', after: initial.seq).listen((
          e,
        ) {
          if ((e is ChildFinished || e is GapEvent) && !finished.isCompleted) {
            finished.complete(e);
          }
        });
        addTearDown(subscription.cancel);
        await peer.waitFor((c) => c.method == 'events.after');
        await backend.cancelChild('s1', 'c1');
        expect(
          peer.calls.singleWhere((c) => c.method == 'child.cancel').params,
          {'parent': 's1', 'child': 'c1'},
        );
        await finished.future.timeout(const Duration(seconds: 2));
        final after = await backend.loadChat('s1');
        expect(after.children.single.state, WorkState.cancelled);
      },
    );

    test('a failed child.cancel is a kit error', () async {
      final peer = _BackendPeer()..features = _v031;
      peer.handler = (method, params) => method == 'child.cancel'
          ? const _RpcFailure('child is not a direct child of parent')
          : peer.defaultResponse(method, params);
      final backend = await peer.connect();
      addTearDown(() => peer.close(backend));
      await expectLater(
        backend.cancelChild('s1', 'c1'),
        throwsA(isA<KitError>()),
      );
    });
  });
}
