// QuestionPrompt: the agent asks the user a question, with suggested answers
// and, when the question allows it, a typed answer. It is the approval bar's
// sibling: the same surface, the same pill and age line, but the mockup has no
// question prompt, so this one is deliberately minimal (a departure, listed
// in the report): the pill reads "Question", the text is plain, each option is
// a button and the free-text answer is one field with an Answer button.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus, Question;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'composer_parts.dart';

/// A pending [question] with its answers.
class QuestionPrompt extends StatefulWidget {
  /// Creates the prompt.
  const QuestionPrompt({
    super.key,
    required this.question,
    required this.onAnswer,
    this.now,
  });

  /// The question, its options and whether a typed answer is allowed.
  final Question question;

  /// The answer, for `answerQuestion`: an option's text or the typed text.
  final ValueChanged<String> onAnswer;

  /// Replaces the wall clock for "waiting 12m" (tests, the gallery).
  final DateTime? now;

  @override
  State<QuestionPrompt> createState() => _QuestionPromptState();
}

class _QuestionPromptState extends State<QuestionPrompt> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'question answer');

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitText() {
    final answer = _text.text.trim();
    if (answer.isEmpty) return;
    widget.onAnswer(answer);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final q = widget.question;
    final touch = isTouch(t);
    final h = controlHeight(t);
    return Semantics(
      container: true,
      label: 'Question from the agent',
      child: SizeClassBuilder(
        builder: (context, size) => BarSurface(
          padding: EdgeInsets.fromLTRB(
            touch ? 10 : 12,
            touch ? 10 : 8,
            touch ? 10 : 8,
            touch ? 10 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const StatusMark.pill(ChatStatus.needsYou, label: 'Question'),
                  const SizedBox(width: 8),
                  WaitingLabel(requestedAt: q.requestedAt, now: widget.now),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                q.text,
                style: ts(
                  touch ? t.typeScale.body : t.typeScale.ui,
                  t.ink,
                  weight: 500,
                ),
              ),
              if (q.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (size.isCompact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < q.options.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        KitButton(
                          label: q.options[i],
                          onTap: () => widget.onAnswer(q.options[i]),
                        ),
                      ],
                    ],
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in q.options)
                        KitButton(
                          label: option,
                          onTap: () => widget.onAnswer(option),
                        ),
                    ],
                  ),
              ],
              if (q.freeText) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FieldFrame(
                        height: h,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Semantics(
                          label: 'Your answer',
                          textField: true,
                          child: PlainField(
                            controller: _text,
                            focusNode: _focus,
                            style: ts(
                              touch ? t.typeScale.body : t.typeScale.ui,
                              t.ink,
                              weight: 400,
                            ),
                            placeholder: q.options.isEmpty
                                ? 'Type an answer'
                                : 'Or type an answer',
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submitText(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    KitButton(
                      label: 'Answer',
                      kind: KitButtonKind.primary,
                      onTap: _text.text.trim().isEmpty ? null : _submitText,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
