// The child question row and the asking-parent status: the states, "Answer
// yourself" only with the capability, sending reaches the backend, and an
// asking child never makes the chat "need you".

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../compositions/compositions_harness.dart';
import '../harness.dart';

final _asked = DateTime.utc(2025, 12, 29, 10);
final _now = _asked.add(const Duration(seconds: 40));

ChildQuestionItem _item({
  ChildQuestionState state = ChildQuestionState.pending,
  String? answer,
  AnsweredBy? by,
}) => ChildQuestionItem(
  id: 'childq:cq2',
  task: 'Trace socket reconnect in the web client',
  question: ChildQuestion(
    id: 'cq2',
    childId: 'c7e4',
    text: 'Is the reconnect handled in web/src/ws.ts?',
    options: const ['ws.ts', 'Shared client'],
    askedAt: _asked,
    state: state,
    answer: answer,
    answeredAt: answer == null ? null : _asked.add(const Duration(seconds: 9)),
    answeredBy: by,
  ),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Scrolls the transcript until [finder] is built.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
}

Widget _pane(ScriptedBackend backend, ManualClock clock) => AgentChatPane(
  backend: backend,
  chatId: quotaChatId,
  now: clock.now(),
  onReviewApproval: (_) {},
);

void main() {
  group('ChildQuestionRow', () {
    testWidgets('pending: waits, offers Open child and Answer yourself', (
      tester,
    ) async {
      String? opened;
      await pumpKit(
        tester,
        ChildQuestionRow(
          _item(),
          now: _now,
          onOpenChild: (id) => opened = id,
          onAnswer: (_, _, _) {},
        ),
        size: const Size(700, 400),
      );
      expect(find.textContaining('Waiting for the agent'), findsOneWidget);
      expect(find.text('Open child'), findsOneWidget);
      expect(find.text('Answer yourself'), findsOneWidget);
      expect(find.textContaining('needs you'), findsNothing);
      expect(find.textContaining('not running'), findsNothing);

      await tester.tap(find.text('Open child'));
      expect(opened, 'c7e4');
    });

    testWidgets('Answer yourself is hidden without an answer handler', (
      tester,
    ) async {
      await pumpKit(
        tester,
        ChildQuestionRow(_item(), now: _now, onOpenChild: (_) {}),
        size: const Size(700, 400),
      );
      expect(find.text('Answer yourself'), findsNothing);
      expect(find.text('Open child'), findsOneWidget);
    });

    testWidgets('composing sends (child, question, text)', (tester) async {
      (String, String, String)? sent;
      await pumpApp(
        tester,
        ChildQuestionRow(
          _item(),
          now: _now,
          onAnswer: (c, q, t) => sent = (c, q, t),
        ),
        width: 700,
        height: 500,
      );
      await tester.tap(find.text('Answer yourself'));
      await _settle(tester);
      expect(find.text('Send answer'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Shared client');
      await _settle(tester);
      await tester.tap(find.text('Send answer'));
      await _settle(tester);
      expect(sent, ('c7e4', 'cq2', 'Shared client'));
    });

    testWidgets('answered by the agent and by you, and cancelled', (
      tester,
    ) async {
      await pumpKit(
        tester,
        Column(
          children: [
            ChildQuestionRow(
              _item(
                state: ChildQuestionState.answered,
                answer: 'Shared client.',
                by: AnsweredBy.parent,
              ),
              now: _now,
            ),
            ChildQuestionRow(
              _item(
                state: ChildQuestionState.answered,
                answer: 'Use net.ts.',
                by: AnsweredBy.user,
              ),
              now: _now,
            ),
            ChildQuestionRow(
              _item(state: ChildQuestionState.cancelled),
              now: _now,
            ),
          ],
        ),
        size: const Size(700, 700),
      );
      expect(find.text('Shared client.'), findsOneWidget);
      expect(find.text('Use net.ts.'), findsOneWidget);
      expect(find.text('Answer yourself'), findsNothing);
    });
  });

  group('asking parent', () {
    testWidgets('the strip shows it, and it never reads as needs you', (
      tester,
    ) async {
      final agent = ChildAgent(
        id: 'c7e4',
        task: 'Trace socket reconnect in the web client',
        state: WorkState.waitingForAnswer,
        startedAt: _asked,
        pendingQuestion: ChildQuestion(
          id: 'cq2',
          childId: 'c7e4',
          text: 'Is the reconnect handled in ws.ts?',
          askedAt: _asked,
        ),
      );
      await pumpKit(
        tester,
        CrewStrip(agents: [agent], now: _now),
        size: const Size(700, 200),
      );
      expect(
        find.textContaining('asking parent', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('needs you'), findsNothing);
      expect(find.textContaining('Needs you'), findsNothing);
    });

    test('a chat whose only open item is a child question is not needsYou', () {
      final snap = ChatSnapshot(
        chatId: 'x',
        children: [
          ChildAgent(
            id: 'c1',
            task: 'Look',
            state: WorkState.waitingForAnswer,
            startedAt: _asked,
          ),
        ],
      );
      expect(deriveStatus(snap), isNot(ChatStatus.needsYou));
    });
  });

  group('AgentChatPane', () {
    testWidgets('Answer yourself reaches the backend', (tester) async {
      final s = await playedBackend(tester);
      await pumpApp(tester, _pane(s.backend, s.clock), height: 2400);
      await tester.pump();
      await _reveal(tester, find.textContaining('Waiting for the agent'));
      await tester.tap(find.text('Answer yourself'));
      await _settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(ChildQuestionRow).last,
          matching: find.byType(EditableText),
        ),
        'Shared client',
      );
      await _settle(tester);
      await tester.tap(find.text('Send answer'));
      await _settle(tester);
      final a = lastArgs(s.backend, 'answerChildQuestion');
      expect(a, [quotaChatId, 'c7e4', 'cq2', 'Shared client']);
    });

    testWidgets('without the capability there is no Answer yourself', (
      tester,
    ) async {
      final caps = KitCapabilities(
        KitCapability.values.where(
          (c) => c != KitCapability.answerChildQuestion,
        ),
      );
      final s = await playedBackend(tester, capabilities: caps);
      await pumpApp(tester, _pane(s.backend, s.clock), height: 2400);
      await tester.pump();
      await _reveal(tester, find.textContaining('Waiting for the agent'));
      expect(find.textContaining('Waiting for the agent'), findsOneWidget);
      expect(find.text('Answer yourself'), findsNothing);
    });
  });
}
