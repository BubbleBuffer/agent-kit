// AgentChatPane: every command reaches the backend, capabilities hide
// controls, a failed command is one inline line, and a chat switch closes the
// old feed.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/composer/composer_parts.dart' show KitIconButton;
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compositions_harness.dart';

Widget _pane(
  ScriptedBackend backend,
  ManualClock clock, {
  String chatId = quotaChatId,
  AgentPaneActions? paneActions,
}) => AgentChatPane(
  backend: backend,
  chatId: chatId,
  now: clock.now(),
  onReviewApproval: (_) {},
  paneActions: paneActions,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('commands reach the backend', () {
    testWidgets('approve for session', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      expect(find.text('Needs approval'), findsOneWidget);

      await tester.tap(find.text('For session'));
      await _settle(tester);
      final d = lastArgs(s.backend, 'decideApproval');
      expect(d[0], quotaChatId);
      expect(d[1], 'ap1');
      expect(
        (d[2]! as ApprovalDecision).choice,
        ApprovalChoice.approveForSession,
      );
      // The fake resolved it, so the bar is gone.
      expect(find.text('Needs approval'), findsNothing);
    });

    testWidgets('approve', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      final d = lastArgs(s.backend, 'decideApproval');
      expect((d[2]! as ApprovalDecision).choice, ApprovalChoice.approve);
    });

    testWidgets('deny sends the reason', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      await tester.tap(find.text('Deny'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).first, 'not that file');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      final decision =
          lastArgs(s.backend, 'decideApproval')[2]! as ApprovalDecision;
      expect(decision.choice, ApprovalChoice.deny);
      expect(decision.reason, 'not that file');
    });

    testWidgets('a message while running steers, or queues in Queue mode', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      await tester.enterText(find.byType(EditableText).last, 'use a flag');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(commandNames(s.backend), contains('steer'));
      expect(lastArgs(s.backend, 'steer')[1], 'use a flag');

      await tester.tap(find.text('Queue'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'then docs');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'followup')[1], 'then docs');
    });

    testWidgets('a message to an idle chat sends', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock, chatId: 'idle'));
      await tester.enterText(find.byType(EditableText).last, 'hello');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'send')[1], 'hello');
    });

    testWidgets('stop cancels the run', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      await tester.tap(find.text('Stop'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'cancel')[0], quotaChatId);
    });

    testWidgets('edit and remove a queued input', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      expect(find.byType(QueuedRow), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.enterText(
        find.byType(EditableText).first,
        'Dim it, keep it',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      final edit = lastArgs(s.backend, 'editQueued');
      expect(edit[1], 'q1');
      expect(edit[2], 'Dim it, keep it');

      final row = tester.widget<QueuedRow>(find.byType(QueuedRow));
      row.onRemove!(row.input);
      await _settle(tester);
      expect(lastArgs(s.backend, 'removeQueued')[1], 'q1');
      expect(find.byType(QueuedRow), findsNothing);
    });

    testWidgets('send now', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      await tester.tap(find.text('Send now'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'sendQueuedNow')[1], 'q1');
    });

    testWidgets('answering a question', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock, chatId: questionChatId));
      final prompt = tester.widget<QuestionPrompt>(find.byType(QuestionPrompt));
      prompt.onAnswer({
        for (final item in prompt.question.items)
          item.id: QuestionAnswer(skipped: true),
      });
      await _settle(tester);
      final args = lastArgs(s.backend, 'answerQuestion');
      expect(args[0], questionChatId);
      expect(args[1], mixedQuestionId);
      // Resolved, it reads as answer lines in the transcript.
      expect(find.byType(QuestionPrompt), findsNothing);
      expect(find.byType(QuestionAnswerLines), findsOneWidget);
    });

    testWidgets('resume an interrupted run, and fork', (tester) async {
      final s = await playedBackend(tester);
      s.backend.emit('int', {'kind': 'chat.renamed', 'title': 'Interrupted'});
      s.backend.emit('int', {'kind': 'run.started', 'runId': 'r1'});
      s.backend.emit('int', {
        'kind': 'run.finished',
        'runId': 'r1',
        'outcome': 'interrupted',
      });
      String? opened;
      await pumpApp(
        tester,
        AgentChatPane(
          backend: s.backend,
          chatId: 'int',
          now: s.clock.now(),
          onOpenChat: (id) => opened = id,
        ),
      );
      expect(find.text('Interrupted by a restart'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await _settle(tester);
      expect(commandNames(s.backend), contains('resume'));

      await tester.tap(find.byKey(const ValueKey('header-menu')));
      await tester.pump();
      await tester.tap(find.text('Fork chat'));
      await _settle(tester);
      expect(commandNames(s.backend), contains('fork'));
      expect(opened, isNotNull);
    });
  });

  group('transcript', () {
    testWidgets('draws the snapshot plan', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      for (var i = 0; i < 8; i++) {
        await tester.drag(find.byType(TranscriptList), const Offset(0, 2000));
        await tester.pump();
      }
      expect(find.text('Plan'), findsOneWidget);
    });
  });

  group('capabilities', () {
    testWidgets('a backend with every capability shows every control', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      expect(find.text('Send now'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Steer'), findsOneWidget);
      expect(find.text('deepseek-v4.1-flash'), findsOneWidget);
      expect(find.byKey(const ValueKey('header-menu')), findsOneWidget);
    });

    testWidgets('a backend without them hides the controls', (tester) async {
      final s = await playedBackend(
        tester,
        capabilities: KitCapabilities(const <KitCapability>[]),
      );
      await pumpApp(tester, _pane(s.backend, s.clock));
      expect(find.byType(QueuedRow), findsOneWidget);
      expect(find.text('Send now'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Steer'), findsNothing);
      expect(find.text('deepseek-v4.1-flash'), findsNothing);
      expect(find.byKey(const ValueKey('header-menu')), findsNothing);
      // The approval and composer stay visible, with their actions disabled.
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(
        tester.widget<ApprovalBar>(find.byType(ApprovalBar)).enabled,
        isFalse,
      );
      final composer = tester.widget<AgentComposer>(find.byType(AgentComposer));
      expect(composer.canSend, isFalse);
      expect(composer.onStop, isNull);
    });

    testWidgets('missing action capabilities block every input path', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final s = await playedBackend(
        tester,
        capabilities: KitCapabilities.none(),
      );
      await pumpApp(tester, _pane(s.backend, s.clock));
      s.backend.commands.clear();

      for (final label in ['Send', 'Stop', 'Approve', 'For session', 'Deny']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
          reason: label,
        );
        await tester.tap(find.text(label));
        await _settle(tester);
      }
      await tester.tap(find.byType(EditableText).last);
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
      ]) {
        await tester.sendKeyEvent(key);
        await _settle(tester);
      }

      // The pane also rejects direct child callbacks, including steer/queue.
      final composer = tester.widget<AgentComposer>(find.byType(AgentComposer));
      for (final delivery in ComposerDelivery.values) {
        composer.onSubmit(
          ComposerSubmission(text: 'blocked', delivery: delivery),
        );
      }
      tester
          .widget<ApprovalBar>(find.byType(ApprovalBar))
          .onDecide(ApprovalDecision.approve);
      await _settle(tester);
      expect(commandNames(s.backend), isEmpty);
      expect(find.text('Needs approval'), findsOneWidget);
      expect(find.text('Reason for the agent (optional)'), findsNothing);
      handle.dispose();
    });

    for (final capability in [
      KitCapability.send,
      KitCapability.cancel,
      KitCapability.approve,
    ]) {
      testWidgets('${capability.name} enables only its own action', (
        tester,
      ) async {
        final s = await playedBackend(
          tester,
          capabilities: KitCapabilities([capability]),
        );
        await pumpApp(tester, _pane(s.backend, s.clock));
        final composer = tester.widget<AgentComposer>(
          find.byType(AgentComposer),
        );
        expect(composer.canSend, capability == KitCapability.send);
        expect(composer.onStop != null, capability == KitCapability.cancel);
        expect(
          tester.widget<ApprovalBar>(find.byType(ApprovalBar)).enabled,
          capability == KitCapability.approve,
        );
        s.backend.commands.clear();
        switch (capability) {
          case KitCapability.send:
            await tester.enterText(find.byType(EditableText).last, 'then docs');
            await tester.pump();
            await tester.tap(find.text('Send'));
            await _settle(tester);
            expect(lastArgs(s.backend, 'followup')[1], 'then docs');
          case KitCapability.cancel:
            await tester.tap(find.text('Stop'));
            await _settle(tester);
            expect(lastArgs(s.backend, 'cancel')[0], quotaChatId);
          case KitCapability.approve:
            await tester.tap(find.text('Approve'));
            await _settle(tester);
            expect(lastArgs(s.backend, 'decideApproval')[1], 'ap1');
          default:
            fail('Unexpected capability: $capability');
        }
      });
    }

    testWidgets('explicit all enables actions without capabilities', (
      tester,
    ) async {
      final s = await playedBackend(
        tester,
        capabilities: KitCapabilities.none(),
      );
      await pumpApp(
        tester,
        _pane(s.backend, s.clock, paneActions: AgentPaneActions.all),
      );
      await tester.enterText(find.byType(EditableText).last, 'then docs');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'followup')[1], 'then docs');
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'decideApproval')[1], 'ap1');
      await tester.tap(find.text('Stop'));
      await _settle(tester);
      expect(lastArgs(s.backend, 'cancel')[0], quotaChatId);
    });

    testWidgets('an explicit mixed override takes precedence per action', (
      tester,
    ) async {
      final s = await playedBackend(
        tester,
        capabilities: KitCapabilities([
          KitCapability.cancel,
          KitCapability.approve,
        ]),
      );
      await pumpApp(
        tester,
        _pane(
          s.backend,
          s.clock,
          paneActions: const AgentPaneActions(
            send: true,
            stop: false,
            decide: false,
          ),
        ),
      );
      final composer = tester.widget<AgentComposer>(find.byType(AgentComposer));
      expect(composer.canSend, isTrue);
      expect(composer.onStop, isNull);
      expect(
        tester.widget<ApprovalBar>(find.byType(ApprovalBar)).enabled,
        isFalse,
      );
    });

    testWidgets('rebuilds resolve current capabilities and overrides', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      final backend = _SpyBackend(s.backend);
      Widget pane({AgentPaneActions? actions}) => AgentChatPane(
        key: const ValueKey('capability-pane'),
        backend: backend,
        chatId: quotaChatId,
        now: s.clock.now(),
        paneActions: actions,
      );
      void expectActions(bool enabled) {
        final composer = tester.widget<AgentComposer>(
          find.byType(AgentComposer),
        );
        expect(composer.canSend, enabled);
        expect(composer.onStop != null, enabled);
        expect(
          tester.widget<ApprovalBar>(find.byType(ApprovalBar)).enabled,
          enabled,
        );
      }

      await pumpApp(tester, pane());
      expectActions(true);
      backend.capabilityOverride = KitCapabilities.none();
      await pumpApp(tester, pane());
      expectActions(false);
      await pumpApp(tester, pane(actions: AgentPaneActions.all));
      expectActions(true);
      await pumpApp(tester, pane());
      expectActions(false);
      backend.capabilityOverride = null;
      await pumpApp(tester, pane());
      expectActions(true);
      // Capability/action updates reuse the existing feed.
      expect(backend.opened, [quotaChatId]);
      expect(backend.closed, isEmpty);
    });
  });

  group('errors', () {
    testWidgets('a failed command is one dismissible line', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      s.backend.failNext = const KitConflict('That was already decided.');
      await tester.tap(find.text('Approve'));
      await _settle(tester);
      expect(find.text('That was already decided.'), findsOneWidget);
      // The approval is still there to try again.
      expect(find.text('Approve'), findsOneWidget);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is KitIconButton && w.label == 'Dismiss',
        ),
      );
      await tester.pump();
      expect(find.text('That was already decided.'), findsNothing);
    });

    testWidgets('a failed send gives the text back', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock, chatId: 'idle'));
      await tester.enterText(find.byType(EditableText).last, 'hello');
      await tester.pump();
      s.backend.failNext = const KitBusy();
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(
        find.text('The chat is busy. Steer or queue instead.'),
        findsOneWidget,
      );
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('a chat that fails to load offers Retry', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock, chatId: 'missing'));
      expect(find.text('No such chat.'), findsOneWidget);
      s.backend.emit('missing', {'kind': 'chat.renamed', 'title': 'Found it'});
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.text('Found it'), findsOneWidget);
    });
  });

  group('read-only', () {
    Widget readOnly(ScriptedBackend backend, ManualClock clock) =>
        AgentChatPane(
          backend: backend,
          chatId: quotaChatId,
          now: clock.now(),
          paneActions: AgentPaneActions.readOnly,
        );

    testWidgets('shows the transcript and the pending approval', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, readOnly(s.backend, s.clock));
      expect(find.byType(TranscriptList), findsOneWidget);
      expect(find.text('Quota bar flickers on reconnect'), findsOneWidget);
      expect(find.text('Needs approval'), findsOneWidget);
      expect(find.byType(ApprovalBar), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('This chat is read-only.'), findsOneWidget);
    });

    testWidgets('send, stop and the decisions cannot be invoked', (
      tester,
    ) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, readOnly(s.backend, s.clock));
      s.backend.commands.clear(); // the pane's own reads on opening

      for (final label in ['Send', 'Stop', 'Approve', 'For session', 'Deny']) {
        await tester.tap(find.text(label));
        await _settle(tester);
      }
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
      ]) {
        await tester.sendKeyEvent(key);
        await _settle(tester);
      }
      expect(commandNames(s.backend), isEmpty);
      // Deny did not open the reason field; the bar is still the same one.
      expect(find.text('Reason for the agent (optional)'), findsNothing);
      expect(find.text('Needs approval'), findsOneWidget);
    });

    testWidgets('semantics call the controls disabled', (tester) async {
      final handle = tester.ensureSemantics();
      final s = await playedBackend(tester);
      await pumpApp(tester, readOnly(s.backend, s.clock));
      for (final label in ['Send', 'Stop', 'Approve', 'For session', 'Deny']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
          reason: label,
        );
      }
      handle.dispose();
    });

    testWidgets('a writable pane keeps those controls enabled', (tester) async {
      final handle = tester.ensureSemantics();
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock));
      for (final label in ['Stop', 'Approve', 'For session', 'Deny']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
          reason: label,
        );
      }
      handle.dispose();
    });
  });

  group('feeds', () {
    testWidgets('a chat switch closes the old feed', (tester) async {
      final s = await playedBackend(tester);
      final spy = _SpyBackend(s.backend);
      Widget pane(String id) => AgentChatPane(
        key: const ValueKey('pane'),
        backend: spy,
        chatId: id,
        now: s.clock.now(),
      );
      await pumpApp(tester, pane(quotaChatId));
      expect(spy.opened, [quotaChatId]);
      expect(spy.closed, isEmpty);
      expect(find.text('Quota bar flickers on reconnect'), findsOneWidget);

      await pumpApp(tester, pane('idle'));
      expect(spy.opened, [quotaChatId, 'idle']);
      expect(spy.closed, [quotaChatId]);
      expect(find.text('Idle chat'), findsOneWidget);
      expect(find.text('Quota bar flickers on reconnect'), findsNothing);

      await pumpApp(tester, const SizedBox());
      expect(spy.closed, [quotaChatId, 'idle']);
    });
  });
}

/// Counts the event streams opened and cancelled; forwards what the pane
/// needs.
class _SpyBackend implements AgentBackend {
  _SpyBackend(this.inner);

  final ScriptedBackend inner;
  final opened = <String>[];
  final closed = <String>[];
  KitCapabilities? capabilityOverride;

  @override
  KitCapabilities get capabilities => capabilityOverride ?? inner.capabilities;

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) =>
      inner.listChats(cursor: cursor, query: query);

  @override
  Future<ChatSnapshot> loadChat(String chatId) => inner.loadChat(chatId);

  @override
  Future<List<KitChoice>> listModels() => inner.listModels();

  @override
  Future<List<KitChoice>> listProfiles() => inner.listProfiles();

  @override
  Stream<KitEvent> events(String chatId, {required int after}) {
    late StreamController<KitEvent> controller;
    StreamSubscription<KitEvent>? sub;
    controller = StreamController<KitEvent>(
      onListen: () {
        opened.add(chatId);
        sub = inner
            .events(chatId, after: after)
            .listen(controller.add, onError: controller.addError);
      },
      onCancel: () {
        closed.add(chatId);
        return sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
