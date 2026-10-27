// ChildQuestionRow: a question a child agent asked its parent (`.cq` in the
// mockup, scene A). It is a quiet inline row, not a card, and not for the
// user: the parent agent answers it. There is no "needs you" treatment here.
//
//   head      the child's task (bold), "asked the agent" (faint) and the
//             status: "Asking parent · 40s", "Answered" or "Cancelled"
//   question  in body type, then the child's suggested options as outline
//             chips (suggestions, not buttons)
//   answered  the reply on a `surface-2` strip, "Agent" or "You"
//   pending   "Waiting for the agent to answer", Open child and, when the
//             backend can take it, Answer yourself
//
// "Answer yourself" opens a small field under the row; Send answer calls
// [ChildQuestionRow.onAnswer]. Without the callback (the backend lacks the
// capability) the button is not drawn. There is no state for a parent that
// is not running.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../composer/composer_parts.dart' show KitButton, KitButtonKind;
import '../status/status.dart';
import '../theme/theme.dart';
import 'transcript_support.dart';

const _glyphBot = (
  LucideIcons.bot300,
  LucideIcons.bot,
  LucideIcons.bot500,
);
const _glyphArrowRight = (
  LucideIcons.arrowRight300,
  LucideIcons.arrowRight,
  LucideIcons.arrowRight500,
);
const _glyphReply = (
  LucideIcons.reply300,
  LucideIcons.reply,
  LucideIcons.reply500,
);

/// The row for [item].
class ChildQuestionRow extends StatefulWidget {
  const ChildQuestionRow(
    this.item, {
    super.key,
    this.now,
    this.onOpenChild,
    this.onAnswer,
    this.initialComposing = false,
  });

  final ChildQuestionItem item;

  /// Replaces the wall clock for the wait time (tests, the gallery).
  final DateTime? now;

  /// Open the child's chat. Gets the child's id.
  final ValueChanged<String>? onOpenChild;

  /// Send the user's answer: `(childId, questionId, text)`. Null leaves
  /// "Answer yourself" out.
  final void Function(String childId, String questionId, String text)?
  onAnswer;

  /// Starts with the answer field open.
  final bool initialComposing;

  @override
  State<ChildQuestionRow> createState() => _ChildQuestionRowState();
}

class _ChildQuestionRowState extends State<ChildQuestionRow> {
  late bool _composing = widget.initialComposing;
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;

