// The plan checklist (`.plan` in the mockup): one line, "Plan 2/5", that
// opens into the steps. Done steps are checked and muted, the current step is
// bold with the running mark, the rest hold a hollow ring.

import 'package:agent_kit_core/agent_kit_core.dart'
    show ChatStatus, PlanItem, PlanItemState;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'markdown.dart';
import 'transcript_support.dart';

class PlanChecklist extends StatefulWidget {
  const PlanChecklist(this.items, {super.key, this.initiallyOpen = false});

  final List<PlanItem> items;
  final bool initiallyOpen;

  @override
  State<PlanChecklist> createState() => _PlanChecklistState();
}

class _PlanChecklistState extends State<PlanChecklist> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final done = items.where((i) => i.state == PlanItemState.done).length;
    final count = '$done/${items.length}';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: t.radii.field,
        border: Border.all(color: t.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: 'Plan, $done of ${items.length} done',
            excludeSemantics: true,
            child: Hover(
              onTap: () => setState(() => _open = !_open),
              lift: 0,
              borderRadius: t.radii.field,
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: isTouch(context) ? 40 : 34,
                ),
                child: Row(
                  children: [
                    glyphIcon(
                      glyphListChecks,
                      size: 14,
                      color: t.colors.iconSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text('Plan', style: ts(t.typeScale.ui, t.ink, weight: 700)),
                    const SizedBox(width: 8),
                    Text(
                      count,
                      style: ts(t.typeScale.ui, t.faint, weight: 400),
                    ),
                    const Spacer(),
                    DisclosureChevron(open: _open),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final item in items) _PlanRow(item: item)],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.item});

  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final style = switch (item.state) {
      PlanItemState.done => ts(t.typeScale.ui, t.muted, weight: 400),
      PlanItemState.now => ts(t.typeScale.ui, t.ink, weight: 700),
      PlanItemState.todo => ts(t.typeScale.ui, t.ink, weight: 400),
    };
    final mark = switch (item.state) {
      PlanItemState.done => glyphIcon(
        glyphCheck,
        size: 14,
        color: t.constructiveInk,
      ),
      PlanItemState.now => const StatusMark(ChatStatus.running, label: ''),
      PlanItemState.todo => const StatusMark(ChatStatus.idle, label: ''),
    };
    final stateLabel = switch (item.state) {
      PlanItemState.done => 'done',
      PlanItemState.now => 'in progress',
      PlanItemState.todo => 'to do',
    };
    return Semantics(
      container: true,
      label: '${item.text}, $stateLabel',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 26),
        child: Row(
          children: [
            SizedBox(width: 16, child: Center(child: mark)),
            const SizedBox(width: 8),
            Expanded(child: MarkdownText(item.text, style: style)),
          ],
        ),
      ),
    );
  }
}
