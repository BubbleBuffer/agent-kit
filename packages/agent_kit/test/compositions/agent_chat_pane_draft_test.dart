// AgentChatPane draft state (chatId null) and the composer slot.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compositions_harness.dart';

/// The commands that change something (the pane also lists the picks).
List<String> _writes(ScriptedBackend backend) => [
  for (final name in commandNames(backend))
    if (!name.startsWith('list')) name,
];

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _draft(
  ScriptedBackend backend,
  ManualClock clock, {
  ValueChanged<String>? onCreated,
  String Function(String)? draftTitle,
  Widget Function(BuildContext, PaneComposerSlot)? composerBuilder,
}) => AgentChatPane(
  backend: backend,
  chatId: null,
  now: clock.now(),
  onChatCreated: onCreated,
  draftTitle: draftTitle,
  composerBuilder: composerBuilder,
);

void main() {
  testWidgets('a draft shows an empty chat with a working composer', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _draft(s.backend, s.clock));
    expect(find.text('New chat'), findsOneWidget);
    expect(find.byType(AgentComposer), findsOneWidget);
    expect(_writes(s.backend), isEmpty);
  });

  testWidgets('the first send creates the chat, sends, then reports it', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    final created = <String>[];
    await pumpApp(tester, _draft(s.backend, s.clock, onCreated: created.add));
    await tester.enterText(find.byType(EditableText).last, 'hello there');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await _settle(tester);

    expect(_writes(s.backend), ['createChat', 'send']);
    expect(lastArgs(s.backend, 'createChat')[0], 'hello there');
    final id = lastArgs(s.backend, 'send')[0]! as String;
    expect(lastArgs(s.backend, 'send')[1], 'hello there');
    expect(created, [id]);
  });

  testWidgets('the title is the first line, cut at 60 characters', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(tester, _draft(s.backend, s.clock));
    final long = 'x' * 70;
    await tester.enterText(find.byType(EditableText).last, '$long\nsecond');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await _settle(tester);
    expect(lastArgs(s.backend, 'createChat')[0], '${'x' * 60}…');
  });

  testWidgets('draftTitle overrides the title', (tester) async {
    final s = await playedBackend(tester);
    await pumpApp(
      tester,
      _draft(s.backend, s.clock, draftTitle: (text) => 'T: $text'),
    );
    await tester.enterText(find.byType(EditableText).last, 'hi');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await _settle(tester);
    expect(lastArgs(s.backend, 'createChat')[0], 'T: hi');
  });

  testWidgets('without createChat a draft cannot send', (tester) async {
    final s = await playedBackend(
      tester,
      capabilities: KitCapabilities([KitCapability.send]),
    );
    await pumpApp(tester, _draft(s.backend, s.clock));
    await tester.enterText(find.byType(EditableText).last, 'hi');
    await tester.pump();
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await _settle(tester);
    expect(_writes(s.backend), isEmpty);
  });

  testWidgets('composerBuilder replaces the composer and gets the wiring', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    PaneComposerSlot? seen;
    await pumpApp(
      tester,
      _draft(
        s.backend,
        s.clock,
        composerBuilder: (context, slot) {
          seen = slot;
          return const Text('host composer', textDirection: TextDirection.ltr);
        },
      ),
    );
    expect(find.text('host composer'), findsOneWidget);
    expect(find.byType(AgentComposer), findsNothing);
    expect(seen!.draft, isTrue);
    expect(seen!.canSend, isTrue);
    expect(seen!.running, isFalse);

    await tester.runAsync(
      () => seen!.submit(
        const ComposerSubmission(
          text: 'from host',
          delivery: ComposerDelivery.send,
        ),
      ),
    );
    expect(_writes(s.backend), ['createChat', 'send']);
  });

  testWidgets('an existing chat hands the slot its state', (tester) async {
    final s = await playedBackend(tester);
    PaneComposerSlot? seen;
    await pumpApp(
      tester,
      AgentChatPane(
        backend: s.backend,
        chatId: quotaChatId,
        now: s.clock.now(),
        composerBuilder: (context, slot) {
          seen = slot;
          return const SizedBox();
        },
      ),
    );
    expect(seen!.draft, isFalse);
    expect(seen!.running, isTrue);
    expect(seen!.onStop, isNotNull);
    expect(seen!.models, isNotEmpty);
  });
}
