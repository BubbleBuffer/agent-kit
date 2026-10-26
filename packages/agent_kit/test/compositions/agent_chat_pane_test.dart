// AgentChatPane: every command reaches the backend, capabilities hide
// controls, a failed command is one inline line, and a chat switch closes the
// old feed.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit/src/composer/composer_parts.dart' show KitIconButton;
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compositions_harness.dart';

Widget _pane(
  ScriptedBackend backend,
  ManualClock clock, {
  String chatId = quotaChatId,
}) => AgentChatPane(
  backend: backend,
  chatId: chatId,
  now: clock.now(),
  onReviewApproval: (_) {},
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
      // The approval and the composer still work.
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
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

  @override
  KitCapabilities get capabilities => inner.capabilities;

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
