// A decision: a ◆ mark and the sentence that was decided.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// The decision line. [peek] keeps it to one clipped line (a folded face);
/// [boxed] sets it on a quiet panel. The caller spaces it.
class DecisionLine extends StatelessWidget {
  const DecisionLine(
    this.text, {
    super.key,
    this.peek = false,
    this.boxed = false,
    this.color,
  });
  final String text;
  final bool peek;
  final bool boxed;

  /// The text colour; primary when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final c = t.colors;
    final ty = t.typeScale;
    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('◆ ', style: ts(ty.uiSmall, c.accent)),
        Expanded(
          child: Text(
            text,
            maxLines: peek ? 1 : null,
            overflow: peek ? TextOverflow.ellipsis : TextOverflow.clip,
            style: ts(ty.uiSmall, color ?? c.textPrimary),
          ),
        ),
      ],
    );
    if (!boxed) return line;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: c.bgSecondary,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: line,
    );
  }
}
