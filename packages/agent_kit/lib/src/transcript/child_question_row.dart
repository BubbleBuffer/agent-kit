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

const _glyphBot = (LucideIcons.bot300, LucideIcons.bot, LucideIcons.bot500);
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
  final void Function(String childId, String questionId, String text)? onAnswer;

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

    final Widget status;
    if (pending) {
      status = StatusMark.askingParent(label: 'Asking parent · ${_wait()}');
    } else if (answered) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyphIcon(glyphCheck, size: IconSize.xs.px, color: t.muted),
          const Gap(Space.xxs),
          Text(
            'Answered',
            style: ts(t.typeScale.uiSmall, t.muted, weight: Weight.strong),
          ),
        ],
      );
    } else {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyphIcon(glyphCircleX, size: IconSize.xs.px, color: t.muted),
          const Gap(Space.xxs),
          Text(
            'Cancelled',
            style: ts(t.typeScale.uiSmall, t.muted, weight: Weight.strong),
          ),
        ],
      );
    }

    final note = ts(t.typeScale.uiSmall, t.faint, weight: Weight.regular);
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
        padding: const EdgeInsets.only(left: Space.xs),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.seam, width: Stroke.bold),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.hair,
              0,
              Space.hair,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          glyphIcon(
                            _glyphBot,
                            size: IconSize.xs.px,
                            color: t.colors.iconSecondary,
                          ),
                          const Gap(Space.sm),
                          Flexible(
                            child: Text(
                              task,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts(
                                t.typeScale.ui,
                                t.ink,
                                weight: Weight.strong,
                              ),
                            ),
                          ),
                          if (!compact) ...[
                            const Gap(Space.sm),
                            Text(
                              'asked the agent',
                              maxLines: 1,
                              style: ts(
                                t.typeScale.ui,
                                t.faint,
                                weight: Weight.regular,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Gap(Space.sm),
                    status,
                  ],
                ),
                const Gap(Space.xxs),
                Text(q.text, style: ts(t.typeScale.body, t.ink)),
                if (q.options.isNotEmpty) ...[
                  const Gap(Space.xxs),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final o in q.options)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: t.radii.pill,
                            border: Border.all(color: t.seam),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: Space.hair,
                            ),
                            child: Text(
                              o,
                              style: ts(
                                t.typeScale.uiSmall,
                                t.muted,
                                weight: Weight.regular,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (answered && q.answer != null) ...[
                  const Gap(Space.xs),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: t.radii.field,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xxs),
                            child: glyphIcon(
                              _glyphReply,
                              size: IconSize.xs.px,
                              color: t.colors.iconSecondary,
                            ),
                          ),
                          const Gap(Space.sm),
                          Padding(
                            padding: const EdgeInsets.only(top: Space.hair),
                            child: Text(
                              q.answeredBy == AnsweredBy.user ? 'You' : 'Agent',
                              style: ts(
                                t.typeScale.uiSmall,
                                t.muted,
                                weight: Weight.strong,
                              ),
                            ),
                          ),
                          const Gap(Space.sm),
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
                  const Gap(Space.hair),
                  Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: Text('The child was cancelled', style: note),
                  ),
                ],
                if (pending) ...[
                  const Gap(Space.hair),
                  if (compact) ...[
                    Text('Waiting for the agent to answer', style: note),
                    if (actions.isNotEmpty)
                      Transform.translate(
                        offset: const Offset(-Space.sm, 0),
                        child: Wrap(children: actions),
                      ),
                  ] else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: ControlSize.sm.height,
                      ),
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
                    const Gap(Space.xs),
                    _AnswerField(
                      controller: _text,
                      focusNode: _focus,
                      hint: 'Your answer',
                    ),
                    const Gap(Space.xs),
                    // The note beside the buttons, or above them when
                    // compact.
                    Flex(
                      direction: compact ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: compact
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.center,
                      spacing: compact ? Space.xs : Space.sm,
                      children: [
                        if (compact)
                          SizedBox(
                            width: double.infinity,
                            child: Text(_answerNote, style: note),
                          )
                        else
                          Expanded(child: Text(_answerNote, style: note)),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: Space.xs,
                          runSpacing: Space.xxs,
                          children: [
                            KitButton(
                              label: 'Cancel',
                              kind: KitButtonKind.quiet,
                              onTap: _toggle,
                            ),
                            KitButton(
                              label: 'Send answer',
                              kind: KitButtonKind.primary,
                              onTap: _text.text.trim().isEmpty ? null : _send,
                            ),
                          ],
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
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
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

/// The note under the answer field.
const _answerNote =
    'Goes to the child as the answer. The agent is told you answered.';
