// ProviderList and ProviderSettings: what the host reports, Make default,
// and the capability gates. The host only says whether a key was found.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chrome/chrome_harness.dart';
import 'provider_samples.dart';

Future<void> _pump(WidgetTester tester, Widget child) => pumpChrome(
  tester,
  SingleChildScrollView(child: child),
  size: const Size(680, 900),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

const _qwen = ValueKey('make-default-openrouter/qwen3-coder');

void main() {
  group('ProviderList', () {
    testWidgets('names providers, keys and the default', (tester) async {
      await _pump(
        tester,
        ProviderList(setup: sampleProviders(), onMakeDefault: (_) {}),
      );
      expect(find.byKey(const ValueKey('provider-default')), findsOneWidget);
      expect(find.text('Key found'), findsOneWidget);
      expect(find.text('Key missing'), findsOneWidget);
      expect(find.text('https://openrouter.ai/api/v1'), findsOneWidget);
      expect(
        find.text(
          'The host did not find ANTHROPIC_API_KEY. Set it for the host and '
          'restart it to use this provider.',
        ),
        findsOneWidget,
      );
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Make default'), findsNWidgets(3));
    });

    testWidgets('a provider without a key requirement is usable', (
      tester,
    ) async {
      await _pump(
        tester,
        ProviderList(setup: sampleProviders(), onMakeDefault: (_) {}),
      );
      expect(find.byKey(const ValueKey('provider-key-demo')), findsNothing);
    });

    testWidgets('Make default is off for a missing key', (tester) async {
      final made = <String>[];
      await _pump(
        tester,
        ProviderList(setup: sampleProviders(), onMakeDefault: made.add),
      );
      await tester.tap(
        find.byKey(const ValueKey('make-default-anthropic/haiku-5.5')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(made, isEmpty);
      await tester.tap(find.byKey(_qwen));
      await tester.pump();
      expect(made, ['openrouter/qwen3-coder']);
    });

    testWidgets('no setter means no buttons', (tester) async {
      await _pump(tester, ProviderList(setup: sampleProviders()));
      expect(find.text('Make default'), findsNothing);
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('a pending change says what is saved', (tester) async {
      await _pump(
        tester,
        ProviderList(
          setup: sampleProviders(reload: true),
          onMakeDefault: (_) {},
        ),
      );
      expect(
        find.text('Saved as openrouter/deepseek-v4.1-flash.'),
        findsOneWidget,
      );
      expect(find.textContaining('has not applied it'), findsOneWidget);
    });

    testWidgets('an empty host says how to add a provider', (tester) async {
      await _pump(tester, ProviderList(setup: ProviderSetup()));
      expect(find.byKey(const ValueKey('provider-empty')), findsOneWidget);
      expect(find.text('None set'), findsOneWidget);
    });

    testWidgets('the busy model says so', (tester) async {
      await _pump(
        tester,
        ProviderList(
          setup: sampleProviders(),
          onMakeDefault: (_) {},
          makingDefault: 'openrouter/qwen3-coder',
        ),
      );
      expect(find.text('Making default…'), findsOneWidget);
    });
  });

  group('ProviderSettings', () {
    ScriptedBackend backend({KitCapabilities? capabilities}) => ScriptedBackend(
      providers: sampleProviders(),
      capabilities: capabilities,
    );

    testWidgets('loads the providers and makes a model the default', (
      tester,
    ) async {
      final b = backend();
      await _pump(tester, ProviderSettings(backend: b));
      await _settle(tester);
      expect(find.byKey(const ValueKey('provider-openrouter')), findsOneWidget);
      await tester.tap(find.byKey(_qwen));
      await _settle(tester);
      expect(
        b.commands.map((c) => c.name),
        containsAllInOrder(['listProviders', 'setDefaultModel']),
      );
      expect(find.byKey(_qwen), findsNothing);
      expect(find.text('openrouter/qwen3-coder'), findsOneWidget);
    });

    testWidgets('a refused change says why', (tester) async {
      final b = backend();
      await _pump(tester, ProviderSettings(backend: b));
      await _settle(tester);
      b.failNext = const KitUnavailable();
      await tester.tap(find.byKey(_qwen));
      await _settle(tester);
      expect(
        find.textContaining('Could not make openrouter/qwen3-coder'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('provider-openrouter')), findsOneWidget);
    });

    testWidgets('a failed load can be tried again', (tester) async {
      final b = backend();
      b.failNext = const KitUnavailable();
      await _pump(tester, ProviderSettings(backend: b));
      await _settle(tester);
      expect(find.byKey(const ValueKey('provider-load-error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('provider-retry')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('provider-openrouter')), findsOneWidget);
      expect(find.byKey(const ValueKey('provider-load-error')), findsNothing);
    });

    testWidgets('without defaultModel the list is read-only', (tester) async {
      final b = backend(
        capabilities: KitCapabilities([KitCapability.providers]),
      );
      await _pump(tester, ProviderSettings(backend: b));
      await _settle(tester);
      expect(find.byKey(const ValueKey('provider-openrouter')), findsOneWidget);
      expect(find.text('Make default'), findsNothing);
    });

    testWidgets('without providers nothing shows', (tester) async {
      final b = backend(capabilities: KitCapabilities.none());
      await _pump(tester, ProviderSettings(backend: b));
      await _settle(tester);
      expect(find.text('Models'), findsNothing);
      expect(b.commands, isEmpty);
    });
  });
}
