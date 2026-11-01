// The composer's semantics: one text-field node, with its label, a hint from
// the placeholder and the tap and focus actions while unfocused.

import 'dart:ui' show Tristate;

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'composer_harness.dart';

List<SemanticsNode> _textFields(WidgetTester tester) {
  final found = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isTextField) found.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  var root = tester.getSemantics(find.byType(EditableText));
  while (root.parent != null) {
    root = root.parent!;
  }
  visit(root);
  return found;
}

void main() {
  testWidgets('one text field, with tap and focus while unfocused', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpComposer(
      tester,
      AgentComposer(onSubmit: (_) => true, placeholder: 'Ask the agent…'),
    );
    final fields = _textFields(tester);
    expect(fields, hasLength(1));
    final data = fields.single.getSemanticsData();
    expect(data.label, 'Message to the agent');
    expect(data.hint, 'Ask the agent…');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.focus), isTrue);
    expect(data.flagsCollection.isFocused, isNot(Tristate.isTrue));

    fields.single.owner!.performAction(fields.single.id, SemanticsAction.focus);
    await tester.pump();
    expect(_textFields(tester), hasLength(1));
    expect(
      _textFields(tester).single.getSemanticsData().flagsCollection.isFocused,
      Tristate.isTrue,
    );
    handle.dispose();
  });
}
