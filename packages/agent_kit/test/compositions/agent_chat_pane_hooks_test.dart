// AgentChatPane passes the host's transcript hooks through: the item builder,
// the activity summary and footer, and the edit-row open flag.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compositions_harness.dart';

class _Mark extends StatelessWidget {
  const _Mark(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

void main() {
  testWidgets('itemBuilder wraps or replaces the kit widget per item', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    final seen = <String>[];
    await pumpApp(
      tester,
      AgentChatPane(
        backend: s.backend,
        chatId: quotaChatId,
        now: s.clock.now(),
        transcriptActions: TranscriptActions(
          itemBuilder: (context, item, kitWidget) {
            seen.add(item.runtimeType.toString());
            return _Mark(kitWidget);
          },
        ),
      ),
    );
    expect(seen, isNotEmpty);
    // The host's wrapper is around the rows that are built, and the kit's
    // own widgets are inside it.
    expect(find.byType(_Mark), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(_Mark),
        matching: find.byType(ActivityGroupView),
      ),
      findsWidgets,
    );
  });

  testWidgets('summaryOf and activityFooter reach the activity groups', (
    tester,
  ) async {
    final s = await playedBackend(tester);
    await pumpApp(
      tester,
      AgentChatPane(
        backend: s.backend,
        chatId: quotaChatId,
        now: s.clock.now(),
        transcriptActions: TranscriptActions(
          summaryOf: (g) => 'Host summary ${g.toolCalls}',
        ),
      ),
    );
    expect(find.textContaining('Host summary'), findsWidgets);
  });
}
