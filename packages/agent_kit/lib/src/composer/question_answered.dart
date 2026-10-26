// QuestionAnswerLines: an answered request as it reads in the transcript, one
// line per question (mockup `.ask-done`): a speech-bubble icon, the question
// in muted text, then the answer in bold, or "Skipped" in italics.
//
// The transcript folder has no row for questions yet (the feed's items hold
// none), so this lives with the prompt. A host places it where the resolved
// request belongs; the transcript owner can move it.

import 'package:agent_kit_core/agent_kit_core.dart'
    show Question, QuestionAnswer, QuestionItem, QuestionState;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'composer_parts.dart';

/// What to show for [answer] to [item]: the chosen labels and the typed text,
/// joined with commas. Null for a skipped item or when there is no answer.
String? answerSummary(QuestionItem item, QuestionAnswer? answer) {
  if (answer == null || answer.skipped) return null;
  final parts = [
    ...answer.choices,
    if (answer.text != null && answer.text!.trim().isNotEmpty)
      answer.text!.trim(),
  ];
  return parts.isEmpty ? 'None' : parts.join(', ');
}

/// One line per question of a resolved [question].
class QuestionAnswerLines extends StatelessWidget {
  /// Creates the lines.
  const QuestionAnswerLines({super.key, required this.question});

  /// The resolved request. Items with no answer show "Skipped", or "No
  /// answer" when the request expired or was cancelled.
  final Question question;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Answered questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in question.items)
            _Line(
              item: item,
              answer: question.answers?[item.id],
              unanswered: question.state != QuestionState.answered,
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.answer,
    required this.unanswered,
  });

  final QuestionItem item;
  final QuestionAnswer? answer;
  final bool unanswered;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final summary = answerSummary(item, answer);
    final style = ts(
      t.typeScale.uiSmall,
      t.muted,
    ).copyWith(fontSize: isTouch(t) ? 14 : 13);
    final TextSpan result;
    if (summary != null) {
      result = TextSpan(
        text: summary,
        style: style.copyWith(color: t.ink, fontWeight: FontWeight.w600),
      );
    } else {
      result = TextSpan(
        text: unanswered ? 'No answer' : 'Skipped',
        style: style.copyWith(
          color: t.faint,
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Semantics(
      container: true,
      label:
          '${item.text} ${summary ?? (unanswered ? 'No answer' : 'Skipped')}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.colors.borderSubtle)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              const KitIcon(ComposerGlyphs.messageSquare, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${item.text} '),
                      result,
                    ],
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
