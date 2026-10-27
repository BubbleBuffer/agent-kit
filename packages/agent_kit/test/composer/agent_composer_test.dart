import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show KitChoice, KitRef;
import 'package:bb_ui/bb_ui.dart' show Hover;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

Finder get _field => find.byType(EditableText);

String _text(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  testWidgets('shows the placeholder and no Stop while idle', (tester) async {
    await pumpComposer(tester, AgentComposer(onSubmit: (_) {}));
    expect(find.text('Steer the agent…'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Steer'), findsNothing);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('Enter sends the trimmed text and clears the field', (
    tester,
  ) async {
    ComposerSubmission? got;
    await pumpComposer(tester, AgentComposer(onSubmit: (s) => got = s));
    await _type(tester, '  hello  ');
    await _enter(tester);
    expect(got?.text, 'hello');
    expect(got?.delivery, ComposerDelivery.send);
    expect(_text(tester), isEmpty);
  });

  testWidgets('Enter on an empty field sends nothing', (tester) async {
    var calls = 0;
    await pumpComposer(tester, AgentComposer(onSubmit: (_) => calls++));
    await _type(tester, '   ');
    await _enter(tester);
    expect(calls, 0);
  });

  testWidgets('Shift+Enter does not send', (tester) async {
    var calls = 0;
    await pumpComposer(tester, AgentComposer(onSubmit: (_) => calls++));
    await _type(tester, 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(calls, 0);
    expect(_text(tester), 'hello');
  });

  testWidgets('the Send button sends, and is off while the field is empty', (
    tester,
  ) async {
    final got = <ComposerSubmission>[];
    await pumpComposer(tester, AgentComposer(onSubmit: got.add));
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(got, isEmpty);
    await _type(tester, 'go');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(got.single.text, 'go');
  });

  testWidgets('while running, Enter steers and Ctrl+Enter queues', (
    tester,
  ) async {
    final got = <ComposerSubmission>[];
    await pumpComposer(tester, AgentComposer(running: true, onSubmit: got.add));
    await _type(tester, 'one');
    await _enter(tester);
    await _type(tester, 'two');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(got.map((s) => s.delivery), [
      ComposerDelivery.steer,
      ComposerDelivery.followup,
    ]);
  });

  testWidgets('the Queue switch makes Enter queue and Ctrl+Enter steer', (
    tester,
  ) async {
    final got = <ComposerSubmission>[];
    final modes = <ComposerMode>[];
    await pumpComposer(
      tester,
      AgentComposer(running: true, onSubmit: got.add, onModeChanged: modes.add),
    );
    await tester.tap(find.text('Queue'));
    await tester.pump();
    expect(modes, [ComposerMode.queue]);
    await _type(tester, 'one');
    await _enter(tester);
    await _type(tester, 'two');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(got.map((s) => s.delivery), [
      ComposerDelivery.followup,
      ComposerDelivery.steer,
    ]);
  });

  testWidgets('Stop shows only while running and calls onStop', (tester) async {
    var stops = 0;
    await pumpComposer(
      tester,
      AgentComposer(running: true, onStop: () => stops++, onSubmit: (_) {}),
    );
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Steer'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(stops, 1);
  });

  testWidgets('below the fit width the buttons drop their labels', (
    tester,
  ) async {
    Widget composer() => AgentComposer(
      running: true,
      models: fixtureModels,
      modelId: 'flash',
      workspaces: fixtureWorkspaces,
      workspaceId: 'base',
      onSubmit: (_) {},
    );
    await pumpComposer(tester, composer(), width: 560);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('BubblePaw-base'), findsOneWidget);

    await pumpComposer(tester, composer(), width: 400);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('BubblePaw-base'), findsNothing);
    expect(find.text('deepseek-v4.1-flash'), findsOneWidget);
  });

  testWidgets('reference chips show and remove', (tester) async {
    final removed = <KitRef>[];
    await pumpComposer(
      tester,
      AgentComposer(
        refs: const [fixtureChip],
        onRemoveRef: removed.add,
        onSubmit: (_) {},
      ),
    );
    expect(find.text('Approval expiry'), findsOneWidget);
    final chip = find.byKey(const ValueKey('chip-page-p1'));
    await tester.tap(
      find.descendant(of: chip, matching: find.byType(Hover)).last,
    );
    await tester.pump();
    expect(removed, [fixtureChip]);
  });

  testWidgets('attached chips go out with the message', (tester) async {
    ComposerSubmission? got;
    await pumpComposer(
      tester,
      AgentComposer(refs: const [fixtureChip], onSubmit: (s) => got = s),
    );
    await _type(tester, 'hi');
    await _enter(tester);
    expect(got?.refs, [fixtureChip]);
  });

  testWidgets('the model pick opens a menu and reports the choice', (
    tester,
  ) async {
    KitChoice? picked;
    await pumpComposer(
      tester,
      AgentComposer(
        models: fixtureModels,
        modelId: 'flash',
        onModelChanged: (c) => picked = c,
        onSubmit: (_) {},
      ),
    );
    await tester.tap(find.text('deepseek-v4.1-flash'));
    await tester.pumpAndSettle();
    expect(find.text('gpt-6.1-sol'), findsOneWidget);
    await tester.tap(find.text('gpt-6.1-sol'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'sol');
    expect(find.text('gpt-6.1-sol'), findsNothing);
  });

  group('canSend off', () {
    testWidgets('Enter and Send submit nothing; the field is read-only', (
      tester,
    ) async {
      var calls = 0;
      final controller = TextEditingController(text: 'hello');
      addTearDown(controller.dispose);
      await pumpComposer(
        tester,
        AgentComposer(
          onSubmit: (_) => calls++,
          controller: controller,
          canSend: false,
        ),
      );
      expect(tester.widget<EditableText>(_field).readOnly, isTrue);
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.tap(_field);
      await _enter(tester);
      expect(calls, 0);
      expect(controller.text, 'hello');
    });

    testWidgets('Stop follows onStop alone', (tester) async {
      var stops = 0;
      await pumpComposer(
        tester,
        AgentComposer(
          onSubmit: (_) {},
          running: true,
          canSend: false,
          onStop: () => stops++,
        ),
      );
      await tester.tap(find.text('Stop'));
      expect(stops, 1);
    });
  });

  group('mentions', () {
    Future<void> pumpMentions(
      WidgetTester tester,
      List<ComposerSubmission> got,
    ) => pumpComposer(
      tester,
      AgentComposer(mentions: fixtureMentions, onSubmit: got.add),
    );

    testWidgets('typing @ lists candidates; arrows and Enter pick one', (
      tester,
    ) async {
      final got = <ComposerSubmission>[];
      await pumpMentions(tester, got);
      await _type(tester, 'see @us');
      await tester.pump();
      expect(find.text('usage/mod.rs'), findsOneWidget);
      expect(find.text('usage/quota.rs'), findsOneWidget);
      expect(find.text('Approval expiry'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_text(tester), 'see @usage/quota.rs ');
      expect(find.text('usage/mod.rs'), findsNothing);
      expect(got, isEmpty); // picking is not sending

      await _enter(tester);
      final ref = got.single.refs.single;
      expect(got.single.text, 'see @usage/quota.rs');
      expect((ref.kind, ref.id), ('file', 'f2'));
      expect((ref.start, ref.end), (4, 4 + '@usage/quota.rs'.length));
    });

    testWidgets('Esc closes the list and Enter then sends', (tester) async {
      final got = <ComposerSubmission>[];
      await pumpMentions(tester, got);
      await _type(tester, '@us');
      await tester.pump();
      expect(find.text('usage/mod.rs'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('usage/mod.rs'), findsNothing);
      await _enter(tester);
      expect(got.single.text, '@us');
      expect(got.single.refs, isEmpty);
    });

    testWidgets('tapping a candidate picks it', (tester) async {
      await pumpMentions(tester, []);
      await _type(tester, '@appr');
      await tester.pump();
      await tester.tap(find.text('Approval expiry'));
      await tester.pump();
      expect(_text(tester), '@Approval expiry ');
    });

    testWidgets('a mention deleted from the text is not reported', (
      tester,
    ) async {
      final got = <ComposerSubmission>[];
      await pumpMentions(tester, got);
      await _type(tester, '@usage/m');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await _type(tester, 'never mind');
      await _enter(tester);
      expect(got.single.refs, isEmpty);
    });
  });
}
