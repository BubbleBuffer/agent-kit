import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show QueuedInput;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

void main() {
  testWidgets('shows the label and text at 640, hides the label at 390', (
    tester,
  ) async {
    await pumpComposer(tester, QueuedRow(input: fixtureQueued));
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text(fixtureQueued.text), findsOneWidget);
    expect(find.text('Send now'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await pumpComposer(tester, QueuedRow(input: fixtureQueued), width: 390);
    expect(find.text('Queued'), findsNothing);
    expect(find.text('Send now'), findsOneWidget);
  });

  testWidgets('long text truncates and the buttons stay', (tester) async {
    final long = QueuedInput(
      id: 'q9',
      text: List.filled(40, 'a long queued message').join(' '),
      queuedAt: fixtureNow,
    );
    await pumpComposer(tester, QueuedRow(input: long), width: 390);
    expect(tester.takeException(), isNull);
    expect(find.text('Send now'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Send now and remove call back', (tester) async {
    final sent = <String>[];
    final removed = <String>[];
    final handle = tester.ensureSemantics();
    await pumpComposer(
      tester,
      QueuedRow(
        input: fixtureQueued,
        onSendNow: (q) => sent.add(q.id),
        onRemove: (q) => removed.add(q.id),
      ),
    );
    await tester.tap(find.text('Send now'));
    await tester.tap(find.bySemanticsLabel('Remove'));
    await tester.pump();
    expect(sent, ['q1']);
    expect(removed, ['q1']);
    handle.dispose();
  });

  testWidgets('Edit turns the row into a field; Save reports the new text', (
    tester,
  ) async {
    final edits = <String>[];
    await pumpComposer(
      tester,
      QueuedRow(input: fixtureQueued, onEdit: (q, text) => edits.add(text)),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Different text');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(edits, ['Different text']);
    expect(find.byType(EditableText), findsNothing);
  });

  testWidgets('Enter saves', (tester) async {
    final edits = <String>[];
    await pumpComposer(
      tester,
      QueuedRow(
        input: fixtureQueued,
        initiallyEditing: true,
        onEdit: (q, text) => edits.add(text),
      ),
    );
    await tester.enterText(find.byType(EditableText), 'Edited');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(edits, ['Edited']);
  });

  testWidgets('Esc cancels without reporting', (tester) async {
    final edits = <String>[];
    await pumpComposer(
      tester,
      QueuedRow(
        input: fixtureQueued,
        initiallyEditing: true,
        onEdit: (q, text) => edits.add(text),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'Dropped');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(edits, isEmpty);
    expect(find.byType(EditableText), findsNothing);
  });
}
