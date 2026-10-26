// The Components scene: each widget in each state. A widget joins the kit
// with a specimen here (see docs/agent-kit.md).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

class ComponentsScene extends StatelessWidget {
  const ComponentsScene({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return ColoredBox(
      color: t.canvas,
      child: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.radii.sheet),
            border: Border.all(color: t.seam),
            boxShadow: t.colors.stack,
          ),
          child: SizedBox.expand(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(t.spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Heading('StatusMark'),
                  const _StatusSpecimens(),
                  SizedBox(height: t.spacing.xl),
                  const _Heading('Not built yet'),
                  for (final line in _planned)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.spacing.xs),
                      child: Text(
                        line,
                        style: ts(t.type.ui, t.muted, weight: 400),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _planned = [
  'transcript: items, activity and evidence rows, edits, diff, plan',
  'composer: composer, approval bar, queue row, picks',
  'chrome: rail, header, crew strip, ledger',
  'workspace: split tree, panes, docking, edge tabs',
  'compositions: AgentWorkbench, AgentChatPane',
];

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.md),
      child: Text(text, style: ts(t.type.h3, t.ink)),
    );
  }
}

/// Every status in the dot form, the dot form with a detail and the pill.
class _StatusSpecimens extends StatelessWidget {
  const _StatusSpecimens();

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in ChatStatus.values)
          Padding(
            padding: EdgeInsets.only(bottom: t.spacing.md),
            child: Wrap(
              spacing: t.spacing.lg,
              runSpacing: t.spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    s.name,
                    style: ts(const TypeSpec(12, 16, 400), t.faint, mono: true),
                  ),
                ),
                SizedBox(width: 170, child: StatusMark(s)),
                SizedBox(
                  width: 190,
                  child: StatusMark(s, detail: '3 agents'),
                ),
                StatusMark.pill(s),
              ],
            ),
          ),
      ],
    );
  }
}