  ChildQuestion get _q => widget.item.question;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (widget.now == null && _q.isPending) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _composing = !_composing);
    if (_composing) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.onAnswer?.call(_q.childId, _q.id, text);
    setState(() => _composing = false);
  }

  String _wait() {
    final now = widget.now ?? DateTime.now();
    final d = now.difference(_q.askedAt);
    final s = d.isNegative ? 0 : d.inSeconds;
    if (s < 60) return '${s < 1 ? 1 : s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final q = _q;
    final compact = sizeClassOf(context).isCompact;
    final task = widget.item.task.isEmpty ? 'A child agent' : widget.item.task;
    final pending = q.isPending;
    final answered = q.state == ChildQuestionState.answered;
    final cancelled = q.state == ChildQuestionState.cancelled;
    final small = ts(t.typeScale.uiSmall, t.muted, weight: 500);

    final Widget status;
    if (pending) {
      status = StatusMark.askingParent(label: 'Asking parent · ${_wait()}');
    } else if (answered) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyphIcon(glyphCheck, size: 14, color: t.muted),
          const SizedBox(width: 4),
          Text('Answered', style: small.copyWith(fontWeight: fw(600))),
        ],
      );
    } else {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyphIcon(glyphCircleX, size: 14, color: t.muted),
          const SizedBox(width: 4),
          Text('Cancelled', style: small.copyWith(fontWeight: fw(600))),
        ],
      );
    }

    final note = ts(t.typeScale.uiSmall, t.faint, weight: 400);
    final canAnswer = widget.onAnswer != null;
    final actions = <Widget>[
      if (widget.onOpenChild != null)
        KitTextButton(
          'Open child',
          glyph: _glyphArrowRight,
          onTap: () => widget.onOpenChild!(q.childId),
        ),
      if (canAnswer)
        _Expandable(
          expanded: _composing,
          child: KitTextButton('Answer yourself', onTap: _toggle),
        ),
    ];

    return Semantics(
      container: true,
      label: 'Question from $task to the agent',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.seam, width: 2)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    glyphIcon(
                      _glyphBot,
                      size: 14,
                      color: t.colors.iconSecondary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        task,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(
                          const TypeSpec(13, 18, 500),
                          t.ink,
                          weight: 700,
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Text(
                        'asked the agent',
                        maxLines: 1,
                        style: ts(
                          const TypeSpec(13, 18, 500),
                          t.faint,
                          weight: 400,
                        ),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(width: 8),
                    status,
                  ],
                ),
                const SizedBox(height: 4),
                Text(q.text, style: ts(t.typeScale.body, t.ink)),
                if (q.options.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final o in q.options)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: t.radii.pill,
                            border: Border.all(color: t.seam),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 1,
                            ),
                            child: Text(o, style: small.copyWith(fontWeight: fw(400))),
                          ),
                        ),
                    ],
                  ),
                ],
                if (answered && q.answer != null) ...[
                  const SizedBox(height: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: t.radii.field,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: glyphIcon(
                              _glyphReply,
                              size: 14,
                              color: t.colors.iconSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              q.answeredBy == AnsweredBy.user ? 'You' : 'Agent',
                              style: ts(
                                t.typeScale.uiSmall,
                                t.muted,
                                weight: 700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              q.answer!,
                              style: ts(t.typeScale.body, t.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (cancelled) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: Text('The child was cancelled', style: note),
                  ),
                ],
                if (pending) ...[
                  const SizedBox(height: 2),
                  if (compact) ...[
                    Text('Waiting for the agent to answer', style: note),
                    if (actions.isNotEmpty)
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: Wrap(children: actions),
                      ),
                  ] else
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 28),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Waiting for the agent to answer',
                              style: note,
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                    ),
                  if (_composing && canAnswer) ...[
                    const SizedBox(height: 6),
                    _AnswerField(
                      controller: _text,
                      focusNode: _focus,
                      hint: 'Answer ${task.split(' ').first} yourself…',
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Goes to the child as the answer. The agent is '
                            'told you answered.',
                            style: note,
                          ),
                        ),
                        const SizedBox(width: 8),
                        KitButton(
                          label: 'Cancel',
                          kind: KitButtonKind.quiet,
                          onTap: _toggle,
                        ),
                        const SizedBox(width: 6),
                        KitButton(
                          label: 'Send answer',
                          kind: KitButtonKind.primary,
                          onTap: _text.text.trim().isEmpty ? null : _send,
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks a button as one that expands something (`aria-expanded`).
class _Expandable extends StatelessWidget {
  const _Expandable({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(expanded: expanded, child: child);
}

class _AnswerField extends StatelessWidget {
  const _AnswerField({
    required this.controller,
    required this.focusNode,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final style = ts(t.typeScale.body, t.ink);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: t.radii.field,
        border: Border.all(color: t.seam),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Semantics(
          label: 'Your answer to the child',
          textField: true,
          multiline: true,
          child: Stack(
            children: [
              if (controller.text.isEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: style.copyWith(color: t.faint),
                    ),
                  ),
                ),
              EditableText(
                controller: controller,
                focusNode: focusNode,
                style: style,
                cursorColor: t.ink,
                backgroundCursorColor: t.faint,
                selectionColor: t.colors.textSelection,
                selectionControls: noteSelectionControls,
                cursorWidth: 1.5,
                minLines: 2,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
