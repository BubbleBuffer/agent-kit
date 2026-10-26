// The diff view: line numbers, added and removed lines on tinted rows, as in
// the Scene D file preview (`.fl` rows in the mockup). Added lines sit on the
// constructive tint, removed lines on the danger tint with the text struck
// through, context on the surface-2 well. Numbers are the new file's; a
// removed line has none.

import 'package:agent_kit_core/agent_kit_core.dart'
    show DiffHunk, DiffLine, DiffOp, FileDiff;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'transcript_support.dart';

class DiffView extends StatelessWidget {
  const DiffView(this.diff, {super.key, this.lineNumbers = true});

  final FileDiff diff;

  /// Whether to draw the number gutter.
  final bool lineNumbers;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    const spec = TypeSpec(12.5, 20, 400);
    final rows = <Widget>[];
    for (var h = 0; h < diff.hunks.length; h++) {
      if (h > 0) rows.add(_Gap(lineNumbers: lineNumbers));
      rows.addAll(_hunkRows(context, diff.hunks[h], spec));
    }
    return Semantics(
      container: true,
      label: 'Diff of ${diff.path}, +${diff.added} −${diff.removed}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radii.sm),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 0,
              ),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _hunkRows(BuildContext context, DiffHunk hunk, TypeSpec spec) {
    var n = hunk.newStart;
    final rows = <Widget>[];
    for (final line in hunk.lines) {
      final number = switch (line.op) {
        DiffOp.del => null,
        _ => n,
      };
      if (line.op != DiffOp.del) n++;
      rows.add(
        _DiffRow(
          line: line,
          number: number,
          spec: spec,
          lineNumbers: lineNumbers,
        ),
      );
    }
    return rows;
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.line,
    required this.number,
    required this.spec,
    required this.lineNumbers,
  });

  final DiffLine line;
  final int? number;
  final TypeSpec spec;
  final bool lineNumbers;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final (bg, ink, sign) = switch (line.op) {
      DiffOp.add => (t.constructive, t.constructiveInk, '+'),
      DiffOp.del => (t.danger, t.dangerInk, '−'),
      DiffOp.ctx => (t.surface2, t.muted, ''),
    };
    final text = line.text.isEmpty ? ' ' : line.text;
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          children: [
            if (lineNumbers)
              SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    number == null ? '' : '$number',
                    textAlign: TextAlign.right,
                    style: monoStyle(spec, t.faint),
                  ),
                ),
              )
            else
              const SizedBox(width: 8),
            SizedBox(
              width: 16,
              child: Text(
                sign,
                textAlign: TextAlign.center,
                style: monoStyle(spec, line.op == DiffOp.ctx ? t.faint : ink),
              ),
            ),
            Text(
              text,
              softWrap: false,
              style: monoStyle(spec, ink).copyWith(
                decoration: line.op == DiffOp.del
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationThickness: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The break between two hunks.
class _Gap extends StatelessWidget {
  const _Gap({required this.lineNumbers});

  final bool lineNumbers;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return ColoredBox(
      color: t.surface2,
      child: SizedBox(
        height: 16,
        child: Padding(
          padding: EdgeInsets.only(left: lineNumbers ? 44 : 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '…',
              style: monoStyle(const TypeSpec(12.5, 16, 400), t.faint),
            ),
          ),
        ),
      ),
    );
  }
}
