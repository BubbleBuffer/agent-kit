// Lines that close a stretch of work: a child agent's return line
// (`.return-line` in the mockup) and the interrupted notice with Resume.

import 'package:agent_kit_core/agent_kit_core.dart'
    show ChatStatus, ChildResult, WorkState;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'transcript_support.dart';

/// "Map UsageState transitions returned", with the result's state as a pill
/// and an Open action for the child's chat.
class ReturnLine extends StatelessWidget {
  const ReturnLine(this.result, {super.key, this.onOpen});

  final ChildResult result;

  /// "Open": show the child's chat. Gets the child's id.
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final verb = switch (result.state) {
      WorkState.running => 'is running',
      WorkState.done => 'returned',
      WorkState.failed => 'failed',
      WorkState.cancelled => 'was cancelled',
      WorkState.waitingForAnswer => 'is waiting for an answer',
      WorkState.idle => 'is idle',
      WorkState.timedOut => 'timed out',
    };
    final pill = switch (result.state) {
      WorkState.running => StatusMark.pill(ChatStatus.running),
      WorkState.done => StatusMark.pill(ChatStatus.done, label: 'Result ready'),
      WorkState.failed => StatusMark.pill(ChatStatus.failed),
      WorkState.cancelled => StatusMark.pill(
        ChatStatus.idle,
        label: 'Cancelled',
      ),
      WorkState.waitingForAnswer || WorkState.idle => StatusMark.pill(
        ChatStatus.idle,
      ),
      WorkState.timedOut => StatusMark.pill(
        ChatStatus.failed,
        label: 'Timed out',
      ),
    };
    final compact = sizeClassOf(context).isCompact;
    final style = ts(const TypeSpec(13, 16, 500), t.muted);
    final line = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: result.task,
            style: style.copyWith(color: t.ink, fontWeight: fw(700)),
          ),
          TextSpan(text: ' $verb'),
        ],
        style: style,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final open = onOpen;
    return Semantics(
      container: true,
      label: '${result.task} $verb',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: t.colors.borderSubtle),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              glyphIcon(glyphEye, size: 14, color: t.colors.iconSecondary),
              const SizedBox(width: 8),
              Expanded(child: line),
              if (!compact) ...[const SizedBox(width: 8), pill],
              if (open != null)
                KitTextButton(
                  'Open',
                  color: t.ink,
                  onTap: () => open(result.childId),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The run was interrupted (a host restart): the interrupted mark, the text,
/// and Resume.
class InterruptedNotice extends StatelessWidget {
  const InterruptedNotice({
    super.key,
    this.text = 'Interrupted by a restart',
    this.onResume,
  });

  final String text;

  /// "Resume": continue from where the run stopped.
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      container: true,
      label: text,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: t.colors.borderSubtle),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusMark(ChatStatus.interrupted, label: text),
                ),
              ),
              if (onResume != null)
                KitTextButton(
                  'Resume',
                  glyph: glyphRefresh,
                  color: t.ink,
                  onTap: onResume,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
