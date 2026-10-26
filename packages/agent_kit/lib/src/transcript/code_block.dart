// A fenced code block: `pre.code` in the mockup. Plain mono text on the
// surface-2 well, scrolling sideways; no syntax colours (a host that wants
// them supplies its own MarkdownRenderer).

import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'transcript_support.dart';

class CodeBlock extends StatelessWidget {
  const CodeBlock(this.code, {super.key, this.language});

  /// The code, without the fences.
  final String code;

  /// The info string after the opening fence, if any.
  final String? language;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final lang = language;
    return Semantics(
      container: true,
      label: lang == null || lang.isEmpty ? 'Code' : 'Code, $lang',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(t.radii.sm),
        ),
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              code,
              softWrap: false,
              style: monoStyle(t.typeScale.code, t.ink),
            ),
          ),
        ),
      ),
    );
  }
}
